<#
.SYNOPSIS
    Create a timestamp with current universal time or convert the given DateTime object to UnixTime (seconds since 01/01/1970) by creating a time span from 01/01/1970 to the given date and calculate the elapsed seconds.

.DESCRIPTION
    Create a timestamp with current universal time or convert the given DateTime object to UnixTime (seconds since 01/01/1970) by creating a time span from 01/01/1970 to the given date and calculate the elapsed seconds.

    File-Name:  ConvertTo-UnixTime.ps1
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
    .\ConvertTo-UnixTime.ps1 -WithMilliseconds

.EXAMPLE
    [String] $FILE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $UnixTimeInMs = & "$FILE_DIR\Utils\ConvertTo-UnixTime.ps1" -DateTime $DateTime -WithMilliseconds
#>
[CmdletBinding()]
[OutputType([Double])]
param (
    [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=0)]
    [DateTime] $DateTime = (Get-Date).ToUniversalTime()  # Use current date as default value.
    ,
    [Parameter(Mandatory=$false, Position=1)]
    [Switch] $WithMilliseconds = $false
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

if ($WithMilliseconds) {
    [System.Math]::Floor((New-TimeSpan -Start ([DateTime]::ParseExact("19700101", "yyyyMMdd", $null)) -End $DateTime).TotalMilliseconds)
} else {
    [System.Math]::Floor((New-TimeSpan -Start ([DateTime]::ParseExact("19700101", "yyyyMMdd", $null)) -End $DateTime).TotalSeconds)
}
