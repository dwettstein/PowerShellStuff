<#
.SYNOPSIS
    Query objects of a certain type in a vCloud server.

.DESCRIPTION
    Query objects of a certain type in a vCloud server.

    File-Name:  Search-VCloud.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2019-05-30, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    $Orgs = & ".\Search-VCloud.ps1" -Server $VCloud -Type "organization" -ResultType "OrgRecord"

.EXAMPLE
    $OrgVdcNetworks = Search-VCloud -Server $VCloud -Type "orgVdcNetwork" -ResultType "OrgVdcNetworkRecord" -Filter "(vdc==$OrgVdcId)"

.EXAMPLE
    $OrgVdcVApps = Search-VCloud -Server $VCloud -Type "adminVApp" -ResultType "AdminVAppRecord" -Filter "(vdc==$OrgVdcId)"
#>
[CmdletBinding()]
[OutputType([Array])]
param (
    [Parameter(Mandatory=$true, Position=0)]
    [String] $Server
    ,
    [Parameter(Mandatory=$true, Position=1)]
    [String] $Type
    ,
    [Parameter(Mandatory=$true, Position=2)]
    [String] $ResultType
    ,
    [Parameter(Mandatory=$false, Position=3)]
    [String] $Filter = $null  # e.g. (org==foo;vdc==bar)
    ,
    [Parameter(Mandatory=$false, Position=4)]
    [String] $SessionToken = $null
    ,
    [Parameter(Mandatory=$false, Position=5)]
    [Switch] $AcceptAllCertificates = $false
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

#===============================================================================
# Initialization and Functions
#===============================================================================
# Make sure the necessary modules are loaded.
$Modules = @()
foreach ($Module in $Modules) {
    if (Get-Module | Where-Object {$_.Name -eq $Module}) {
        # Module already imported. Do nothing.
    } else {
        Import-Module $Module
    }
}

$StartDate = [DateTime]::Now

[String] $FILE_NAME = $MyInvocation.MyCommand.Name
if ($PSVersionTable.PSVersion.Major -lt 3) {
    [String] $FILE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
} else {
    [String] $FILE_DIR = $PSScriptRoot
}

$ExitCode = 0
$ErrorOut = ""
$OutputMessage = ""

Write-Verbose "$($FILE_NAME): CALL."

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    $Results = @()
    $Page = 1
    do {
        $Endpoint = "/query?type=$Type"
        if (-not [String]::IsNullOrEmpty($Filter)) {
            $Endpoint += "&filter=$Filter"
        }
        $Endpoint += "&page=$Page"
        if ($AcceptAllCertificates) {
            [Xml] $Response = & "$FILE_DIR\Invoke-VCloudRequest.ps1" -Server $Server -Method "GET" -Endpoint $Endpoint -SessionToken $SessionToken -AcceptAllCertificates
        } else {
            [Xml] $Response = & "$FILE_DIR\Invoke-VCloudRequest.ps1" -Server $Server -Method "GET" -Endpoint $Endpoint -SessionToken $SessionToken
        }
        if ($Response.QueryResultRecords.total -gt 0) {
            $Results += $Response.QueryResultRecords."$ResultType"
            $Page++
        }
    } while ($Response.QueryResultRecords.Link.rel -contains "nextPage")
    $OutputMessage = $Results
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())" -WarningAction Continue
    $ErrorOut = "$($_.Exception.Message)"
    $ExitCode = 1
} finally {
    $EndDate = [DateTime]::Now
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ($EndDate - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        if ($OutputMessage.Length -le 1) {
            # See here: http://stackoverflow.com/questions/18476634/powershell-doesnt-return-an-empty-array-as-an-array
            ,$OutputMessage  # Write OutputMessage to output stream.
        } else {
            $OutputMessage  # Write OutputMessage to output stream.
        }
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}