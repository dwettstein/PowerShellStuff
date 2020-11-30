<#
.SYNOPSIS
    Move a VM to the given compute cluster or host and/or datastore or datastore cluster.

.DESCRIPTION
    Move a VM to the given compute cluster or host and/or datastore or datastore cluster.

    File-Name:  Move-VSphereVM.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2020-11-04, David Wettstein: Refactor script and release.
                v0.0.1, 2019-01-07, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Result = & "Move-VSphereVM" -Server "vcenter.vsphere.local" -Name "vm_name" -DatastoreClusterName "datastore_cluster_name" -ClusterName "host_cluster_name"
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
    [String] $DatastoreClusterName
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $DatastoreName
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $ClusterName
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [String] $VMHostName  # If VMHostName is not given, then ClusterName is mandatory!
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
        $ApproveAllCertificates = [Boolean] (& "${FILE_DIR}Sync-VSphereVariableCache" "ApproveAllCertificates" $PSCmdlet.MyInvocation.BoundParameters.ApproveAllCertificates)

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

        # If a datastore or datastore cluster is given, get the object.
        # Otherwise just continue, as the datastore is optional.
        $Datastore = $null
        if (-not [String]::IsNullOrEmpty($DatastoreName)) {
            $Datastore = Get-Datastore -Server $Server -Name $DatastoreName
        } elseif (-not [String]::IsNullOrEmpty($DatastoreClusterName)) {
            $Datastore = Get-DatastoreCluster -Server $Server -Name $DatastoreClusterName
        }

        # ================================================================================
        # Execute the relocation with given specification.
        if (-not [String]::IsNullOrEmpty($Location)) {
            if (-not [String]::IsNullOrEmpty($DiskStorageFormat)) {
                $MoveVmTask = Move-VM -Server $Server -VM $VM -Destination $VMHost -Datastore $Datastore -InventoryLocation $Location -DiskStorageFormat $DiskStorageFormat -Confirm:$false -RunAsync:$true
            } else {
                $MoveVmTask = Move-VM -Server $Server -VM $VM -Destination $VMHost -Datastore $Datastore -InventoryLocation $Location -Confirm:$false -RunAsync:$true
            }
        } else {
            if (-not [String]::IsNullOrEmpty($DiskStorageFormat)) {
                $MoveVmTask = Move-VM -Server $Server -VM $VM -Destination $VMHost -Datastore $Datastore -DiskStorageFormat $DiskStorageFormat -Confirm:$false -RunAsync:$true
            } else {
                $MoveVmTask = Move-VM -Server $Server -VM $VM -Destination $VMHost -Datastore $Datastore -Confirm:$false -RunAsync:$true
            }
        }
        if (-not $MoveVmTask.Id.StartsWith("Task")) {
            Write-Verbose "PowerCLI cmdlet returned a client-side task: $MoveVmTask"
            if ($MoveVmTask.Name -eq "ApplyStorageDrsRecommendation_Task") {
                $VMEventChainIds = Get-VIEvent $VM | ForEach-Object ChainId
                $MoveVmTask = Get-Task | Where-Object { $_.Name -eq $MoveVmTask.Name -and $_.State -eq $MoveVmTask.State -and $VMEventChainIds -contains $_.ExtensionData.Info.EventChainId }
            } else {
                $MoveVmTask = Get-Task | Where-Object { $_.Name -eq $MoveVmTask.Name -and $_.ObjectId -eq $VM.Id -and $_.State -eq $MoveVmTask.State }
            }
        }
        Write-Verbose "Move-VM task: $MoveVmTask"

        $ResultObj = @{
            "Name" = $VM.Name
            "Id" = $VM.Id
            "TaskId" = "$($MoveVmTask.Id)"
        }  # Build your result object (hashtable)

        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        $ScriptOut = ConvertTo-Json $ResultObj -Depth 10 -Compress
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction:Continue
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
