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

        switch ($Stream) {
            Host {
                Write-Output "$LogDate | $FILE_NAME | $PID | HOST | $Message" | Out-File -FilePath $LogFileName -Append
                Write-Host $Message
                break
            }
            Output {
                Write-Output "$LogDate | $FILE_NAME | $PID | OUTPUT | $Message" | Out-File -FilePath $LogFileName -Append
                Write-Output $Message
                break
            }
            Verbose {
                if ($IsVerboseGiven) {
                    Write-Output "$LogDate | $FILE_NAME | $PID | VERBOSE | $Message" | Out-File -FilePath $LogFileName -Append
                }
                Write-Verbose $Message
                break
            }
            Warning {
                Write-Output "$LogDate | $FILE_NAME | $PID | WARNING | $Message" | Out-File -FilePath $LogFileName -Append -Force
                Write-Warning $Message -WarningAction Continue
                break
            }
            Error {
                Write-Output "$LogDate | $FILE_NAME | $PID | ERROR | $Message" | Out-File -FilePath $LogFileName -Append -Force
                Write-Error $Message
                break
            }
            Debug {
                if ($IsDebugGiven) {
                    Write-Output "$LogDate | $FILE_NAME | $PID | DEBUG | $Message" | Out-File -FilePath $LogFileName -Append -Force
                }
                Write-Debug $Message
                break
            }
            default {
                Write-Output "$LogDate | $FILE_NAME | $PID | DEFAULT | $Message" | Out-File -FilePath $LogFileName -Append
                break
            }
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
    $ErrorOut = ""

    try {
        # Do whatever you have to...
        $ResultObj = @{ "key" = "value" }  # Build your result object (hashtable)

        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        $ScriptOut = ConvertTo-Json $ResultObj -Depth 10 -Compress
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction Continue
        $Ex = $_.Exception; while ($Ex.InnerException) { $Ex = $Ex.InnerException }
        $ErrorOut = "$($Ex.Message)"
        $ExitCode = 1
    } finally {
        if ([String]::IsNullOrEmpty($ErrorOut)) {
            Write-Log Output $ScriptOut  # Write ScriptOut to output stream.
            # Delete log file if no error.
            #Remove-Item $logFileName
        } else {
            Write-Log Error "$ErrorOut"  # Use Write-Error only here.
        }
    }
}

end {
    Write-Log Verbose "$($FILE_NAME): ExitCode: $ExitCode. Execution time: $(([DateTime]::Now - $StartDate).TotalMilliseconds) ms. Started: $($StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))."
    # exit $ExitCode
}
