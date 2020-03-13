<#
.SYNOPSIS
    Get all ProviderVdcs of a vCloud server.

.DESCRIPTION
    Get all ProviderVdcs of a vCloud server.

    File-Name:  Get-VCloudProviderVdcs.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2019-05-30, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    Example of how to use this cmdlet
#>
[CmdletBinding()]
[OutputType([PSObject])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $IncludeResourcePools = $false
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $AuthorizationToken = $null
    ,
    [Parameter(Mandatory = $false, Position = 3)]
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
    if ($AcceptAllCertificates) {
        [Xml] $Response = & "$FILE_DIR\Invoke-VCloudRequest.ps1" -Server $Server -Method "GET" -Endpoint "/api/admin/extension/providerVdcReferences" -AuthorizationToken $AuthorizationToken -AcceptAllCertificates
    } else {
        [Xml] $Response = & "$FILE_DIR\Invoke-VCloudRequest.ps1" -Server $Server -Method "GET" -Endpoint "/api/admin/extension/providerVdcReferences" -AuthorizationToken $AuthorizationToken
    }
    $ScriptOut = $Response.VMWProviderVdcReferences.ProviderVdcReference

    if ($IncludeResourcePools) {
        foreach ($ProviderVdc in $ScriptOut) {
            if ($AcceptAllCertificates) {
                $ProviderVdcResourcePools = & "$FILE_DIR\Get-VCloudProviderVdcResourcePools.ps1" -Server $Server -ProviderVdc $ProviderVdc.id -AuthorizationToken $AuthorizationToken -AcceptAllCertificates
            } else {
                $ProviderVdcResourcePools = & "$FILE_DIR\Get-VCloudProviderVdcResourcePools.ps1" -Server $Server -ProviderVdc $ProviderVdc.id -AuthorizationToken $AuthorizationToken
            }
            Add-Member -InputObject $ProviderVdc -NotePropertyName "resourcePools" -NotePropertyValue $ProviderVdcResourcePools -Force
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
        $ScriptOut  # Write ScriptOut to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
