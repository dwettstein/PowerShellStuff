<#
.SYNOPSIS
    Generate a PSCredential either with given username and password, or with Get-Credential and export it under the given path (default is "$HOME\.pscredentials"). The input "server" and the current logged-in user will be used as file name: {{server}}-${env:USERNAME}.xml

.DESCRIPTION
    Generate a PSCredential either with given username and password, or with Get-Credential and export it under the given path (default is "$HOME\.pscredentials"). The input "server" and the current logged-in user will be used as file name: {{server}}-${env:USERNAME}.xml

    Info: For importing the credential under the Local System Account, run this script as Scheduled Task with the account "SYSTEM" once.
    Program: powershell.exe
    Arguments: -File "C:\Export-PSCredential.ps1" -Server "{{server}}" -Username "{{username}}" -Password "{{password}}"

    To import the credential in a script use the following code (see also here: https://stackoverflow.com/questions/40029235/save-pscredential-in-the-file):
    $credential = Import-Clixml "$HOME\.pscredentials\$Server-${env:USERNAME}.xml"

    A manual export could be done with:
    Get-Credential "${env:USERNAME}" | Export-Clixml "$HOME\.pscredentials\$Server-${env:USERNAME}.xml"

    File-Name:  Import-PSCredential.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2019-07-26, David Wettstein: First implementation.

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
    [Parameter(Mandatory = $true, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [String] $Path = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

$FileName = "$Server-${env:USERNAME}.xml"
$CredPath = ($Path + "\" + $FileName)
$PSCredential = $null
try {
    if (Test-Path $CredPath) {
        $PSCredential = Import-Clixml -Path $CredPath
        Write-Verbose "PSCredential imported from: $CredPath"
    } else {
        Write-Verbose "No file found at path '$CredPath'."
        # Prompt for credentials, if no file found.
        $PSCredential = Get-Credential -Message $Server -UserName ${env:USERNAME}
        $DoSave = Read-Host -Prompt "Save credential at '$CredPath'? [Y/n] "
        if (-not $DoSave -or $DoSave -match "^[yY]{1}(es)?$") {
            if (-not (Test-Path $Path)) {
                $null = New-Item -ItemType Directory -Path $Path
            }
            $null = Export-Clixml -Path $CredPath -InputObject $PSCredential
            Write-Verbose "PSCredential exported to: $CredPath"
        }
    }
} catch {
    Write-Error "Failed to import PSCredential. Error: $($_.Exception.ToString())"
    exit 1
}
$PSCredential
