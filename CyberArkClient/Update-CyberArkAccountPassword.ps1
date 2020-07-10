<#
.SYNOPSIS
    Update the password of an account on a CyberArk server.

.DESCRIPTION
    Update the password of an account on a CyberArk server.

    Also have a look at https://github.com/pspete/psPAS for more functionality.

    CyberArk API documentation can be found here: https://docs.cyberark.com/

    File-Name:  Update-CyberArkAccountPassword.ps1
    Author:     David Wettstein
    Version:    v1.0.2

    Changelog:
                v1.0.2, 2020-05-07, David Wettstein: Reorganize input params.
                v1.0.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.0.0, 2020-03-19, David Wettstein: First implementation.

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
    $Account = & "Update-CyberArkAccountPassword" $Account -Interactive

.EXAMPLE
    $Account = & "$PSScriptRoot\Update-CyberArkAccountPassword" -Account $Account -Password "password" -Server "example.com"
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    $Account  # Account ID or output from Get-CyberArkAccount
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Username = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 6)]
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
    if ($Account.GetType() -eq [String]) {
        $AccountId = $Account
    } else {
        $AccountId = $Account.id
    }
    # If username is given as SecureString string, convert it to plain text.
    try {
        $UsernameSecureString = ConvertTo-SecureString -String $Username -ErrorAction:SilentlyContinue
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
        $Cred = Get-Credential -Message $AccountId -UserName $Username
        if (-not $Cred -or [String]::IsNullOrEmpty($Cred.GetNetworkCredential().Password)) {
            throw "Password is null or empty."
        }
    } else {
        throw "No credentials found. Please use the input parameters or interactive mode."
    }

    $Body = @{
        "ChangeEntireGroup" = $false
        "NewCredentials" = $Cred.GetNetworkCredential().Password
    }
    $BodyJson = ConvertTo-Json -Depth 10 $Body -Compress
    $Endpoint = "/PasswordVault/api/Accounts/$AccountId/Password/Update"
    if ($ApproveAllCertificates) {
        $Response = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "POST" -Endpoint $Endpoint -Body $BodyJson -AuthorizationToken $AuthorizationToken -ApproveAllCertificates
    } else {
        $Response = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "POST" -Endpoint $Endpoint -Body $BodyJson -AuthorizationToken $AuthorizationToken
    }
    if ($Response.StatusCode -lt 200 -or $Response.StatusCode -ge 300) {
        throw "Failed to invoke $($Endpoint): $($Response.StatusCode) - $($Response.Content)"
    }
    Write-Verbose "Password of account $AccountId successfully updated: $($Response.StatusCode)"
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
