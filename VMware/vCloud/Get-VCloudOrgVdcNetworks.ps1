<#
.SYNOPSIS
    Get all OrgVdc Networks of a vCloud server.

.DESCRIPTION
    Get all OrgVdc Networks of a vCloud server. To exclude shared networks use the param -ExcludeShared. This is only possible when a OrgVdc was given.

    File-Name:  Get-VCloudOrgVdcNetworks.ps1
    Author:     David Wettstein
    Version:    v1.0.2

    Changelog:
                v1.0.2, 2020-05-07, David Wettstein: Reorganize input params.
                v1.0.1, 2020-04-09, David Wettstein: Improve path handling.
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
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [ValidatePattern('.*[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}.*')]
    [String] $OrgVdc = $null
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $IncludeShared = $false
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Switch] $ApproveAllCertificates = $false
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
foreach ($Module in $Modules) {
    if (Get-Module | Where-Object { $_.Name -eq $Module }) {
        # Module already imported. Do nothing.
    } else {
        Import-Module $Module
    }
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
    $Filter = $null
    if (-not [String]::IsNullOrEmpty($OrgVdc)) {
        $Filter = "(vdc==$OrgVdc)"
    }
    if ($ApproveAllCertificates) {
        $OrgVdcNetworks = & "${FILE_DIR}Search-VCloud" -Server $Server -Type "orgVdcNetwork" -ResultType "OrgVdcNetworkRecord" -Filter $Filter -AuthorizationToken $AuthorizationToken -ApproveAllCertificates
    } else {
        $OrgVdcNetworks = & "${FILE_DIR}Search-VCloud" -Server $Server -Type "orgVdcNetwork" -ResultType "OrgVdcNetworkRecord" -Filter $Filter -AuthorizationToken $AuthorizationToken
    }

    $ScriptOut = @()
    if ($OrgVdc -and $IncludeShared) {
        $ScriptOut = $OrgVdcNetworks
    } else {
        foreach ($OrgVdcNetwork in $OrgVdcNetworks) {
            $OrgVdcNetworkOwnerId = & "${FILE_DIR}Split-VCloudId" -UrnOrHref $OrgVdcNetwork.vdc
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
