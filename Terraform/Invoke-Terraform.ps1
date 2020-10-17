<#
.SYNOPSIS
    Invokes Terraform and executes the given action in the current or given folder.

    Login to given server using the following order:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with `TF_VAR_username` and `TF_VAR_password` env vars.
        5. If not interactive, try with PSCredential file "$Username.xml".

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
        4. If not interactive, try with `TF_VAR_username` and `TF_VAR_password` env vars.
        5. If not interactive, try with PSCredential file "$Username.xml".

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
    Version:    v1.0.2

    Changelog:
                v1.0.2, 2020-05-17, David Wettstein: Improve command execution.
                v1.0.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.0.0, 2020-03-21, David Wettstein: Refactor and improve credential handling.
                v0.0.1, 2018-10-03, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.LINK
    https://www.terraform.io/docs/

.EXAMPLE
    Invoke-Terraform -Action "apply" -Server "example.com" -Interactive

.EXAMPLE
    $Result = & "Invoke-Terraform" -Action "apply" -Server "example.com" -VarsJson '{"vm_name": "my terraform vm"}'

.EXAMPLE
    $Result = & "$PSScriptRoot\Invoke-Terraform" -Action "apply" -Server "example.com" -Username "user" -Password "changeme" -AutoApprove -ApproveAllCertificates
#>
[CmdletBinding()]
[OutputType([String])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password')]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("init", "plan", "apply", "refresh", "state", "destroy")]
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
    [Switch] $AutoApprove
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Switch] $NoRefresh
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [Array] $Targets = @()
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [ValidateNotNullOrEmpty()]
    [String] $Args = ""
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [ValidateNotNullOrEmpty()]
    [String] $ConfigDir = ""  # Dir for Terraform `.tf` or `.tf.json` config files
    ,
    [Parameter(Mandatory = $false, Position = 8)]
    [ValidateNotNullOrEmpty()]
    [String] $BinaryDir = "${env:TF_HOME}"  # Dir for Terraform binary and plugins (subfolder `plugin-cache`)
    ,
    [Parameter(Mandatory = $false, Position = 9)]
    [ValidateNotNullOrEmpty()]
    [String] $Username = "${env:USERNAME}"  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 10)]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 11)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 12)]
    [ValidateNotNullOrEmpty()]
    [String] $PswdDir = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
    ,
    [Parameter(Mandatory = $false, Position = 13)]
    [Alias("Insecure")]
    [Switch] $ApproveAllCertificates
    ,
    [Parameter(Mandatory = $false, Position = 14)]
    [Switch] $CredAsCliArgs
    ,
    [Parameter(Mandatory = $false, Position = 15)]
    [Switch] $Unsafe
)

if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

#===============================================================================
# Initialization and Functions
#===============================================================================
# Make sure the necessary modules are loaded.
$Modules = @()
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
# if ($MyInvocation.MyCommand.Module) {
#     $FILE_DIR = ""  # If this script is part of a module, we want to call module functions not files.
# }

$ExitCode = 0
$ErrorOut = ""
# $ScriptOut = ""

Write-Verbose "$($FILE_NAME): CALL."

