<#
.SYNOPSIS
    Convert the given Base64 encoded string to username and password strings (hashtable).

.DESCRIPTION
    Convert the given Base64 encoded string to username and password strings (hashtable).

    File-Name:  ConvertFrom-Base64String.ps1
    Author:     David Wettstein
    Version:    1.0.1

    Changelog:
                v1.0.1, 2020-10-20, David Wettstein: Add function blocks.
                v1.0.0, 2018-08-01, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    ConvertFrom-Base64String -String "dXNlcm5hbWU6cGFzc3dvcmQ="

.EXAMPLE
    $String = & "$PSScriptRoot\Utils\ConvertFrom-Base64String" -String "dXNlcm5hbWU6cGFzc3dvcmQ="
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $String
)

begin {
    if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","
}

process {
    $StringInBytes = [System.Convert]::FromBase64String($String)
    $StringPlainText = [System.Text.Encoding]::UTF8.GetString($StringInBytes, 0, $StringInBytes.length)
    $StringPlainText
}

end {}
