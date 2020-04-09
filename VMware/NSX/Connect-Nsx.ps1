<#
.SYNOPSIS
    Login to a NSX-V server using the following order and return an authorization token:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".

.DESCRIPTION
    Login to a NSX-V server using the following order and return an authorization token:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".

    Also have a look at https://github.com/vmware/powernsx for more functionality.

    File-Name:  Connect-Nsx.ps1
    Author:     David Wettstein
    Version:    v1.1.1

    Changelog:
                v1.1.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.1.0, 2020-04-07, David Wettstein: Sync input variables with cache.
                v1.0.3, 2020-03-12, David Wettstein: Refactor and improve credential handling.
                v1.0.2, 2019-12-17, David Wettstein: Improve parameter validation.
                v1.0.1, 2019-12-13, David Wettstein: Improve credential handling.
                v1.0.0, 2019-08-23, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.LINK
    https://github.com/vmware/powernsx

.EXAMPLE
    $NsxConnection = & "Connect-Nsx" "nsx.vsphere.local"

.EXAMPLE
    $NsxConnection = & "$PSScriptRoot\Connect-Nsx" -Server "nsx.vsphere.local" -Username "user" -Password "changeme"
#>
[CmdletBinding()]
[OutputType([PSObject])]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Switch] $AsPlainText = $false
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $Username = "${env:USERNAME}"  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [ValidateNotNullOrEmpty()]
    [String] $PswdDir = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [Switch] $AcceptAllCertificates = $false
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
    "VMware.VimAutomation.Core", "PowerNSX"
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

function Approve-AllCertificates {
    $CSSource = @'
using System.Net;

public class ServerCertificate {
    public static void approveAllCertificates() {
        ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
    }
}
'@
    if (-not ([System.Management.Automation.PSTypeName]'ServerCertificate').Type) {
        Add-Type -TypeDefinition $CSSource
    }
    # Ignore self-signed SSL certificates.
    [ServerCertificate]::approveAllCertificates()
    # Disable certificate revocation check.
    [System.Net.ServicePointManager]::CheckCertificateRevocationList = $false;
    # Allow all security protocols.
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
}

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    $Server = Sync-VariableCache "Server" $Server "NSXClient" -IsMandatory
    $AcceptAllCertificates = Sync-VariableCache "AcceptAllCertificates" $AcceptAllCertificate "NSXClient"

    if ($AcceptAllCertificates) {
        Approve-AllCertificates
    }

    # If username is given as SecureString string, convert it to plain text.
    try {
        $UsernameSecureString = ConvertTo-SecureString -String $Username
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($UsernameSecureString)
        $Username = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        $null = [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    } catch {
        # Username was already given as plain text.
    }
    if (-not (Test-Path $PswdDir)) {
        $null = New-Item -ItemType Directory -Path $PswdDir
    }
    $CredPath = Join-Path $PswdDir "$Server-$Username.xml"
    $UserCredPath = Join-Path $PswdDir "$Username.xml"
    $Cred = $null
    if (-not [String]::IsNullOrEmpty($Username) -and -not [String]::IsNullOrEmpty($Password)) {
        # 1. Try with username and password, if provided.
        try {
            $PasswordSecureString = ConvertTo-SecureString -String $Password
        } catch [System.FormatException] {
            # Password was likely given as plain text, convert it to SecureString.
            $PasswordSecureString = ConvertTo-SecureString -AsPlainText -Force $Password
        }
        $Cred = New-Object System.Management.Automation.PSCredential ($Username, $PasswordSecureString)
    } elseif (Test-Path $CredPath) {
        # 2. Try with PSCredential file $Server-$Username.xml.
        $Cred = Import-Clixml -Path $CredPath
        Write-Verbose "Credentials imported from: $CredPath"
    } elseif ($Interactive) {
        # 3. If interactive, get credentials from user with a prompt.
        Write-Verbose "No credentials found at path '$CredPath', get them interactively."
        $Cred = Get-Credential -Message $Server -UserName $Username
        if ($Cred -and -not [String]::IsNullOrEmpty($Cred.GetNetworkCredential().Password)) {
            $DoSave = Read-Host -Prompt "Save credentials at '$CredPath'? [y/N] "
            if ($DoSave -match "^[yY]{1}(es)?$") {
                $null = Export-Clixml -Path $CredPath -InputObject $Cred
                Write-Verbose "Credentials exported to: $CredPath"
            } else {
                Write-Verbose "Credentials not exported."
            }
        } else {
            throw "Password is null or empty."
        }
    } elseif (Test-Path $UserCredPath) {
        # 4. If not interactive, try with PSCredential file $Username.xml.
        $Cred = Import-Clixml -Path $UserCredPath
        Write-Verbose "Credentials imported from: $UserCredPath"
    } else {
        throw "No credentials found. Please use the input parameters or a PSCredential xml file at path '$CredPath'."
    }

    $NsxConnection = Connect-NsxServer -Server $Server -Credential $Cred -DisableVIAutoConnect -WarningAction SilentlyContinue

    $null = Sync-VariableCache "NsxConnection" $NsxConnection "NSXClient"
    if ($ModuleConfig -and [String]::IsNullOrEmpty($ModuleConfig.NsxConnection)) {
        $null = Add-Member -InputObject $ModuleConfig -MemberType NoteProperty -Name "NsxConnection" -Value $NsxConnection -Force
    }

    $ScriptOut = $NsxConnection
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())" -WarningAction Continue
    $ErrorOut = "$($_.Exception.Message)"
    $ExitCode = 1
} finally {
    $EndDate = [DateTime]::Now
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ($EndDate - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        $ScriptOut  # Write ScriptOut to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
