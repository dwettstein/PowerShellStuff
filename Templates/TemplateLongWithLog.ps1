<#
.SYNOPSIS
    Short description

.DESCRIPTION
    Long description

    File-Name:  template_long_with_file_log.ps1
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
    # Param1 help description
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    # [ValidatePattern('.*[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}.*')]
    [String] $Param1
    ,
    # Param2 help description
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateSet(0, 1, 2)]
    [Int] $Param2
)

begin {
    if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","

    #===============================================================================
    # Modules
    #===============================================================================
    # Make sure the necessary modules are loaded.
    $Modules = @()
    $LoadedModules = Get-Module; $Modules | ForEach-Object {
        if ($_ -notin $LoadedModules.Name) { Import-Module $_ -DisableNameChecking }
    }

    #===============================================================================
    # Variables
    #===============================================================================
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
    $ScriptOut = ""

    #===============================================================================
    # Functions
    #===============================================================================

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

    #===============================================================================
    # Initialization
    #===============================================================================
    Write-Log Verbose "$($FILE_NAME): CALL."
}

#===============================================================================
# Main
#===============================================================================
process {
    #trap { Write-Error $_; $ExitCode = 1; break; }

    try {
        # Do whatever you have to...
        $ResultObj = @{ "key" = "value" }  # Build your result object (hashtable)

        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        $ScriptOut = ConvertTo-Json $ResultObj -Depth 10 -Compress
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Log Warning "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())"
        $ErrorOut = "$($_.Exception.Message)"
        $ExitCode = 1
    } finally {
    }
}

end {
    $EndDate = [DateTime]::Now
    Write-Log Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ($EndDate - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        Write-Log Output "$ScriptOut"
        $ScriptOut  # Write ScriptOut to output stream.
        # Delete log file if no error.
        #Remove-Item $logFileName;
    } else {
        Write-Log Error "$ErrorOut"
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
