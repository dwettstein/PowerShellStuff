<#
.SYNOPSIS
    Register/add an existing VM using the VMX file.

.DESCRIPTION
    Register/add an existing VM using the VMX file.

    File-Name:  Register-VSphereVM.ps1
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
    $Result = & "Register-VSphereVM" -Server "vcenter.vsphere.local" -Name "vm_name" -VMXPath "[datastore_name] vm_name/vm_name.vmx" -ClusterName "host_cluster_name"

.EXAMPLE
    $Result = & "Register-VSphereVM" -Server "vcenter.vsphere.local" -Name "vm_name" -VMXPath "[datastore_name] vm_name/vm_name.vmx" -ClusterName "host_cluster_name" -ConsiderMigrations
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
    [String] $VMXPath
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $ClusterName
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $VMHostName  # If VMHostName is not given, then ClusterName is mandatory!
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [String] $ResourcePoolName  # If ResourcePoolName is not given, the pool of the cluster will be used.
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [String] $Location  # The Location or also Folder where the VM should be in.
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [Switch] $ConsiderMigrations
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [Alias("VCenter")]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 8)]
    [Object] $VSphereConnection
    ,
    [Parameter(Mandatory = $false, Position = 9)]
    [Switch] $Disconnect
    ,
    [Parameter(Mandatory = $false, Position = 10)]
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

        # Get given destination host for VM or determine it by least memory usage in given cluster.
        if ([String]::IsNullOrEmpty($VMHostName)) {
            if ([String]::IsNullOrEmpty($ClusterName)) {
                throw "One of VMHostName or ClusterName is mandatory!"
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
            if ($ResourcePool.Length -gt 1) {
                $ResourcePool = $ResourcePool[0]  # Try with the first.
            }
        }

        $VMFilePath = $VMXPath -replace "`n|`r"
        $VM = New-VM -Server $Server -VMHost $VMHostName -Name $Name -VMFilePath $VMFilePath -ResourcePool $ResourcePool -Location $Location -Confirm:$false
        Write-Verbose "The VM $($VM.Name) has been successfully registered in vCenter $Server."

        $ResultObj = @{
            "Name" = $VM.Name
            "Id" = $VM.Id
            "PowerState" = $VM.PowerState
            "VMHost" =  $VM.VMHost.Name
            "Cluster" = $VM.VMHost.Parent.Name
            "ResourcePool" = $VM.ResourcePool.Name
            "Folder" = $VM.Folder.Name
        }  # Build your result object (hashtable)

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
