<#
.SYNOPSIS
    Get information about one or a list of datastore(s).

.DESCRIPTION
    Get information about one or a list of datastore(s).

    File-Name:  Get-VSphereDatastoreInfo.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2020-11-04, David Wettstein: Refactor script and release.
                v0.0.3, 2018-11-19, David Wettstein: Add switch for reading datastores in a datastore cluster.
                v0.0.2, 2018-06-08, David Wettstein: Add possibilty to give a list of datastore names, add capacity values to output.
                v0.0.1, 2018-03-21, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Result = & "Get-VSphereDatastoreInfo" -Server "vcenter.vsphere.local" -Name "datastore_name"

.EXAMPLE
    $Result = & "Get-VSphereDatastoreInfo" -Server "vcenter.vsphere.local" -Name '["datastore_name1", "datastore_name2"]'
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [Alias("DatastoreName")]
    [String] $Name
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $IsCluster
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

        # Parse datastores from inputs
        $IsList = $false
        try {
            $InputList = $Name | ConvertFrom-Json
            $IsList = $true
        } catch {
            # No list was provided, only one datastore.
            $InputList = $($Name)
        }

        $ResultObj = @{
            "Datastores" = @()
        }  # Build your result object (hashtable)

        $DatastoreNames = @()
        if ($IsCluster) {
            foreach ($Cluster in $InputList) {
                $DatastoreNames += Get-DatastoreCluster -Server $Server -Name $Cluster | Get-Datastore | ForEach-Object { $_.Name }
            }
        } else {
            $DatastoreNames = $InputList
        }
        foreach ($Name in $DatastoreNames) {
            try {
                $Datastore = Get-Datastore -Server $Server -Name $Name
                $Row = @{
                    "Name" = $Datastore.Name
                    "Id" = $Datastore.Id
                    "Type" = $Datastore.Type
                    "State" = "$($Datastore.State)"
                    "CapacityMB" = $Datastore.CapacityMB
                    "CapacityGB" = $Datastore.CapacityGB
                    "FreeSpaceMB" = $Datastore.FreeSpaceMB
                    "FreeSpaceGB" = $Datastore.FreeSpaceGB
                    "Datacenter" = "$($Datastore.Datacenter)"
                    "RemoteHost" = "$($Datastore.RemoteHost)"
                    "RemotePath" = "$($Datastore.RemotePath)"
                }
                $ResultObj.Datastores += $Row
            } catch {
                if (-not $IsList) {
                    throw $_
                }
                $Ex = $_.Exception
                while ($Ex.InnerException) { $Ex = $Ex.InnerException }
                $Row = @{
                    "Name" = $Name
                    "Error" = "$($Ex.Message)"
                }
                $ResultObj.Datastores += $Row
            }
        }

        if (-not $IsList -and -not $IsCluster) {
            # If no list was provided as input, return only the results from the one datastore and not a list.
            $ResultObj = $ResultObj.Datastores[0]
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
