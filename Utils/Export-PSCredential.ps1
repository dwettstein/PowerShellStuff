<#
.SYNOPSIS
    Generate a PSCredential either with given username and password, or with Get-Credential and export it under the given path ("$HOME\.pscredentials" by default). The inputs $Server and $Username (currently logged-in user by default) will be used as file name: "$Server-$Username.xml"

.DESCRIPTION
    Generate a PSCredential either with given username and password, or with Get-Credential and export it under the given path ("$HOME\.pscredentials" by default). The inputs $Server and $Username (currently logged-in user by default) will be used as file name: "$Server-$Username.xml"

    Info: For importing the credential under the Local System Account, run this script as Scheduled Task with the account "SYSTEM" once.
    Program: powershell.exe
    Arguments: -File "C:\Export-PSCredential.ps1" -Server "{{server}}" -Username "{{username}}" -Password "{{password}}"

    To import the credential in a script use the following code (see also here: https://stackoverflow.com/questions/40029235/save-pscredential-in-the-file):
    $credential = Import-Clixml "$HOME\.pscredentials\$Server-${env:USERNAME}.xml"

    A manual export could be done with:
    Get-Credential "${env:USERNAME}" | Export-Clixml "$HOME\.pscredentials\$Server-${env:USERNAME}.xml"

    File-Name:  Export-PSCredential.ps1
    Author:     David Wettstein
    Version:    v1.0.1

    Changelog:
                v1.0.0, 2018-08-01, David Wettstein: First implementation.
                v1.0.1, 2019-12-13, David Wettstein: Improve credential handling.

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
    [Parameter(Mandatory = $true, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [String] $Username = "${env:USERNAME}"
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $Path = "$HOME\.pscredentials"  # $HOME for Local System Account: C:\Windows\System32\config\systemprofile
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

if ([String]::IsNullOrEmpty($Username)) {
    $Username = "${env:USERNAME}"
}
if (-not (Test-Path $Path)) {
    $null = New-Item -ItemType Directory -Path $Path
}
$CredPath = ($Path + "\" + "$Server-$Username.xml")
$ScriptOut = ""
try {
    if ([String]::IsNullOrEmpty($Password)) {
        $PSCredential = Get-Credential -Message $Server -UserName $Username
    } else {
        $PSCredential = New-Object System.Management.Automation.PSCredential ($Username, (ConvertTo-SecureString -AsPlainText -Force $Password))
    }
    if ($PSCredential -and -not [String]::IsNullOrEmpty($PSCredential.GetNetworkCredential().Password)) {
        $DoSave = Read-Host -Prompt "Save credentials at '$CredPath'? [Y/n] "
        if (-not $DoSave -or $DoSave -match "^[yY]{1}(es)?$") {
            $null = Export-Clixml -Path $CredPath -InputObject $PSCredential
            $ScriptOut = "Credentials exported to: $CredPath"
        }
    } else {
        throw "Password was null or empty."
    }
} catch {
    Write-Error "Failed to export credentials. Error: $($_.Exception.ToString())"
    exit 1
}
$ScriptOut
