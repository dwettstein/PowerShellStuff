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

    File-Name:  Export-PSCredential.ps1
    Author:     David Wettstein
    Version:    v1.0.2

    Changelog:
                v1.0.0, 2018-08-01, David Wettstein: First implementation.
                v1.0.1, 2019-12-13, David Wettstein: Improve credential handling.
                v1.0.2, 2019-12-17, David Wettstein: Improve parameter validation and documentation.

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
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $Server = "${env:USERDOMAIN}"
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Username = "${env:USERNAME}"
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $Password = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 3)]
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
$ScriptOut = ""
try {
    if ([String]::IsNullOrEmpty($Password)) {
        $PSCredential = Get-Credential -Message $Server -UserName $Username
    } else {
        $PSCredential = New-Object System.Management.Automation.PSCredential ($Username, (ConvertTo-SecureString -AsPlainText -Force $Password))
    }
    if ($PSCredential -and -not [String]::IsNullOrEmpty($PSCredential.GetNetworkCredential().Password)) {
        $DoSave = Read-Host -Prompt "Save credentials at '$CredPath'? [y/N] "
        if ($DoSave -match "^[yY]{1}(es)?$") {
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
