<#
.SYNOPSIS
    Convert the given username and password to a Base64 encoded string.

.DESCRIPTION
    Convert the given username and password to a Base64 encoded string.

    File-Name:  ConvertTo-Base64String.ps1
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
    .\ConvertTo-Base64String.ps1 -String "username:password"

.EXAMPLE
    $StringInBase64 = & "$PSScriptRoot\Utils\ConvertTo-Base64String.ps1" -String "username:password"
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [String] $String
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

$StringInBytes = [System.Text.Encoding]::UTF8.GetBytes($String)
$StringInBase64 = [System.Convert]::ToBase64String($StringInBytes)
$StringInBase64
