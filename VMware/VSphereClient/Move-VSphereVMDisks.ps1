<#
.SYNOPSIS
    Relocate the disks of a VM and the VM to the given cluster or host.

.DESCRIPTION
    Relocate the disks of a VM and the VM to the given cluster or host.

    File-Name:  Move-VSphereVMDisks.ps1
    Author:     David Wettstein
    Version:    1.0.1

    Changelog:
                v1.0.1, 2020-12-01, David Wettstein: Refactor error handling.
                v1.0.0, 2020-11-04, David Wettstein: Refactor script and release.
                v0.0.1, 2018-02-22, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Result = & "Move-VSphereVMDisks" -Server "vcenter.vsphere.local" -Name "vm_name" -DatastoreMapping '{"vmx": "change_to_datastore_name", "disks": [{"uuid": "01234567-89ab-cdef-0123-456789abcdef", "datastore": "change_to_datastore_name"}]}' -ClusterName "host_cluster_name"
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [Alias("VMName")]
    [String] $Name
    ,
    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $DatastoreMapping  # JSON string: {"vmx": "vmx_datastore_name", "disks": [{"uuid": "disk1_uuid", "datastore": "disk1_datastore_name"}, {"uuid": "disk2_uuid", "datastore": "disk2_datastore_name"}]}
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $ClusterName
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $VMHostName  # If VMHostName is not given, then ClusterName is mandatory!
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [String] $ResourcePoolName  # If the resource pool is not given, the pool of the cluster will be used.
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [String] $Location  # The Location or also Folder where the VM should be in.
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [ValidateSet("Thin", "Thick", "EagerZeroedThick")]  # Default for option IgnoreCase is true, so the case is ignored.
    [String] $DiskStorageFormat
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [Switch] $ConsiderMigrations
    ,
    [Parameter(Mandatory = $false, Position = 8)]
    [Alias("VCenter")]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 9)]
    [Object] $VSphereConnection
    ,
    [Parameter(Mandatory = $false, Position = 10)]
    [Switch] $Disconnect
    ,
    [Parameter(Mandatory = $false, Position = 11)]
    [Alias("Insecure")]
    [Switch] $ApproveAllCertificates
)

