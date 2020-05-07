<#
.SYNOPSIS
    Invokes Terraform and executes the given action in the current or given folder.

    Login to given server using the following order:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".

    Setup of Terraform binaries on Windows:
        1. Download Terrform from https://releases.hashicorp.com/
        2. Extract the archive to a location of your choice.
        3. Create an environment variable `TF_HOME` with that location, add that variable to the `PATH` variable by appending `;%TF_HOME%` to it.
        4. Create another environment variable `TF_PLUGIN_CACHE_DIR` with the value `%TF_HOME%\plugin-cache`.
        5. Download additionally needed plugins.
        6. Extract them into the subfolder with name `plugin-cache`.

    ATTENTION: Be aware that the `TF_LOG` and especially `TF_LOG_PATH` environment variables are not set, otherwise your credentials might be exposed and logged to a file.

.DESCRIPTION
    Invokes Terraform and executes the given action in the current or given folder.

    Login to given server using the following order:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".

    Setup of Terraform binaries on Windows:
        1. Download Terrform from https://releases.hashicorp.com/
        2. Extract the archive to a location of your choice.
        3. Create an environment variable `TF_HOME` with that location, add that variable to the `PATH` variable by appending `;%TF_HOME%` to it.
        4. Create another environment variable `TF_PLUGIN_CACHE_DIR` with the value `%TF_HOME%\plugin-cache`.
        5. Download additionally needed plugins.
        6. Extract them into the subfolder with name `plugin-cache`.

    ATTENTION: Be aware that the `TF_LOG` and especially `TF_LOG_PATH` environment variables are not set, otherwise your credentials might be exposed and logged to a file.

    The following variables are mandatory in your Terraform config file (see also file `vsphere_template.tf.json` for an example):
    {
        "variable": {
            "server": {},
            "username": {},
            "password": {},
            "allow_unverified_ssl": {
                "default": false
            }
        }
    }

    Plugin locations:
    See also: https://www.terraform.io/docs/extend/how-terraform-works.html#plugin-locations
    - `.`: For convenience during plugin development.
    - Location of the terraform binary (/usr/local/bin, for example.)
    - `terraform.d/plugins/<OS>_<ARCH>`: For checking custom providers into a configuration's VCS repository (not recommended).
    - `.terraform/plugins/<OS>_<ARCH>`: Automatically downloaded providers.
    - `~/.terraform.d/plugins/<OS>_<ARCH>` or `%APPDATA%\terraform.d\plugins\<OS>_<ARCH>`: The user plugins directory.

    If Terraform `init` is run with the `-plugin-dir=<PATH>` option, it overrides the default plugin locations and searches only the specified path.

    File-Name:  Invoke-Terraform.ps1
    Author:     David Wettstein
    Version:    v1.0.1

    Changelog:
                v1.0.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.0.0, 2020-03-21, David Wettstein: Refactor and improve credential handling.
                v0.0.1, 2018-10-03, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.LINK
    https://www.terraform.io/docs/

.EXAMPLE
    Invoke-Terraform -Action "apply" -Server "example.com" -Interactive

.EXAMPLE
    $Result = & "Invoke-Terraform" -Action "apply" -Server "example.com" -VarsJson '{"vm_name": "my terraform vm"}'

.EXAMPLE
    $Result = & "$PSScriptRoot\Invoke-Terraform" -Action "apply" -Server "example.com" -Username "user" -Password "changeme" -AutoApprove -AcceptAllCertificates
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("init", "plan", "apply", "refresh", "destroy")]
    [String] $Action = "plan"
    ,
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $VarsJson = "{}"
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $AutoApprove = $false
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [ValidateNotNullOrEmpty()]
    [String] $ConfigDir = ""  # Dir for Terraform `.tf` or `.tf.json` config files
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [ValidateNotNullOrEmpty()]
    [String] $BinaryDir = "${env:TF_HOME}"  # Dir for Terraform binary and plugins (subfolder `plugin-cache`)
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [ValidateNotNullOrEmpty()]
    [String] $Username = "${env:USERNAME}"  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 8)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 9)]
    [ValidateNotNullOrEmpty()]
    [String] $PswdDir = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
    ,
    [Parameter(Mandatory = $false, Position = 10)]
    [Switch] $AcceptAllCertificates = $false
    ,
    [Parameter(Mandatory = $false, Position = 11)]
    [Switch] $Unsafe = $false
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

