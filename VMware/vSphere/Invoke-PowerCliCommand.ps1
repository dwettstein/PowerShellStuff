<#
.SYNOPSIS
    Wrapper cmdlet for directly invoking any PowerCLI command using the provided credentials, an existing PSCredential or Windows SSPI for authentication.

.DESCRIPTION
    Wrapper cmdlet for directly invoking any PowerCLI command using the provided credentials, an existing PSCredential or Windows SSPI for authentication.

    File-Name:  Invoke-PowerCliCommand.ps1
    Author:     David Wettstein
    Version:    v1.1.0

    Changelog:
                v1.1.0, 2020-04-07, David Wettstein: Sync input variables with cache.
                v1.0.1, 2020-03-13, David Wettstein: Change AsObj to AsJson.
                v1.0.0, 2019-03-10, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    $Result = & ".\Invoke-PowerCliCommand.ps1" "vcenter.vsphere.local" "Get-VM -Name 'vm_name'"

.EXAMPLE
    $Result = & "$PSScriptRoot\Invoke-PowerCliCommand.ps1" -Server "vcenter.vsphere.local" -Command "Get-VM -Name 'vm_name'" -Username "user" -Password "changeme"
#>
[CmdletBinding()]
[OutputType([Object])]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 1)]
    [String] $Command
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [Switch] $AsJson
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Object] $VCenterConnection
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Switch] $DisconnectVCenter
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [String] $Username  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [String] $Password  # secure string or plain text (not recommended)
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

#===============================================================================
# Initialization and Functions
#===============================================================================
# Make sure the necessary modules are loaded.
$Modules = @(
    "VMware.VimAutomation.Core"
)
foreach ($Module in $Modules) {
    if (Get-Module | Where-Object { $_.Name -eq $Module }) {
        # Module already imported. Do nothing.
    } else {
        Import-Module $Module
    }
}

$StartDate = [DateTime]::Now

[String] $FILE_NAME = $MyInvocation.MyCommand.Name
if ($PSVersionTable.PSVersion.Major -lt 3) {
    [String] $FILE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
} else {
    [String] $FILE_DIR = $PSScriptRoot
}

$ExitCode = 0
$ErrorOut = ""
$ScriptOut = ""

Write-Verbose "$($FILE_NAME): CALL."

if ($MyInvocation.MyCommand.Module) {
    $ModulePrivateData = $MyInvocation.MyCommand.Module.PrivateData
    Write-Verbose "$($ModulePrivateData.GetEnumerator() | ForEach-Object { "$($_.Name)=$($_.Value)" })"
    if ($ModulePrivateData.ModuleConfig) {
        $ModuleConfig = Get-Variable -Name $ModulePrivateData.ModuleConfig -ValueOnly
        Write-Verbose "$($ModuleConfig.GetEnumerator() | ForEach-Object { "$($_.Name)=$($_.Value)" })"
    }
}

function Sync-VariableCache ($VarName, $VarValue, [String] $VariableCachePrefix = "", [Switch] $IsMandatory = $false) {
    if (-not (Test-Path Variable:\$($VariableCachePrefix + "VariableCache"))) {  # Don't overwrite the variable if it already exists.
        Set-Variable -Name ($VariableCachePrefix + "VariableCache") -Value @{} -Scope "Global"
    }
    $VariableCache = Get-Variable -Name ($VariableCachePrefix + "VariableCache") -ValueOnly

    if ([String]::IsNullOrEmpty($VarValue)) {
        Write-Verbose "$VarName is null or empty. Try to use value from cache or module config. Mandatory variable? $IsMandatory"
        if (-not [String]::IsNullOrEmpty($VariableCache."$VarName")) {
            $VarValue = $VariableCache."$VarName"
            Write-Verbose "Found value in cache: $VarName = $VarValue"
        } elseif (-not [String]::IsNullOrEmpty($ModuleConfig."$VarName")) {
            $VarValue = $ModuleConfig."$VarName"
            Write-Verbose "Found value in module config: $VarName = $VarValue"
        } else {
            if ($IsMandatory) {
                throw "$VarName is null or empty. Please use the input parameters or the module config."
            }
        }
    } else {
        Write-Verbose "Update cache with variable: $VarName = $VarValue."
        if ([String]::IsNullOrEmpty($VariableCache."$VarName")) {
            $null = Add-Member -InputObject $VariableCache -MemberType NoteProperty -Name $VarName -Value $VarValue -Force
        } else {
            $VariableCache."$VarName" = $VarValue
        }
    }
    $VarValue
}

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    $Server = Sync-VariableCache "Server" $Server "VSphereClient" -IsMandatory
    $VCenterConnection = Sync-VariableCache "VCenterConnection" $VCenterConnection "VSphereClient"

    # First check if given command is from PowerCLI module.
    $Cmdlet = $Command.Split(' ')[0]
    $CmdletModule = (Get-Command $Cmdlet).ModuleName
    Write-Verbose "Given cmdlet '$Cmdlet' is from module '$CmdletModule'."
    if (-not $Modules.Contains($CmdletModule)) {
        throw "Only cmdlets from the following modules are allowed to be invoked: $($Modules -join ',')"
    }

    if (-not $VCenterConnection) {
        $VCenterConnection = & "$FILE_DIR\Connect-VCenter.ps1" -Server $Server -Username $Username -Password $Password
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
    if ($DisconnectVCenter -and $VCenterConnection) {
        $null = Disconnect-VIServer -Server $VCenterConnection -Confirm:$false
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
