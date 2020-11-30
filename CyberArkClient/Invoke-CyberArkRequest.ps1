<#
.SYNOPSIS
    Wrapper cmdlet for directly invoking any RESTful API request on the given server,
    using the provided authorization token, e.g. "Basic username:password",
    or an existing PSCredential for authentication.

.DESCRIPTION
    Wrapper cmdlet for directly invoking any RESTful API request on the given server,
    using the provided authorization token, e.g. "Basic username:password",
    or an existing PSCredential for authentication.

    File-Name:  Invoke-ServerRequest.ps1
    Author:     David Wettstein
    Version:    v1.1.2

    Changelog:
                v1.1.2, 2020-10-20, David Wettstein: Add function blocks.
                v1.1.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.1.0, 2020-04-07, David Wettstein: Sync input variables with cache.
                v1.0.1, 2020-03-13, David Wettstein: Refactor and generalize cmdlet.
                v1.0.0, 2019-05-30, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Result = & "Invoke-ServerRequest" "/api/v1/version"

.EXAMPLE
    [Xml] $Result = & "$PSScriptRoot\Invoke-ServerRequest" -Server "example.com" -Endpoint "/api/v1/version" -Method "GET" -MediaType "application/*+xml" -ApproveAllCertificates
#>
[CmdletBinding()]
[OutputType([Object])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $Endpoint
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateSet("GET", "POST", "PUT", "PATCH", "UPDATE", "DELETE")]
    [String] $Method = "GET"
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [ValidateNotNullOrEmpty()]
    [String] $Body = $null
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [ValidateSet("application/*", "application/json", "application/xml", "application/*+xml", "application/x-www-form-urlencoded", "multipart/form-data", "text/plain", "text/xml", IgnoreCase = $false)]
    [String] $MediaType = "application/json"
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [ValidateNotNullOrEmpty()]
    [String] $AuthorizationHeader = "Authorization"
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [ValidateSet("http", "https", IgnoreCase = $false)]
    [String] $Protocol = "https"
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
        $Server = & "${FILE_DIR}Sync-CyberArkVariableCache" "Server" $Server -IsMandatory
        $AuthorizationToken = & "${FILE_DIR}Sync-CyberArkVariableCache" "AuthorizationToken" $AuthorizationToken
        $ApproveAllCertificates = [Boolean] (& "${FILE_DIR}Sync-CyberArkVariableCache" "ApproveAllCertificates" $PSCmdlet.MyInvocation.BoundParameters.ApproveAllCertificates)

        $BaseUrl = "${Protocol}://$Server"
        $EndpointUrl = "${BaseUrl}${Endpoint}"

        $Headers = @{
            "Accept" = "$MediaType"
            "Content-Type" = "$MediaType"
            "Cache-Control" = "no-cache"
        }

        # If no AuthorizationToken is given, try to get it.
        if ([String]::IsNullOrEmpty($AuthorizationToken)) {
            $AuthorizationToken = & "${FILE_DIR}Connect-CyberArk" -Server $Server -ApproveAllCertificates:$ApproveAllCertificates
        }
        # If AuthorizationToken is given as SecureString string, convert it to plain text.
        try {
            $AuthorizationTokenSecureString = ConvertTo-SecureString -String $AuthorizationToken
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AuthorizationTokenSecureString)
            $AuthorizationToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            $null = [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        } catch {
            # AuthorizationToken was already given as plain text.
        }
        if (-not [String]::IsNullOrEmpty($AuthorizationToken)) {
            $Headers."$AuthorizationHeader" = "$AuthorizationToken"
        }

        if ($Body) {
            $Response = Invoke-WebRequest -Method $Method -Headers $Headers -Uri $EndpointUrl -Body $Body
        } else {
            $Response = Invoke-WebRequest -Method $Method -Headers $Headers -Uri $EndpointUrl
        }

        $ScriptOut = $Response
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction:Continue
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
