<#
.SYNOPSIS
    Approve all certificates, including self-signed and unsecure ones.
    ATTENTION: Using this function is not recommended and unsafe!

.DESCRIPTION
    Approve all certificates, including self-signed and unsecure ones.
    ATTENTION: Using this function is not recommended and unsafe!

    File-Name:  Approve-AllCertificates.ps1
    Author:     David Wettstein
    Version:    v1.0.1

    Changelog:
                v1.0.0, 2018-08-01, David Wettstein: First implementation.
                v1.0.1, 2019-12-17, David Wettstein: Disable certificate revocation check.

.NOTES
    Copyright (c) 2018 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    .\Approve-AllCertificates.ps1

.EXAMPLE
    $null = & "$PSScriptRoot\Utils\Approve-AllCertificates.ps1"
#>
[CmdletBinding()]
#[OutputType([Int])]
param (
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

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
