<#
.SYNOPSIS
    Approve all certificates, including self-signed and unsecure ones.
    ATTENTION: Using this function is not recommended and unsafe!

.DESCRIPTION
    Approve all certificates, including self-signed and unsecure ones.
    ATTENTION: Using this function is not recommended and unsafe!

    File-Name:  Approve-AllCertificates.ps1
    Author:     David Wettstein
    Version:    1.0.3

    Changelog:
                v1.0.3, 2021-09-13, David Wettstein: Remove deprecated Ssl3 and add Tls1.3 protocol.
                v1.0.2, 2020-10-20, David Wettstein: Add function blocks.
                v1.0.1, 2019-12-17, David Wettstein: Disable certificate revocation check.
                v1.0.0, 2018-08-01, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2021 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    Approve-AllCertificates.ps1

.EXAMPLE
    $null = & "$PSScriptRoot\Utils\Approve-AllCertificates"
#>
[CmdletBinding()]
[OutputType([Void])]
param (
)

begin {
    if (-not $PSBoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","
}

process {
    $CSSource = @'
using System.Net;

public class ServerCertificate {
    public static void approveAllCertificates() {
        ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
    }
}
'@

    if (-not ([System.Management.Automation.PSTypeName]"ServerCertificate").Type) {
        Add-Type -TypeDefinition $CSSource
    }

    # Ignore self-signed SSL certificates.
    [ServerCertificate]::approveAllCertificates()

    # Disable certificate revocation check.
    [System.Net.ServicePointManager]::CheckCertificateRevocationList = $false;

    # Allow all security protocols.
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]"Tls,Tls11,Tls12,Tls13"
}

end {}
