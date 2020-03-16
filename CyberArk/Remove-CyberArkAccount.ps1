<#
.SYNOPSIS
    Remove an account from a CyberArk server.

.DESCRIPTION
    Remove an account from a CyberArk server.

    Also have a look at https://github.com/pspete/psPAS for more functionality.

    CyberArk API documentation can be found here: https://docs.cyberark.com/

    File-Name:  Remove-CyberArkAccount.ps1
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
    $Result = & ".\Remove-CyberArkAccount.ps1" "example.com" $Account

.EXAMPLE
    $Result = & "$PSScriptRoot\Remove-CyberArkAccount.ps1" -Server "example.com" -Account $Account -AsJson

.EXAMPLE
    & "$PSScriptRoot\Get-CyberArkAccount.ps1" "example.com" "query params" | & "$PSScriptRoot\Remove-CyberArkAccount.ps1" "example.com"
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $Server
    ,
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    $Account  # Account ID or output from Get-CyberArkAccount
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $AuthorizationToken = $null
    ,
    [Parameter(Mandatory = $false, Position = 4)]
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
    if ($Account.GetType() -eq [String]) {
        $AccountId = $Account
    } else {
        $AccountId = $Account.id
    }
    $Endpoint = "/PasswordVault/api/Accounts/$AccountId"
    if ($AcceptAllCertificates) {
        $Response = & "$FILE_DIR\Invoke-CyberArkRequest.ps1" -Server $Server -Method "DELETE" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken -AcceptAllCertificates
    } else {
        $Response = & "$FILE_DIR\Invoke-CyberArkRequest.ps1" -Server $Server -Method "DELETE" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken
    }
    if (-not 200 -le $Response.StatusCode -lt 300 -or $Response.StatusCode -ne 204) {
        throw "Failed to invoke $($Endpoint): $($Response.StatusCode) - $($Response.Content)"
    }
    Write-Verbose "Account $AccountId successfully deleted: $($Response.StatusCode)"
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
