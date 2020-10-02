<#
.SYNOPSIS
    Wrapper cmdlet for directly invoking any PowerCLI command using the provided credentials, an existing PSCredential or Windows SSPI for authentication.

.DESCRIPTION
    Wrapper cmdlet for directly invoking any PowerCLI command using the provided credentials, an existing PSCredential or Windows SSPI for authentication.

    File-Name:  Invoke-VSpherePowerCLICommand.ps1
    Author:     David Wettstein
    Version:    v2.0.1

    Changelog:
                v2.0.1, 2020-10-02, David Wettstein: Check for semicolon and pipes in Command.
                v2.0.0, 2020-07-20, David Wettstein: Rename script and variables.
                v1.1.2, 2020-05-07, David Wettstein: Reorganize input params.
                v1.1.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.1.0, 2020-04-07, David Wettstein: Sync input variables with cache.
                v1.0.1, 2020-03-13, David Wettstein: Change AsObj to AsJson.
                v1.0.0, 2019-03-10, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Result = & "Invoke-VSpherePowerCLICommand" "Get-VM -Name 'vm_name'"

.EXAMPLE
    $Result = & "$PSScriptRoot\Invoke-VSpherePowerCLICommand" -Server "vcenter.vsphere.local" -Command "Get-VM -Name 'vm_name'" -Username "user" -Password "changeme"
#>
[CmdletBinding()]
[OutputType([Object])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [String] $Command
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $AsJson
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Object] $VSphereConnection
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Switch] $Disconnect
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [Switch] $ApproveAllCertificates
)

if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

#===============================================================================
# Initialization and Functions
#===============================================================================
# Make sure the necessary modules are loaded.
$Modules = @(
    "VMware.VimAutomation.Core"
)
$LoadedModules = Get-Module; $Modules | ForEach-Object {
    if ($_ -notin $LoadedModules.Name) { Import-Module $_ -DisableNameChecking }
}

$StartDate = [DateTime]::Now

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

$ExitCode = 0
$ErrorOut = ""
$ScriptOut = ""

Write-Verbose "$($FILE_NAME): CALL."

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    $Server = & "${FILE_DIR}Sync-VSphereVariableCache" "Server" $Server -IsMandatory
    $VSphereConnection = & "${FILE_DIR}Sync-VSphereVariableCache" "VSphereConnection" $VSphereConnection
    $ApproveAllCertificates = & "${FILE_DIR}Sync-VSphereVariableCache" "ApproveAllCertificates" $PSCmdlet.MyInvocation.BoundParameters.ApproveAllCertificates

    # First check if all given commands are from PowerCLI module.
    $Cmdlets = $Command.Split(';').Split('|').Trim()
    foreach ($Cmdlet in $Cmdlets) {
        $Cmdlet = $Cmdlet.Split(' ')[0]
        $CmdletModule = (Get-Command $Cmdlet).ModuleName
        Write-Verbose "Given cmdlet '$Cmdlet' is from module '$CmdletModule'."
        if (-not $Modules.Contains($CmdletModule)) {
            throw "Only cmdlets from the following modules are allowed to be invoked: $($Modules -join ',')"
        }
    }

    if (-not $VSphereConnection) {
        if ($ApproveAllCertificates) {
            $VSphereConnection = & "${FILE_DIR}Connect-VSphere" -Server $Server -ApproveAllCertificates
        } else {
            $VSphereConnection = & "${FILE_DIR}Connect-VSphere" -Server $Server
        }
    }

    Write-Verbose "Execute command: $Command"
    $CommandResult = Invoke-Expression -Command $Command
    Write-Verbose "$CommandResult"

    if ($AsJson) {
        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        try {
            $ScriptOut = ConvertTo-Json $CommandResult -Depth 10 -Compress
        } catch {
            Write-Verbose "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())" -WarningAction Continue
            try {
                # Try again with depth 1, as the exception was likely the following:
                # System.ArgumentException: An item with the same key has already been added.
                $ScriptOut = ConvertTo-Json $CommandResult -Depth 1 -Compress
            } catch {
                Write-Verbose "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())" -WarningAction Continue
                $ResultObj = @{
                    "Name" = $CommandResult.Name
                    "Id" = $CommandResult.Id
                }  # Build your result object (hashtable)
                $ScriptOut = ConvertTo-Json $ResultObj -Depth 10 -Compress
            }
        }
    } else {
        $ScriptOut = $CommandResult
    }
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())" -WarningAction Continue
    $ErrorOut = "$($_.Exception.Message)"
    $ExitCode = 1
} finally {
    if ($Disconnect -and $VSphereConnection) {
        $null = Disconnect-VIServer -Server $VSphereConnection -Confirm:$false
    }

    $EndDate = [DateTime]::Now
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ($EndDate - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        $ScriptOut  # Write ScriptOut to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
