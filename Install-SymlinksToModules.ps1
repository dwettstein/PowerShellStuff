<#
.SYNOPSIS
    Create symlinks (junctions) to all modules in this repository either in
    - "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\" or
    - "C:\Program Files\WindowsPowerShell\Modules\", if elevated (administrator) permissions.

.DESCRIPTION
    Create symlinks (junctions) to all modules in this repository either in
    - "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\" or
    - "C:\Program Files\WindowsPowerShell\Modules\", if elevated (administrator) permissions.

    Filename:   Install-SymlinksToModules.ps1
    Author:     David Wettstein
    Version:    1.0.2

    Changelog:
    - v1.0.2, 2020-12-01, David Wettstein: Refactor error handling.
    - v1.0.1, 2020-10-20, David Wettstein: Add function blocks.
    - v1.0.0, 2020-06-02, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2021 David Wettstein,
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

begin {
    if (-not $PSBoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.WarningAction) { $WarningPreference = "Continue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","

    $StartDate = [DateTime]::Now
    $ExitCode = 0
    $ErrorOut = ""

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

    Write-Verbose "$($FILE_NAME): CALL."

    # Make sure the necessary modules are loaded.
    # By default, this will load the latest version. Else, add the full path of *.psd1 to the list.
    $Modules = @()
    $Modules | ForEach-Object { Get-Module $_ -ListAvailable | Import-Module -DisableNameChecking }
}

process {
    #trap { Write-Error "$($_.Exception)"; $ExitCode = 1; break; }
    # $ScriptOut = ""
    try {
        $AllModulesPath = $env:PSModulePath -split ";"

        if (& "${FILE_DIR}Utils\Test-Administrator") {
            Write-Verbose "PowerShell sessions has elevated permissions."
            if (-not $PSBoundParameters.Path) {
                # Get path "C:\Program Files\WindowsPowerShell\Modules\" or similar,
                # if path is not explicitly given as input.
                $Path = $AllModulesPath | Where-Object { $_ -match ".*Program[ a-zA-Z]*\\WindowsPowerShell\\Modules"}
                Write-Verbose "Create symlinks in $Path"
                if (-not ($Path.GetType() -eq [String])) {
                    throw "Could not determine unique path, please use the input param."
                }
            }
        }

        if (-not ($Path -in $AllModulesPath -or $Path.Trim("\") -in $AllModulesPath)) {
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

        #$ScriptOut  # Write $ScriptOut to output stream.
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction:Continue
        $Ex = $_.Exception; while ($Ex.InnerException) { $Ex = $Ex.InnerException }
        # Add error to $ErrorOut and continue with next item to process or end block.
        $ErrorOut += if ($ErrorOut) { "`n$($Ex.Message)" } else { "$($Ex.Message)" }
        $ExitCode = 1
    } finally {
    }
}

end {
    Write-Verbose "$($FILE_NAME): ExitCode: $ExitCode. Execution time: $(([DateTime]::Now - $StartDate).TotalMilliseconds) ms. Started: $($StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))."
    # Set the script/function exit code. Can be accessed with `$LASTEXITCODE` automatic variable.
    # Don't use `exit $ExitCode` as it also exits the console itself when invoked as module function.
    & "powershell.exe" "-NoLogo" "-NoProfile" "-NonInteractive" "-Command" "exit $ExitCode"
    if ((-not [String]::IsNullOrEmpty($ErrorOut)) -or $ExitCode -ne 0) {
        Write-Error "$ErrorOut"
    }
}
