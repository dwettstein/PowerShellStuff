<#
.SYNOPSIS
    Update the password of an account on a CyberArk server.

.DESCRIPTION
    Update the password of an account on a CyberArk server.

    Also have a look at https://github.com/pspete/psPAS for more functionality.

    CyberArk API documentation can be found here: https://docs.cyberark.com/

    File-Name:  Update-CyberArkAccountPassword.ps1
    Author:     David Wettstein
    Version:    v1.0.4

    Changelog:
                v1.0.4, 2020-12-01, David Wettstein: Refactor error handling.
                v1.0.3, 2020-10-20, David Wettstein: Add function blocks.
                v1.0.2, 2020-05-07, David Wettstein: Reorganize input params.
                v1.0.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.0.0, 2020-03-19, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.LINK
    https://github.com/pspete/psPAS

.LINK
    https://docs.cyberark.com/

.EXAMPLE
    $Account = & "Update-CyberArkAccountPassword" $Account -Interactive

.EXAMPLE
    $Account = & "$PSScriptRoot\Update-CyberArkAccountPassword" -Account $Account -Password "password" -Server "example.com"
#>
[CmdletBinding()]
[OutputType([String])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "Password")]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    $Account  # Account ID or output from Get-CyberArkAccount
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Username = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 6)]
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
    $Modules = @()
    $LoadedModules = Get-Module; $Modules | ForEach-Object {
        if ($_ -notin $LoadedModules.Name) { Import-Module $_ -DisableNameChecking }
    }
}

process {
    #trap { Write-Error "$($_.Exception)"; $ExitCode = 1; break; }
    $ScriptOut = ""
    try {
        if ($Account.GetType() -eq [String]) {
            $AccountId = $Account
        } else {
            $AccountId = $Account.id
        }
        # If username is given as SecureString string, convert it to plain text.
        try {
            $UsernameSecureString = ConvertTo-SecureString -String $Username -ErrorAction:SilentlyContinue
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($UsernameSecureString)
            $Username = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            $null = [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        } catch {
            # Username was already given as plain text.
        }
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
        } elseif ($Interactive) {
            # 2. If interactive, get credentials from user with a prompt.
            $Cred = Get-Credential -Message $AccountId -UserName $Username
            if (-not $Cred -or [String]::IsNullOrEmpty($Cred.GetNetworkCredential().Password)) {
                throw "Password is null or empty."
            }
        } else {
            throw "No credentials found. Please use the input parameters or interactive mode."
        }

        $Body = @{
            "ChangeEntireGroup" = $false
            "NewCredentials" = $Cred.GetNetworkCredential().Password
        }
        $BodyJson = ConvertTo-Json -Depth 10 $Body -Compress
        $Endpoint = "/PasswordVault/api/Accounts/$AccountId/Password/Update"
        $Response = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "POST" -Endpoint $Endpoint -Body $BodyJson -AuthorizationToken $AuthorizationToken -ApproveAllCertificates:$ApproveAllCertificates

        if ($Response.StatusCode -lt 200 -or $Response.StatusCode -ge 300) {
            throw "Failed to invoke $($Endpoint): $($Response.StatusCode) - $($Response.Content)"
        }
        Write-Verbose "Password of account $AccountId successfully updated: $($Response.StatusCode)"

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
