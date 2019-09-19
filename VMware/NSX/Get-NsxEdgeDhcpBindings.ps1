<#
.SYNOPSIS
    Short description

.DESCRIPTION
    Long description

    File-Name:  Get-NsxEdgeDhcpBindings.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2019-08-23, David Wettstein: First implementation.

.EXAMPLE
    Example of how to use this cmdlet
#>
[CmdletBinding()]
[OutputType([PSObject])]
param (
    [Parameter(Mandatory=$true, Position=0)]
    [String] $Server
    ,
    [Parameter(Mandatory=$true, Position=1)]
    [ValidatePattern("^edge-\d+$")]
    [String] $EdgeId
    ,
    [Parameter(Mandatory=$false, Position=2)]
    [Switch] $AsObj
    ,
    [Parameter(Mandatory=$false, Position=3)]
    [PSObject] $NsxConnection
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

#===============================================================================
# Initialization and Functions
#===============================================================================
# Make sure the necessary modules are loaded.
$Modules = @(
    "VMware.VimAutomation.Core", "PowerNSX"
)
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
    if (-not $NsxConnection) {
        $NsxConnection = & "$FILE_DIR\Connect-Nsx.ps1" -Server $Server
    }

    $Uri = "/api/4.0/edges/$EdgeId/dhcp/config/bindings"
    $Response = Invoke-NsxWebRequest -method "GET" -URI $Uri -connection $NsxConnection -WarningAction SilentlyContinue
    if (-not 200 -le $Response.StatusCode -lt 300) {
        throw "Failed to invoke $($Uri): $($Response.StatusCode) - $($Response.Content)"
    }

    if ($AsObj) {
        [Xml] $ResponseXml = $Response.Content
        $OutputMessage = $ResponseXml.staticBindings.staticBinding
    } else {
        $OutputMessage = $Response.Content
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
        $OutputMessage  # Write OutputMessage to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    exit $ExitCode
}
