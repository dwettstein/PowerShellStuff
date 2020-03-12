<#
.SYNOPSIS
    Login to a vCenter server using the following order and return a PowerCLI connection:
        1. Try with username and password, if provided.
        2. Try with PSCredential file $Server-$Username.xml in folder $HOME\.pscredentials\.
        3. Get credentials from user with a prompt.
        4. If nothing provided from above, try with Windows SSPI authentication

.DESCRIPTION
    Login to a vCenter server using the following order and return a PowerCLI connection:
        1. Try with username and password, if provided.
        2. Try with PSCredential file $Server-$Username.xml in folder $HOME\.pscredentials\.
        3. Get credentials from user with a prompt.
        4. If nothing provided from above, try with Windows SSPI authentication.

    File-Name:  Connect-VCenter.ps1
    Author:     David Wettstein
    Version:    v1.1.2

    Changelog:
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
    $VCenterConnection = & ".\Connect-VCenter.ps1" "vcenter.vsphere.local"

.EXAMPLE
    $VCenterConnection = & "$PSScriptRoot\Connect-VCenter.ps1" -Server "vcenter.vsphere.local" -Username "user" -Password "changeme"
#>
[CmdletBinding()]
[OutputType([PSObject])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Username = "${env:USERNAME}"  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $Password = $null  # secure string or plain text (not recommended)
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
    # If username is given as SecureString string, convert it to plain text.
    try {
        $UsernameSecureString = ConvertTo-SecureString -String $Username
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($UsernameSecureString)
        $Username = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        $null = [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    } catch {
        # Username was already given as plain text.
    }
    # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
    if (-not (Test-Path "$HOME\.pscredentials")) {
        $null = New-Item -ItemType Directory -Path "$HOME\.pscredentials"
    }
    $CredPath = "$HOME\.pscredentials\$Server-$Username.xml"
    $Cred = $null
    if (-not [String]::IsNullOrEmpty($Password)) {
        # Convert given password to SecureString obj.
        try {
            $PasswordSecureString = ConvertTo-SecureString -String $Password
        } catch {
            # Password was given as plain text, convert it to secure string
            $PasswordSecureString = ConvertTo-SecureString -AsPlainText -Force $Password
        }
        $Cred = New-Object System.Management.Automation.PSCredential ($Username, $PasswordSecureString)
    } elseif (Test-Path $CredPath) {
        $Cred = Import-Clixml -Path $CredPath
        Write-Verbose "Credentials imported from: $CredPath"
    } else {
        Write-Verbose "No credentials found. Please use the input parameters or a PSCredential xml file at path '$CredPath'."
        $Cred = Get-Credential -Message $Server -UserName $Username
        if ($Cred -and -not [String]::IsNullOrEmpty($Cred.GetNetworkCredential().Password)) {
            $DoSave = Read-Host -Prompt "Save credentials at '$CredPath'? [y/N] "
            if ($DoSave -match "^[yY]{1}(es)?$") {
                $null = Export-Clixml -Path $CredPath -InputObject $Cred
                Write-Verbose "Credentials exported to: $CredPath"
            }
        }
    }

    if ($Cred -and -not [String]::IsNullOrEmpty($Cred.GetNetworkCredential().Password)) {
        $ScriptOut = Connect-VIServer -Server $Server -Credential $Cred
    } else {
        $ScriptOut = Connect-VIServer -Server $Server
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
