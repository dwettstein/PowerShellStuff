<#
.SYNOPSIS
    Login to a CyberArk server using the following order and return a session token:
        1. Try with username and password, if provided.
        2. Try with PSCredential file $Server-$Username.xml in folder $HOME\.pscredentials\.
        3. Get credentials from user with a prompt.

.DESCRIPTION
    Login to a CyberArk server using the following order and return a session token:
        1. Try with username and password, if provided.
        2. Try with PSCredential file $Server-$Username.xml in folder $HOME\.pscredentials\.
        3. Get credentials from user with a prompt.

    Also have a look at https://github.com/pspete/psPAS for more functionality.

    File-Name:  Connect-CyberArk.ps1
    Author:     David Wettstein
    Version:    v1.0.1

    Changelog:
                v0.0.1, 2019-02-26, David Wettstein: First implementation.
                v1.0.0, 2019-07-26, David Wettstein: Refactor and improve script.
                v1.0.1, 2019-12-13, David Wettstein: Improve credential handling.

.NOTES
    Copyright (c) 2019 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.LINK
    https://github.com/pspete/psPAS

.EXAMPLE
    $CyberArkToken = & ".\Connect-CyberArk.ps1" "cyberark.local"

.EXAMPLE
    $CyberArkToken = & "$PSScriptRoot\Connect-CyberArk.ps1" -Server "cyberark.local" -Username "user" -Password "changeme" -AcceptAllCertificates
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [String] $Username = "${env:USERNAME}"  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $Password = $null  # secure string or plain text (not recommended)
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

function Approve-AllCertificates {
    $CSSource = @'
using System.Net;

public class ServerCertificate {
    public static void approveAllCertificates() {
        ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
    }
}
'@
    if (-not ([System.Management.Automation.PSTypeName]'ServerCertificate').Type) {
        Add-Type -TypeDefinition $CSSource
    }
    # Ignore self-signed SSL certificates.
    [ServerCertificate]::approveAllCertificates()
    # Allow all security protocols.
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
}

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    if ($AcceptAllCertificates) {
        Approve-AllCertificates
    }

    if ([String]::IsNullOrEmpty($Username)) {
        $Username = "${env:USERNAME}"
    } else {
        # If username is given as SecureString string, convert it to plain text.
        try {
            $UsernameSecureString = ConvertTo-SecureString -String $Username
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($UsernameSecureString)
            $Username = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            $null = [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        } catch {
            # Username was already given as plain text.
        }
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
            $DoSave = Read-Host -Prompt "Save credentials at '$CredPath'? [Y/n] "
            if (-not $DoSave -or $DoSave -match "^[yY]{1}(es)?$") {
                $null = Export-Clixml -Path $CredPath -InputObject $Cred
                Write-Verbose "Credentials exported to: $CredPath"
            }
        } else {
            throw "Password was null or empty."
        }
    }

    $BaseUrl = "https://$Server"
    $EndpointUrl = "$BaseUrl/PasswordVault/api/auth/LDAP/Logon"

    $CredString = $Cred.GetNetworkCredential().Username + "@" + $Organization + ":" + $Cred.GetNetworkCredential().Password
    $CredStringInBytes = [System.Text.Encoding]::UTF8.GetBytes($CredString)
    $CredStringInBase64 = [System.Convert]::ToBase64String($CredStringInBytes)

    $Headers = @{
        "Accept" = "application/json"
        "Content-Type" = "application/json"
        "Cache-Control" = "no-cache"
    }

    $Body = @{
        "username" = $Cred.UserName
        "password" = $Cred.GetNetworkCredential().Password
    }

    $Response = Invoke-WebRequest -Method Post -Headers $Headers -Body (ConvertTo-Json $Body) -Uri $EndpointUrl

    $ScriptOut = $Response.Content.Trim('"')
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
