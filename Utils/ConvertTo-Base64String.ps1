<#
.SYNOPSIS
    Convert the given username and password to a Base64 encoded string.

.DESCRIPTION
    Convert the given username and password to a Base64 encoded string.

    Filename:   ConvertTo-Base64String.ps1
    Author:     David Wettstein
    Version:    1.0.1

    Changelog:
    - v1.0.1, 2020-10-20, David Wettstein: Add function blocks.
    - v1.0.0, 2018-08-01, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2021 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    ConvertTo-Base64String -String "username:password"

.EXAMPLE
    $StringInBase64 = & "$PSScriptRoot\Utils\ConvertTo-Base64String" -String "username:password"
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $String
)

begin {
    if (-not $PSBoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","
}

process {
    $StringInBytes = [System.Text.Encoding]::UTF8.GetBytes($String)
    $StringInBase64 = [System.Convert]::ToBase64String($StringInBytes)
    $StringInBase64
}

end {}
