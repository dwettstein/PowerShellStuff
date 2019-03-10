<#
.SYNOPSIS
    Export all files within the same folder as module functions.

.DESCRIPTION
    Export all files within the same folder as module functions using the following procedure:
        1. Use the file name without extension as function name
        2. Read the content of the file
        3. Add function wrapper lines
        4. Save as temporary file
        5. Dot-source it
        6. Export function as module member
        7. Delete the temporary file

    File-Name:  Utils.psm1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2018-08-03, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell
#>
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

[String] $FILE_NAME = $MyInvocation.MyCommand.Name
[String] $FILE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition

$ChildItems = Get-ChildItem -Path "$FILE_DIR\*.ps1"

foreach ($Item in $ChildItems) {
    $FunctionName = [System.IO.Path]::GetFileNameWithoutExtension($Item.FullName)
    if ($FunctionName -like $FILE_NAME) {
        continue
    }
    $ItemContent = Get-Content -Path $Item.FullName
    $TempFileName = "$FILE_DIR\$FunctionName.temp.ps1"
    $TempFileContent = ""
    $TempFileContent += "function $FunctionName {`n"
    foreach ($Line in $ItemContent) {
        $TempFileContent += "$Line`n"
    }
    $TempFileContent += "}"

    Set-Content -Encoding UTF8 -Path $TempFileName -Value $TempFileContent
    . $TempFileName

    Export-ModuleMember -Function $FunctionName
    Remove-Item -Path $TempFileName
}
