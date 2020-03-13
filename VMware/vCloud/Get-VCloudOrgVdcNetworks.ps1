<#
.SYNOPSIS
    Get all OrgVdc Networks of a vCloud server.

.DESCRIPTION
    Get all OrgVdc Networks of a vCloud server. To exclude shared networks use the param -ExcludeShared. This is only possible when a OrgVdc was given.

    File-Name:  Get-VCloudOrgVdcNetworks.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2019-09-17, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    Example of how to use this cmdlet
#>
[CmdletBinding()]
[OutputType([Array])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidatePattern('.*[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}.*')]
    [String] $OrgVdc = $null
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [Switch] $IncludeShared = $false
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $AuthorizationToken = $null
    ,
    [Parameter(Mandatory = $false, Position = 4)]
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
    if (Get-Module | Where-Object { $_.Name -eq $Module }) {
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
$ScriptOut = ""

Write-Verbose "$($FILE_NAME): CALL."

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    $Filter = $null
    if (-not [String]::IsNullOrEmpty($OrgVdc)) {
        $Filter = "(vdc==$OrgVdc)"
    }
    if ($AcceptAllCertificates) {
        $OrgVdcNetworks = & "$FILE_DIR\Search-VCloud.ps1" -Server $Server -Type "orgVdcNetwork" -ResultType "OrgVdcNetworkRecord" -Filter $Filter -AuthorizationToken $AuthorizationToken -AcceptAllCertificates
    } else {
        $OrgVdcNetworks = & "$FILE_DIR\Search-VCloud.ps1" -Server $Server -Type "orgVdcNetwork" -ResultType "OrgVdcNetworkRecord" -Filter $Filter -AuthorizationToken $AuthorizationToken
    }

    $ScriptOut = @()
    if ($OrgVdc -and $IncludeShared) {
        $ScriptOut = $OrgVdcNetworks
    } else {
        foreach ($OrgVdcNetwork in $OrgVdcNetworks) {
            $OrgVdcNetworkOwnerId = & "$FILE_DIR\Split-VCloudId.ps1" -UrnOrHref $OrgVdcNetwork.vdc
            if ($OrgVdcNetwork.isShared -and -not ($OrgVdcNetworkOwnerId -eq $OrgVdc)) {
                Write-Verbose "OrgVdc network '$($OrgVdcNetwork.name)' is shared and owner is '$($OrgVdcNetwork.vdcName)', skip it."
                continue
            } else {
                $ScriptOut += $OrgVdcNetwork
            }
        }
    }
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())" -WarningAction Continue
    $ErrorOut = "$($_.Exception.Message)"
    $ExitCode = 1
} finally {
    $EndDate = [DateTime]::Now
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ($EndDate - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        if ($ScriptOut.Length -le 1) {
            # See here: http://stackoverflow.com/questions/18476634/powershell-doesnt-return-an-empty-array-as-an-array
            , $ScriptOut  # Write ScriptOut to output stream.
        } else {
            $ScriptOut  # Write ScriptOut to output stream.
        }
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
