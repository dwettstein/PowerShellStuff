<#
.SYNOPSIS
    Add an account to a CyberArk server.

.DESCRIPTION
    Add an account to a CyberArk server.

    Also have a look at https://github.com/pspete/psPAS for more functionality.

    CyberArk API documentation can be found here: https://docs.cyberark.com/

    File-Name:  Add-CyberArkAccount.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2020-03-16, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.LINK
    https://github.com/pspete/psPAS

.LINK
    https://docs.cyberark.com/

.EXAMPLE
    $Account = & ".\Add-CyberArkAccount.ps1" "example.com" "safeName" "customPlatformId" "server.example.com" -Interactive

.EXAMPLE
    $Account = & "$PSScriptRoot\Add-CyberArkAccount.ps1" -Server "example.com" -Safe "safeName" -PlatformId "customPlatformId" -Address "server.example.com" -DeviceType "Application" -Username "username" -Password "password" -AsJson
#>
[CmdletBinding()]
[OutputType([PSObject])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $Server
    ,
    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Safe
    ,
    [Parameter(Mandatory = $true, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $Address
    ,
    [Parameter(Mandatory = $true, Position = 3)]
    [ValidateNotNullOrEmpty()]
    [String] $PlatformId
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [ValidateNotNullOrEmpty()]
    [String] $DeviceType = "Application"
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [ValidateNotNullOrEmpty()]
    [String] $Username = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [ValidateNotNullOrEmpty()]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 8)]
    [Switch] $AsJson
    ,
    [Parameter(Mandatory = $false, Position = 9)]
    [ValidateNotNullOrEmpty()]
    [String] $AuthorizationToken = $null
    ,
    [Parameter(Mandatory = $false, Position = 10)]
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
    $Cred = $null
    if (-not [String]::IsNullOrEmpty($Username) -and -not [String]::IsNullOrEmpty($Password)) {
        # 1. Try with username and password, if provided.
        try {
            $PasswordSecureString = ConvertTo-SecureString -String $Password
        } catch [System.FormatException] {
            # Password was likely given as plain text, convert it to SecureString.
            $PasswordSecureString = ConvertTo-SecureString -AsPlainText -Force $Password
        }
        $Cred = New-Object System.Management.Automation.PSCredential ($Username, $PasswordSecureString)
    } elseif ($Interactive) {
        # 2. If interactive, get credentials from user with a prompt.
        $Cred = Get-Credential -Message $Address -UserName $Username
        if (-not $Cred -or [String]::IsNullOrEmpty($Cred.GetNetworkCredential().Password)) {
            throw "Password is null or empty."
        }
    } else {
        throw "No credentials found. Please use the input parameters or interactive mode."
    }

    $AccountName = "$DeviceType-$PlatformId-$Address-$($Cred.UserName)"
    Write-Verbose "Account name will be: $AccountName"

    $Body = @{
        "safeName" = $Safe
        "deviceType" = $DeviceType
        "platformId" = $PlatformId
        "address" = $Address
        "name" = $AccountName
        "userName" = $Cred.UserName
        "secretType" = "password"
        "secret" = $Cred.GetNetworkCredential().Password
    }
    $BodyJson = ConvertTo-Json -Depth 10 $Body

    $Endpoint = "/PasswordVault/api/Accounts"
    if ($AcceptAllCertificates) {
        $Response = & "$FILE_DIR\Invoke-CyberArkRequest.ps1" -Server $Server -Method "POST" -Endpoint $Endpoint -Body $BodyJson -AuthorizationToken $AuthorizationToken -AcceptAllCertificates
    } else {
        $Response = & "$FILE_DIR\Invoke-CyberArkRequest.ps1" -Server $Server -Method "POST" -Endpoint $Endpoint -Body $BodyJson -AuthorizationToken $AuthorizationToken
    }
    # ErrorCode "PASWS027E": The account already exists in CyberArk.
    $ResponseObj = ConvertFrom-Json $Response.Content
    $AccountId = $ResponseObj.id
    Write-Verbose "Account $AccountId successfully added: $($Response.StatusCode)"

    if ($AsJson) {
        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        $OutputJson = ConvertTo-Json $ResponseObj -Depth 10 -Compress
        # Replace Unicode chars with UTF8
        $ScriptOut = [Regex]::Unescape($OutputJson)
    } else {
        $ScriptOut = $ResponseObj
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
