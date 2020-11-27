<#
.SYNOPSIS
    Logs a given message with defined stream to stream and log-file.

.DESCRIPTION
    Logs a given message with defined stream to stream and log-file.

    NOTE: The parameter "Stream" is only needed for the function Write-Log. The usual
    functions Log-Host, Log-Output, Log-Verbose, Log-Warning, Log-Error and Log-Debug
    already include this parameter.

    VERBOSE and DEBUG:
    Use the -Verbose option to see the Write-Verbose outputs in the console.
    Use the -Debug option to see the Write-Debug outputs in the console.

    File-Name:  Write-Log.ps1
    Author:     David Wettstein
    Version:    v1.0.3

    Changelog:
                v1.0.3, 2020-11-27, David Wettstein: Refactor and use System.IO.File.
                v1.0.2, 2020-10-20, David Wettstein: Add function blocks.
                v1.0.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.0.0, 2020-01-03, David Wettstein: First implementation, based on my old Logger module.

.NOTES
    Copyright (c) 2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.PARAMETER Stream
    The stream for the message (Host, Output, Verbose, Warning, Error).
    (Default is Output)

.PARAMETER Message
    The message to write into a file and display in the console.

.EXAMPLE
    Write-Log Host "Message"

.EXAMPLE
    & "$PSScriptRoot\Utils\Write-Log" Host "Message"
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("Host", "Output", "Verbose", "Warning", "Error", "Debug")]
    [String] $Stream
    ,
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 1)]
    [String] $Message
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $LogFileRoot
)

begin {
    if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","

    # If this script was called from another script use its name for the log entry.
    if (-not [String]::IsNullOrEmpty($MyInvocation.PSCommandPath)) {
        [String] $FILE_NAME = Get-ChildItem $MyInvocation.PSCommandPath | Select-Object -Expand Name
        [String] $FILE_DIR = Join-Path (Split-Path -Parent $MyInvocation.PSCommandPath) ""
    } else {
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
    }

    if ([String]::IsNullOrEmpty($LogFileRoot)) {
        [String] $LogFileName = "${FILE_DIR}${FILE_NAME}_$(Get-Date -Format 'yyyy-MM-dd').log"
    } else {
        [String] $LogFileName = "${LogFileRoot}${FILE_NAME}_$(Get-Date -Format 'yyyy-MM-dd').log"
    }
    $LogDate = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffzzz"  # ISO8601

    [Boolean] $IsVerboseGiven = $VerbosePreference -ne "SilentlyContinue"
    [Boolean] $IsDebugGiven = $DebugPreference -ne "SilentlyContinue"
}

process {
    $Text = "$LogDate | $FILE_NAME | $PID | $($Stream.ToUpper()) | $Message"
    $DoWriteFile = $true
    switch ($Stream) {
        Host {
            Write-Host $Message
            break
        }
        Output {
            Write-Output $Message
            break
        }
        Verbose {
            if (-not $IsVerboseGiven) {
                $DoWriteFile = $false
            }
            Write-Verbose $Message
            break
        }
        Warning {
            Write-Warning $Message -WarningAction Continue
            break
        }
        Error {
            Write-Error $Message
            break
        }
        Debug {
            if (-not $IsDebugGiven) {
                $DoWriteFile = $false
            }
            Write-Debug $Message
            break
        }
        default {
            break
        }
    }
    if ($DoWriteFile) {
        # Write-Output $Text | Out-File -Encoding UTF8 -FilePath $LogFileName -Append -Force  # ! Writes UTF8 with BOM
        [System.IO.File]::AppendAllText($LogFileName, "$Text`n")
    }
}

end {
    Remove-Variable IsVerboseGiven, IsDebugGiven
    Remove-Variable LogDate
    Remove-Variable Stream, Message
}
