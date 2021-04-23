<#
.SYNOPSIS
    Convert the given UnixTime (seconds since 01/01/1970) to a DateTime object
    by adding the given amount of seconds to a DateTime object refering to the 01/01/1970.

.DESCRIPTION
    Convert the given UnixTime (seconds since 01/01/1970) to a DateTime object
    by adding the given amount of seconds to a DateTime object refering to the 01/01/1970.

    File-Name:  ConvertFrom-UnixTime.ps1
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
    ConvertFrom-UnixTime -UnixTimestamp 1502798835021

.EXAMPLE
    $DateTime = & "$PSScriptRoot\Utils\ConvertFrom-UnixTime" -UnixTimestamp 1502798835021 -UniversalTime -ISO8601
#>
[CmdletBinding()]
[OutputType([DateTime])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [Double] $UnixTimestamp
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $UniversalTime
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [Switch] $ISO8601
)

begin {
    if (-not $PSBoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","
}

process {
    $DateTime = $null
    if ($UnixTimestamp.ToString().Length -eq 13) {
        $DateTime = [DateTime]::ParseExact("19700101", "yyyyMMdd", $null).AddMilliseconds($UnixTimestamp)
    } else {
        $DateTime = [DateTime]::ParseExact("19700101", "yyyyMMdd", $null).AddSeconds($UnixTimestamp)
    }

    if ($UniversalTime) {
        $DateTime = $DateTime.ToLocalTime()
    }

    if ($Iso8601) {
        $DateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")
    } else {
        $DateTime
    }
}

end {}
