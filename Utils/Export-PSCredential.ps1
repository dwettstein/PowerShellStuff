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

    File-Name:  Export-PSCredential.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2018-08-01, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    .\Export-PSCredential.ps1 -Server '{{server}}' -Username '{{username}}' -Password '{{password}}'

.EXAMPLE
    $Result = & "$PSScriptRoot\Utils\Export-PSCredential.ps1" -Server '{{server}}' -Username '{{username}}' -Password '{{password}}'
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory=$true, Position=0)]
    [String] $Server
    ,
    [Parameter(Mandatory=$false, Position=1)]
    [String] $Username = $null
    ,
    [Parameter(Mandatory=$false, Position=2)]
    [String] $Password = $null
    ,
    [Parameter(Mandatory=$false, Position=3)]
    [String] $Path = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

$FileName = "$Server-${env:USERNAME}.xml"
$OutputMessage = ""
try {
    if ([String]::IsNullOrEmpty($Username)) {
        $Username = "${env:USERNAME}"
    }
    if ([String]::IsNullOrEmpty($Password)) {
        $PSCredential = Get-Credential -Message $Server -UserName $Username
    } else {
        $PSCredential = New-Object System.Management.Automation.PSCredential ($Username, (ConvertTo-SecureString -AsPlainText -Force $Password))
    }

    if (-not (Test-Path $Path)) {
        $null = New-Item -ItemType Directory -Path $Path
    }
    Export-Clixml -Path ($Path + "\" + $FileName) -InputObject $PSCredential
    $OutputMessage = "PSCredential exported to: $($Path + "\" + $FileName)"
} catch {
    $OutputMessage = "Failed to export PSCredential. Error: $($_.Exception.ToString())"
    Write-Error $OutputMessage
    exit 1
}
Write-Verbose $OutputMessage
$OutputMessage
