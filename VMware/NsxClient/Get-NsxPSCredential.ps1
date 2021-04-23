<#
.SYNOPSIS
    Get a PSCredential for authentication.

.DESCRIPTION
    Get a PSCredential for authentication using the following order:
        1. Try with username and password, if provided.
        2. Try with PSCredential file "$Server-$Username.xml" in given directory (default "$HOME\.pscredentials").
        3. If interactive, get credentials from user with a prompt.
        4. If not interactive, try with PSCredential file "$Username.xml".

    A manual export could also be done with:
    Get-Credential "$([System.Environment]::UserName)" | Export-Clixml "$HOME\.pscredentials\$([System.Environment]::UserName).xml"

    NOTE: To export a credential file under the Local System Account, run the script Get-PSCredential.ps1 as a
    Scheduled Task using the account "SYSTEM" once:
    - Program: powershell.exe
    - Arguments: -File "C:\Get-PSCredential.ps1" -Server "{{server}}" -Username "{{username}}" -Password "{{password}}"

    File-Name:  Get-PSCredential.ps1
    Author:     David Wettstein
    Version:    2.0.3

    Changelog:
                v2.0.3, 2021-01-15, David Wettstein: Make script cross-platform.
                v2.0.2, 2020-10-20, David Wettstein: Add function blocks.
                v2.0.1, 2020-04-09, David Wettstein: Improve path handling.
                v2.0.0, 2020-03-12, David Wettstein: Refactor credential handling, merge duplicated script.
                v1.0.2, 2019-12-17, David Wettstein: Improve parameter validation and documentation.
                v1.0.1, 2019-12-13, David Wettstein: Improve credential handling.
                v1.0.0, 2019-07-26, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    Get-PSCredential -Server "{{server}}"

.EXAMPLE
    $Cred = & "$PSScriptRoot\Utils\Get-PSCredential" -Server "{{server}}"
#>
[CmdletBinding()]
[OutputType([PSCredential])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "Password")]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $Server = "${env:USERDOMAIN}"
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [String] $Username = "$([System.Environment]::UserName)"  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $Interactive
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [ValidateNotNullOrEmpty()]
    [String] $PswdDir = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
)

begin {
    if (-not $PSBoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","
}

process {
    try {
        # If username is given as SecureString string, convert it to plain text.
        try {
            $UsernameSecureString = ConvertTo-SecureString -String $Username -ErrorAction:SilentlyContinue
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
            } catch {
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
        $Cred
    } catch {
        Write-Error "Failed to get credentials. Error: $($_.Exception)"
    }
}

end {}