#===============================================================================
# Initialization and Functions
#===============================================================================
# Make sure the necessary modules are loaded.
$Modules = @()
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
# if ($MyInvocation.MyCommand.Module) {
#     $FILE_DIR = ""  # If this script is part of a module, we want to call module functions not files.
# }

$ExitCode = 0
$ErrorOut = ""
$ScriptOut = ""

Write-Verbose "$($FILE_NAME): CALL."

$CurrentLocation = Get-Location

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    if (-not [String]::IsNullOrEmpty($env:TF_LOG) -or -not [String]::IsNullOrEmpty($env:TF_LOG_PATH)) {
        $Message = "ATTENTION: Environment variable(s) TF_LOG: '${env:TF_LOG}' and/or TF_LOG_PATH: '${env:TF_LOG_PATH}' are set. Your credentials might be exposed and logged to a file. Use the param -Unsafe to proceed anyway."
        Write-Verbose $Message
        if (-not $Unsafe) {
            throw "$Message"
        }
    }

    # Terraform just executes the `.tf` or `.tf.json` config file in the current dir.
    if (-not [String]::IsNullOrEmpty($ConfigDir)) {
        $null = Set-Location "$ConfigDir"
    }

    if (-not [String]::IsNullOrEmpty($BinaryDir)) {
        $BinaryDir = Join-Path -Path $BinaryDir -ChildPath ""
    }
    $Command = "${BinaryDir}terraform.exe $Action"

    if ($Action -ne "init") {
        if ($Interactive) {
            $Cred = & "${FILE_DIR}Get-TerraformPSCredential" -Server $Server -Username $Username -Password $Password -Interactive -PswdDir $PswdDir -ErrorAction:Stop
        } else {
            $Cred = & "${FILE_DIR}Get-TerraformPSCredential" -Server $Server -Username $Username -Password $Password -PswdDir $PswdDir -ErrorAction:Stop
        }

        $Command += " -var 'server=$Server' -var 'username=$($Cred.UserName)' -var 'password=$($Cred.GetNetworkCredential().Password)' -var 'allow_unverified_ssl=$("$AcceptAllCertificates".ToLower())'"

        $Vars = ConvertFrom-Json $VarsJson
        foreach ($Var in (Get-Member -MemberType NoteProperty -InputObject $Vars)) {
            $VarName = $Var.Name
            $VarValue = $Vars."$VarName"
            $Command += " -var '$VarName=$VarValue'"
        }
    }

    # The plugin cache dir can also be specified with the `TF_PLUGIN_CACHE_DIR` environment variable.
    # export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
    if (-not [String]::IsNullOrEmpty($BinaryDir) -and $Action -eq "init") {
        $Command += " -plugin-dir='${BinaryDir}plugin-cache'"
    }

    if ($AutoApprove -and ($Action -eq "apply" -or $Action -eq "destroy")) {
        $Command += " -auto-approve"
    }

    # Redirect stderr to stdout
    $Command += " 2>&1"

    Invoke-Expression -Command $Command
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())" -WarningAction Continue
    $ErrorOut = "$($_.Exception.Message)"
    $ExitCode = 1
} finally {
    if (-not [String]::IsNullOrEmpty($ConfigDir)) {
        $null = Set-Location $CurrentLocation
    }

    $EndDate = [DateTime]::Now
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ($EndDate - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        # $ScriptOut  # Write ScriptOut to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
