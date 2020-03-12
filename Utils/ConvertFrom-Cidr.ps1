<#
.SYNOPSIS
    Convert a given IP address in CIDR notation to its IP address, subnet mask,
    network address and gateway address.

.DESCRIPTION
    Convert a given IP address in CIDR notation to its IP address, subnet mask,
    network address and gateway address.

    File-Name:  ConvertFrom-Cidr.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2020-01-03, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    .\ConvertFrom-Cidr.ps1 -CidrAddress "192.168.0.100/24"

.EXAMPLE
    $IpAddress = & "$PSScriptRoot\Utils\ConvertFrom-Cidr.ps1" -CidrAddress "192.168.0.100/24"
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidatePattern("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/([0-9]|[0-2][0-9]|3[0-2])$")]
    [String] $CidrAddress
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $AsObj
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

# IMPORTANT: The var CidrSuffix has to be of type double!
$IpAddress, [Double] $CidrSuffix = $CidrAddress.Split('/')

# Convert CIDR suffix to subnet mask using bitshift right:
# 1. Get the whole IPv4 address range (indices) as double (4.GB => 32 bits => 255.255.255.255).
# 2. Subtract the number of address indices, which are not needed using bitshift right.
# 3. Cast the address index to an IP address.
$SubnetMask = '' + [IpAddress](4.GB - (4.GB -shr $CidrSuffix))

[IpAddress] $NetworkAddressObj = ([IpAddress]$IpAddress).Address -band ([IpAddress]$SubnetMask).Address
$NetworkAddress = $NetworkAddressObj.IPAddressToString

$GatewayAddress = $NetworkAddress.Remove($NetworkAddress.LastIndexOf('.')) + '.' + (([Int] $NetworkAddress.Split('.')[-1]) + 1)

$ResultObj = New-Object PSObject
$null = Add-Member -InputObject $ResultObj -MemberType NoteProperty -Name "IpAddress" -Value $IpAddress
$null = Add-Member -InputObject $ResultObj -MemberType NoteProperty -Name "SubnetMask" -Value $SubnetMask
$null = Add-Member -InputObject $ResultObj -MemberType NoteProperty -Name "NetworkAddress" -Value $NetworkAddress
$null = Add-Member -InputObject $ResultObj -MemberType NoteProperty -Name "GatewayAddress" -Value $GatewayAddress
$null = Add-Member -InputObject $ResultObj -MemberType NoteProperty -Name "CidrSuffix" -Value $CidrSuffix

if ($AsObj) {
    $ResultObj
} else {
    ConvertTo-Json $ResultObj -Depth 10 -Compress
}
