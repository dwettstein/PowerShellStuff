<#
.SYNOPSIS
    Short description

.DESCRIPTION
    Long description

    File-Name:  Get-NsxEdgeDhcpLeases.ps1
    Author:     David Wettstein
    Version:    v2.0.1

    Changelog:
                v2.0.1, 2020-05-07, David Wettstein: Reorganize input params.
                v2.0.0, 2020-04-23, David Wettstein: Refactor and get rid of PowerNSX.
                v1.0.3, 2020-04-09, David Wettstein: Improve path handling.
                v1.0.2, 2020-04-08, David Wettstein: Use helper Invoke-NsxRequest.
                v1.0.1, 2020-03-13, David Wettstein: Change AsObj to AsXml.
                v1.0.0, 2019-08-23, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    Example of how to use this cmdlet
#>
[CmdletBinding()]
[OutputType([Object])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidatePattern("^edge-\d+$")]
    [String] $EdgeId
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $AsXml
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 4)]
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
    $Endpoint = "/api/4.0/edges/$EdgeId/dhcp/leaseInfo"
    if ($ApproveAllCertificates) {
        $Response = & "${FILE_DIR}Invoke-NsxRequest" -Server $Server -Method "GET" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken -ApproveAllCertificates
    } else {
        $Response = & "${FILE_DIR}Invoke-NsxRequest" -Server $Server -Method "GET" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken
    }
    if ($Response.StatusCode -lt 200 -or $Response.StatusCode -ge 300) {
        throw "Failed to invoke $($Endpoint): $($Response.StatusCode) - $($Response.Content)"
    }

    if ($AsXml) {
        $ScriptOut = $Response.Content
    } else {
        [Xml] $ResponseXml = $Response.Content
        $ScriptOut = $ResponseXml.dhcpLeases.dhcpLeaseInfo.leaseInfo
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
