<#
.SYNOPSIS
    Approve all certificates, including self-signed and unsecure ones.
    ATTENTION: Using this function is not recommended and unsafe!

.DESCRIPTION
    Approve all certificates, including self-signed and unsecure ones.
    ATTENTION: Using this function is not recommended and unsafe!

    File-Name:  Approve-AllCertificates.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2018-08-01, David Wettstein: First implementation.

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

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

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
