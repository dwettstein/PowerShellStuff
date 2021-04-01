<#
.SYNOPSIS
    Encrypt the given string with either the given key or default Windows Data Protection API (DPAPI).

.DESCRIPTION
    Encrypt the given string with either the given key or default Windows Data Protection API (DPAPI).

    File-Name:  ConvertTo-EncryptedString.ps1
    Author:     David Wettstein
    Version:    1.0.1

    Changelog:
                v1.0.1, 2020-10-20, David Wettstein: Add function blocks.
                v1.0.0, 2018-09-05, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    ConvertTo-EncryptedString -String "Plain Text String"

.EXAMPLE
    ConvertTo-EncryptedString -String "Plain Text String" -Key "changeme0123456789"

.EXAMPLE
    $EncryptedString = & "$PSScriptRoot\Utils\ConvertTo-EncryptedString" -String "Plain Text String" -Key "changeme0123456789"
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $String  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Key = $null  # secure string or plain text (not recommended)
)

begin {
    if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","

    function Get-PlainText($Text, $KeyInBytes = $null) {
        # If text is given as SecureString string, convert it to plain text.
        try {
            $InputSecureString = ConvertTo-SecureString -String $Text -Key $KeyInBytes
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($InputSecureString)
            $Text = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            $null = [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        } catch {
            # The text was already given as plain text.
        }
        $Text
    }

    function Get-KeyInBytes($Text) {
        $Length = $Text.Length
        $Pad = 32 - $Length
        if ($Length -lt 16 -or $Length -gt 32) {
            throw "The key must be between 16 and 32 characters long in plain text!"
        }
        [System.Text.Encoding]::UTF8.GetBytes($KeyPlainText + "0" * $Pad)
    }
}

process {
    $KeyInBytes = $null
    if (-not [String]::IsNullOrEmpty($Key)) {
        $KeyPlainText = Get-PlainText -Text $Key
        $KeyInBytes = Get-KeyInBytes -Text $KeyPlainText
    }

    [String] $StringPlainText = Get-PlainText -Text $String
    $SecureString = New-Object System.Security.SecureString
    $StringChars = $StringPlainText.ToCharArray()
    foreach ($Char in $StringChars) {
        $SecureString.AppendChar($Char)
    }

    ConvertFrom-SecureString -SecureString $SecureString -Key $KeyInBytes
}

end {}
