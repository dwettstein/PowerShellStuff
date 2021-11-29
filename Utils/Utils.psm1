<#
.SYNOPSIS
    Export all files within the same folder as module functions.

.DESCRIPTION
    Export all files within the same folder as module functions using the following procedure:
        1. Use the file name without extension as function name.
        2. Read the content of the file.
        3. Add function wrapper lines.
        4. Save as temporary file in system temp path.
        5. Dot-source it.
        6. Export function as module member.
        7. Delete the temporary file.

    Author:     David Wettstein
    Version:    1.1.4

    Changelog:
    - v1.1.4, 2021-01-15, David Wettstein: Make script cross-platform.
    - v1.1.3, 2020-11-14, David Wettstein: Refactor variables.
    - v1.1.2, 2020-10-19, David Wettstein: Load ps1 files recursively.
    - v1.1.1, 2020-04-09, David Wettstein: Improve path handling.
    - v1.1.0, 2020-04-07, David Wettstein: Load module config from XML file.
    - v1.0.1, 2020-03-13, David Wettstein: Use system temp path.
    - v1.0.0, 2018-08-03, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2021 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff
#>
if (-not $PSBoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
if (-not $PSBoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

[String] $FILE_NAME = $MyInvocation.MyCommand.Name
if ($PSVersionTable.PSVersion.Major -lt 3 -or [String]::IsNullOrEmpty($PSScriptRoot)) {
    # Join-Path with empty child path is used to append a path separator.
    [String] $FILE_DIR = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) ""
} else {
    [String] $FILE_DIR = Join-Path $PSScriptRoot ""
}

$ChildItems = Get-ChildItem -Path "${FILE_DIR}" -Recurse -File -Filter "*.ps1"
foreach ($Item in $ChildItems) {
    $FunctionName = [System.IO.Path]::GetFileNameWithoutExtension($Item.FullName)
    if ($FunctionName -like $FILE_NAME) {
        continue
    }
    $ItemContent = Get-Content -Path $Item.FullName

    $FileContent = ""
    $FileContent += "function $FunctionName {`n"
    foreach ($Line in $ItemContent) {
        $FileContent += "$Line`n"
    }
    $FileContent += "}"

    $FileName = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "$FunctionName.ps1"
    Set-Content -Encoding UTF8 -Path $FileName -Value $FileContent
    . $FileName  # Dot-source the file to load the function into current scope.

    Export-ModuleMember -Function $FunctionName
    Remove-Item -Path $FileName
}

# Load module config from an XML file and export it under the same variable name as in PrivateData section of *.psd1 file.
# NOTE: $MyInvocation.MyCommand.Module.PrivateData is not yet accessible here.
# See also: https://stackoverflow.com/questions/22269275/accessing-privatedata-during-import-module
[String] $ModuleName = (Get-Item $PSCommandPath).BaseName
[String] $ModuleConfigVariableName = $ModuleName.Replace(".", "_")
[String] $ModuleConfigPath = Join-Path -Path $FILE_DIR -ChildPath "$ModuleName.xml"

if (-not (Test-Path Variable:\$($ModuleConfigVariableName))) {  # Don't overwrite the variable if it already exists.
    $ModuleConfig = @{}
    if (Test-Path -Path $ModuleConfigPath) {
        Write-Verbose "Loading module configuration file from path: $ModuleConfigPath"
        $ModuleConfig = (Import-Clixml -Path $ModuleConfigPath)
    }
    Set-Variable -Name $ModuleConfigVariableName -Value $ModuleConfig -Force
}

Export-ModuleMember -Variable $ModuleConfigVariableName