begin {
    if (-not $PSBoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
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
        $ApproveAllCertificates = [Boolean] (& "${FILE_DIR}Sync-VSphereVariableCache" "ApproveAllCertificates" $PSBoundParameters.ApproveAllCertificates)

        if (-not $VSphereConnection) {
            $VSphereConnection = & "${FILE_DIR}Connect-VSphere" -Server $Server -ApproveAllCertificates:$ApproveAllCertificates
        }

        # Get objects from source vCenter
        $VM = Get-VM -Server $Server -Name $Name

        # Get given destination host for VM or determine it by least memory usage in given cluster.
        if ([String]::IsNullOrEmpty($VMHostName)) {
            if ([String]::IsNullOrEmpty($ClusterName)) {
                $VMHost = Get-VMHost -Server $Server -VM $VM
                Write-Verbose "Both VMHostName and ClusterName are null, use the current host of the VM '$($VMHost.Name)'."
            } else {
                $VMHost = & "${FILE_DIR}Select-VSphereDestinationVMHost" -Server $Server -ClusterName $ClusterName -ConsiderMigrations:$ConsiderMigrations -VSphereConnection $VSphereConnection
            }
        } else {
            $VMHost = Get-VMHost -Server $Server -Name $VMHostName
        }
        $Cluster = Get-Cluster -Server $Server -VMHost $VMHost

        # Assert VMHost and Cluster are not null
        if (-not $VMHost -or -not $Cluster) {
            throw "The host '$VMHost' or cluster '$Cluster' is not found or valid."
        }

        if (-not [String]::IsNullOrEmpty($ResourcePoolName)) {
            $ResourcePool = Get-ResourcePool -Location $Cluster -Name $ResourcePoolName
        } else {
            $ResourcePool = Get-ResourcePool -Location $Cluster | Where-Object { $_.Parent -eq $Cluster }
        }
        if ($ResourcePool.Length -gt 1) {
            $ResourcePool = $ResourcePool[0]  # Try with the first.
        }

        # Get view and disks from the VM
        $VMView = Get-View -Id $VM.Id
        $VMDisks = Get-HardDisk -VM $VM
        $VMDiskUuids = $VMDisks | ForEach-Object { $_.ExtensionData.Backing.Uuid }

        # Parse DatastoreMapping from inputs
        $DatastoreMappingObj = ConvertFrom-Json $DatastoreMapping

        # ================================================================================
        # Prepare VirtualMachineRelocateSpec
        $RelocateSpec = New-Object VMware.Vim.VirtualMachineRelocateSpec

        # Add VM host information
        $VMHostMoref = ($VMHost | Get-View).moref
        $RelocateSpec.host = New-Object VMware.Vim.ManagedObjectReference
        $RelocateSpec.host.type = $VMHostMoref.type
        $RelocateSpec.host.value = $VMHostMoref.value

        # Add resource pool information
        $ResourcePoolMoref = ($ResourcePool | Get-View).moref
        $RelocateSpec.pool = New-Object VMware.Vim.ManagedObjectReference
        $RelocateSpec.pool.type = $ResourcePoolMoref.type
        $RelocateSpec.pool.value = $ResourcePoolMoref.value

        # Add location/folder information, if given
        if (-not [String]::IsNullOrEmpty($Location)) {
            $FolderMoref = (Get-Folder -Name $Location | Get-View).moref
            $RelocateSpec.folder = New-Object VMware.Vim.ManagedObjectReference
            $RelocateSpec.folder.type = $FolderMoref.type
            $RelocateSpec.folder.value = $FolderMoref.value
        }

        # Add VMX datastore information
        Write-Verbose "VMX should be moved to datastore '$($DatastoreMappingObj.vmx)'."
        $VMXDatastoreMoref = (Get-Datastore -Name $DatastoreMappingObj.vmx | Get-View).moref
        $RelocateSpec.datastore = New-Object VMware.Vim.ManagedObjectReference
        $RelocateSpec.datastore.type = $VMXDatastoreMoref.type
        $RelocateSpec.datastore.value = $VMXDatastoreMoref.value

        # Add disk(s) information
        # Make the array a bit longer than actually needed to avoid a IndexOutOfRangeException if the disks are not correctly numbered.
        $RelocateSpec.disk = New-Object VMware.Vim.VirtualMachineRelocateSpecDiskLocator[] ($VMDiskUuids.Length + 16)
        foreach ($DiskJson in $DatastoreMappingObj.disks) {
            if (-not ($VMDiskUuids -contains $DiskJson.uuid)) {
                throw "Disk '$($DiskJson.uuid)' from DatastoreMapping not found in VM '$($VM.Name)'!"
            }
            $Disk = $VMDisks | Where-Object { $_.ExtensionData.Backing.Uuid -eq $DiskJson.uuid }
            $DiskNumber = $Disk.ExtensionData.UnitNumber
            Write-Verbose "Disk $DiskNumber with uuid '$($DiskJson.uuid)' should be moved to datastore '$($DiskJson.datastore)'."

            $TargetDatastoreMoref = (Get-Datastore -Name $DiskJson.datastore | Get-View).moref
            $RelocateSpec.disk[$DiskNumber] = New-Object VMware.Vim.VirtualMachineRelocateSpecDiskLocator
            $RelocateSpec.disk[$DiskNumber].diskId = $Disk.Id.split("/")[1]
            $RelocateSpec.disk[$DiskNumber].datastore = New-Object VMware.Vim.ManagedObjectReference
            $RelocateSpec.disk[$DiskNumber].datastore.type = $TargetDatastoreMoref.type
            $RelocateSpec.disk[$DiskNumber].datastore.value = $TargetDatastoreMoref.value

            if ($DiskStorageFormat) {
                switch ($DiskStorageFormat.ToLower()) {
                    "thin" {
                        # $RelocateSpec.disk[$DiskNumber].diskBackingInfo = New-Object VMware.Vim.VirtualDiskFlatVer2BackingInfo
                        $RelocateSpec.disk[$DiskNumber].diskBackingInfo = $Disk.ExtensionData.Backing
                        $RelocateSpec.disk[$DiskNumber].diskBackingInfo.thinProvisioned = $true
                        $RelocateSpec.disk[$DiskNumber].diskBackingInfo.eagerlyScrub = $false
                    }
                    "thick" {  # Equal to lazy zeroed thick.
                        $RelocateSpec.disk[$DiskNumber].diskBackingInfo = $Disk.ExtensionData.Backing
                        $RelocateSpec.disk[$DiskNumber].diskBackingInfo.thinProvisioned = $false
                        $RelocateSpec.disk[$DiskNumber].diskBackingInfo.eagerlyScrub = $false
                    }
                    "eagerzeroedthick" {
                        $RelocateSpec.disk[$DiskNumber].diskBackingInfo = $Disk.ExtensionData.Backing
                        $RelocateSpec.disk[$DiskNumber].diskBackingInfo.thinProvisioned = $false
                        $RelocateSpec.disk[$DiskNumber].diskBackingInfo.eagerlyScrub = $true
                    }
                    default {
                        # Do nothing.
                    }
                }
            }
        }

        # ================================================================================
        # Execute the relocation with given specification.
        $RelocateTask = $VMView.RelocateVM_Task($RelocateSpec, "defaultPriority")
        Write-Verbose "RelocateVM_Task Id: $RelocateTask"

        $ResultObj = @{
            "Name" = $VM.Name
            "Id" = $VM.Id
            "TaskId" = "$RelocateTask"
            "Disks" = @()
        }  # Build your result object (hashtable)

        $Disks = Get-HardDisk -Server $Server -VM $VM
        foreach ($Disk in $Disks) {
            $Row = @{}
            $Row.Name = $Disk.Name
            $Row.Id = $Disk.Id
            $Row.CapacityGB = [Math]::round($Disk.CapacityGB)
            $Row.Filename = $Disk.Filename
            $Row.StorageFormat = "$($Disk.StorageFormat)"
            # $DatastoreTemp = $Disk.Filename.Split()[0]
            # $Row.Datastore = $DatastoreTemp.Substring(1, $DatastoreTemp.Length - 2)
            $Row.DatastoreId = "$($Disk.ExtensionData.Backing.Datastore)"
            if ($Row.DatastoreId) {
                $Row.Datastore = (Get-Datastore -Id $Row.DatastoreId).Name
            } else {
                $Row.Datastore = ""
            }
            $Row.Uuid = $Disk.ExtensionData.Backing.Uuid
            $Row.UnitNumber = $Disk.ExtensionData.UnitNumber
            $ResultObj.Disks += $Row
        }

        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        $ScriptOut = ConvertTo-Json $ResultObj -Depth 10 -Compress

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
