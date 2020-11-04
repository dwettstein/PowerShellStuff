<#
.SYNOPSIS
    Repair an existing scoop installation:
    - 'current' symlink for scoop itself
    - Reset all apps (re-creates 'current' symlinks too)
    - Unzip archive from https://github.com/lukesampson/scoop

.DESCRIPTION
    Repair an existing scoop installation:
    - 'current' symlink for scoop itself
    - Reset all apps (re-creates 'current' symlinks too)
    - Unzip archive from https://github.com/lukesampson/scoop

    File-Name:  Repair-Scoop.ps1
    Author:     David Wettstein
    Version:    v1.1.1

    Changelog:
                v1.1.1, 2020-10-20, David Wettstein: Add function blocks.
                v1.1.0, 2020-10-17, David Wettstein: Add switch to install Scoop as usual.
                v1.0.0, 2020-05-13, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.LINK
    https://github.com/lukesampson/scoop

.EXAMPLE
    Repair-Scoop -Symlink -ResetAll -Proxy "http://proxy.example.com:8080"

.EXAMPLE
    Repair-Scoop -Symlink -ResetAll -UnzipFromPath "$HOME\scoop-master.zip" -Proxy "http://proxy.example.com:8080"
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [Switch] $Install
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $Symlink
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [Switch] $ResetAll
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [ValidateNotNullOrEmpty()]
    [String] $UnzipFromPath = $null
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [String] $Proxy = $null
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [PSCredential] $ProxyCredential = $null
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [ValidateNotNullOrEmpty()]
    [String] $ScoopHome = "$HOME\scoop\apps\scoop\"
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [ValidateNotNullOrEmpty()]
    [String] $ScoopVersion = "master"
    ,
    [Parameter(Mandatory = $false, Position = 8)]
    [ValidateNotNullOrEmpty()]
    [String] $ScoopVersionPrefix = "scoop-"
)

begin {
    if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","

    $StartDate = [DateTime]::Now
    $ExitCode = 0

    [String] $FILE_NAME = $MyInvocation.MyCommand.Name
    if ($PSVersionTable.PSVersion.Major -lt 3 -or [String]::IsNullOrEmpty($PSScriptRoot)) {
        # Join-Path with empty child path is used to append a path separator.
        [String] $FILE_DIR = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) ""
    } else {
        [String] $FILE_DIR = Join-Path $PSScriptRoot ""
    }
    if ($MyInvocation.MyCommand.Module) {
        $FILE_DIR = ""  # If this script is part of a module, we want to call module functions not files.
    }

    Write-Verbose "$($FILE_NAME): CALL."

    # Make sure the necessary modules are loaded.
    $Modules = @()
    $LoadedModules = Get-Module; $Modules | ForEach-Object {
        if ($_ -notin $LoadedModules.Name) { Import-Module $_ -DisableNameChecking }
    }
}

process {
    #trap { Write-Error "$($_.Exception)"; $ExitCode = 1; break; }
    # $ScriptOut = ""
    $ErrorOut = ""

    try {
        if ($Install -and [String]::IsNullOrEmpty($UnzipFromPath)) {
            Invoke-Expression (New-Object System.Net.WebClient).DownloadString("https://get.scoop.sh")
        }

        if (-not [String]::IsNullOrEmpty($UnzipFromPath)) {
            Write-Verbose "Unzip from '$UnzipFromPath' to '$ScoopHome'."
            Add-Type -Assembly "System.IO.Compression.FileSystem"
            [IO.Compression.ZipFile]::ExtractToDirectory($UnzipFromPath, $ScoopHome)
        }

        if ($Symlink) {
            Write-Verbose "Try to find existing version folder:"
            $VersionDir = Join-Path $ScoopHome $ScoopVersion
            Write-Verbose "$VersionDir"
            if (-not (Test-Path $VersionDir)) {
                $VersionDir = Join-Path $ScoopHome "${ScoopVersionPrefix}${ScoopVersion}"
                Write-Verbose "$VersionDir"
                if (-not (Test-Path $VersionDir)) {
                    throw "Unknown version folder under '$ScoopHome', use param '-ScoopVersion' or '-UnzipFromPath' with a ZIP from: https://github.com/lukesampson/scoop"
                }
            }

            $CurrentDir = Join-Path $ScoopHome "current"
            if (Test-Path $CurrentDir) {
                Write-Verbose "Remove existing current folder '$CurrentDir'."
                Remove-Item $CurrentDir -Force -Recurse
            }

            Write-Verbose "Create new symlink from '$CurrentDir' to '$VersionDir'."
            & "$env:COMSPEC" /c mklink /j $CurrentDir $VersionDir
            $null = attrib $CurrentDir +R /L
        }

        if ($ResetAll) {
            $null = & "${FILE_DIR}Set-DefaultWebProxy" -Proxy $Proxy -Credential $ProxyCredential

            Write-Verbose "Reset all existing scoop apps."
            $ErrorActionPreference = "Continue"
            & "$env:COMSPEC" /c scoop reset *
        }
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction Continue
        $Ex = $_.Exception; while ($Ex.InnerException) { $Ex = $Ex.InnerException }
        $ErrorOut = "$($Ex.Message)"
        $ExitCode = 1
    } finally {
        if ([String]::IsNullOrEmpty($ErrorOut)) {
             # $ScriptOut  # Write ScriptOut to output stream.
        } else {
            Write-Error "$ErrorOut"  # Use Write-Error only here.
        }
    }
}

end {
    Write-Verbose "$($FILE_NAME): ExitCode: $ExitCode. Execution time: $(([DateTime]::Now - $StartDate).TotalMilliseconds) ms. Started: $($StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))."
    # exit $ExitCode
}
