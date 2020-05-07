<#
.SYNOPSIS
    Login to a vCenter server using the following order and return a PowerCLI connection:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".
        5. If nothing provided from above, try with PowerCLI and Windows SSPI authentication.

.DESCRIPTION
    Login to a vCenter server using the following order and return a PowerCLI connection:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".
        5. If nothing provided from above, try with PowerCLI and Windows SSPI authentication.

    File-Name:  Connect-VCenter.ps1
    Author:     David Wettstein
    Version:    v1.2.2

    Changelog:
                v1.2.2, 2020-05-07, David Wettstein: Reorganize input params.
                v1.2.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.2.0, 2020-04-07, David Wettstein: Sync input variables with cache.
                v1.1.3, 2020-03-12, David Wettstein: Refactor and improve credential handling.
                v1.1.2, 2019-12-17, David Wettstein: Improve parameter validation.
                v1.1.1, 2019-12-13, David Wettstein: Improve credential handling.
                v1.1.0, 2019-07-26, David Wettstein: Prompt for credentials and ask to save them.
                v1.0.0, 2019-03-10, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    $VCenterConnection = & "Connect-VCenter" "vcenter.vsphere.local"

.EXAMPLE
    $VCenterConnection = & "$PSScriptRoot\Connect-VCenter" -Server "vcenter.vsphere.local" -Username "user" -Password "changeme"
#>
[CmdletBinding()]
[OutputType([Object])]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Username = "${env:USERNAME}"  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [ValidateNotNullOrEmpty()]
    [String] $PswdDir = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
)

if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

#===============================================================================
# Initialization and Functions
#===============================================================================
# Make sure the necessary modules are loaded.
$Modules = @(
    "VMware.VimAutomation.Core"
)
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
    $Server = & "${FILE_DIR}Sync-VSphereVariableCache" "Server" $Server -IsMandatory

    if ($Interactive) {
        $Cred = & "${FILE_DIR}Get-VSpherePSCredential" -Server $Server -Username $Username -Password $Password -Interactive -PswdDir $PswdDir -ErrorAction:Continue
    } else {
        $Cred = & "${FILE_DIR}Get-VSpherePSCredential" -Server $Server -Username $Username -Password $Password -PswdDir $PswdDir -ErrorAction:Continue
    }


    if ($Cred -and -not [String]::IsNullOrEmpty($Cred.GetNetworkCredential().Password)) {
        $VCenterConnection = Connect-VIServer -Server $Server -Credential $Cred
    } else {
        # If no credentials provided, try with PowerCLI and Windows SSPI authentication.
        $VCenterConnection = Connect-VIServer -Server $Server
    }

    $null = & "${FILE_DIR}Sync-VSphereVariableCache" "VCenterConnection" $VCenterConnection

    $ScriptOut = $VCenterConnection
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
