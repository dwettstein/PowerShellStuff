<#
.SYNOPSIS
    Select a destination host within the given cluser based on least memory usage
    and optionally current running migrations/relocations.

.DESCRIPTION
    Select a destination host within the given cluser based on least memory usage
    and optionally current running migrations/relocations.

    File-Name:  Select-VSphereDestinationVMHost.ps1
    Author:     David Wettstein
    Version:    v1.0.1

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
    $Result = & "Select-VSphereDestinationVMHost" -Server "vcenter.vsphere.local" -ClusterName "host_cluster_name"
#>
[CmdletBinding()]
[OutputType([PSObject])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $ClusterName
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $ConsiderMigrations
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

        $MAX_VMS_PER_HOST = 1024  # Ref: https://www.vmware.com/pdf/vsphere6/r65/vsphere-65-configuration-maximums.pdf
        $Cluster = Get-Cluster -Server $Server -Name $ClusterName
        $HostsInCluster = $Cluster | Get-VMHost | Where-Object { $_.ConnectionState -eq "Connected" }
        Write-Verbose "Found $($HostsInCluster.Length) hosts in cluster '$ClusterName'."
        $CandidateHosts = @()
        foreach ($CurrentHost in $HostsInCluster) {
            $Candidate = New-Object PSObject
            $null = Add-Member -InputObject $Candidate -MemberType NoteProperty -Name "Host" -Value $CurrentHost
            $HostVms = $CurrentHost | Get-VM | ForEach-Object { $_.Name }
            $null = Add-Member -InputObject $Candidate -MemberType NoteProperty -Name "HostVms" -Value $HostVms
            $null = Add-Member -InputObject $Candidate -MemberType NoteProperty -Name "NumberOfVms" -Value $HostVms.Count
            $FreeMemory = $CurrentHost.MemoryTotalMB - $CurrentHost.MemoryUsageMB
            $null = Add-Member -InputObject $Candidate -MemberType NoteProperty -Name "FreeMemory" -Value $FreeMemory
            $null = Add-Member -InputObject $Candidate -MemberType NoteProperty -Name "WeightedFreeMemory" -Value ($FreeMemory * (1 - ($HostVms.Count / $MAX_VMS_PER_HOST)))
            $CandidateHosts += $Candidate
        }

        if ($ConsiderMigrations) {
            $CurrentRelocateVmTasks = Get-Task -Server $Server | Where-Object { $_.Name -like "RelocateVM_Task" -and ($_.State -like "Queued" -or $_.State -like "Running") }
            # First, count current migrations per host
            $LeastMigrations = 9999
            foreach ($Candidate in $CandidateHosts) {
                $NumberOfMigrations = 0
                foreach ($RelocateTask in $CurrentRelocateVmTasks) {
                    $TaskVmName = $RelocateTask.ExtensionData.Info.EntityName
                    if ($Candidate.HostVms -contains $TaskVmName) {
                        $NumberOfMigrations++
                    }
                }
                $null = Add-Member -InputObject $Candidate -MemberType NoteProperty -Name "NumberOfMigrations" -Value $NumberOfMigrations
                if ($NumberOfMigrations -lt $LeastMigrations) {
                    $LeastMigrations = $NumberOfMigrations
                }
            }
            # Second, filter out the hosts with least current migrations
            $CandidateHosts = $CandidateHosts | Where-Object { $_.NumberOfMigrations -le $LeastMigrations }
        }

        $CandidateHosts = ($CandidateHosts | Sort-Object WeightedFreeMemory -Descending)
        if (-not $CandidateHosts) {
            throw "No appropriate host found in cluster '$ClusterName'."
        }
        $VMHost = $CandidateHosts[0].Host  # Take the one with most free weighted memory.
        Write-Verbose "Host '$($VMHost.Name)' was chosen."

        $ScriptOut = $VMHost

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
