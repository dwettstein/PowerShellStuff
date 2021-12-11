<#
.SYNOPSIS
    Install Scoop.

.DESCRIPTION
    Install Scoop.
    - Set a proxy or proxy credentials if needed
    - Install to default or custom location
    - Change existing Scoop installation to Shovel fork (see https://github.com/Ash258/Scoop-Core)

    Filename:   Install-Scoop.ps1
    Author:     David Wettstein
    Version:    1.0.0

    Changelog:
    - v1.0.0, 2021-12-11, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2021 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.LINK
    https://github.com/ScoopInstaller/Scoop

.EXAMPLE
    Install-Scoop

.EXAMPLE
    Install-Scoop -ScoopAppVersion "develop" -SetScoopHomeEnv -ScoopHome "D:\Applications\Scoop"

.EXAMPLE
    Install-Scoop -Proxy "http://proxy.example.com:8080" -ApproveAllCertificates

.EXAMPLE
    Install-Scoop -InstallShovel  # Existing Scoop installation needed
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    # Change existing Scoop installation to Shovel fork (see https://github.com/Ash258/Scoop-Core)
    [Switch] $InstallShovel
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [String] $Proxy = $null
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [PSCredential] $ProxyCredential = $null
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $SetScoopHomeEnv
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [ValidateNotNullOrEmpty()]
    [String] $ScoopHome = $(if (-not [String]::IsNullOrEmpty($env:SCOOP)) { $env:SCOOP } else { "$HOME\scoop\" })
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [ValidateNotNullOrEmpty()]
    # Set a Git branch to install from, e. g. master or develop
    [String] $ScoopAppVersion = "master"
    ,
    [Parameter(Mandatory = $false, Position = 6)]
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

        if ($InstallShovel) {
            # Change existing Scoop installation to Shovel fork (see https://github.com/Ash258/Scoop-Core)
            if ((& "$env:COMSPEC" /c scoop config 7ZIPEXTRACT_USE_EXTERNAL) -ne $true) {
                & "$env:COMSPEC" /c scoop install 7zip
            }
            & "$env:COMSPEC" /c scoop config SCOOP_REPO "https://github.com/Ash258/Scoop-Core"
            & "$env:COMSPEC" /c scoop update
            Get-ChildItem "$env:SCOOP\shims" -Filter "scoop.*" | Copy-Item -Destination { Join-Path $_.Directory.FullName (($_.BaseName -replace "scoop", "shovel") + $_.Extension) }
        } else {
            # Install original Scoop from web: https://get.scoop.sh
            Invoke-Expression (New-Object System.Net.WebClient).DownloadString("https://raw.githubusercontent.com/ScoopInstaller/Scoop/$ScoopAppVersion/bin/install.ps1")
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
