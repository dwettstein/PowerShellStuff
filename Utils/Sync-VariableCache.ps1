<#
.SYNOPSIS
    Save and/or load a variable from/to a global cache variable, available as long as the session exists.

    If the variable is null or empty, the cmdlet tries to get it using the following order:
        1. Get the variable from VariableCache.
        2. Get the variable from ModuleConfig, if the cmdlet is part of a module.
        3. Throw if the variable is mandatory but not found.

.DESCRIPTION
    Save and/or load a variable from/to a global cache variable, available as long as the session exists.

    If the variable is null or empty, the cmdlet tries to get it using the following order:
        1. Get the variable from VariableCache.
        2. Get the variable from ModuleConfig, if the cmdlet is part of a module.
        3. Throw if the variable is mandatory but not found.

    File-Name:  Sync-VariableCache.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2020-04-07, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    .\Sync-VariableCache.ps1 "MyVar" $MyVar -Verbose

.EXAMPLE
    $MyVar = & "$PSScriptRoot\Utils\Sync-VariableCache.ps1" -VarName "MyVar" -VarValue $MyVar -VariableCachePrefix "Utils" -IsMandatory
#>
[CmdletBinding()]
[OutputType([Object])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $VarName
    ,
    [Parameter(Mandatory = $true, Position = 1)]
    [AllowNull()]
    $VarValue
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $VariableCachePrefix = ""
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $IsMandatory
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

if ($MyInvocation.MyCommand.Module) {
    $ModulePrivateData = $MyInvocation.MyCommand.Module.PrivateData
    Write-Verbose "$($ModulePrivateData.GetEnumerator() | ForEach-Object { "$($_.Name)=$($_.Value)" })"
    if ($ModulePrivateData.ModuleConfig) {
        $ModuleConfig = Get-Variable -Name $ModulePrivateData.ModuleConfig -ValueOnly
        Write-Verbose "$($ModuleConfig.GetEnumerator() | ForEach-Object { "$($_.Name)=$($_.Value)" })"
    }
}

if (-not (Test-Path Variable:\$($VariableCachePrefix + "VariableCache"))) {  # Don't overwrite the variable if it already exists.
    Set-Variable -Name ($VariableCachePrefix + "VariableCache") -Value @{} -Scope "Global"
}
$VariableCache = Get-Variable -Name ($VariableCachePrefix + "VariableCache") -ValueOnly

if ([String]::IsNullOrEmpty($VarValue)) {
    Write-Verbose "$VarName is null or empty. Try to use value from cache or module config. Mandatory variable? $IsMandatory"
    if (-not [String]::IsNullOrEmpty($VariableCache."$VarName")) {
        $VarValue = $VariableCache."$VarName"
        Write-Verbose "Found value in cache: $VarName = $VarValue"
    } elseif (-not [String]::IsNullOrEmpty($ModuleConfig."$VarName")) {
        $VarValue = $ModuleConfig."$VarName"
        Write-Verbose "Found value in module config: $VarName = $VarValue"
    } else {
        if ($IsMandatory) {
            throw "$VarName is null or empty. Please use the input parameters or the module config."
        }
    }
} else {
    Write-Verbose "Update cache with variable: $VarName = $VarValue."
    if ([String]::IsNullOrEmpty($VariableCache."$VarName")) {
        $null = Add-Member -InputObject $VariableCache -MemberType NoteProperty -Name $VarName -Value $VarValue -Force
    } else {
        $VariableCache."$VarName" = $VarValue
    }
}
$VarValue
