<#
.SYNOPSIS
    Login to a CyberArk server using the following order and return an authorization token:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".

.DESCRIPTION
    Login to a CyberArk server using the following order and return an authorization token:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".

    Also have a look at https://github.com/pspete/psPAS for more functionality.

    File-Name:  Connect-CyberArk.ps1
    Author:     David Wettstein
    Version:    v1.1.2

    Changelog:
                v1.1.2, 2020-05-07, David Wettstein: Reorganize input params.
                v1.1.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.1.0, 2020-04-07, David Wettstein: Sync input variables with cache.
                v1.0.4, 2020-04-06, David Wettstein: Return a secure string by default.
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
    $AuthorizationToken = & "Connect-CyberArk" "example.com"

.EXAMPLE
    $AuthorizationToken = & "$PSScriptRoot\Connect-CyberArk" -Server "example.com" -Username "user" -Password "changeme" -ApproveAllCertificates
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $AsPlainText = $false
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $Username = "${env:USERNAME}"  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [ValidateNotNullOrEmpty()]
    [String] $PswdDir = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [Switch] $ApproveAllCertificates = $false
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
    $Server = & "${FILE_DIR}Sync-CyberArkVariableCache" "Server" $Server -IsMandatory
    $ApproveAllCertificates = & "${FILE_DIR}Sync-CyberArkVariableCache" "ApproveAllCertificates" $ApproveAllCertificates

    if ($ApproveAllCertificates) {
        Approve-AllCertificates
    }

    if ($Interactive) {
        $Cred = & "${FILE_DIR}Get-CyberArkPSCredential" -Server $Server -Username $Username -Password $Password -Interactive -PswdDir $PswdDir -ErrorAction:Stop
    } else {
        $Cred = & "${FILE_DIR}Get-CyberArkPSCredential" -Server $Server -Username $Username -Password $Password -PswdDir $PswdDir -ErrorAction:Stop
    }

    $BaseUrl = "https://$Server"
    $EndpointUrl = "$BaseUrl/PasswordVault/api/auth/LDAP/Logon"

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
    $AuthorizationToken = $Response.Content.Trim('"')
    $AuthorizationTokenSecureString = (ConvertTo-SecureString -AsPlainText -Force $AuthorizationToken | ConvertFrom-SecureString)

    $null = & "${FILE_DIR}Sync-CyberArkVariableCache" "AuthorizationToken" $AuthorizationTokenSecureString

    if ($AsPlainText) {
        $ScriptOut = $AuthorizationToken
    } else {
        $ScriptOut = $AuthorizationTokenSecureString
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
