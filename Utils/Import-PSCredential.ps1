<#
.SYNOPSIS
    Generate a PSCredential either with given username and password, or with Get-Credential
    and export it under the given path ("$HOME\.pscredentials" by default).

    The inputs $Server (currently logged-in user domain by default) and $Username (currently logged-in user by default)
    will be used as the file name: "$Server-$Username.xml"

.DESCRIPTION
    Generate a PSCredential either with given username and password, or with Get-Credential
    and export it under the given path ("$HOME\.pscredentials" by default).

    The inputs $Server (currently logged-in user domain by default) and $Username (currently logged-in user by default)
    will be used as the file name: "$Server-$Username.xml"

    To import the credential in a script use the following code:
    $credential = Import-Clixml "$HOME\.pscredentials\${env:USERDOMAIN}-${env:USERNAME}.xml"

    A manual export could be done with:
    Get-Credential "${env:USERNAME}" | Export-Clixml "$HOME\.pscredentials\${env:USERDOMAIN}-${env:USERNAME}.xml"

    NOTE: For importing a credential under the Local System Account, run the script Export-PSCredential.ps1 as a
    Scheduled Task using the account "SYSTEM" once:
    - Program: powershell.exe
    - Arguments: -File "C:\Export-PSCredential.ps1" -Server "{{server}}" -Username "{{username}}" -Password "{{password}}"

    File-Name:  Import-PSCredential.ps1
    Author:     David Wettstein
    Version:    v1.0.2

    Changelog:
                v1.0.0, 2019-07-26, David Wettstein: First implementation.
                v1.0.1, 2019-12-13, David Wettstein: Improve credential handling.
                v1.0.2, 2019-12-17, David Wettstein: Improve parameter validation and documentation.

.NOTES
    Copyright (c) 2019 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    .\Import-PSCredential.ps1 -Server '{{server}}'

.EXAMPLE
    $Cred = & "$PSScriptRoot\Utils\Import-PSCredential.ps1" -Server '{{server}}'
#>
[CmdletBinding()]
[OutputType([PSCredential])]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $Server = "${env:USERDOMAIN}"
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Username = "${env:USERNAME}"
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $Path = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

if (-not (Test-Path $Path)) {
    $null = New-Item -ItemType Directory -Path $Path
}
$CredPath = ($Path + "\" + "$Server-$Username.xml")
$PSCredential = $null
try {
    if (Test-Path $CredPath) {
        $PSCredential = Import-Clixml -Path $CredPath
        Write-Verbose "Credentials imported from: $CredPath"
    } else {
        Write-Verbose "No credentials found at path '$CredPath'."
        # Prompt for credentials, if no file found.
        $PSCredential = Get-Credential -Message $Server -UserName $Username
        if ($PSCredential -and -not [String]::IsNullOrEmpty($PSCredential.GetNetworkCredential().Password)) {
            $DoSave = Read-Host -Prompt "Save credentials at '$CredPath'? [y/N] "
            if ($DoSave -match "^[yY]{1}(es)?$") {
                $null = Export-Clixml -Path $CredPath -InputObject $PSCredential
                Write-Verbose "Credentials exported to: $CredPath"
            }
        } else {
            throw "Password was null or empty."
        }
    }
} catch {
    Write-Error "Failed to import credentials. Error: $($_.Exception.ToString())"
    exit 1
}
$PSCredential
