<#
.SYNOPSIS
    Convert the given UnixTime (seconds since 01/01/1970) to a DateTime object by adding the given amount of seconds to a DateTime object refering to the 01/01/1970.

.DESCRIPTION
    Convert the given UnixTime (seconds since 01/01/1970) to a DateTime object by adding the given amount of seconds to a DateTime object refering to the 01/01/1970.

    File-Name:  ConvertFrom-UnixTime.ps1
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
    .\ConvertFrom-UnixTime.ps1 -UnixTimestamp 1502798835021

.EXAMPLE
    $DateTime = & "$PSScriptRoot\Utils\ConvertFrom-UnixTime.ps1" -UnixTimestamp 1502798835021 -ToUniversalTime
#>
[CmdletBinding()]
[OutputType([DateTime])]
param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
    [Double] $UnixTimestamp
    ,
    [Parameter(Mandatory=$false, Position=1)]
    [Switch] $ToUniversalTime = $false
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

$DateTime = $null
if ($UnixTimestamp.ToString().Length -eq 13) {
    $DateTime = [DateTime]::ParseExact("19700101", "yyyyMMdd", $null).AddMilliseconds($UnixTimestamp)
} else {
    $DateTime = [DateTime]::ParseExact("19700101", "yyyyMMdd", $null).AddSeconds($UnixTimestamp)
}

if ($ToUniversalTime) {
    $DateTime.ToUniversalTime()
} else {
    $DateTime
}
