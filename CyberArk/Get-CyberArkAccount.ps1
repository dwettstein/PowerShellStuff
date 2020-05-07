<#
.SYNOPSIS
    Search and get accounts including secrets from a CyberArk server.

.DESCRIPTION
    Search and get accounts including secrets from a CyberArk server.

    Also have a look at https://github.com/pspete/psPAS for more functionality.

    CyberArk API documentation can be found here: https://docs.cyberark.com/

    File-Name:  Get-CyberArkAccount.ps1
    Author:     David Wettstein
    Version:    v1.2.1

    Changelog:
                v1.2.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.2.0, 2020-03-19, David Wettstein: Implement get account by id.
                v1.1.0, 2020-03-15, David Wettstein: Add more switches, use SecureString as default.
                v1.0.1, 2020-03-13, David Wettstein: Change AsObj to AsJson.
                v1.0.0, 2019-07-26, David Wettstein: First implementation.

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
    $Account = & "Get-CyberArkAccount" "example.com" "query params"

.EXAMPLE
    $Account = & "$PSScriptRoot\Get-CyberArkAccount" -Server "example.com" -Query "query params" -AsJson
#>
[CmdletBinding()]
[OutputType([PSObject])]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Query
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $Safe
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [ValidateNotNullOrEmpty()]
    $Account  # Account ID or output from Get-CyberArkAccount
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Switch] $AsCredential
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [Switch] $AsPlainText
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [Switch] $AsJson
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 8)]
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

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    if (-not [String]::IsNullOrEmpty($Account)) {
        if ($Account.GetType() -eq [String]) {
            $AccountId = $Account
        } else {
            $AccountId = $Account.id
        }
        $Endpoint = "/PasswordVault/api/Accounts/$AccountId"
        if ($ApproveAllCertificates) {
            $Response = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "GET" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken -ApproveAllCertificates
        } else {
            $Response = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "GET" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken
        }
        Write-Verbose "Account $AccountId successfully found: $($Response.StatusCode)"
        $ResponseObj = ConvertFrom-Json $Response.Content
        $Accounts = @()
        $Accounts += $ResponseObj
    } else {
        if ([String]::IsNullOrEmpty($Query)) {
            throw "One of parameter Query or Account is mandatory!"
        }
        Add-Type -AssemblyName System.Web
        $EncodedQuery = [System.Web.HttpUtility]::UrlEncode($Query)
        $QueryEndpoint = "/PasswordVault/api/Accounts?search=$EncodedQuery"
        if ($Safe) {
            $EncodedSafe = [System.Web.HttpUtility]::UrlEncode("safename eq $Safe")
            $QueryEndpoint += "&filter=$EncodedSafe"
        }

        if ($ApproveAllCertificates) {
            $Response = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "GET" -Endpoint $QueryEndpoint -AuthorizationToken $AuthorizationToken -ApproveAllCertificates
        } else {
            $Response = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "GET" -Endpoint $QueryEndpoint -AuthorizationToken $AuthorizationToken
        }
        $ResponseObj = ConvertFrom-Json $Response.Content
        Write-Verbose "Found $($ResponseObj.count) account(s) matching the query '$Query'."
        $Accounts = $ResponseObj.value
    }

    foreach ($Account in $Accounts) {
        $RetrieveEndpoint = "/PasswordVault/api/Accounts/$($Account.id)/Password/Retrieve"
        if ($ApproveAllCertificates) {
            $RetrieveResponse = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "POST" -Endpoint $RetrieveEndpoint -AuthorizationToken $AuthorizationToken -ApproveAllCertificates
        } else {
            $RetrieveResponse = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "POST" -Endpoint $RetrieveEndpoint -AuthorizationToken $AuthorizationToken
        }
        $Password = $RetrieveResponse.Content.Trim('"')

        if ($AsPlainText) {
            Add-Member -InputObject $Account -MemberType NoteProperty -Name "secretValue" -Value $Password -Force
        } else {
            if (-not [String]::IsNullOrEmpty($Password)) {
                $PasswordSecureString = ConvertTo-SecureString -AsPlainText -Force $Password
            }
            Add-Member -InputObject $Account -MemberType NoteProperty -Name "secretValue" -Value (ConvertFrom-SecureString $PasswordSecureString) -Force
        }
    }

    if ($AsJson) {
        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        $OutputJson = ConvertTo-Json $Accounts -Depth 10 -Compress
        # Replace Unicode chars with UTF8
        $ScriptOut = [Regex]::Unescape($OutputJson)
    } else {
        if ($AsCredential) {
            $ScriptOut = @()
            foreach ($Account in $Accounts) {
                try {
                    $PasswordSecureString = ConvertTo-SecureString -String $Account.secretValue
                } catch [System.FormatException] {
                    # Password was likely given as plain text, convert it to SecureString.
                    $PasswordSecureString = ConvertTo-SecureString -AsPlainText -Force $Account.secretValue
                }
                $Cred = New-Object System.Management.Automation.PSCredential ($Account.userName, $PasswordSecureString)
                $ScriptOut += $Cred
            }
        } else {
            $ScriptOut = $Accounts
        }
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
