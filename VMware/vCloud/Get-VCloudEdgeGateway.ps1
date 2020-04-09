<#
.SYNOPSIS
    Get the Edge Gateway with given id or href of a vCloud server.

.DESCRIPTION
    Get the Edge Gateway with given id or href of a vCloud server.

    File-Name:  Get-VCloudEdgeGateway.ps1
    Author:     David Wettstein
    Version:    v1.0.1

    Changelog:
                v1.0.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.0.0, 2020-02-09, David Wettstein: First implementation.

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
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $Server
    ,
    [Parameter(Mandatory = $true, Position = 1)]
    [ValidatePattern('.*[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}.*')]
    [String] $EdgeGateway = $null
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
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
    $EdgeGatewayId = & "${FILE_DIR}Split-VCloudId" -UrnOrHref $EdgeGateway
    if ($AcceptAllCertificates) {
        [Xml] $Response = & "${FILE_DIR}Invoke-VCloudRequest" -Server $Server -Method "GET" -Endpoint "/api/admin/edgeGateway/$EdgeGatewayId" -AuthorizationToken $AuthorizationToken -AcceptAllCertificates
    } else {
        [Xml] $Response = & "${FILE_DIR}Invoke-VCloudRequest" -Server $Server -Method "GET" -Endpoint "/api/admin/edgeGateway/$EdgeGatewayId" -AuthorizationToken $AuthorizationToken
    }
    $ScriptOut = $Response.EdgeGateway
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
