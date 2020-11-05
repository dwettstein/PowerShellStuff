<#
.SYNOPSIS
    Unregister or delete an existing VM.

.DESCRIPTION
    Unregister or delete an existing VM.

    File-Name:  Unregister-VSphereVM.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2020-11-04, David Wettstein: Refactor script and release.
                v0.0.1, 2018-03-22, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Result = & "Unregister-VSphereVM" -Server "vcenter.vsphere.local" -Name "vm_name"
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
    [Switch] $DeletePermanently
    ,
    [Parameter(Mandatory = $false, Position = 2)]
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
    $ErrorOut = ""

    try {
        $Server = & "${FILE_DIR}Sync-VSphereVariableCache" "Server" $Server -IsMandatory
        $VSphereConnection = & "${FILE_DIR}Sync-VSphereVariableCache" "VSphereConnection" $VSphereConnection
        $ApproveAllCertificates = & "${FILE_DIR}Sync-VSphereVariableCache" "ApproveAllCertificates" $PSCmdlet.MyInvocation.BoundParameters.ApproveAllCertificates

        if (-not $VSphereConnection) {
            $VSphereConnection = & "${FILE_DIR}Connect-VSphere" -Server $Server -ApproveAllCertificates:$ApproveAllCertificates
        }

        $VM = Get-VM -Server $Server -Name $Name

        # Unregister VM from vCenter
        $Result = Remove-VM -Server $Server -VM $VM -DeletePermanently:$DeletePermanently -RunAsync:$RunAsync -Confirm:$false
        Write-Verbose "$Result"
        if ($RunAsync) {
            $ScriptOut = $Result
        } else {
            $ScriptOut = "VM $($VM.Name) has been removed from inventory."
        }
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction Continue
        $Ex = $_.Exception; while ($Ex.InnerException) { $Ex = $Ex.InnerException }
        $ErrorOut = "$($Ex.Message)"
        $ExitCode = 1
    } finally {
        if ($Disconnect -and $VSphereConnection) {
            $null = Disconnect-VIServer -Server $VSphereConnection -Confirm:$false
        }

        if ([String]::IsNullOrEmpty($ErrorOut)) {
            $ScriptOut  # Write ScriptOut to output stream.
        } else {
            Write-Error "$ErrorOut"  # Use Write-Error only here.
        }
    }
}

end {
    Write-Verbose "$($FILE_NAME): ExitCode: $ExitCode. Execution time: $(([DateTime]::Now - $StartDate).TotalMilliseconds) ms. Started: $($StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))."
    # exit $ExitCode
}
