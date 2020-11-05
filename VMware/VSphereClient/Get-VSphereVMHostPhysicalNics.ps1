<#
.SYNOPSIS
    Get a list of physical NICs from an ESXi host.

.DESCRIPTION
    Get a list of physical NICs from an ESXi host.

    File-Name:  Get-VSphereVMHostPhysicalNics.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2020-11-04, David Wettstein: Refactor script and release.
                v0.0.2, 2020-02-28, David Wettstein: Added optional filters.
                v0.0.1, 2018-11-21, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Result = & "Get-VSphereVMHostPhysicalNics" -Server "vcenter.vsphere.local" -Name "vmhost_name" -OnlyConnected
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [Alias("VMHostName", "HostName")]
    [String] $Name
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $OnlyConnected
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [Alias("VCenter")]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Object] $VSphereConnection
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Switch] $Disconnect
    ,
    [Parameter(Mandatory = $false, Position = 5)]
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

        $VMHost = Get-VMHost -Server $Server -Name $Name
        $VMHostView = Get-View -VIObject $VMHost
        $VMHostConfigNetworkView = Get-View $VMHostView.ConfigManager.NetworkSystem

        $ResultObj = @()  # Build your result object (hashtable)

        $Nics = Get-VMHostNetworkAdapter -Server $Server -VMHost $VMHost -Physical
        foreach ($Nic in $Nics) {
            $Row = @{}
            $Row.Name = $Nic.Name
            $Row.DeviceName = $Nic.DeviceName
            $Row.Id = $Nic.Id
            $Row.Mac = $Nic.Mac
            $Row.IP = $Nic.IP
            $Row.SubnetMask = $Nic.SubnetMask
            $Row.DhcpEnabled = $Nic.DhcpEnabled
            $Row.BitRatePerSec = $Nic.BitRatePerSec
            $Row.FullDuplex = $Nic.FullDuplex

            try {
                $NicHintInfo = $VMHostConfigNetworkView.QueryNetworkHint($Nic.DeviceName)
                $Row.PhysicalNicHintInfo = $NicHintInfo
            } catch {
                Write-Verbose "Failed to get PhysicalNicHintInfo for NIC $($Nic.Name):`n$($_.Exception)"
                $Row.PhysicalNicHintInfo = $null
            }

            if ($OnlyConnected) {
                if (-not $Row.PhysicalNicHintInfo -or -not $Row.PhysicalNicHintInfo[0].ConnectedSwitchPort) {
                    continue
                }
            }

            $ResultObj += $Row
        }

        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        $ScriptOut = ConvertTo-Json $ResultObj -Depth 10 -Compress
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
