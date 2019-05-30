<#
.SYNOPSIS
    Short description

.DESCRIPTION
    Long description

    File-Name:  template_long.ps1
    Author:     David Wettstein
    Version:    v0.0.1

    Changelog:
                v0.0.1, yyyy-mm-dd, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.PARAMETER Param1
    Param1 description

.EXAMPLE
    Example of how to use this cmdlet
#>
[CmdletBinding()]
[OutputType([String])]
param (
    # Param1 help description
    [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
    [String] $Param1
    ,
    # Param2 help description
    [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=1)]
    [Int] $Param2
)

begin {
    $ErrorActionPreference = "Stop"
    $WarningPreference = "SilentlyContinue"
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","

    #===============================================================================
    # Modules
    #===============================================================================
    # Make sure the necessary modules are loaded.
    $Modules = @()
    foreach ($Module in $Modules) {
        if (Get-Module | Where-Object {$_.Name -eq $Module}) {
            # Module already imported. Do nothing.
        } else {
            Import-Module $Module
        }
    }

    #===============================================================================
    # Variables
    #===============================================================================
    $StartDate = [DateTime]::Now

    [String] $FILE_NAME = $MyInvocation.MyCommand.Name
    if ($PSVersionTable.PSVersion.Major -lt 3) {
        [String] $FILE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
    } else {
        [String] $FILE_DIR = $PSScriptRoot
    }

    $ExitCode = 0
    $ErrorOut = ""
    $OutputMessage = ""

    #===============================================================================
    # Functions
    #===============================================================================


    #===============================================================================
    # Initialization
    #===============================================================================
    Write-Verbose "$($FILE_NAME): CALL."
}

#===============================================================================
# Main
#===============================================================================
process {
    #trap { Write-Error $_; $ExitCode = 1; break; }

    try {
        # Do whatever you have to...
        $ResultObj = @{"key" = "value"}  # Build your result object (hashtable)

        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        $OutputMessage = ConvertTo-Json $ResultObj -Depth 10 -Compress
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Warning "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())" -WarningAction Continue
        $ErrorOut = "$($_.Exception.Message)"
        $ExitCode = 1
    } finally {
    }
}

end {
    $EndDate = [DateTime]::Now
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ($EndDate - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        "$OutputMessage"  # Write OutputMessage to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    exit $ExitCode
}
