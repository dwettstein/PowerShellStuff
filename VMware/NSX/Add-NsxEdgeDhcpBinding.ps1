<#
.SYNOPSIS
    Short description

.DESCRIPTION
    Long description

    File-Name:  Add-NsxEdgeDhcpBinding.ps1
    Author:     David Wettstein
    Version:    v1.0.1

    Changelog:
                v1.0.1, 2020-03-13, David Wettstein: Change AsObj to AsXml.
                v1.0.0, 2019-08-23, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    Example of how to use this cmdlet
#>
[CmdletBinding()]
[OutputType([PSObject])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [String] $Server
    ,
    [Parameter(Mandatory = $true, Position = 1)]
    [ValidatePattern("^edge-\d+$")]
    [String] $EdgeId
    ,
    [Parameter(Mandatory = $true, Position = 2)]
    [ValidatePattern("^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$")]
    [String] $MacAddress
    ,
    [Parameter(Mandatory = $true, Position = 3)]
    [String] $Hostname
    ,
    [Parameter(Mandatory = $true, Position = 4)]
    [ValidatePattern("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")]
    [String] $IpAddress
    ,
    [Parameter(Mandatory = $true, Position = 5)]
    [ValidatePattern("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")]
    [String] $SubnetMask
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [ValidatePattern("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")]
    [String] $DefaultGateway
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [String] $DomainName
    ,
    [Parameter(Mandatory = $false, Position = 8)]
    [Int] $LeaseTime = 86400
    ,
    [Parameter(Mandatory = $false, Position = 9)]
    [String] $PrimaryNameServer
    ,
    [Parameter(Mandatory = $false, Position = 10)]
    [String] $SecondaryNameServer
    ,
    [Parameter(Mandatory = $false, Position = 11)]
    [String] $DhcpOptionNextServer
    ,
    [Parameter(Mandatory = $false, Position = 12)]
    [String] $DhcpOptionTFTPServer
    ,
    [Parameter(Mandatory = $false, Position = 13)]
    [String] $DhcpOptionBootfile
    ,
    [Parameter(Mandatory = $false, Position = 14)]
    [Switch] $AsXml
    ,
    [Parameter(Mandatory = $false, Position = 15)]
    [PSObject] $NsxConnection
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

#===============================================================================
# Initialization and Functions
#===============================================================================
# Make sure the necessary modules are loaded.
$Modules = @(
    "VMware.VimAutomation.Core", "PowerNSX"
)
foreach ($Module in $Modules) {
    if (Get-Module | Where-Object { $_.Name -eq $Module }) {
        # Module already imported. Do nothing.
    } else {
        Import-Module $Module
    }
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
#trap { Write-Error $_; exit 1; break; }

try {
    if (-not $NsxConnection) {
        $NsxConnection = & "$FILE_DIR\Connect-Nsx.ps1" -Server $Server
    }

    # Template for request body
    [Xml] $Body = @"
<staticBinding>
    <macAddress></macAddress>
    <hostname></hostname>
    <ipAddress></ipAddress>
    <subnetMask></subnetMask>
    <leaseTime></leaseTime>
    <autoConfigureDNS>true</autoConfigureDNS>
    <dhcpOptions></dhcpOptions>
</staticBinding>
"@
#     [Xml] $Body = @"
# <staticBinding>
#     <macAddress></macAddress>
#     <hostname></hostname>
#     <ipAddress></ipAddress>
#     <subnetMask></subnetMask>
#     <defaultGateway></defaultGateway>
#     <domainName></domainName>
#     <leaseTime></leaseTime>
#     <autoConfigureDNS>true</autoConfigureDNS>
#     <primaryNameServer></primaryNameServer>
#     <secondaryNameServer></secondaryNameServer>
#     <nextServer></nextServer>
#     <dhcpOptions>
#         <option66></option66>
#         <option67></option67>
#     </dhcpOptions>
# </staticBinding>
# "@

    # Add values from input
    $Body.staticBinding.macAddress = $MacAddress
    $Body.staticBinding.hostname = $Hostname
    $Body.staticBinding.ipAddress = $IpAddress
    $Body.staticBinding.subnetMask = $SubnetMask
    if ($DefaultGateway) {
        Add-XmlElement $Body.staticBinding "defaultGateway" $DefaultGateway
        # $Body.staticBinding.defaultGateway = $DefaultGateway
    }
    if ($DomainName) {
        Add-XmlElement $Body.staticBinding "domainName" $DomainName
        # $Body.staticBinding.domainName = $DomainName
    }
    $Body.staticBinding.leaseTime = [String] $LeaseTime
    if ($PrimaryNameServer) {
        $Body.staticBinding.autoConfigureDNS = "false"
        Add-XmlElement $Body.staticBinding "primaryNameServer" $PrimaryNameServer
        # $Body.staticBinding.primaryNameServer = $PrimaryNameServer
    }
    if ($SecondaryNameServer) {
        $Body.staticBinding.autoConfigureDNS = "false"
        Add-XmlElement $Body.staticBinding "secondaryNameServer" $SecondaryNameServer
        # $Body.staticBinding.secondaryNameServer = $SecondaryNameServer
    }
    if ($DhcpOptionNextServer) {
        Add-XmlElement $Body.staticBinding "nextServer" $DhcpOptionNextServer
        # $Body.staticBinding.nextServer = $DhcpOptionNextServer
    }
    if ($DhcpOptionTFTPServer) {
        Add-XmlElement $Body.staticBinding.dhcpOptions "option66" $DhcpOptionTFTPServer
        # $Body.staticBinding.dhcpOptions.option66 = $DhcpOptionTFTPServer
    }
    if ($DhcpOptionBootfile) {
        Add-XmlElement $Body.staticBinding.dhcpOptions "option67" $DhcpOptionBootfile
        # $Body.staticBinding.dhcpOptions.option67 = $DhcpOptionBootfile
    }

    # Invoke API with this body
    $Uri = "/api/4.0/edges/$EdgeId/dhcp/config/bindings"
    $Response = Invoke-NsxWebRequest -method "POST" -URI $Uri -body $Body.OuterXml -connection $NsxConnection -WarningAction SilentlyContinue
    if ($Response.StatusCode -lt 200 -or $Response.StatusCode -ge 300) {
        throw "Failed to invoke $($Uri): $($Response.StatusCode) - $($Response.Content)"
    }

    if ($AsXml) {
        $ScriptOut = $Response.Content
    } else {
        [Xml] $ResponseXml = $Response.Content
        $ScriptOut = $ResponseXml
    }
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
