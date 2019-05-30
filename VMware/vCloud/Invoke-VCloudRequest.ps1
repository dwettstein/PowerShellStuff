<#
.SYNOPSIS
    Wrapper cmdlet for directly invoking any vCloud API request using the provided session token or an existing PSCredential for authentication.

.DESCRIPTION
    Wrapper cmdlet for directly invoking any vCloud API request using the provided session token or an existing PSCredential for authentication.

    File-Name:  Invoke-VCloudRequest.ps1
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
    [Xml] $Result = & ".\Invoke-VCloudRequest.ps1" "vcloud.local" "/admin/orgs/query" -SessionToken $VCloudToken

.EXAMPLE
    [Xml] $Result = & "$PSScriptRoot\Invoke-VCloudRequest.ps1" -Server "vcloud.local" -Endpoint "/admin/orgs/query" -Method "GET" -SessionToken $VCloudToken -AcceptAllCertificates
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory=$true, Position=0)]
    [String] $Server
    ,
    [Parameter(Mandatory=$true, Position=1)]
    [String] $Endpoint
    ,
    [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'UPDATE', 'DELETE', IgnoreCase=$true)]  # See also -Method here: https://technet.microsoft.com/en-us/library/hh849901%28v=wps.620%29.aspx
    [Parameter(Mandatory=$false, Position=2)]
    [String] $Method = "GET"
    ,
    [Parameter(Mandatory=$false, Position=3)]
    [String] $Body = $null
    ,
    [Parameter(Mandatory=$false, Position=4)]
    [String] $SessionToken = $null
    ,
    [Parameter(Mandatory=$false, Position=5)]
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

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    if ($AcceptAllCertificates) {
        $CSSource = @'
using System.Net;

public class ServerCertificate {
    public static void approveAllCertificates() {
        ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
    }
}
'@
        Add-Type -TypeDefinition $CSSource

        # Ignore self-signed SSL certificates.
        [ServerCertificate]::approveAllCertificates()

        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
    }

    if ([String]::IsNullOrEmpty($SessionToken)) {
        if ($AcceptAllCertificates) {
            $SessionToken = & "$FILE_DIR\Connect-VCloud.ps1" -Server $Server -AcceptAllCertificates
        } else {
            $SessionToken = & "$FILE_DIR\Connect-VCloud.ps1" -Server $Server
        }
    }

    $BaseUrl = "https://$Server"
    $EndpointUrl = "$BaseUrl/api$endpoint"

    $Headers = @{
        "x-vcloud-authorization" = "$SessionToken"
        "Accept" = "application/*+xml;version=31.0"
    }

    if ($Body) {
        $Response = Invoke-WebRequest -Method $Method -Headers $Headers -Uri $EndpointUrl -Body $Body
    } else {
        $Response = Invoke-WebRequest -Method $Method -Headers $Headers -Uri $EndpointUrl
    }

    $OutputMessage = $Response
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
