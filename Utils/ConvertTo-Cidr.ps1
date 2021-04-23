<#
.SYNOPSIS
    Convert a given IP address and subnet mask to its equal CIDR notation.
    Default subnet mask is 255.255.255.0 or /24.

.DESCRIPTION
    Convert a given IP address and subnet mask to its equal CIDR notation.
    Default subnet mask is 255.255.255.0 or /24.

    File-Name:  ConvertTo-Cidr.ps1
    Author:     David Wettstein
    Version:    1.0.1

    Changelog:
                v1.0.1, 2020-10-20, David Wettstein: Add function blocks.
                v1.0.0, 2020-01-03, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    ConvertTo-Cidr.ps1 -IpAddress "192.168.0.100"

.EXAMPLE
    $CidrAddress = & "$PSScriptRoot\Utils\ConvertTo-Cidr" -IpAddress "192.168.0.100" -SubnetMask "255.255.0.0"
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidatePattern("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")]
    [String] $IpAddress
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidatePattern("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")]
    [String] $SubnetMask = "255.255.255.0"
)

begin {
    if (-not $PSBoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","
}

process {
    $SubnetMaskBinary = [Convert]::ToString(([IpAddress]$SubnetMask).Address, 2)
    $CidrSuffix = ($SubnetMaskBinary -replace 0, $null).Length  # Only count the 1's, remove the 0's.

    $CidrAddress = "$IpAddress/$CidrSuffix"
    $CidrAddress
}

end {}
