<#
.SYNOPSIS
    Search and get accounts including secrets from a CyberArk server.

.DESCRIPTION
    Search and get accounts including secrets from a CyberArk server.

    Also have a look at https://github.com/pspete/psPAS for more functionality.

    File-Name:  Get-CyberArkAccount.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2019-07-26, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.LINK
    https://github.com/pspete/psPAS

.EXAMPLE
    Example of how to use this cmdlet
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
    [Switch] $AsObj
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [String] $Username = "${env:USERNAME}"  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 5)]
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
    $CyberArkToken = & "$FILE_DIR\Connect-CyberArk.ps1" -Server $Server -Username $Username -Password $Password

    $BaseUrl = "https://$Server"
    $EncodedQuery = [System.Web.HttpUtility]::UrlEncode($Query)
    $EndpointUrl = "$BaseUrl/PasswordVault/api/Accounts?search=$EncodedQuery"
    if ($Safe) {
        $EncodedSafe = [System.Web.HttpUtility]::UrlEncode("safename eq $Safe")
        $EndpointUrl += "&filter=$EncodedSafe"
    }

    $Headers = @{
        "Authorization" = $CyberArkToken
        "Accept" = "application/json"
        "Content-Type" = "application/json"
        "Cache-Control" = "no-cache"
    }

    $Response = Invoke-WebRequest -Method Get -Headers $Headers -Uri $EndpointUrl
    $ResponseObj = ConvertFrom-Json $Response.Content
    Write-Verbose "Found $($ResponseObj.count) account(s) matching the query '$Query'."

    $Accounts = $ResponseObj.value

    foreach ($Account in $Accounts) {
        $EndpointUrl = "$BaseUrl/PasswordVault/api/Accounts/$($Account.id)/Password/Retrieve"
        $Response = Invoke-WebRequest -Method Post -Headers $Headers -Uri $EndpointUrl
        Add-Member -InputObject $Account -MemberType NoteProperty -Name "secretValue" -Value $Response.Content.Trim('"') -Force
    }

    if ($AsObj) {
        $ScriptOut = $Accounts
    } else {
        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        $OutputJson = ConvertTo-Json $Accounts -Depth 10 -Compress
        # Replace Unicode chars with UTF8
        $ScriptOut = [Regex]::Unescape($OutputJson)
    }
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())" -WarningAction Continue
    $ErrorOut = "$($_.Exception.Message)"
    $ExitCode = 1
} finally {
    if ($null -ne $CyberArkToken) {
        $null = Invoke-WebRequest -Method Post -Headers @{"Authorization" = $CyberArkToken } -Uri "$BaseUrl/PasswordVault/api/auth/Logoff"
    }

    $EndDate = [DateTime]::Now
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ($EndDate - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        $ScriptOut  # Write ScriptOut to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
