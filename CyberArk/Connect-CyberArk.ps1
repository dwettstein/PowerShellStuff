<#
.SYNOPSIS
    Login to a CyberArk server using the following order and return a session token:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".

.DESCRIPTION
    Login to a CyberArk server using the following order and return a session token:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".

    Also have a look at https://github.com/pspete/psPAS for more functionality.

    File-Name:  Connect-CyberArk.ps1
    Author:     David Wettstein
    Version:    v1.0.3

    Changelog:
                v1.0.3, 2020-03-12, David Wettstein: Refactor and improve credential handling.
                v1.0.2, 2019-12-17, David Wettstein: Improve parameter validation.
                v1.0.1, 2019-12-13, David Wettstein: Improve credential handling.
                v1.0.0, 2019-07-26, David Wettstein: Refactor and improve script.
                v0.0.1, 2019-02-26, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
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
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [ValidateNotNullOrEmpty()]
    [String] $FileDir = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
    ,
    [Parameter(Mandatory = $false, Position = 5)]
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
    # Disable certificate revocation check.
    [System.Net.ServicePointManager]::CheckCertificateRevocationList = $false;
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

    # If username is given as SecureString string, convert it to plain text.
    try {
        $UsernameSecureString = ConvertTo-SecureString -String $Username
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($UsernameSecureString)
        $Username = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        $null = [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    } catch {
        # Username was already given as plain text.
    }
    if (-not (Test-Path $FileDir)) {
        $null = New-Item -ItemType Directory -Path $FileDir
    }
    $CredPath = ($FileDir + "\" + "$Server-$Username.xml")
    $UserCredPath = ($FileDir + "\" + "$Username.xml")
    $Cred = $null
    if (-not [String]::IsNullOrEmpty($Password)) {
        # 1. Try with username and password, if provided.
        try {
            $PasswordSecureString = ConvertTo-SecureString -String $Password
        } catch [System.FormatException] {
            # Password was likely given as plain text, convert it to SecureString.
            $PasswordSecureString = ConvertTo-SecureString -AsPlainText -Force $Password
        }
        $Cred = New-Object System.Management.Automation.PSCredential ($Username, $PasswordSecureString)
    } elseif (Test-Path $CredPath) {
        # 2. Try with PSCredential file $Server-$Username.xml.
        $Cred = Import-Clixml -Path $CredPath
        Write-Verbose "Credentials imported from: $CredPath"
    } elseif ($Interactive) {
        # 3. If interactive, get credentials from user with a prompt.
        Write-Verbose "No credentials found at path '$CredPath', get them interactively."
        $Cred = Get-Credential -Message $Server -UserName $Username
        if ($Cred -and -not [String]::IsNullOrEmpty($Cred.GetNetworkCredential().Password)) {
            $DoSave = Read-Host -Prompt "Save credentials at '$CredPath'? [y/N] "
            if ($DoSave -match "^[yY]{1}(es)?$") {
                $null = Export-Clixml -Path $CredPath -InputObject $Cred
                Write-Verbose "Credentials exported to: $CredPath"
            } else {
                Write-Verbose "Credentials not exported."
            }
        } else {
            throw "Password is null or empty."
        }
    } elseif (Test-Path $UserCredPath) {
        # 4. If not interactive, try with PSCredential file $Username.xml.
        $Cred = Import-Clixml -Path $UserCredPath
        Write-Verbose "Credentials imported from: $UserCredPath"
    } else {
        throw "No credentials found. Please use the input parameters or a PSCredential xml file at path '$CredPath'."
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
