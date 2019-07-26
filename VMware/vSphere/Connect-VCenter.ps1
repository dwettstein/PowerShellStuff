<#
.SYNOPSIS
    Login to a vCenter server using the following order and return a PowerCLI connection:
        1. Try with username and password, if provided
        2. Try with PSCredential file $Server-${env:USERNAME}.xml in folder $HOME\.pscredentials\
        3. If nothing provided from above, try with Windows SSPI authentication
        4. Get credentials from user with a prompt.

.DESCRIPTION
    Login to a vCenter server using the following order and return a PowerCLI connection:
        1. Try with username and password, if provided
        2. Try with PSCredential file $Server-${env:USERNAME}.xml in folder $HOME\.pscredentials\
        3. If nothing provided from above, try with Windows SSPI authentication
        4. Get credentials from user with a prompt.

    File-Name:  Connect-VCenter.ps1
    Author:     David Wettstein
    Version:    v1.1.0

    Changelog:
                v1.0.0, 2019-03-10, David Wettstein: First implementation.
                v1.1.0, 2019-07-26, David Wettstein: Prompt for credentials and ask to save them.

.NOTES
    Copyright (c) 2019 David Wettstein,
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
    [Parameter(Mandatory=$true, Position=0)]
    [String] $Server
    ,
    [Parameter(Mandatory=$false, Position=1)]
    [String] $Username  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory=$false, Position=2)]
    [String] $Password  # secure string or plain text (not recommended)
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
    $Cred = $null
    # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
    $CredPath = "$HOME\.pscredentials\$Server-${env:USERNAME}.xml"
    if (-not [String]::IsNullOrEmpty($Username) -and -not [String]::IsNullOrEmpty($Password)) {
        # If username is given as SecureString string, convert it to plain text.
        try {
            $UsernameSecureString = ConvertTo-SecureString -String $Username
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($UsernameSecureString)
            $Username = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            $null = [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        } catch {
            # Username was already given as plain text.
        }
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
    }

    $VCenterConnection = $null
    try {
        if ($Cred) {
            $VCenterConnection = Connect-VIServer -Server $Server -Credential $Cred -WarningAction SilentlyContinue
        } else {
            $VCenterConnection = Connect-VIServer -Server $Server -WarningAction SilentlyContinue
        }
    } catch {
        Write-Warning "No credentials were given and Windows SSPI authentication failed. Please use the input parameters or a PSCredential xml file at path '$CredPath'."
        $Cred = Get-Credential -Message $Server -UserName ${env:USERNAME}
        $DoSave = Read-Host -Prompt "Save credential at '$CredPath'? [Y/n] "
        if (-not $DoSave -or $DoSave -match "^[yY]{1}(es)?$") {
            $null = Export-Clixml -Path $CredPath -InputObject $Cred
            Write-Verbose "PSCredential exported to: $CredPath"
        }
        $VCenterConnection = Connect-VIServer -Server $Server -Credential $Cred -WarningAction SilentlyContinue
    }

    $OutputMessage = $VCenterConnection
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
