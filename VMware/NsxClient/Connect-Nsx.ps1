<#
.SYNOPSIS
    Login to a server and return an authorization token.

.DESCRIPTION
    Login to a server and return an authorization token using the following procedure:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".

    Also have a look at https://github.com/vmware/powernsx for more functionality.

    Filename:   Connect-Nsx.ps1
    Author:     David Wettstein
    Version:    2.0.4

    Changelog:
    - v2.0.4, 2021-01-15, David Wettstein: Make script cross-platform.
    - v2.0.3, 2020-12-01, David Wettstein: Refactor error handling.
    - v2.0.2, 2020-10-20, David Wettstein: Add function blocks.
    - v2.0.1, 2020-05-07, David Wettstein: Reorganize input params.
    - v2.0.0, 2020-04-23, David Wettstein: Refactor and get rid of PowerNSX.
    - v1.1.1, 2020-04-09, David Wettstein: Improve path handling.
    - v1.1.0, 2020-04-07, David Wettstein: Sync input variables with cache.
    - v1.0.3, 2020-03-12, David Wettstein: Refactor and improve credential handling.
    - v1.0.2, 2019-12-17, David Wettstein: Improve parameter validation.
    - v1.0.1, 2019-12-13, David Wettstein: Improve credential handling.
    - v1.0.0, 2019-08-23, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2021 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.LINK
    https://github.com/vmware/powernsx

.EXAMPLE
    $AuthorizationToken = & "Connect-Nsx" "example.com"

.EXAMPLE
    $AuthorizationToken = & "$PSScriptRoot\Connect-Nsx" -Server "example.com" -Username "user" -Password "changeme"
#>
[CmdletBinding()]
[OutputType([String])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "Password")]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $UseJWT
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [Switch] $AsPlainText
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $Username = "$([System.Environment]::UserName)"  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [ValidateNotNullOrEmpty()]
    [String] $PswdDir = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
    ,
    [Parameter(Mandatory = $false, Position = 7)]
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
        $Server = & "${FILE_DIR}Sync-NsxVariableCache" "Server" $Server -IsMandatory
        $ApproveAllCertificates = [Boolean] (& "${FILE_DIR}Sync-NsxVariableCache" "ApproveAllCertificates" $PSBoundParameters.ApproveAllCertificates)

        if ($ApproveAllCertificates) {
            Approve-AllCertificates
        }

        $Cred = & "${FILE_DIR}Get-NsxPSCredential" -Server $Server -Username $Username -Password $Password -Interactive:$Interactive -PswdDir $PswdDir -ErrorAction:Stop

        $BaseUrl = "https://$Server"
        $EndpointUrl = "$BaseUrl/api/2.0/services/auth/token"

        $CredString = $Cred.GetNetworkCredential().Username + "@" + $Organization + ":" + $Cred.GetNetworkCredential().Password
        $CredStringInBytes = [System.Text.Encoding]::UTF8.GetBytes($CredString)
        $CredStringInBase64 = [System.Convert]::ToBase64String($CredStringInBytes)

        if ($UseJWT) {
            $Headers = @{
                "Authorization" = "Basic $CredStringInBase64"
                "Accept" = "application/xml"
            }

            $Response = Invoke-WebRequest -Method Post -Headers $Headers -Uri $EndpointUrl
            [Xml] $ResponseXml = $Response.Content
            $AuthorizationToken = "AUTHTOKEN $($ResponseXml.authToken.value)"
        } else {
            $AuthorizationToken = "Basic $CredStringInBase64"
        }
        $AuthorizationTokenSecureString = (ConvertTo-SecureString -AsPlainText -Force $AuthorizationToken | ConvertFrom-SecureString)

        $null = & "${FILE_DIR}Sync-NsxVariableCache" "AuthorizationToken" $AuthorizationTokenSecureString

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
