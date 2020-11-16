<#
.SYNOPSIS
    Create a timestamp with current universal time or convert the given DateTime object to UnixTime (seconds since 01/01/1970)
    by creating a time span from 01/01/1970 to the given date and calculate the elapsed seconds.

.DESCRIPTION
    Create a timestamp with current universal time or convert the given DateTime object to UnixTime (seconds since 01/01/1970)
    by creating a time span from 01/01/1970 to the given date and calculate the elapsed seconds.

    File-Name:  ConvertTo-UnixTime.ps1
    Author:     David Wettstein
    Version:    v1.0.1

    Changelog:
                v1.0.1, 2020-10-20, David Wettstein: Add function blocks.
                v1.0.0, 2018-08-01, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    ConvertTo-UnixTime -Milliseconds

.EXAMPLE
    $UnixTimeInMs = & "$PSScriptRoot\Utils\ConvertTo-UnixTime" -DateTime $DateTime -Milliseconds
#>
[CmdletBinding()]
[OutputType([Double])]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [DateTime] $DateTime = (Get-Date)  # Use current date as default value.
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $UniversalTime
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [Switch] $Milliseconds
)

begin {
    if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","
}

process {
    if ($UniversalTime) {
        $DateTime = $DateTime.ToUniversalTime()
    }
    $TimeSpan = New-TimeSpan -Start ([DateTime]::ParseExact("19700101", "yyyyMMdd", $null)) -End $DateTime
    if ($Milliseconds) {
        [System.Math]::Floor($TimeSpan.TotalMilliseconds)
    } else {
        [System.Math]::Floor($TimeSpan.TotalSeconds)
    }
}

end {}
