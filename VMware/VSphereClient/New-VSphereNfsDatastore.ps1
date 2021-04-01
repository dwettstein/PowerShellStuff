<#
.SYNOPSIS
    Mount a NFS datastore to a given host or to all hosts of a given cluster.

.DESCRIPTION
    Mount a NFS datastore to a given host or to all hosts of a given cluster.

    File-Name:  New-VSphereNfsDatastore.ps1
    Author:     David Wettstein
    Version:    1.0.1

    Changelog:
                v1.0.1, 2020-12-01, David Wettstein: Refactor error handling.
                v1.0.0, 2020-11-04, David Wettstein: Refactor script and release.
                v0.0.1, 2018-03-19, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Result = & "New-VSphereNfsDatastore" -Server "vcenter.vsphere.local" -Name "datastore_name" -RemotePath "/datastore_name" -RemoteHost "127.0.0.1" -ClusterName "host_cluster_name"

#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [Alias("DatastoreName")]
    [String] $Name
    ,
    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [Alias("DatastoreRemotePath")]
    [String] $RemotePath
    ,
    [Parameter(Mandatory = $true, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [Alias("DatastoreRemoteHost")]
    [String] $RemoteHost
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $ClusterName
    ,
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 4)]
    [String] $VMHostName  # If VMHostName is not given, then ClusterName is mandatory!
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

        # Get given host or get all hosts of given cluster.
        $HostsToUpdate = @()
        if ([String]::IsNullOrEmpty($VMHostName)) {
            if ([String]::IsNullOrEmpty($ClusterName)) {
                throw "One of VMHostName or ClusterName is mandatory!"
            }
            $Cluster = Get-Cluster -Name $ClusterName
            $HostsToUpdate = $Cluster | Get-VMHost | Where-Object { $_.ConnectionState -eq "Connected" }
        } else {
            $VMHost = Get-VMHost -Name $VMHostName
            $HostsToUpdate += $VMHost
        }

        # Assert HostsToUpdate is not null or empty.
        if (-not $HostsToUpdate -or $HostsToUpdate.Length -eq 0) {
            throw "There was no host found to mount the given datastore."
        }

        $HostResults = @()
        $HasError = $false
        # Mount the datastore to hosts.
        foreach ($CurrentHost in $HostsToUpdate) {
            $IsSuccess = $false
            $State = ""
            $HostDatastoreNames = ($CurrentHost | Get-Datastore | ForEach-Object { $_.Name })
            if ($HostDatastoreNames -contains $Name) {
                $IsSuccess = $true
                $State = "already mounted"
            } else {
                try {
                    $Result = New-Datastore -Server $Server -VMHost $CurrentHost -Nfs -Name $Name -Path $RemotePath -NfsHost $RemoteHost -Confirm:$false -WarningAction:SilentlyContinue
                    Write-Verbose "$Result"
                    $IsSuccess = $true
                    $State = "successfully mounted"
                } catch {
                    Write-Verbose "Failed to mount datastore '$Name' to host '$($CurrentHost.Name)':`n$($_.Exception)"
                    $IsSuccess = $false
                    $Ex = $_.Exception
                    while ($Ex.InnerException) { $Ex = $Ex.InnerException }
                    $State = "error: $($Ex.Message)"
                    $HasError = $true
                }
            }

            $Row = @{}
            $Row.Name = $CurrentHost.Name
            $Row.Id = $CurrentHost.Id
            $Row.ConnectionState = "$($CurrentHost.ConnectionState)"
            $Row.PowerState = "$($CurrentHost.PowerState)"
            $Row.Parent = "$($CurrentHost.Parent)"
            $Row.Result = $IsSuccess
            $Row.State = $State
            $HostResults += $Row
        }

        $Datastore = Get-Datastore -Server $Server -Name $Name
        # Assert datastore exists.
        if (-not $Datastore) {
            throw "The datastore '$Name' was not found!"
        }

        $ResultObj = @{
            "Name" = $Datastore.Name
            "Id" = $Datastore.Id
            "Type" = $Datastore.Type
            "State" = "$($Datastore.State)"
            "Datacenter" = "$($Datastore.Datacenter)"
            "RemoteHost" = "$($Datastore.RemoteHost)"
            "RemotePath" = "$($Datastore.RemotePath)"
            "Hosts" = $HostResults
        }  # Build your result object (hashtable)

        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        $ScriptOut = ConvertTo-Json $ResultObj -Depth 10 -Compress

        # Assert no error occurred
        if ($HasError) {
            throw "An error occurred while mounting the datastores! Output: $ScriptOut"
        }

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
