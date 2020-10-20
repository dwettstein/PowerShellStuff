<#
.SYNOPSIS
    Login to a vSphere server using the following order and return a PowerCLI connection:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".
        5. If nothing provided from above, try with PowerCLI and Windows SSPI authentication.

.DESCRIPTION
    Login to a vSphere server using the following order and return a PowerCLI connection:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".
        5. If nothing provided from above, try with PowerCLI and Windows SSPI authentication.

    File-Name:  Connect-VSphere.ps1
    Author:     David Wettstein
    Version:    v2.0.2

    Changelog:
                v2.0.2, 2020-10-20, David Wettstein: Add function blocks.
                v2.0.1, 2020-10-02, David Wettstein: Add param ApproveAllCertificates.
                v2.0.0, 2020-07-20, David Wettstein: Rename script and variables.
                v1.2.2, 2020-05-07, David Wettstein: Reorganize input params.
                v1.2.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.2.0, 2020-04-07, David Wettstein: Sync input variables with cache.
                v1.1.3, 2020-03-12, David Wettstein: Refactor and improve credential handling.
                v1.1.2, 2019-12-17, David Wettstein: Improve parameter validation.
                v1.1.1, 2019-12-13, David Wettstein: Improve credential handling.
                v1.1.0, 2019-07-26, David Wettstein: Prompt for credentials and ask to save them.
                v1.0.0, 2019-03-10, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $VSphereConnection = & "Connect-VSphere" "vcenter.vsphere.local"

.EXAMPLE
    $VSphereConnection = & "$PSScriptRoot\Connect-VSphere" -Server "vcenter.vsphere.local" -Username "user" -Password "changeme"
#>
[CmdletBinding()]
[OutputType([Object])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password')]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Username = "${env:USERNAME}"  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [ValidateNotNullOrEmpty()]
    [String] $PswdDir = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
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
        $ApproveAllCertificates = & "${FILE_DIR}Sync-VSphereVariableCache" "ApproveAllCertificates" $PSCmdlet.MyInvocation.BoundParameters.ApproveAllCertificates

        if ($ApproveAllCertificates) {
            $null = Set-PowerCLIConfiguration -InvalidCertificateAction "Ignore" -Confirm:$false
        }

        $Cred = & "${FILE_DIR}Get-VSpherePSCredential" -Server $Server -Username $Username -Password $Password -Interactive:$Interactive -PswdDir $PswdDir -ErrorAction:Continue

        if ($Cred -and -not [String]::IsNullOrEmpty($Cred.GetNetworkCredential().Password)) {
            $VSphereConnection = Connect-VIServer -Server $Server -Credential $Cred -WarningAction SilentlyContinue
        } else {
            # If no credentials provided, try with PowerCLI and Windows SSPI authentication.
            $VSphereConnection = Connect-VIServer -Server $Server -WarningAction SilentlyContinue
        }

        $null = & "${FILE_DIR}Sync-VSphereVariableCache" "VSphereConnection" $VSphereConnection

        $ScriptOut = $VSphereConnection
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction Continue
        $Ex = $_.Exception; while ($Ex.InnerException) { $Ex = $Ex.InnerException }
        $ErrorOut = "$($Ex.Message)"
        $ExitCode = 1
    } finally {
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
