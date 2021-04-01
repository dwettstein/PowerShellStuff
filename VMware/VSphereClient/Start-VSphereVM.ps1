<#
.SYNOPSIS
    Start a VM.

.DESCRIPTION
    Start a VM.

    File-Name:  Start-VSphereVM.ps1
    Author:     David Wettstein
    Version:    1.0.1

    Changelog:
                v1.0.1, 2020-12-01, David Wettstein: Refactor error handling.
                v1.0.0, 2020-11-04, David Wettstein: Refactor script and release.
                v0.0.1, 2018-04-06, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Result = & "Start-VSphereVM" -Server "vcenter.vsphere.local" -Name "vm_name"

.EXAMPLE
    $Result = & "Start-VSphereVM" -Server "vcenter.vsphere.local" -Name "vm_name" -RunAsync
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [Alias("VMName")]
    [String] $Name
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $VMCopied
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [Alias("BiosBoot")]
    [Switch] $RunAsync
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Alias("VCenter")]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Object] $VSphereConnection
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [Switch] $Disconnect
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [Alias("Insecure")]
    [Switch] $ApproveAllCertificates
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
    if ($MyInvocation.MyCommand.Module) {
        $FILE_DIR = ""  # If this script is part of a module, we want to call module functions not files.
    }

    Write-Verbose "$($FILE_NAME): CALL."

    # Make sure the necessary modules are loaded.
    $Modules = @(
        "VMware.VimAutomation.Core"
    )
    $LoadedModules = Get-Module; $Modules | ForEach-Object {
        if ($_ -notin $LoadedModules.Name) { Import-Module $_ -DisableNameChecking }
    }
}

process {
    #trap { Write-Error "$($_.Exception)"; $ExitCode = 1; break; }
    $ScriptOut = ""
    try {
        $Server = & "${FILE_DIR}Sync-VSphereVariableCache" "Server" $Server -IsMandatory
        $VSphereConnection = & "${FILE_DIR}Sync-VSphereVariableCache" "VSphereConnection" $VSphereConnection
        $ApproveAllCertificates = [Boolean] (& "${FILE_DIR}Sync-VSphereVariableCache" "ApproveAllCertificates" $PSCmdlet.MyInvocation.BoundParameters.ApproveAllCertificates)

        if (-not $VSphereConnection) {
            $VSphereConnection = & "${FILE_DIR}Connect-VSphere" -Server $Server -ApproveAllCertificates:$ApproveAllCertificates
        }

        $VM = Get-VM -Server $Server -Name $Name

        $ToolsStatus = $VM.ExtensionData.Guest.ToolsRunningStatus
        if ($ToolsStatus -eq "guestToolsNotRunning") {
            $SLEEP_IN_SEC = 10
            try {
                try {
                    $Result = Start-VM -Server $Server -VM $VM -Confirm:$false
                    Write-Verbose "$Result"
                } catch {
                    Write-Verbose "Failed to start VM:`n$($_.Exception)"
                    if ($_.FullyQualifiedErrorId -eq "VMware.VimAutomation.ViCore.Types.V1.ErrorHandling.VmBlockedByQuestionException" -or $_.Exception.Message -like "*VM has questions*") {
                        Write-Verbose "Answer the VMQuestion and try again."
                        $VM = Get-VM -Server $Server -Name $Name
                        try {
                            # Possible options: "Cancel", "button.uuid.movedTheVM", "button.uuid.copiedTheVM"
                            $Option = "button.uuid.movedTheVM"
                            if ($VMCopied) {
                                $Option = "button.uuid.copiedTheVM"
                            }
                            $Result = ($VM | Get-VMQuestion | Set-VMQuestion -Option $Option -Confirm:$false -WarningAction:SilentlyContinue)
                            Write-Verbose "$Result"
                        } catch {
                            Write-Verbose "Failed to answer VMQuestion:`n$($_.Exception)"
                            # Ignore and continue.
                        }
                        Write-Verbose "Sleep $SLEEP_IN_SEC seconds before retrying again."
                        $null = Start-Sleep -Seconds $SLEEP_IN_SEC
                        try {
                            $Result = Start-VM -Server $Server -VM $VM -Confirm:$false -WarningAction:SilentlyContinue
                            Write-Verbose "$Result"
                        } catch {
                            Write-Verbose "Failed to start VM:`n$($_.Exception)"
                            if ($_.FullyQualifiedErrorId -eq "VMware.VimAutomation.ViCore.Types.V1.ErrorHandling.VmBlockedByQuestionException" -or $_.Exception.Message -like "*VM has questions*") {
                                Write-Verbose "Ignore it this time, continue."
                            } elseif ($_.FullyQualifiedErrorId -eq "VMware.VimAutomation.ViCore.Types.V1.ErrorHandling.InvalidPowerState" -or $_.Exception.Message -like "*operation cannot be performed in the current state (Powered on)*") {
                                Write-Verbose "VM is already running, but the VMware Tools not, continue."
                            } else {
                                throw $_  # Re-throw if a different exception occurred.
                            }
                        }
                    } elseif ($_.FullyQualifiedErrorId -eq "VMware.VimAutomation.ViCore.Types.V1.ErrorHandling.InvalidPowerState" -or $_.Exception.Message -like "*operation cannot be performed in the current state (Powered on)*") {
                        Write-Verbose "VM is already running, but the VMware Tools not, continue."
                    } else {
                        throw $_  # Re-throw if a different exception occurred.
                    }
                }

                if (-not $RunAsync) {
                    # Wait until VM has been started.
                    $INITIAL_SLEEP_IN_SEC = 60
                    Write-Verbose "Sleep $INITIAL_SLEEP_IN_SEC sec initially before polling."
                    $null = Start-Sleep -Seconds $INITIAL_SLEEP_IN_SEC

                    $MAX_STATE_WAIT_IN_SEC = 10 * 60  # min * sec
                    $VM = Get-VM -Server $Server -Name $Name
                    $ToolsStatus = $VM.ExtensionData.Guest.ToolsRunningStatus
                    while ($ToolsStatus -ne "guestToolsNotRunning") {
                        Write-Verbose "VM is starting..."
                        $null = Start-Sleep -Seconds $SLEEP_IN_SEC
                        $VM = Get-VM -Server $Server -Name $Name
                        $ToolsStatus = $VM.ExtensionData.Guest.ToolsRunningStatus
                        if (([DateTime]::Now - $StartDate).TotalSeconds -gt $MAX_STATE_WAIT_IN_SEC) {
                            throw "Start VM not completed after $($MAX_STATE_WAIT_IN_SEC / 60) minutes, abort. Current PowerState: $($VM.PowerState)"
                        }
                    }
                }
            } catch {
                throw "Failed to start VM:`n$($_.Exception)"
            }
        }
        $ScriptOut = $VM.PowerState

        $ScriptOut  # Write $ScriptOut to output stream.
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction:Continue
        $Ex = $_.Exception; while ($Ex.InnerException) { $Ex = $Ex.InnerException }
        # Add error to $ErrorOut and continue with next item to process or end block.
        $ErrorOut += if ($ErrorOut) { "`n$($Ex.Message)" } else { "$($Ex.Message)" }
        $ExitCode = 1
    } finally {
        if ($Disconnect -and $VSphereConnection) {
            $null = Disconnect-VIServer -Server $VSphereConnection -Confirm:$false
        }
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
