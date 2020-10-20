<#
.SYNOPSIS
    Approve all certificates, including self-signed and unsecure ones.
    ATTENTION: Using this function is not recommended and unsafe!

.DESCRIPTION
    Approve all certificates, including self-signed and unsecure ones.
    ATTENTION: Using this function is not recommended and unsafe!

    File-Name:  Approve-AllCertificates.ps1
    Author:     David Wettstein
    Version:    v1.0.2

    Changelog:
                v1.0.2, 2020-10-20, David Wettstein: Add function blocks.
                v1.0.1, 2019-12-17, David Wettstein: Disable certificate revocation check.
                v1.0.0, 2018-08-01, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
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
    if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
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

    if (-not ([System.Management.Automation.PSTypeName]'ServerCertificate').Type) {
        Add-Type -TypeDefinition $CSSource
    }

    # Ignore self-signed SSL certificates.
    [ServerCertificate]::approveAllCertificates()

    # Disable certificate revocation check.
    [System.Net.ServicePointManager]::CheckCertificateRevocationList = $false;

    # Allow all security protocols.
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
}

end {}
