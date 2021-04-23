<#
.SYNOPSIS
    Add an existing virtual network adapter to a VM.

.DESCRIPTION
    Add an existing virtual network adapter to a VM.

    File-Name:  Add-VSphereVMNetworkAdapter.ps1
    Author:     David Wettstein
    Version:    1.0.1

    Changelog:
                v1.0.1, 2020-12-01, David Wettstein: Refactor error handling.
                v1.0.0, 2020-11-04, David Wettstein: Refactor script and release.
                v0.0.1, 2018-02-26, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Result = & "Add-VSphereVMNetworkAdapter" -Server "vcenter.vsphere.local" -Name "vm_name" -NetworkName "network_name"
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [Alias("VMName")]
    [String] $Name
    ,
    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $NetworkName
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $NetworkType
    ,
    # An optional MAC address in the format aa:bb:cc:dd:ee:ff
    [Parameter(Mandatory = $false, Position = 3)]
    [ValidatePattern("^(?:[a-fA-F0-9]{2}([-:]))(?:[a-fA-F0-9]{2}\1){4}[a-fA-F0-9]{2}$")]
    [String] $MacAddress
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Boolean] $StartConnected = $true
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [Boolean] $WakeOnLan = $true
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [Alias("VCenter")]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [Object] $VSphereConnection
    ,
    [Parameter(Mandatory = $false, Position = 8)]
    [Switch] $Disconnect
    ,
    [Parameter(Mandatory = $false, Position = 9)]
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

        $VM = Get-VM -Server $Server -Name $Name

        $NetworkAdapter = New-NetworkAdapter -VM $VM -NetworkName $NetworkName -Type $NetworkType -MacAddress $MacAddress -StartConnected:$StartConnected -WakeOnLan:$WakeOnLan
        Write-Verbose "$NetworkAdapter"

        $ResultObj = @{
            "Name" = $VM.Name
            "Id" = $VM.Id
            "Nics" = @()
        }  # Build your result object (hashtable)

        $Nics = Get-NetworkAdapter -Server $Server -VM $VM
        foreach ($Nic in $Nics) {
            $Row = @{}
            $Row.Name = $Nic.Name
            $Row.Id = $Nic.Id
            $Row.NetworkName = $Nic.NetworkName
            $Row.MacAddress = $Nic.MacAddress
            $Row.Type = "$($Nic.Type)"
            $Row.Connected = $Nic.ConnectionState.Connected
            $Row.StartConnected = $Nic.ConnectionState.StartConnected
            $ResultObj.Nics += $Row
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
