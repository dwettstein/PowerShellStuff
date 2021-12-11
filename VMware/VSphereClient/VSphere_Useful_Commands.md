# Useful commands for vSphere

- [Useful commands for vSphere](#useful-commands-for-vsphere)
  - [Capacity Management](#capacity-management)
    - [Get a list of all clusters containing the name, memory usage in MB, memory capacity in MB and total memory usage in percent, sorted by highest memory usage in percent](#get-a-list-of-all-clusters-containing-the-name-memory-usage-in-mb-memory-capacity-in-mb-and-total-memory-usage-in-percent-sorted-by-highest-memory-usage-in-percent)
    - [Get a list of all hosts containing the name, memory usage in MB, memory capacity in MB and total memory usage in percent, sorted by highest memory usage in percent](#get-a-list-of-all-hosts-containing-the-name-memory-usage-in-mb-memory-capacity-in-mb-and-total-memory-usage-in-percent-sorted-by-highest-memory-usage-in-percent)
  - [Storage](#storage)
    - [Get a list of all storage tags and assigned datastores, sorted by tag](#get-a-list-of-all-storage-tags-and-assigned-datastores-sorted-by-tag)
    - [Get a list of all datastores containing the name and overprovisioning factor, sorted by highest overprovisioning factor](#get-a-list-of-all-datastores-containing-the-name-and-overprovisioning-factor-sorted-by-highest-overprovisioning-factor)
    - [Get a datastore recommendation for relocating VMs](#get-a-datastore-recommendation-for-relocating-vms)
    - [Get a list of all NFS datastore disconnects during a given time](#get-a-list-of-all-nfs-datastore-disconnects-during-a-given-time)
  - [Compute](#compute)
    - [Get all VMs of a host with mounted VMware Tools Installer or connected CD drive](#get-all-vms-of-a-host-with-mounted-vmware-tools-installer-or-connected-cd-drive)
    - [Get a report of all host ESXi versions and number of attached datastores, sorted by cluster](#get-a-report-of-all-host-esxi-versions-and-number-of-attached-datastores-sorted-by-cluster)
    - [Get all hosts with disabled alarm actions](#get-all-hosts-with-disabled-alarm-actions)
    - [Get all hosts with enabled SSH](#get-all-hosts-with-enabled-ssh)
  - [Others](#others)
    - [Export any command result as JSON](#export-any-command-result-as-json)

## Capacity Management

### Get a list of all clusters containing the name, memory usage in MB, memory capacity in MB and total memory usage in percent, sorted by highest memory usage in percent

```powershell
Get-Cluster | Get-View | select Name, @{N="MemUsedMB"; E={$_.GetResourceUsage().MemUsedMB}}, @{N="MemCapacityMB"; E={$_.GetResourceUsage().MemCapacityMB}}, @{N="MemUsedPercent"; E={[Math]::Round(($_.GetResourceUsage().MemUsedMB / $_.GetResourceUsage().MemCapacityMB * 100), 2)}} | sort MemUsedPercent -Descending
```

### Get a list of all hosts containing the name, memory usage in MB, memory capacity in MB and total memory usage in percent, sorted by highest memory usage in percent

```powershell
Get-VMHost | select Name, MemoryUsageMB, MemoryTotalMB, @{N="MemoryUsagePercent"; E={[Math]::Round(($_.MemoryUsageMB / $_.MemoryTotalMB * 100), 2)}} | sort MemoryUsagePercent -Descending
```

## Storage

### Get a list of all storage tags and assigned datastores, sorted by tag

```powershell
$TagCategoryName = "your_tag_category_name"
Get-TagAssignment | ? {$_.Tag.Category.Name -eq $TagCategoryName -and $_.Entity.Name -notmatch "_edge"} | select @{N="TagName"; E={$_.Tag.Name}}, Entity | sort TagName
```

### Get a list of all datastores containing the name and overprovisioning factor, sorted by highest overprovisioning factor

```powershell
Get-Datastore | Get-View | select Name, @{N="OverprovisioningFactor"; E={[Math]::Round(($_.Summary.Capacity – $_.Summary.FreeSpace + $_.Summary.Uncommitted) / $_.Summary.Capacity, 2)}}, @{N="FreeSpaceInGB"; E={[Math]::Round($_.Summary.FreeSpace / (1024*1024*1024), 2)}} | sort OverprovisioningFactor -Descending
```

### Get a datastore recommendation for relocating VMs

Use the command above, remove the -Descending at the end, append the following code and update the datastore kind (e.g. ssd):

```powershell
| ? {$_.Name -match "ssd"}
```

### Get a list of all NFS datastore disconnects during a given time

```powershell
Get-VIEvent -MaxSamples 100000 -Start (Get-Date).AddHours(-12) -Finish (Get-Date).AddHours(-0) | where { $_.EventTypeId -eq "esx.problem.vmfs.nfs.server.disconnect" } | select CreatedTime, @{N="HostName"; E={$_.Host.Name}}, @{N="Datastore"; E={[regex]::Match($_.FullFormattedMessage, "\(.*\)").Value.Trim("()")}}, @{N="DatastoreIP"; E={[regex]::Match($_.FullFormattedMessage, "((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)").Value}}, FullFormattedMessage | sort CreatedTime
```

## Compute

### Get all VMs of a host with mounted VMware Tools Installer or connected CD drive

```powershell
$VMHostName = "vmhost_name"
Get-VMHost $VMHostName | Get-VM | ? {$_.ExtensionData.Runtime.ToolsInstallerMounted -or ($_ | Get-CDDrive | ? {$_.ConnectionState.Connected -eq "true" -or $_.ConnectionState.StartConnected -eq "true"})}

# To just get all VMs with mounted VMware Tools Installer, the following command is much faster.
Get-View -ViewType VirtualMachine -Filter @{"Runtime.ToolsInstallerMounted"="True"} -SearchRoot (Get-VMHost $VMHostName).Id
```

If you rather want all VMs and not only the ones from a certain host, just remove the first or last part with `Get-VMHost`.

### Get a report of all host ESXi versions and number of attached datastores, sorted by cluster

```powershell
Get-VMHost | select Parent, Name, Version, @{N="NumDatastores"; E={$_.DatastoreIdList.Length}} | sort Parent, Name
```

### Get all hosts with disabled alarm actions

```powershell
Get-VMHost | where { $_.ExtensionData.AlarmActionsEnabled -eq $False } | sort Name
```

### Get all hosts with enabled SSH

```powershell
Get-VMHost | where { $_ | Get-VMHostService | where { $_.Key -eq "TSM-SSH" -and $_.Policy -eq "on" } } | sort Name
```

## Others

### Export any command result as JSON

Just append the following code to your command:

```powershell
| ConvertTo-Json -Depth 100 | Out-File -Encoding UTF8 "export.json"
```
