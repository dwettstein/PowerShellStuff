<#
.SYNOPSIS
    Search and get accounts including secrets from a CyberArk server.

.DESCRIPTION
    Search and get accounts including secrets from a CyberArk server.

    Also have a look at https://github.com/pspete/psPAS for more functionality.

    CyberArk API documentation can be found here: https://docs.cyberark.com/

    File-Name:  Get-CyberArkAccount.ps1
    Author:     David Wettstein
    Version:    1.2.4

    Changelog:
                v1.2.4, 2020-12-01, David Wettstein: Refactor error handling.
                v1.2.3, 2020-10-20, David Wettstein: Add function blocks.
                v1.2.2, 2020-05-07, David Wettstein: Reorganize input params.
                v1.2.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.2.0, 2020-03-19, David Wettstein: Implement get account by id.
                v1.1.0, 2020-03-15, David Wettstein: Add more switches, use SecureString as default.
                v1.0.1, 2020-03-13, David Wettstein: Change AsObj to AsJson.
                v1.0.0, 2019-07-26, David Wettstein: First implementation.

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
    $Account = & "Get-CyberArkAccount" "query params"

.EXAMPLE
    $Account = & "Get-CyberArkAccount" -Account $Account -Server "example.com"

.EXAMPLE
    $Account = & "$PSScriptRoot\Get-CyberArkAccount" -Query "query params" -AsJson
#>
[CmdletBinding()]
[OutputType([PSObject])]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $Query
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    $Account  # Account ID or output from Get-CyberArkAccount
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $Safe
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $AsCredential
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Switch] $AsPlainText
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [Switch] $AsJson
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
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
        $Safe = & "${FILE_DIR}Sync-CyberArkVariableCache" "Safe" $Safe

        if (-not [String]::IsNullOrEmpty($Account)) {
            if ($Account.GetType() -eq [String]) {
                $AccountId = $Account
            } else {
                $AccountId = $Account.id
            }
            $Endpoint = "/PasswordVault/api/Accounts/$AccountId"
            $Response = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "GET" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken -ApproveAllCertificates:$ApproveAllCertificates
            Write-Verbose "Account $AccountId successfully found: $($Response.StatusCode)"
            $ResponseObj = ConvertFrom-Json $Response.Content
            $Accounts = @()
            $Accounts += $ResponseObj
        } else {
            if ([String]::IsNullOrEmpty($Query)) {
                throw "One of parameter Query or Account is mandatory!"
            }
            Add-Type -AssemblyName System.Web
            $EncodedQuery = [System.Web.HttpUtility]::UrlEncode($Query)
            $QueryEndpoint = "/PasswordVault/api/Accounts?search=$EncodedQuery"
            if (-not [String]::IsNullOrEmpty($Safe)) {
                $EncodedSafe = [System.Web.HttpUtility]::UrlEncode("safename eq $Safe")
                $QueryEndpoint += "&filter=$EncodedSafe"
            }
            $Response = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "GET" -Endpoint $QueryEndpoint -AuthorizationToken $AuthorizationToken -ApproveAllCertificates:$ApproveAllCertificates
            $ResponseObj = ConvertFrom-Json $Response.Content
            Write-Verbose "Found $($ResponseObj.count) account(s) matching the query '$Query'."
            $Accounts = $ResponseObj.value
        }

        foreach ($Account in $Accounts) {
            $RetrieveEndpoint = "/PasswordVault/api/Accounts/$($Account.id)/Password/Retrieve"
            $RetrieveResponse = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "POST" -Endpoint $RetrieveEndpoint -AuthorizationToken $AuthorizationToken -ApproveAllCertificates:$ApproveAllCertificates
            $Password = $RetrieveResponse.Content.Trim('"')

            if ($AsPlainText) {
                Add-Member -InputObject $Account -MemberType NoteProperty -Name "secretValue" -Value $Password -Force
            } else {
                if (-not [String]::IsNullOrEmpty($Password)) {
                    $PasswordSecureString = ConvertTo-SecureString -AsPlainText -Force $Password
                }
                Add-Member -InputObject $Account -MemberType NoteProperty -Name "secretValue" -Value (ConvertFrom-SecureString $PasswordSecureString) -Force
            }
        }

        if ($AsJson) {
            # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
            $OutputJson = ConvertTo-Json $Accounts -Depth 10 -Compress
            # Replace Unicode chars with UTF8
            $ScriptOut = [Regex]::Unescape($OutputJson)
        } else {
            if ($AsCredential) {
                $ScriptOut = @()
                foreach ($Account in $Accounts) {
                    try {
                        $PasswordSecureString = ConvertTo-SecureString -String $Account.secretValue
                    } catch [System.FormatException] {
                        # Password was likely given as plain text, convert it to SecureString.
                        $PasswordSecureString = ConvertTo-SecureString -AsPlainText -Force $Account.secretValue
                    }
                    $Cred = New-Object System.Management.Automation.PSCredential ($Account.userName, $PasswordSecureString)
                    $ScriptOut += $Cred
                }
            } else {
                $ScriptOut = $Accounts
            }
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
