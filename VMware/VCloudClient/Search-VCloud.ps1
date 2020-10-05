<#
.SYNOPSIS
    Query objects of a certain type in a vCloud server.

.DESCRIPTION
    Query objects of a certain type in a vCloud server.

    File-Name:  Search-VCloud.ps1
    Author:     David Wettstein
    Version:    v1.0.2

    Changelog:
                v1.0.2, 2020-05-07, David Wettstein: Reorganize input params.
                v1.0.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.0.0, 2019-05-30, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Orgs = & "Search-VCloud" -Server $VCloud -Type "organization" -ResultType "OrgRecord"

.EXAMPLE
    $OrgVdcNetworks = Search-VCloud -Server $VCloud -Type "orgVdcNetwork" -ResultType "OrgVdcNetworkRecord" -Filter "(vdc==$OrgVdcId)"

.EXAMPLE
    $OrgVdcVApps = Search-VCloud -Server $VCloud -Type "adminVApp" -ResultType "AdminVAppRecord" -Filter "(vdc==$OrgVdcId)"
#>
[CmdletBinding()]
[OutputType([Array])]
param (
    [Parameter(Mandatory=$true, ValueFromPipeline = $true, Position=0)]
    [String] $Type
    ,
    [Parameter(Mandatory=$true, Position=1)]
    [String] $ResultType
    ,
    [Parameter(Mandatory=$false, Position=2)]
    [String] $Filter = $null  # e.g. (org==foo;vdc==bar)
    ,
    [Parameter(Mandatory=$false, Position=3)]
    [String] $Server
    ,
    [Parameter(Mandatory=$false, Position=4)]
    [String] $AuthorizationToken = $null
    ,
    [Parameter(Mandatory=$false, Position=5)]
    [Alias("Insecure")]
    [Switch] $ApproveAllCertificates
)

if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

#===============================================================================
# Initialization and Functions
#===============================================================================
# Make sure the necessary modules are loaded.
$Modules = @()
$LoadedModules = Get-Module; $Modules | ForEach-Object {
    if ($_ -notin $LoadedModules.Name) { Import-Module $_ -DisableNameChecking }
}

$StartDate = [DateTime]::Now

[String] $FILE_NAME = $MyInvocation.MyCommand.Name
if ($PSVersionTable.PSVersion.Major -lt 3 -or [String]::IsNullOrEmpty($PSScriptRoot)) {
    # Join-Path with empty child path is used to append a path separator.
    [String] $FILE_DIR = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) ""
} else {
    [String] $FILE_DIR = Join-Path $PSScriptRoot ""
}
if ($MyInvocation.MyCommand.Module) {
    $FILE_DIR = ""  # If this script is part of a module, we want to call module functions not files.
}

$ExitCode = 0
$ErrorOut = ""
$ScriptOut = ""

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
        if ($ApproveAllCertificates) {
            [Xml] $Response = & "${FILE_DIR}Invoke-VCloudRequest" -Server $Server -Method "GET" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken -ApproveAllCertificates
        } else {
            [Xml] $Response = & "${FILE_DIR}Invoke-VCloudRequest" -Server $Server -Method "GET" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken
        }
        if ($Response.QueryResultRecords.total -gt 0) {
            $Results += $Response.QueryResultRecords."$ResultType"
            $Page++
        }
    } while ($Response.QueryResultRecords.Link.rel -contains "nextPage")
    $ScriptOut = $Results
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction Continue
    $Ex = $_.Exception
    if ($Ex.InnerException) { $Ex = $Ex.InnerException }
    $ErrorOut = "$($Ex.Message)"
    $ExitCode = 1
} finally {
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ([DateTime]::Now - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        if ($ScriptOut.Length -le 1) {
            # See here: http://stackoverflow.com/questions/18476634/powershell-doesnt-return-an-empty-array-as-an-array
            ,$ScriptOut  # Write ScriptOut to output stream.
        } else {
            $ScriptOut  # Write ScriptOut to output stream.
        }
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
