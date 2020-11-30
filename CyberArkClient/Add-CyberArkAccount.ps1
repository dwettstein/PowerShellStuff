<#
.SYNOPSIS
    Add an account to a CyberArk server.

.DESCRIPTION
    Add an account to a CyberArk server.

    Also have a look at https://github.com/pspete/psPAS for more functionality.

    CyberArk API documentation can be found here: https://docs.cyberark.com/

    File-Name:  Add-CyberArkAccount.ps1
    Author:     David Wettstein
    Version:    v1.0.3

    Changelog:
                v1.0.3, 2020-10-20, David Wettstein: Add function blocks.
                v1.0.2, 2020-05-07, David Wettstein: Reorganize input params.
                v1.0.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.0.0, 2020-03-16, David Wettstein: First implementation.

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
    $Account = & "Add-CyberArkAccount" "safeName" "customPlatformId" "server.example.com" -Interactive -Server "example.com"

.EXAMPLE
    $Account = & "$PSScriptRoot\Add-CyberArkAccount" -Safe "safeName" -PlatformId "customPlatformId" -Address "server.example.com" -DeviceType "Application" -Username "username" -Password "password" -AsJson
#>
[CmdletBinding()]
[OutputType([PSObject])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "Password")]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $Address
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [String] $Safe
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $PlatformId
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [ValidateNotNullOrEmpty()]
    [String] $DeviceType = "Application"
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [ValidateNotNullOrEmpty()]
    [String] $Username = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [ValidateNotNullOrEmpty()]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 8)]
    [Switch] $AsJson
    ,
    [Parameter(Mandatory = $false, Position = 9)]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 10)]
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
        $Safe = & "${FILE_DIR}Sync-CyberArkVariableCache" "Safe" $Safe -IsMandatory
        $PlatformId = & "${FILE_DIR}Sync-CyberArkVariableCache" "PlatformId" $PlatformId -IsMandatory

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
            $Cred = Get-Credential -Message $Address -UserName $Username
            if (-not $Cred -or [String]::IsNullOrEmpty($Cred.GetNetworkCredential().Password)) {
                throw "Password is null or empty."
            }
        } else {
            throw "No credentials found. Please use the input parameters or interactive mode."
        }

        $AccountName = "$DeviceType-$PlatformId-$Address-$($Cred.UserName)"
        Write-Verbose "Account name will be: $AccountName"

        $Body = @{
            "safeName" = $Safe
            "deviceType" = $DeviceType
            "platformId" = $PlatformId
            "address" = $Address
            "name" = $AccountName
            "userName" = $Cred.UserName
            "secretType" = "password"
            "secret" = $Cred.GetNetworkCredential().Password
        }
        $BodyJson = ConvertTo-Json -Depth 10 $Body

        $Endpoint = "/PasswordVault/api/Accounts"
        $Response = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "POST" -Endpoint $Endpoint -Body $BodyJson -AuthorizationToken $AuthorizationToken -ApproveAllCertificates:$ApproveAllCertificates

        # ErrorCode "PASWS027E": The account already exists in CyberArk.
        $ResponseObj = ConvertFrom-Json $Response.Content
        $AccountId = $ResponseObj.id
        Write-Verbose "Account $AccountId successfully added: $($Response.StatusCode)"

        if ($AsJson) {
            # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
            $OutputJson = ConvertTo-Json $ResponseObj -Depth 10 -Compress
            # Replace Unicode chars with UTF8
            $ScriptOut = [Regex]::Unescape($OutputJson)
        } else {
            $ScriptOut = $ResponseObj
        }
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
