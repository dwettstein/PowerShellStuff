<#
.SYNOPSIS
    Invoke a Net.HttpWebRequest with given parameters. Returns a hashtable with keys "StatusCode", "Headers", "Response".

.DESCRIPTION
    Invoke a Net.HttpWebRequest with given parameters. Returns a hashtable with keys "StatusCode", "Headers", "Response".

    File-Name:  Invoke-HttpRequest.ps1
    Author:     David Wettstein
    Version:    v1.1.0

    Changelog:
                v1.0.0, 2016-04-13, David Wettstein: First implementation.
                v1.0.1, 2016-10-17, David Wettstein: Add minor improvements.
                v1.0.2, 2018-08-01, David Wettstein: Update code formatting.
                v1.1.0, 2019-01-10, David Wettstein: Add switch for enabling all security protocols.

.NOTES
    Copyright (c) 2018 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    .\Invoke-HttpRequest.ps1 -Method GET -Uri "https://example.com"

.EXAMPLE
    .\Invoke-HttpRequest.ps1 -Method GET -Uri "https://example.com/api/users?name=David" -Headers @{"Accept"="application/json"; "Authorization"="Basic dXNlcm5hbWU6cGFzc3dvcmQ="} -AcceptAllCertificates
#>
[CmdletBinding()]
[OutputType([Hashtable])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidatePattern('^(http[s]?)(:\/\/)([\S]+)$')]
    [String] $Uri
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'UPDATE', 'DELETE', IgnoreCase = $true)]  # See also -Method here: https://technet.microsoft.com/en-us/library/hh849901%28v=wps.620%29.aspx
    [String] $Method = "GET"
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [Hashtable] $Headers = @{ }
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [String] $Body
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Switch] $AcceptAllCertificates = $false
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

#===============================================================================
# Initialization and Functions
#===============================================================================

function Get-ResponseBody {
    Param (
        [Parameter(Mandatory = $true, Position = 0)]
        $Response
        ,
        [Parameter(Mandatory = $false, Position = 1)]
        [String] $AcceptType
    )

    $ResponseStream = $Response.GetResponseStream()
    $StreamReader = New-Object System.IO.StreamReader($ResponseStream)

    $ResponseString = ""
    while ($StreamReader.Peek() -ge 0) {
        $ResponseString = $ResponseString + $StreamReader.ReadLine()
    }
    $StreamReader.Close()

    $ResponseBody = $null
    try {
        if ($AcceptType -eq "JSON") {
            $ResponseBody = ConvertFrom-Json $ResponseString
        } else {
            $ResponseBody = ([xml] $ResponseString).DocumentElement
        }
    } catch {
        # Write-Warning "The response string was not JSON or XML, unable to convert. Exception: $($_.Exception.ToString())"
        $ResponseBody = $ResponseString
    }
    $ResponseBody
}

function Approve-AllCertificates {
    $CSSource = @'
using System.Net;

public class ServerCertificate {
    public static void approveAllCertificates() {
        ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
    }
}
'@
    if (-not ([System.Management.Automation.PSTypeName]'ServerCertificate').Type) {
        Add-Type -TypeDefinition $CSSource
    }
    # Ignore self-signed SSL certificates.
    [ServerCertificate]::approveAllCertificates()
    # Disable certificate revocation check.
    [System.Net.ServicePointManager]::CheckCertificateRevocationList = $false;
    # Allow all security protocols.
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
}

$StartDate = [DateTime]::Now

[String] $FILE_NAME = $MyInvocation.MyCommand.Name
if ($PSVersionTable.PSVersion.Major -lt 3) {
    [String] $FILE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
} else {
    [String] $FILE_DIR = $PSScriptRoot
}

$ExitCode = 0
$ErrorOut = ""
$ScriptOut = ""

Write-Verbose "$($FILE_NAME): CALL."

#===============================================================================
# Main
#===============================================================================
trap { Write-Error $_; exit 1; break; }

try {
    Write-Verbose "Create HttpWebRequest '$Method' with URI: '$Uri'"

    if ($AcceptAllCertificates) {
        Approve-AllCertificates
    }

    $Request = [Net.HttpWebRequest]::Create("$Uri")
    $Request.Method = $Method

    $LocalHeaders = $Headers.Clone()
    $AcceptType = ""
    # This is needed for Powershell 3.0.
    if ($LocalHeaders.Contains("Accept")) {
        $AcceptValue = $LocalHeaders.Item("Accept")
        if ($AcceptValue.ToLower().Contains("json")) {
            $AcceptType = "JSON"
        } else {
            $AcceptType = "XML"
        }
        $Request.Accept = $AcceptValue
        $LocalHeaders.Remove("Accept")
    }
    if ($LocalHeaders.Contains("Content-Type")) {
        $Request.ContentType = $LocalHeaders.Item("Content-Type")
        $LocalHeaders.Remove("Content-Type")
    }

    foreach ($HeaderKey in $LocalHeaders.Keys) {
        if ([Net.WebHeaderCollection]::IsRestricted($HeaderKey)) {
            Write-Warning "The header '$HeaderKey' is restricted, skip it. See here for more information: https://stackoverflow.com/questions/239725/cannot-set-some-http-headers-when-using-system-net-webrequest#4752359"
            continue
        } else {
            $Request.Headers.Add($HeaderKey, $LocalHeaders.Item($HeaderKey))
        }
    }

    # Add request body
    if (-not [String]::IsNullOrEmpty($Body)) {
        if ($Method.ToLower() -eq "post" -or $Method.ToLower() -eq "put" -or $Method.ToLower() -eq "patch") {
            $Buffer = [Text.Encoding]::Ascii.GetBytes($Body)
            $Request.ContentLength = $Buffer.Length

            $RequestStream = $Request.GetRequestStream()
            $RequestStream.Write($Buffer, 0, $Buffer.length)
            $RequestStream.Flush()
            $RequestStream.Close()
        }
    }

    $Response = $null
    try {
        $Response = [Net.HttpWebResponse] $Request.GetResponse()
        Write-Verbose "Received response status code: $($Response.StatusCode.value__)"

        $StatusCode = $Response.StatusCode.value__
        $ResponseBody = Get-ResponseBody -response $Response -acceptType $AcceptType
        $ResponseHeaders = $Response.Headers
    } catch [Net.WebException] {
        $StatusCode = $_.Exception.Response.StatusCode.value__
        if ($null -eq $StatusCode) {
            throw $_  # Re-throw if request could not be executed.
        }
        Write-Verbose "Catched WebException, StatusCode '$StatusCode', exception: '$_'"

        $ResponseBody = Get-ResponseBody -Response $_.Exception.Response -AcceptType $acceptType
        if ([String]::IsNullOrEmpty($ResponseBody)) {
            $ResponseBody = @{
                "ErrorCode" = $_.Exception.Response.StatusCode
                "Response" = $_.Exception.Response
            }
        }
        $ResponseHeaders = @{ }
    } finally {
        $ResultObj = @{
            "StatusCode" = $StatusCode
            "Response" = $ResponseBody
            "Headers" = $ResponseHeaders
        }  # Build your result object (hashtable)

        if ($null -ne $Response) {
            $Response.Close()
        }
    }

    # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
    # $ScriptOut = ConvertTo-Json $ResultObj -Depth 10 -Compress
    $ScriptOut = $ResultObj
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())" -WarningAction Continue
    $ErrorOut = "$($_.Exception.Message)"
    $ExitCode = 1
} finally {
    $EndDate = [DateTime]::Now
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ($EndDate - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        $ScriptOut  # Write ScriptOut to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
