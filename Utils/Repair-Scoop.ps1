<#
.SYNOPSIS
    Repair an existing scoop installation.

.DESCRIPTION
    Repair an existing scoop installation:
        - Re-create 'current' symlink for scoop itself
        - Reset and cleanup all apps (re-creates 'current' symlinks for apps too)
        - Unzip archive from https://github.com/lukesampson/scoop
        - Change Scoop to Shovel (see https://github.com/Ash258/Scoop-Core)

    Filename:   Repair-Scoop.ps1
    Author:     David Wettstein
    Version:    1.3.1

    Changelog:
    - v1.3.1, 2021-04-29, David Wettstein: Do -UnzipFromPath earlier.
    - v1.3.0, 2021-04-23, David Wettstein: Add switch to change Scoop to Shovel.
    - v1.2.1, 2020-12-01, David Wettstein: Refactor error handling.
    - v1.2.0, 2020-11-23, David Wettstein: Allow non-standard home dirs.
    - v1.1.1, 2020-10-20, David Wettstein: Add function blocks.
    - v1.1.0, 2020-10-17, David Wettstein: Add switch to install Scoop as usual.
    - v1.0.0, 2020-05-13, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2021 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.LINK
    https://github.com/ScoopInstaller/Scoop

.EXAMPLE
    Repair-Scoop -Symlink -ResetAll -Proxy "http://proxy.example.com:8080"

.EXAMPLE
    Repair-Scoop -Install -InstallShovel -UnzipFromPath "$HOME\scoop-master.zip" -Proxy "http://proxy.example.com:8080" -ApproveAllCertificates
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [Switch] $Install
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    # Change Scoop to Shovel (see https://github.com/Ash258/Scoop-Core)
    [Switch] $InstallShovel
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [Switch] $Symlink
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $ResetAll
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [ValidateNotNullOrEmpty()]
    [String] $UnzipFromPath = $null
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [String] $Proxy = $null
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [PSCredential] $ProxyCredential = $null
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [Switch] $SetScoopHomeEnv
    ,
    [Parameter(Mandatory = $false, Position = 8)]
    [ValidateNotNullOrEmpty()]
    [String] $ScoopHome = $(if (-not [String]::IsNullOrEmpty($env:SCOOP)) { $env:SCOOP } else { "$HOME\scoop\" })
    ,
    [Parameter(Mandatory = $false, Position = 9)]
    [ValidateNotNullOrEmpty()]
    [String] $ScoopAppHome = "$ScoopHome\apps\scoop\"
    ,
    [Parameter(Mandatory = $false, Position = 10)]
    [ValidateNotNullOrEmpty()]
    [String] $ScoopAppVersion = "master"
    ,
    [Parameter(Mandatory = $false, Position = 11)]
    [ValidateNotNullOrEmpty()]
    [String] $ScoopAppVersionPrefix = "scoop-"
    ,
    [Parameter(Mandatory = $false, Position = 12)]
    [Alias("Insecure")]
    [Switch] $ApproveAllCertificates
)

begin {
    if (-not $PSBoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
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
    if ($MyInvocation.MyCommand.Module) {
        $FILE_DIR = ""  # If this script is part of a module, we want to call module functions not files.
    }

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
        if ($SetScoopHomeEnv) {
            $env:SCOOP = $ScoopHome
            [System.Environment]::SetEnvironmentVariable("SCOOP", $ScoopHome, "User")
        }

        if ($ApproveAllCertificates) {
            $null = & "${FILE_DIR}Approve-AllCertificates"
        }

        if ($Proxy -or $ProxyCredential) {
            $null = & "${FILE_DIR}Set-DefaultWebProxy" -Proxy $Proxy -Credential $ProxyCredential
        }

        if (-not [String]::IsNullOrEmpty($UnzipFromPath)) {
            Write-Verbose "Unzip from '$UnzipFromPath' to '$ScoopAppHome'."
            Add-Type -Assembly "System.IO.Compression.FileSystem"
            [IO.Compression.ZipFile]::ExtractToDirectory($UnzipFromPath, $ScoopAppHome)
        } elseif ($Install) {
            # If -UnzipFromPath is given, don't do -Install.
            Invoke-Expression (New-Object System.Net.WebClient).DownloadString("https://get.scoop.sh")
        }

        if ($InstallShovel) {
            # Change Scoop to Shovel (see https://github.com/Ash258/Scoop-Core)
            if ((& "$env:COMSPEC" /c scoop config 7ZIPEXTRACT_USE_EXTERNAL) -ne $true) {
                & "$env:COMSPEC" /c scoop install 7zip
            }
            & "$env:COMSPEC" /c scoop config SCOOP_REPO "https://github.com/Ash258/Scoop-Core"
            & "$env:COMSPEC" /c scoop update
            Get-ChildItem "$env:SCOOP\shims" -Filter "scoop.*" | Copy-Item -Destination { Join-Path $_.Directory.FullName (($_.BaseName -replace "scoop", "shovel") + $_.Extension) }
        }

        if ($Symlink) {
            Write-Verbose "Try to find existing version folder:"
            $VersionDir = Join-Path $ScoopAppHome $ScoopAppVersion
            Write-Verbose "$VersionDir"
            if (-not (Test-Path $VersionDir)) {
                $VersionDir = Join-Path $ScoopAppHome "${ScoopAppVersionPrefix}${ScoopAppVersion}"
                Write-Verbose "$VersionDir"
                if (-not (Test-Path $VersionDir)) {
                    throw "Unknown version folder under '$ScoopAppHome', use param '-ScoopAppVersion' or '-UnzipFromPath' with a ZIP from: https://github.com/lukesampson/scoop"
                }
            }

            $CurrentDir = Join-Path $ScoopAppHome "current"
            if (Test-Path $CurrentDir) {
                Write-Verbose "Remove existing current folder '$CurrentDir'."
                Remove-Item $CurrentDir -Force -Recurse
            }

            Write-Verbose "Create new symlink from '$CurrentDir' to '$VersionDir'."
            & "$env:COMSPEC" /c mklink /j $CurrentDir $VersionDir
            $null = attrib $CurrentDir +R /L
        }

        if ($ResetAll) {
            Write-Verbose "Reset and cleanup all existing scoop apps."
            $ErrorActionPreference = "Continue"
            & "$env:COMSPEC" /c scoop reset *
            & "$env:COMSPEC" /c scoop cleanup --cache *
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
