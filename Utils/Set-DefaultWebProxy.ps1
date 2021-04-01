<#
.SYNOPSIS
    Set the default web proxy and credentials to default Internet Options
    values, or given custom values.

.DESCRIPTION
    Set the default web proxy and credentials to default Internet Options
    values, or given custom values.

    File-Name:  Set-DefaultWebProxy.ps1
    Author:     David Wettstein
    Version:    1.0.1

    Changelog:
                v1.0.1, 2020-10-20, David Wettstein: Add function blocks.
                v1.0.0, 2020-05-13, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    Set-DefaultWebProxy -Proxy "http://proxy.example.com:8080"

.EXAMPLE
    Set-DefaultWebProxy -Proxy "http://proxy.example.com:8080" -Credential (Get-Credential)
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, Position = 0)]
    [String] $Proxy = $null
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [PSCredential] $Credential = $null
)

begin {
    if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","
}

process {
    if ($Proxy) {
        # If you want to use a proxy that isn't already configured in Internet Options.
        Write-Verbose "Set DefaultWebProxy to '$Proxy'."
        [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy $Proxy
    } else {
        Write-Verbose "Set DefaultWebProxy to 'System Proxy'."
        [System.Net.WebRequest]::DefaultWebProxy = [System.Net.WebRequest]::GetSystemWebProxy()
    }

    if ($Credential) {
        # If you want to use custom proxy credentials.
        Write-Verbose "Use custom Credentials for DefaultWebProxy."
        [System.Net.WebRequest]::DefaultWebProxy.Credentials = $Credential
    } else {
        # If you want to use the Windows credentials of the logged-in user to authenticate with your proxy.
        Write-Verbose "Use DefaultCredentials for DefaultWebProxy."
        [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    }
}

end {}
