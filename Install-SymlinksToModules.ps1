<#
.SYNOPSIS
    Create symlinks (junctions) to all modules in this repository either in
    - "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\" or
    - "C:\Program Files\WindowsPowerShell\Modules\", if elevated (administrator) permissions.

.DESCRIPTION
    Create symlinks (junctions) to all modules in this repository either in
    - "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\" or
    - "C:\Program Files\WindowsPowerShell\Modules\", if elevated (administrator) permissions.

    File-Name:  Install-SymlinksToModules.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2020-06-02, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    Install-SymlinksToModules
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $Path = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
)

if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "Continue" }
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

#===============================================================================
# Initialization and Functions
#===============================================================================
# Make sure the necessary modules are loaded.
$Modules = @()
$LoadedModules = Get-Module; $Modules | ForEach-Object {
    if ($_ -notin $LoadedModules.Name) { Import-Module $_ -DisableNameChecking }
}

$StartDate = [DateTime]::Now

[String] $FILE_NAME = $MyInvocation.MyCommand.Name
if ($PSVersionTable.PSVersion.Major -lt 3 -or [String]::IsNullOrEmpty($PSScriptRoot)) {
    # Join-Path with empty child path is used to append a path separator.
    [String] $FILE_DIR = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) ""
} else {
    [String] $FILE_DIR = Join-Path $PSScriptRoot ""
}
# if ($MyInvocation.MyCommand.Module) {
#     $FILE_DIR = ""  # If this script is part of a module, we want to call module functions not files.
# }

$ExitCode = 0
$ErrorOut = ""
# $ScriptOut = ""

Write-Verbose "$($FILE_NAME): CALL."

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    $AllModulesPath = $env:PSModulePath -split ';'

    if (& "${FILE_DIR}Utils\Test-Administrator") {
        Write-Verbose "PowerShell sessions has elevated permissions."
        if (-not $PSCmdlet.MyInvocation.BoundParameters.Path) {
            # Get path "C:\Program Files\WindowsPowerShell\Modules\" or similar,
            # if path is not explicitly given as input.
            $Path = $AllModulesPath | Where-Object { $_ -match ".*Program[ a-zA-Z]*\\WindowsPowerShell\\Modules"}
            Write-Verbose "Create symlinks in $Path"
            if (-not ($Path.GetType() -eq [String])) {
                throw "Could not determine unique path, please use the input param."
            }
        }
    }

    if (-not ($Path -in $AllModulesPath)) {
        Write-Warning "$Path is not in `$env:PSModulePath:`n$($env:PSModulePath)"
    }

    if (-not (Test-Path $Path)) {
        Write-Verbose "Folder $Path doesn't exist, create it."
        $null = New-Item -Path $Path -ItemType Directory
    }

    # Get all folders containing a *.psd1 file.
    $ModulesInRepository = Get-ChildItem "${FILE_DIR}*.psd1" -Recurse | Select-Object Directory -Unique | Where-Object {$_ -notmatch ".*Templates.*"}

    foreach ($Mod in $ModulesInRepository) {
        $Link = Join-Path $Path $Mod.Directory.Name
        $Target = $Mod.Directory
        Write-Verbose "Create new symlink from '$Link' to '$Target'."
        & "$env:COMSPEC" /c mklink /j $Link $Target
    }
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction Continue
    $Ex = $_.Exception
    while ($Ex.InnerException) { $Ex = $Ex.InnerException }
    $ErrorOut = "$($Ex.Message)"
    $ExitCode = 1
} finally {
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ([DateTime]::Now - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        # $ScriptOut  # Write ScriptOut to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
