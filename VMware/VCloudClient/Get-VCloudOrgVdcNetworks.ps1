<#
.SYNOPSIS
    Get all OrgVdc Networks of a vCloud server.

.DESCRIPTION
    Get all OrgVdc Networks of a vCloud server. To exclude shared networks use the param -ExcludeShared. This is only possible when a OrgVdc was given.

    Filename:   Get-VCloudOrgVdcNetworks.ps1
    Author:     David Wettstein
    Version:    1.0.4

    Changelog:
    - v1.0.4, 2020-12-01, David Wettstein: Refactor error handling.
    - v1.0.3, 2020-10-20, David Wettstein: Add function blocks.
    - v1.0.2, 2020-05-07, David Wettstein: Reorganize input params.
    - v1.0.1, 2020-04-09, David Wettstein: Improve path handling.
    - v1.0.0, 2019-09-17, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2021 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    Example of how to use this cmdlet
#>
[CmdletBinding()]
[OutputType([Array])]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [ValidatePattern(".*[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}.*")]
    [String] $OrgVdc = $null
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $IncludeShared
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 4)]
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
    # By default, this will load the latest version. Else, add the full path of *.psd1 to the list.
    $Modules = @()
    $Modules | ForEach-Object { Get-Module $_ -ListAvailable | Import-Module -DisableNameChecking }
}

process {
    #trap { Write-Error "$($_.Exception)"; $ExitCode = 1; break; }
    $ScriptOut = ""
    try {
        $Filter = $null
        if (-not [String]::IsNullOrEmpty($OrgVdc)) {
            $Filter = "(vdc==$OrgVdc)"
        }
        $OrgVdcNetworks = & "${FILE_DIR}Search-VCloud" -Server $Server -Type "orgVdcNetwork" -ResultType "OrgVdcNetworkRecord" -Filter $Filter -AuthorizationToken $AuthorizationToken -ApproveAllCertificates:$ApproveAllCertificates

        $ScriptOut = @()
        if ($OrgVdc -and $IncludeShared) {
            $ScriptOut = $OrgVdcNetworks
        } else {
            foreach ($OrgVdcNetwork in $OrgVdcNetworks) {
                $OrgVdcNetworkOwnerId = & "${FILE_DIR}Split-VCloudId" -UrnOrHref $OrgVdcNetwork.vdc
                if ($OrgVdcNetwork.isShared -and -not ($OrgVdcNetworkOwnerId -eq $OrgVdc)) {
                    Write-Verbose "OrgVdc network '$($OrgVdcNetwork.name)' is shared and owner is '$($OrgVdcNetwork.vdcName)', skip it."
                    continue
                } else {
                    $ScriptOut += $OrgVdcNetwork
                }
            }
        }

        if ($ScriptOut.Length -le 1) {
            # See here: http://stackoverflow.com/questions/18476634/powershell-doesnt-return-an-empty-array-as-an-array
            , $ScriptOut  # Write $ScriptOut to output stream.
        } else {
            $ScriptOut  # Write $ScriptOut to output stream.
        }
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction:Continue
        $Ex = $_.Exception; while ($Ex.InnerException) { $Ex = $Ex.InnerException }
        # Add error to $ErrorOut and continue with next item to process or end block.
        $ErrorOut += if ($ErrorOut) { "`n$($Ex.Message)" } else { "$($Ex.Message)" }
        $ExitCode = 1
    } finally {
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
