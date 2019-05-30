<#
.SYNOPSIS
    Login to a vCloud server using the following order and return a vCloud session token:
        1. Try with username and password, if provided
        2. Try with PSCredential file $vCenter-${env:USERNAME}.xml in folder $HOME\.pscredentials\

.DESCRIPTION
    Login to a vCloud server using the following order and return a vCloud session token:
        1. Try with username and password, if provided
        2. Try with PSCredential file $vCenter-${env:USERNAME}.xml in folder $HOME\.pscredentials\

    File-Name:  Connect-VCloud.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2019-05-30, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    $VCloudToken = & ".\Connect-VCloud.ps1" "vcloud.local"

.EXAMPLE
    $VCloudToken = & "$PSScriptRoot\Connect-VCloud.ps1" -Server "vcloud.local" -Organization "system" -Username "user" -Password "changeme" -AcceptAllCertificates
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory=$true, Position=0)]
    [String] $Server
    ,
    [Parameter(Mandatory=$false, Position=1)]
    [String] $Organization = "system"
    ,
    [Parameter(Mandatory=$false, Position=2)]
    [String] $Username  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory=$false, Position=3)]
    [String] $Password  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory=$false, Position=4)]
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

    $Cred = $null
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
    } elseif (Test-Path "$HOME\.pscredentials\$Server-${env:USERNAME}.xml") {  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
        $Cred = Import-Clixml -Path "$HOME\.pscredentials\$Server-${env:USERNAME}.xml"
    } else {
        Write-Warning "No credentials were given. Please use the input parameters or a PSCredential xml file with name '$Server-${env:USERNAME}.xml' in folder '$HOME\.pscredentials\'."
        $Cred = Get-Credential -Message $Server -UserName ${env:USERNAME}
    }

    $BaseUrl = "https://$Server"
    $EndpointUrl = "$BaseUrl/api/sessions"

    $CredString = $Cred.GetNetworkCredential().Username + "@" + $Organization + ":" + $Cred.GetNetworkCredential().Password
    $CredStringInBytes = [System.Text.Encoding]::UTF8.GetBytes($CredString)
    $CredStringInBase64 = [System.Convert]::ToBase64String($CredStringInBytes)

    $Headers = @{
        "Authorization" = "Basic $CredStringInBase64"
        "Accept" = "application/*+xml;version=31.0"
    }

    $Response = Invoke-WebRequest -Method Post -Headers $Headers -Uri $EndpointUrl

    $OutputMessage = $Response.Headers.'x-vcloud-authorization'
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())" -WarningAction Continue
    $ErrorOut = "$($_.Exception.Message)"
    $ExitCode = 1
} finally {
    $EndDate = [DateTime]::Now
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ($EndDate - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        "$OutputMessage"  # Write OutputMessage to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
