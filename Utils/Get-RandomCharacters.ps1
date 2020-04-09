<#
.SYNOPSIS
    Get a random string of given length and characters.

.DESCRIPTION
    Get a random string of given length and characters.

    Defaults:
        - Length: 12
        - Characters: abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789

    File-Name:  Get-RandomCharacters.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2018-08-01, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    Get-RandomCharacters -Length 32

.EXAMPLE
    $RandomString = & "$PSScriptRoot\Utils\Get-RandomCharacters" -Length 32 -Characters "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [Int] $Length = 12
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
# $private:OFS = ","

# Get an array of random numbers.
$Randoms = 1..$Length | ForEach-Object { Get-Random -Maximum $Characters.Length }
# Use empty string as output field separator (special variable $OFS).
$private:OFS = ""
# Generate a string with the characters corresponding to the numbers.
[String] $Characters[$Randoms]
