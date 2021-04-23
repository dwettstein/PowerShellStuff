<#
.SYNOPSIS
    Test if the current PowerShell session has elevated (administrator) permissions.

.DESCRIPTION
    Test if the current PowerShell session has elevated (administrator) permissions.

    File-Name:  Test-Administrator.ps1
    Author:     David Wettstein
    Version:    1.0.1

    Changelog:
                v1.0.1, 2020-10-20, David Wettstein: Add function blocks.
                v1.0.0, 2020-06-02, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.LINK
    https://ss64.com/ps/syntax-elevate.html

.EXAMPLE
    Test-Administrator
#>
[CmdletBinding()]
[OutputType([Boolean])]
param ()

begin {
    if (-not $PSBoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","
}

process {
    $IsAdmin = $False
    try {
        $CurrentPrincipal = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent())
        $IsAdmin = $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        Write-Verbose "Failed to test if the current principal is in the Administrator group. Error: $($_.Exception)"
    }
    $IsAdmin
}

end {}
