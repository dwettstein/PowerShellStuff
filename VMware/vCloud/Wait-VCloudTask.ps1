<#
.SYNOPSIS
    Wait until a task of a vCloud server has been completed (either successfully or not).

.DESCRIPTION
    Wait until a task of a vCloud server has been completed (either successfully or not).

    File-Name:  Wait-VCloudTask.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2019-05-30, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    Example of how to use this cmdlet
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory=$true, Position=0)]
    [String] $Server
    ,
    [Parameter(Mandatory=$true, Position=1)]
    [String] $Task
    ,
    [Parameter(Mandatory=$false, Position=2)]
    [Int] $SleepInSec = 5
    ,
    [Parameter(Mandatory=$false, Position=3)]
    [Int] $TimeoutInSec = 3600  # 60min
    ,
    [Parameter(Mandatory=$false, Position=4)]
    [String] $SessionToken = $null
    ,
    [Parameter(Mandatory=$false, Position=5)]
    [Switch] $AcceptAllCertificates = $false
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

#===============================================================================
# Initialization and Functions
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

Write-Verbose "$($FILE_NAME): CALL."

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

$StatusRunning = @('queued', 'preRunning', 'running')
$StatusCompleted = @('success', 'error', 'canceled', 'aborted')

try {
    $TaskId = & "$FILE_DIR\Split-VCloudId.ps1" -UrnOrHref $Task
    do {
        $CurrentDate = [DateTime]::Now
        if ($TimeoutInSec -and ($CurrentDate -gt $StartDate.AddSeconds($TimeoutInSec))) {
            throw "Timeout while waiting for task '$Task' to complete, current status is '$TaskStatus'."
        }
        $null = Start-Sleep -Seconds $SleepInSec
        if ($AcceptAllCertificates) {
            [Xml] $TaskResponse = Invoke-VCloudRequest -Server $Server -Endpoint "/task/$TaskId" -SessionToken $SessionToken -AcceptAllCertificates
        } else {
            [Xml] $TaskResponse = Invoke-VCloudRequest -Server $Server -Endpoint "/task/$TaskId" -SessionToken $SessionToken
        }
        $TaskStatus = $TaskResponse.Task.status
    } while ($TaskStatus -in $StatusRunning)
    $OutputMessage = $TaskResponse.Task
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())" -WarningAction Continue
    $ErrorOut = "$($_.Exception.Message)"
    $ExitCode = 1
} finally {
    $EndDate = [DateTime]::Now
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ($EndDate - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        $OutputMessage  # Write OutputMessage to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
