<#
.SYNOPSIS
    Login to a server and return an authorization token.

.DESCRIPTION
    Login to a server and return an authorization token using the following procedure:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".

    Filename:   Connect-VCloud.ps1
    Author:     David Wettstein
    Version:    1.2.6

    Changelog:
    - v1.2.6, 2021-01-15, David Wettstein: Make script cross-platform.
    - v1.2.5, 2020-12-01, David Wettstein: Refactor error handling.
    - v1.2.4, 2020-10-20, David Wettstein: Add function blocks.
    - v1.2.3, 2020-10-05, David Wettstein: Add param AuthorizationHeader.
    - v1.2.2, 2020-05-07, David Wettstein: Reorganize input params.
    - v1.2.1, 2020-04-09, David Wettstein: Improve path handling.
    - v1.2.0, 2020-04-07, David Wettstein: Sync input variables with cache.
    - v1.1.4, 2020-04-06, David Wettstein: Return a secure string by default.
    - v1.1.3, 2020-03-12, David Wettstein: Refactor and improve credential handling.
    - v1.1.2, 2019-12-17, David Wettstein: Improve parameter validation.
    - v1.1.1, 2019-12-13, David Wettstein: Improve credential handling.
    - v1.1.0, 2019-07-26, David Wettstein: Prompt for credentials and ask to save them.
    - v1.0.0, 2019-05-30, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2021 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $AuthorizationToken = & "Connect-VCloud" "example.com"

.EXAMPLE
    $AuthorizationToken = & "$PSScriptRoot\Connect-VCloud" -Server "example.com" -Organization "system" -Username "user" -Password "changeme" -ApproveAllCertificates
#>
[CmdletBinding()]
[OutputType([String])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "Password")]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Organization = "system"
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $APIVersion = "31.0"
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [ValidateNotNullOrEmpty()]
    [String] $AuthorizationHeader = "x-vcloud-authorization"
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Switch] $AsPlainText
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [String] $Username = "$([System.Environment]::UserName)"  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 8)]
    [ValidateNotNullOrEmpty()]
    [String] $PswdDir = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
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
    # By default, this will load the latest version. Else, add the full path of *.psd1 to the list.
    $Modules = @()
    $Modules | ForEach-Object { Get-Module $_ -ListAvailable | Import-Module -DisableNameChecking }

    function Approve-AllCertificates {
        $CSSource = @'
using System.Net;

public class ServerCertificate {
    public static void approveAllCertificates() {
        ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
    }
}
'@
        if (-not ([System.Management.Automation.PSTypeName]"ServerCertificate").Type) {
            Add-Type -TypeDefinition $CSSource
        }
        # Ignore self-signed SSL certificates.
        [ServerCertificate]::approveAllCertificates()
        # Disable certificate revocation check.
        [System.Net.ServicePointManager]::CheckCertificateRevocationList = $false;
        # Allow all security protocols.
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]"Ssl3,Tls,Tls11,Tls12"
    }
}

process {
    #trap { Write-Error "$($_.Exception)"; $ExitCode = 1; break; }
    $ScriptOut = ""
    try {
        $Server = & "${FILE_DIR}Sync-VCloudVariableCache" "Server" $Server -IsMandatory
        $ApproveAllCertificates = [Boolean] (& "${FILE_DIR}Sync-VCloudVariableCache" "ApproveAllCertificates" $PSBoundParameters.ApproveAllCertificates)

        if ($ApproveAllCertificates) {
            Approve-AllCertificates
        }

        $Cred = & "${FILE_DIR}Get-VCloudPSCredential" -Server $Server -Username $Username -Password $Password -Interactive:$Interactive -PswdDir $PswdDir -ErrorAction:Stop

        $BaseUrl = "https://$Server"
        $EndpointUrl = "$BaseUrl/api/sessions"

        $CredString = $Cred.GetNetworkCredential().Username + "@" + $Organization + ":" + $Cred.GetNetworkCredential().Password
        $CredStringInBytes = [System.Text.Encoding]::UTF8.GetBytes($CredString)
        $CredStringInBase64 = [System.Convert]::ToBase64String($CredStringInBytes)

        $Headers = @{
            "Authorization" = "Basic $CredStringInBase64"
            "Accept" = "application/*+xml;version=$APIVersion"
        }

        $Response = Invoke-WebRequest -Method Post -Headers $Headers -Uri $EndpointUrl
        $AuthorizationToken = $Response.Headers.$AuthorizationHeader
        $AuthorizationTokenSecureString = (ConvertTo-SecureString -AsPlainText -Force $AuthorizationToken | ConvertFrom-SecureString)

        $null = & "${FILE_DIR}Sync-VCloudVariableCache" "AuthorizationToken" $AuthorizationTokenSecureString

        if ($AsPlainText) {
            $ScriptOut = $AuthorizationToken
        } else {
            $ScriptOut = $AuthorizationTokenSecureString
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
