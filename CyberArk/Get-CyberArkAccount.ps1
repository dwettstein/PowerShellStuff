<#
.SYNOPSIS
    Search and get accounts including secrets from a CyberArk server.

.DESCRIPTION
    Search and get accounts including secrets from a CyberArk server.

    Also have a look at https://github.com/pspete/psPAS for more functionality.

    File-Name:  Get-CyberArkAccount.ps1
    Author:     David Wettstein
    Version:    v1.0.1

    Changelog:
                v1.0.1, 2020-03-13, David Wettstein: Change AsObj to AsJson.
                v1.0.0, 2019-07-26, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.LINK
    https://github.com/pspete/psPAS

.EXAMPLE
    $Account = & ".\Get-CyberArkAccount.ps1" "example.com" "query params"

.EXAMPLE
    $Account = & "$PSScriptRoot\Get-CyberArkAccount.ps1" -Server "example.com" -Query "query params" -AsJson
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $true, Position = 1)]
    [String] $Query
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $Safe
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $AsJson
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [String] $AuthorizationToken = $null
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

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    $EncodedQuery = [System.Web.HttpUtility]::UrlEncode($Query)
    $QueryEndpoint = "/PasswordVault/api/Accounts?search=$EncodedQuery"
    if ($Safe) {
        $EncodedSafe = [System.Web.HttpUtility]::UrlEncode("safename eq $Safe")
        $QueryEndpoint += "&filter=$EncodedSafe"
    }

    if ($AcceptAllCertificates) {
        $Response = & "$FILE_DIR\Invoke-CyberArkRequest.ps1" -Server $Server -Method "GET" -Endpoint $QueryEndpoint -AuthorizationToken $AuthorizationToken -AcceptAllCertificates
    } else {
        $Response = & "$FILE_DIR\Invoke-CyberArkRequest.ps1" -Server $Server -Method "GET" -Endpoint $QueryEndpoint -AuthorizationToken $AuthorizationToken
    }
    $ResponseObj = ConvertFrom-Json $Response.Content
    Write-Verbose "Found $($ResponseObj.count) account(s) matching the query '$Query'."

    $Accounts = $ResponseObj.value

    foreach ($Account in $Accounts) {
        $RetrieveEndpoint = "/PasswordVault/api/Accounts/$($Account.id)/Password/Retrieve"
        if ($AcceptAllCertificates) {
            $Response = & "$FILE_DIR\Invoke-CyberArkRequest.ps1" -Server $Server -Method "GET" -Endpoint $RetrieveEndpoint -AuthorizationToken $AuthorizationToken -AcceptAllCertificates
        } else {
            $Response = & "$FILE_DIR\Invoke-CyberArkRequest.ps1" -Server $Server -Method "GET" -Endpoint $RetrieveEndpoint -AuthorizationToken $AuthorizationToken
        }
        Add-Member -InputObject $Account -MemberType NoteProperty -Name "secretValue" -Value $Response.Content.Trim('"') -Force
    }

    if ($AsJson) {
        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        $OutputJson = ConvertTo-Json $Accounts -Depth 10 -Compress
        # Replace Unicode chars with UTF8
        $ScriptOut = [Regex]::Unescape($OutputJson)
    } else {
        $ScriptOut = $Accounts
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
