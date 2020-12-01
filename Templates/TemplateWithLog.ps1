<#
.SYNOPSIS
    Short description

.DESCRIPTION
    Long description

    File-Name:  TemplateWithLog.ps1
    Author:     David Wettstein
    Version:    v0.0.1

    Changelog:
                v0.0.1, yyyy-mm-dd, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.PARAMETER Param1
    Param1 description

.EXAMPLE
    Example of how to use this cmdlet
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    # [ValidatePattern("[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}")]
    [String] $Param1
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateSet(0, 1, 2)]
    [Alias("Var2")]
    [Int] $Param2
)

begin {
    if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
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

    function Write-Log {
        <#
        .SYNOPSIS
            Logs a given message with defined stream to stream and log-file.
        #>
        param (
            [Parameter(Mandatory = $false, Position = 0)]
            [ValidateSet("Host", "Output", "Verbose", "Warning", "Error", "Debug")]
            [String] $Stream
            ,
            [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 1)]
            [String] $Message
            ,
            [Parameter(Mandatory = $false, Position = 2)]
            [String] $LogFileRoot
        )

        if ([String]::IsNullOrEmpty($LogFileRoot)) {
            [String] $LogFileName = "${FILE_DIR}${FILE_NAME}_$(Get-Date -Format 'yyyy-MM-dd').log"
        } else {
            [String] $LogFileName = "${LogFileRoot}${FILE_NAME}_$(Get-Date -Format 'yyyy-MM-dd').log"
        }
        $LogDate = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffzzz"  # ISO8601

        [Boolean] $IsVerboseGiven = $VerbosePreference -ne "SilentlyContinue"
        [Boolean] $IsDebugGiven = $DebugPreference -ne "SilentlyContinue"

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
                Write-Warning $Message -WarningAction:Continue
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

        Remove-Variable IsVerboseGiven, IsDebugGiven
        Remove-Variable LogDate
        Remove-Variable Stream, Message
    }

    Write-Log Verbose "$($FILE_NAME): CALL."

    # Make sure the necessary modules are loaded.
    $Modules = @()
    $LoadedModules = Get-Module; $Modules | ForEach-Object {
        if ($_ -notin $LoadedModules.Name) { Import-Module $_ -DisableNameChecking }
    }
}

process {
    #trap { Write-Error "$($_.Exception)"; $ExitCode = 1; break; }
    $ScriptOut = ""
    try {
        # Do whatever you have to...
        $ResultObj = @{ "key" = "value" }  # Build your result object (hashtable)

        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        $ScriptOut = ConvertTo-Json $ResultObj -Depth 10 -Compress

        Write-Log Output $ScriptOut  # Write $ScriptOut to output stream.
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Log Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction:Continue
        $Ex = $_.Exception; while ($Ex.InnerException) { $Ex = $Ex.InnerException }
        # Add error to $ErrorOut and continue with next item to process or end block.
        $ErrorOut += if ($ErrorOut) { "`n$($Ex.Message)" } else { "$($Ex.Message)" }
        $ExitCode = 1
    } finally {
        # Optionally delete log file if no error.
        # Remove-Item $LogFileName
    }
}

end {
    Write-Log Verbose "$($FILE_NAME): ExitCode: $ExitCode. Execution time: $(([DateTime]::Now - $StartDate).TotalMilliseconds) ms. Started: $($StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))."
    # Set the script/function exit code. Can be accessed with `$LASTEXITCODE` automatic variable.
    # Don't use `exit $ExitCode` as it also exits the console itself when invoked as module function.
    & "powershell.exe" "-NoLogo" "-NoProfile" "-NonInteractive" "-Command" "exit $ExitCode"
    if ((-not [String]::IsNullOrEmpty($ErrorOut)) -or $ExitCode -ne 0) {
        Write-Log Error "$ErrorOut"
    }
}
