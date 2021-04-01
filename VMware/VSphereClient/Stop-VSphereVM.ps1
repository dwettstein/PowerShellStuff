<#
.SYNOPSIS
    Stop or gracefully shut down a VM.

.DESCRIPTION
    Stop or gracefully shut down a VM.

    File-Name:  Stop-VSphereVM.ps1
    Author:     David Wettstein
    Version:    1.0.1

    Changelog:
                v1.0.1, 2020-12-01, David Wettstein: Refactor error handling.
                v1.0.0, 2020-11-04, David Wettstein: Refactor script and release.
                v0.0.1, 2018-03-22, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Result = & "Stop-VSphereVM" -Server "vcenter.vsphere.local" -Name "vm_name"

.EXAMPLE
    $Result = & "Stop-VSphereVM" -Server "vcenter.vsphere.local" -Name "vm_name" -Shutdown
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
    [Alias("Graceful")]
    [Switch] $Shutdown
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [Switch] $Force
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $RunAsync
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Int] $MaxRetries = 5
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [Alias("VCenter")]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [Object] $VSphereConnection
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [Switch] $Disconnect
    ,
    [Parameter(Mandatory = $false, Position = 8)]
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

        if ($VM.PowerState -ne "PoweredOff") {
            if ($Shutdown) {
                if (-not $RunAsync) {
                    # Wait for VMware Tools.
                    $MAX_TOOLS_WAIT_IN_SEC = 5 * 60  # min * sec
                    try {
                        $Result = $VM | Wait-Tools -TimeoutSeconds $MAX_TOOLS_WAIT_IN_SEC
                        Write-Verbose "$Result"
                    } catch {
                        Write-Verbose "Failed to wait for VMware Tools:`n$($_.Exception)"
                    }
                }

                try {
                    if (@("toolsOk", "toolsOld") -notcontains $VM.ExtensionData.Guest.ToolsStatus -and -not $Force) {
                        throw "Failed to shut down VM, invalid VMware Tools status: $($VM.ExtensionData.Guest.ToolsStatus)"
                    }
                    $SLEEP_IN_SEC = 10
                    Write-Verbose "VM is in PowerState $($VM.PowerState), try to shut down now with $MaxRetries retries."
                    foreach ($RetryCount in (1..$MaxRetries)) {
                        try {
                            $VM = Get-VM -Server $Server -Name $Name
                            if ($VM.PowerState -eq "PoweredOff") {
                                break
                            }
                            # Gracefully shut down VM
                            $Result = Shutdown-VMGuest -Server $Server -VM $VM -Confirm:$false -ErrorAction:Stop
                            Write-Verbose "$Result"
                            break
                        } catch {
                            Write-Verbose "Failed to shut down VM [$RetryCount/$MaxRetries]:`n$($_.Exception)"
                            if ($RetryCount -ge $MaxRetries) {
                                throw $_
                            }
                            $null = Start-Sleep -Seconds ($SLEEP_IN_SEC * $RetryCount)  # Sleep incrementally.
                        }
                    }

                    if (-not $RunAsync) {
                        # Wait until VM has been shut down.
                        $MAX_STATE_WAIT_IN_SEC = 10 * 60  # min * sec
                        $VM = Get-VM -Server $Server -Name $Name
                        while ($VM.PowerState -ne "PoweredOff") {
                            Write-Verbose "VM is shutting down..."
                            $null = Start-Sleep -Seconds $SLEEP_IN_SEC
                            $VM = Get-VM -Server $Server -Name $Name
                            if (([DateTime]::Now - $StartDate).TotalSeconds -gt $MAX_STATE_WAIT_IN_SEC) {
                                throw "Shut down VM not completed after $($MAX_STATE_WAIT_IN_SEC / 60) minutes, abort. Current PowerState: $($VM.PowerState)"
                            }
                        }
                    }
                } catch {
                    Write-Verbose "Failed to shut down VM (try force stop? $Force):`n$($_.Exception)"
                    if ($Force) {
                        $Result = Stop-VM -Server $Server -VM $VM -Confirm:$false -ErrorAction:SilentlyContinue
                        Write-Verbose "$Result"
                    }
                    $VM = Get-VM -Server $Server -Name $Name
                    if ($VM.PowerState -ne "PoweredOff") {
                        throw "Failed to shut down VM:`n$($_.Exception)"
                    }
                }
            } else {
                $Result = Stop-VM -Server $Server -VM $VM -Confirm:$false -ErrorAction:SilentlyContinue
                Write-Verbose "$Result"
                $VM = Get-VM -Server $Server -Name $Name
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