$CurrentLocation = Get-Location
$CurrentTfVarUsername = [System.Environment]::GetEnvironmentVariable("TF_VAR_username")
$CurrentTfVarPassword = [System.Environment]::GetEnvironmentVariable("TF_VAR_password")

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    if ($CredAsCliArgs) {
        if (-not [String]::IsNullOrEmpty($env:TF_LOG) -or -not [String]::IsNullOrEmpty($env:TF_LOG_PATH)) {
            $Message = "ATTENTION: Environment variable(s) TF_LOG: '${env:TF_LOG}' and/or TF_LOG_PATH: '${env:TF_LOG_PATH}' are set. Your credentials might be exposed and logged to a file. Use the param -Unsafe to proceed anyway."
            Write-Verbose $Message
            if (-not $Unsafe) {
                throw "$Message"
            }
        }
    }

    # Terraform just executes the `.tf` or `.tf.json` config file in the current dir.
    if (-not [String]::IsNullOrEmpty($ConfigDir)) {
        $null = Set-Location "$ConfigDir"
    }

    if (-not [String]::IsNullOrEmpty($BinaryDir)) {
        if (-not (Test-Path $BinaryDir)) {
            throw "Path $BinaryDir not found."
        }
        $BinaryDir = Join-Path -Path $BinaryDir -ChildPath ""
    }

    $Arguments = "$Action"
    if (-not [String]::IsNullOrEmpty($Args)) {
        $Arguments += " $Args"
    }

    if ($Action -eq "init") {
        if (-not [String]::IsNullOrEmpty($BinaryDir)) {
            # The plugin cache dir can also be specified with the `TF_PLUGIN_CACHE_DIR` environment variable.
            # export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
            $Arguments += " -plugin-dir='${BinaryDir}plugin-cache'"
        }
    } elseif ($Action -eq "state") {
        # Advanced (local) state management. No additional args needed.
    } else {
        # Add Terraform input variables.
        $Arguments += " -var 'server=$Server'"
        if ($PSCmdlet.MyInvocation.BoundParameters.ApproveAllCertificates) {
            $Arguments += " -var 'allow_unverified_ssl=$("$ApproveAllCertificates".ToLower())'"
        }

        # Get credentials.
        if (-not [String]::IsNullOrEmpty($env:TF_VAR_username) -and -not [String]::IsNullOrEmpty($env:TF_VAR_password)) {
            # 1. Try with username and password from TF_ENV_ if available.
            try {
                $PasswordSecureString = ConvertTo-SecureString -String $env:TF_VAR_password
            } catch {
                # Password was likely given as plain text, convert it to SecureString.
                $PasswordSecureString = ConvertTo-SecureString -AsPlainText -Force $env:TF_VAR_password
            }
            $Cred = New-Object System.Management.Automation.PSCredential ($env:TF_VAR_username, $PasswordSecureString)
        } else {
            $Cred = & "${FILE_DIR}Get-TerraformPSCredential" -Server $Server -Username $Username -Password $Password -Interactive:$Interactive -PswdDir $PswdDir -ErrorAction:Stop
        }

        # Hand them over to Terraform, either as session ENV or CLI var.
        if ($CredAsCliArgs) {
            $Arguments += " -var 'username=$($Cred.UserName)'"
            $Arguments += " -var 'password=$($Cred.GetNetworkCredential().Password)'"
        } else {
            $env:TF_VAR_username = $Cred.UserName
            $env:TF_VAR_password = $Cred.GetNetworkCredential().Password
        }

        # Add other input variables.
        $Vars = ConvertFrom-Json $VarsJson
        foreach ($Var in (Get-Member -MemberType NoteProperty -InputObject $Vars)) {
            $VarName = $Var.Name
            $VarValue = $Vars."$VarName"
            $Arguments += " -var '$VarName=$VarValue'"
        }

        if ($AutoApprove -and ($Action -eq "apply" -or $Action -eq "destroy")) {
            $Arguments += " -auto-approve"
        }

        if ($NoRefresh) {
            $Arguments += " -refresh=false"
        }

        foreach ($Target in $Targets) {
            $Arguments += " -target=$Target"
        }
    }

    if ($Action -eq "state") {
        # Advanced (local) state management. Execute TF for each given target.
        foreach ($Target in $Targets) {
            Invoke-Expression -Command "${BinaryDir}terraform.exe $Arguments $Target"
        }
    } else  {
        # & "${BinaryDir}terraform.exe" @Arguments
        Invoke-Expression -Command "${BinaryDir}terraform.exe $Arguments"
    }
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction Continue
    $Ex = $_.Exception
    while ($Ex.InnerException) { $Ex = $Ex.InnerException }
    $ErrorOut = "$($Ex.Message)"
    $ExitCode = 1
} finally {
    # Reset session
    $env:TF_VAR_username = $CurrentTfVarUsername
    $env:TF_VAR_password = $CurrentTfVarPassword
    if (-not [String]::IsNullOrEmpty($ConfigDir)) {
        $null = Set-Location $CurrentLocation
    }

    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ([DateTime]::Now - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        # $ScriptOut  # Write ScriptOut to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
