<#
.SYNOPSIS
    Save and/or load a variable from/to a global cache variable, available as long as the session exists.

.DESCRIPTION
    Save and/or load a variable from/to a global cache variable, available as long as the session exists.

    If the variable is null or empty, the cmdlet tries to get it using the following order:
        1. Get the variable from VariableCache.
        2. Get the variable from ModuleConfig, if the cmdlet is part of a module.
        3. Throw if the variable is mandatory but not found.

    File-Name:  Sync-VariableCache.ps1
    Author:     David Wettstein
    Version:    1.1.1

    Changelog:
                v1.1.1, 2020-10-20, David Wettstein: Add function blocks.
                v1.1.0, 2020-05-07, David Wettstein: Always update cache if not null.
                v1.0.0, 2020-04-07, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    Sync-VariableCache "MyVar" $MyVar -Verbose

.EXAMPLE
    $MyVar = & "$PSScriptRoot\Utils\Sync-VariableCache" -VarName "MyVar" -VarValue $MyVar -VariableCachePrefix "Utils" -IsMandatory
#>
[CmdletBinding()]
[OutputType([Object])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $VarName
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [AllowNull()]
    $VarValue = $null
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $VariableCachePrefix = ""
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $IsMandatory
)

begin {
    if (-not $PSBoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","

    function Get-ModuleConfigVariable($VarName) {
        # First, get ModuleConfig variable if not done yet.
        if ($MyInvocation.MyCommand.Module -and -not $Script:ModuleConfig) {
            $ModulePrivateData = $MyInvocation.MyCommand.Module.PrivateData
            Write-Verbose "$($ModulePrivateData.GetEnumerator() | ForEach-Object { "$($_.Name)=$($_.Value)" })"
            if ($ModulePrivateData.ModuleConfig) {
                $Script:ModuleConfig = Get-Variable -Name $ModulePrivateData.ModuleConfig -ValueOnly
                Write-Verbose "$($Script:ModuleConfig.GetEnumerator() | ForEach-Object { "$($_.Name)=$($_.Value)" })"
            }
        }
        # Then, get the variable value if available.
        if ($Script:ModuleConfig) {
            if (-not [String]::IsNullOrEmpty($Script:ModuleConfig."$VarName")) {
                $VarValue = $Script:ModuleConfig."$VarName"
                Write-Verbose "Found variable in module config: $VarName = $VarValue"
                $VarValue
            } else {
                Write-Verbose "Variable was not found in module config: $VarName"
                $null  # If variable not found in config, return null.
            }
        }
    }
}

process {
    #trap { Write-Error "$($_.Exception)"; $ExitCode = 1; break; }

    if (-not (Test-Path Variable:\$($VariableCachePrefix + "VariableCache"))) {  # Don't overwrite the variable if it already exists.
        Set-Variable -Name ($VariableCachePrefix + "VariableCache") -Value @{} -Scope "Global"
    }
    $VariableCache = Get-Variable -Name ($VariableCachePrefix + "VariableCache") -ValueOnly

    if ([String]::IsNullOrEmpty($VarValue)) {
        Write-Verbose "Variable $VarName is null or empty. Try to use value from cache or module config. Mandatory variable? $IsMandatory"
        if (-not [String]::IsNullOrEmpty($VariableCache."$VarName")) {
            $VarValue = $VariableCache."$VarName"
            Write-Verbose "Found variable in cache: $VarName = $VarValue"
        } else {
            $VarValue = Get-ModuleConfigVariable $VarName
        }

        if ($IsMandatory -and -not $VarValue) {
            throw "Variable $VarName is null or empty. Please use the input parameters or the module config."
        }
    }

    if (-not [String]::IsNullOrEmpty($VarValue)) {
        Write-Verbose "Update cache with variable: $VarName = $VarValue."
        if ([String]::IsNullOrEmpty($VariableCache."$VarName")) {
            $null = Add-Member -InputObject $VariableCache -MemberType NoteProperty -Name $VarName -Value $VarValue -Force
        } else {
            $VariableCache."$VarName" = $VarValue
        }
    }

    $VarValue
}

end {}
