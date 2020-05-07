<#
.SYNOPSIS
    Wrapper cmdlet for directly invoking any RESTful API request on the given server,
    using the provided authorization token, e.g. "Basic username:password", or an existing PSCredential for authentication.

.DESCRIPTION
    Wrapper cmdlet for directly invoking any RESTful API request on the given server,
    using the provided authorization token, e.g. "Basic username:password", or an existing PSCredential for authentication.

    File-Name:  Invoke-ServerRequest.ps1
    Author:     David Wettstein
    Version:    v2.0.0

    Changelog:
                v2.0.0, 2020-04-23, David Wettstein: Refactor and get rid of PowerNSX.
                v1.1.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.1.0, 2020-04-07, David Wettstein: Sync input variables with cache.
                v1.0.1, 2020-03-13, David Wettstein: Refactor and generalize cmdlet.
                v1.0.0, 2019-05-30, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    $Result = & "Invoke-ServerRequest" "example.com" "/api/v1/version" -AuthorizationToken $AuthorizationToken

.EXAMPLE
    [Xml] $Result = & "$PSScriptRoot\Invoke-ServerRequest" -Server "example.com" -Endpoint "/api/v1/version" -Method "GET" -MediaType "application/*+xml" -ApproveAllCertificates
#>
[CmdletBinding()]
[OutputType([Object])]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Endpoint
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'UPDATE', 'DELETE')]
    [String] $Method = "GET"
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [ValidateNotNullOrEmpty()]
    [String] $Body = $null
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [ValidateSet('application/*', 'application/json', 'application/xml', 'application/*+xml', 'application/x-www-form-urlencoded', 'multipart/form-data', 'text/plain', 'text/xml', IgnoreCase = $false)]
    [String] $MediaType = "application/xml"
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [ValidateNotNullOrEmpty()]
    [String] $AuthorizationHeader = "Authorization"
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [ValidateSet('http', 'https', IgnoreCase = $false)]
    [String] $Protocol = "https"
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
    $Server = & "${FILE_DIR}Sync-NsxVariableCache" "Server" $Server -IsMandatory
    $AuthorizationToken = & "${FILE_DIR}Sync-NsxVariableCache" "AuthorizationToken" $AuthorizationToken
    $ApproveAllCertificates = & "${FILE_DIR}Sync-NsxVariableCache" "ApproveAllCertificates" $ApproveAllCertificates

    $BaseUrl = "${Protocol}://$Server"
    $EndpointUrl = "${BaseUrl}${Endpoint}"

    $Headers = @{
        "Accept" = "$MediaType"
        "Content-Type" = "$MediaType"
        "Cache-Control" = "no-cache"
    }

    # If no AuthorizationToken is given, try to get it.
    if ([String]::IsNullOrEmpty($AuthorizationToken)) {
        if ($ApproveAllCertificates) {
            $AuthorizationToken = & "${FILE_DIR}Connect-Nsx" -Server $Server -ApproveAllCertificates
        } else {
            $AuthorizationToken = & "${FILE_DIR}Connect-Nsx" -Server $Server
        }
    }
    # If AuthorizationToken is given as SecureString string, convert it to plain text.
    try {
        $AuthorizationTokenSecureString = ConvertTo-SecureString -String $AuthorizationToken
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AuthorizationTokenSecureString)
        $AuthorizationToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        $null = [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    } catch {
        # AuthorizationToken was already given as plain text.
    }
    if (-not [String]::IsNullOrEmpty($AuthorizationToken)) {
        $Headers."$AuthorizationHeader" = "$AuthorizationToken"
    }

    if ($Body) {
        $Response = Invoke-WebRequest -Method $Method -Headers $Headers -Uri $EndpointUrl -Body $Body
    } else {
        $Response = Invoke-WebRequest -Method $Method -Headers $Headers -Uri $EndpointUrl
    }

    $ScriptOut = $Response
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
