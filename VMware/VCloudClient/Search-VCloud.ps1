<#
.SYNOPSIS
    Query objects of a certain type in a vCloud server.

.DESCRIPTION
    Query objects of a certain type in a vCloud server.

    File-Name:  Search-VCloud.ps1
    Author:     David Wettstein
    Version:    v1.0.3

    Changelog:
                v1.0.3, 2020-10-20, David Wettstein: Add function blocks.
                v1.0.2, 2020-05-07, David Wettstein: Reorganize input params.
                v1.0.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.0.0, 2019-05-30, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Orgs = & "Search-VCloud" -Server $VCloud -Type "organization" -ResultType "OrgRecord"

.EXAMPLE
    $OrgVdcNetworks = Search-VCloud -Server $VCloud -Type "orgVdcNetwork" -ResultType "OrgVdcNetworkRecord" -Filter "(vdc==$OrgVdcId)"

.EXAMPLE
    $OrgVdcVApps = Search-VCloud -Server $VCloud -Type "adminVApp" -ResultType "AdminVAppRecord" -Filter "(vdc==$OrgVdcId)"
#>
[CmdletBinding()]
[OutputType([Array])]
param (
    [Parameter(Mandatory=$true, ValueFromPipeline = $true, Position=0)]
    [String] $Type
    ,
    [Parameter(Mandatory=$true, Position=1)]
    [String] $ResultType
    ,
    [Parameter(Mandatory=$false, Position=2)]
    [String] $Filter = $null  # e.g. (org==foo;vdc==bar)
    ,
    [Parameter(Mandatory=$false, Position=3)]
    [String] $Server
    ,
    [Parameter(Mandatory=$false, Position=4)]
    [String] $AuthorizationToken = $null
    ,
    [Parameter(Mandatory=$false, Position=5)]
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
    $Modules = @()
    $LoadedModules = Get-Module; $Modules | ForEach-Object {
        if ($_ -notin $LoadedModules.Name) { Import-Module $_ -DisableNameChecking }
    }
}

process {
    #trap { Write-Error "$($_.Exception)"; $ExitCode = 1; break; }
    $ScriptOut = ""
    $ErrorOut = ""

    try {
        $Results = @()
        $Page = 1
        do {
            $Endpoint = "/query?type=$Type"
            if (-not [String]::IsNullOrEmpty($Filter)) {
                $Endpoint += "&filter=$Filter"
            }
            $Endpoint += "&page=$Page"
            [Xml] $Response = & "${FILE_DIR}Invoke-VCloudRequest" -Server $Server -Method "GET" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken -ApproveAllCertificates:$ApproveAllCertificates
            if ($Response.QueryResultRecords.total -gt 0) {
                $Results += $Response.QueryResultRecords."$ResultType"
                $Page++
            }
        } while ($Response.QueryResultRecords.Link.rel -contains "nextPage")
        $ScriptOut = $Results
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction Continue
        $Ex = $_.Exception; while ($Ex.InnerException) { $Ex = $Ex.InnerException }
        $ErrorOut = "$($Ex.Message)"
        $ExitCode = 1
    } finally {
        if ([String]::IsNullOrEmpty($ErrorOut)) {
            if ($ScriptOut.Length -le 1) {
                # See here: http://stackoverflow.com/questions/18476634/powershell-doesnt-return-an-empty-array-as-an-array
                ,$ScriptOut  # Write ScriptOut to output stream.
            } else {
                $ScriptOut  # Write ScriptOut to output stream.
            }
        } else {
            Write-Error "$ErrorOut"  # Use Write-Error only here.
        }
    }
}

end {
    Write-Verbose "$($FILE_NAME): ExitCode: $ExitCode. Execution time: $(([DateTime]::Now - $StartDate).TotalMilliseconds) ms. Started: $($StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))."
    # exit $ExitCode
}
