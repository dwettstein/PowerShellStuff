# PowerShell Quick Style Guide

This guide is intended to be a short overview of [The PowerShell Best Practices and Style Guide](https://poshcode.gitbooks.io/powershell-practice-and-style/) and some additional tips based on my experience.

Author: David Wettstein<br/>
Version: 1.3.0, 2021-04-23<br/>
License: Copyright (c) 2019-2021 David Wettstein, http://wettste.in, licensed under the [Creative Commons Attribution-ShareAlike 4.0 International License (CC BY-SA 4.0)](https://creativecommons.org/licenses/by-sa/4.0/).<br/>
All attributions and credits for [The PowerShell Best Practices and Style Guide](https://poshcode.gitbooks.io/powershell-practice-and-style/) go to Don Jones, Matt Penny, Carlos Perez, Joel Bennett and the PowerShell Community.

If you rather search a cheat sheet, I recommend the PDF from Warren Frame: [PowerShell Cheat Sheet](powershell-cheat-sheet.pdf)
<br/>(Source: [PowerShell Cheat Sheet](http://ramblingcookiemonster.github.io/images/Cheat-Sheets/powershell-cheat-sheet.pdf), all credits go to [Warren Frame](http://ramblingcookiemonster.github.io/).)


**Table of Contents**

- [PowerShell Quick Style Guide](#powershell-quick-style-guide)
  - [Code Layout and Formatting](#code-layout-and-formatting)
  - [Function Structure](#function-structure)
  - [Documentation and Comments](#documentation-and-comments)
  - [Naming Conventions](#naming-conventions)
  - [Tips and Common Pitfalls](#tips-and-common-pitfalls)


## Code Layout and Formatting

- Capitalization Conventions
    - Use _PascalCase_ or _camelCase_ for all public identifiers: module names, function or cmdlet names, class, enum, and attribute names, public fields or properties, global variables and constants, parameters etc.
        ```powershell
        [String] $MyVariable = "A typed variable."
        ```
    - PowerShell language keywords are written in _lowercase_ (e.g. `if`, `foreach`), as well as operators such as `-eq` and `-match`.
        ```powershell
        if ($MyVariable -eq "AnyValue") {
            # ...
        ```
    - Keywords in comment-based help are written in _UPPERCASE_ (e.g. `.SYNOPSIS`).
        ```powershell
        <#
        .SYNOPSIS
            A short description...
        #>
        ```
    - Function names should follow PowerShell's _Verb-Noun_ naming conventions, using _PascalCase_ within both Verb and Noun (list allowed verbs with the cmdlet `Get-Verb`).
        ```powershell
        function Invoke-HttpRequest {
            # ...
        ```
- Start all scripts or functions with `[CmdletBinding()]`.
    ```powershell
    function Invoke-HttpRequest {
        [CmdletBinding()]
        param (
            # ...
    ```
- Follow either the _Stroustrup_ or the _One True Brace Style (1TBS or OTBS)_ brace style. Write the opening brace always on the same line and the closing brace on a new line!
    ```powershell
    function Invoke-HttpRequest {
        # ...
        end {
            if ($MyVariable -eq "AnyValue") {
                # either Stroustrup:
            }
            elseif {
                # or 1TBS:
            } else {
                # ...
            }
        }
    }
    ```
- Indentation and line handling
    - Use four spaces per indentation level (and never tabs!).
    - Lines should not have trailing whitespace.
    - Limit lines to 115 characters when possible, but avoid backticks.
    - Surround function and class definitions with two blank lines (similar to Python).
    - Method definitions within a class are surrounded by a single blank line (similar to Python).
    - End each file with a single blank line.
    - I recommend using [EditorConfig](https://editorconfig.org/) plugin to automatically set indentation levels and trim trailing whitespaces. Example config (create new file `.editorconfig` in root folder):
        ```text
        root = true

        [*]
        indent_style = space
        indent_size = 4
        charset = utf-8
        trim_trailing_whitespace = true
        insert_final_newline = true
        ```
- Put spaces around keywords, operators and special characters
    ```powershell
    # Bad
    if($MyVariable-eq"AnyValue"){
        $Index=$MyVariable.Length+1
    }

    # Good
    if ($MyVariable -eq "AnyValue") {
        $Index = $MyVariable.Length + 1
    }
    ```
- Avoid using semicolons `;` as line terminators
    - PowerShell will not complain about extra semicolons, but they are unnecessary.
    - When declaring hashtables, which extend past one line, put each element on it's own line.

Read the full page [Code Layout and Formatting](https://poshcode.gitbooks.io/powershell-practice-and-style/Style-Guide/Code-Layout-and-Formatting.html) for more information.


## Function Structure

- When declaring simple functions leave a space between the function name and the parameters.
- For advanced functions follow PowerShell's _Verb-Noun_ naming conventions as mentioned in section [Code Layout and Formatting](#Code-Layout-and-Formatting).

- Avoid using the `return` keyword in your functions. Just place the object variable on its own.
    ```powershell
    function MyAddition ($Number1, $Number2) {
        $Result = $Number1 + $Number2
        $Result
    }
    ```
- When using blocks, return objects inside the `process` block and not in `begin` or `end`.
- When using parameters from pipeline use at least a `process` block.
- Specify an `OutputType` attribute if the advanced function returns an object or collection of objects.
    ```powershell
    function Invoke-HttpRequest {
        [CmdletBinding()]
        [OutputType([PSObject])]
        param(
            # ...
    ```
- For validating function or script parameters, use validation attributes (e.g. `ValidateNotNullOrEmpty` or `ValidatePattern`)
    ```powershell
    function Invoke-HttpRequest {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
            [ValidatePattern("^http(s)?.*")]
            [String] $Url
        )
        # ...
    ```

Read the full page [Function Structure](https://poshcode.gitbooks.io/powershell-practice-and-style/Style-Guide/Function-Structure.html) for more information.


## Documentation and Comments

- Indent comments to the same level as the corresponding code.
- Each comment line should start with a # and a single space.
- Keep comments up-to-date when code changes.
- Write comments in English and as complete sentences.
- Inline comments should be separated with two spaces.
    ```powershell
    $MyVariable = $null  # Declare variable
    ```
- Comments should serve to your reasoning and decision-making, not attempt to explain what a command does.
    ```powershell
    # Bad
    # Decrease length by one
    $LastIndex = $MyVariable.Length - 1

    # Good
    # Indices usually start at 0, thus subtract one to access the last char.
    $LastIndex = $MyVariable.Length - 1
    ```
- When documenting functions, place the comment inside the function at the top, instead of above.
- Provide usage examples when documenting functions (`.EXAMPLE`)

Read the full page [Documentation and Comments](https://poshcode.gitbooks.io/powershell-practice-and-style/Style-Guide/Documentation-and-Comments.html) for more information.


## Naming Conventions

- Use the full name of each command instead of aliases or short forms.
- Additionally, use full parameter names.
    ```powershell
    # Bad
    gps Explorer

    # Good
    Get-Process -Name Explorer
    ```
- Use full, explicit paths when possible (avoid `..` or `.`).
    ```powershell
    # Bad
    $Result = & ".\Invoke-AnotherScript.ps1" -Param1 "Value"

    # Good
    $Result = & "$PSScriptRoot\Invoke-AnotherScript.ps1" -Param1 "Value"
    ```
- Avoid using `~`, instead use `$HOME` or `$env:USERPROFILE`.

Read the full page [Naming Conventions](https://poshcode.gitbooks.io/powershell-practice-and-style/Style-Guide/Naming-Conventions.html) for more information.


## Tips and Common Pitfalls

- When creating a new file, ensure that the encoding is _UTF-8_. Be aware that PowerShell creates files with encoding _UTF-8 with BOM_ by default. See also [What's the difference between UTF-8 and UTF-8 without BOM?](https://stackoverflow.com/questions/2223882/whats-the-difference-between-utf-8-and-utf-8-without-bom) and [Using PowerShell to write a file in UTF-8 without the BOM](https://stackoverflow.com/questions/5596982/using-powershell-to-write-a-file-in-utf-8-without-the-bom).
    ```powershell
    # Attention: Out-File writes UTF8 with BOM!
    Write-Output $Text | Out-File -Encoding UTF8 -FilePath $Path -Append
    # As an alternative use:
    [System.IO.File]::AppendAllText($Path, "$Text`n")
    ```
- See `Get-Verb` to list all approved PowerShell verbs, always use one of them for your functions.
- Directly use the [automatic variables](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables), e.g. `$MyInvocation` or `$PSBoundParameters`, instead of the `$PSCmdlet.MyInvocation.*` variants, as the $PSCmdlet variable is only available when the `[CmdletBinding()]` attribute is given. See also [Any difference or drawback of using $MyInvocation instead of $PSCmdlet.MyInvocation](https://stackoverflow.com/questions/66060418/any-difference-or-drawback-of-using-myinvocation-instead-of-pscmdlet-myinvocat).
- `$ErrorActionPreference` is set to `Continue` by default, thus the script continues to run even after an error happens. Additionally, `$WarningActionPreference` is set to `Continue` as well, and thus unwanted output might be in the standard output of your script. Add the following code at the beginning of your script to change the default behavior:
    ```powershell
    if (-not $PSBoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    ```
- Even when you add `-ErrorAction:SilentlyContinue`, the errors are written to the error stream (but not displayed). To ignore all error output use `-ErrorAction:Ignore` or stream redirection and append ` 2>$null`.
- The results of each statement are added to the output stream and thus returned as script output, not only the ones containing the `return` keyword.
    - Use `$null = {{statement}}` or `{{statement}} | Out-Null`, to ignore certain results.
- When invoking other scripts within your script, use explicit not relative paths.
    - Since PowerShell 3.0 you can get the directory of the current script with `$PSScriptRoot`.
- Avoid blocking/waiting statements, like `Read-Host` or `Get-Credential`, in scripts that are run as child processes or in background.
- When using `ConvertTo-Json` be aware that the default value for the parameter `-Depth` is only `2`.
    > _-Depth [\<Int32\>]_<br/>
    > &emsp;_Specifies how many levels of contained objects are included in the JSON representation. The default value is 2._
- Additionally `ConvertTo-Json` replaces special characters with _Unicode_ escape characters. See also [ConvertTo-Json problem containing special characters](https://stackoverflow.com/questions/29306439/powershell-convertto-json-problem-containing-special-characters). If you need the unescaped characters, use the following code:
    ```powershell
    $UnescapedJson = [Regex]::Unescape($EscapedJson)
    ```
- For returning/printing a string with a colon (`:`) or text right after a variable, use `"${MyVariable}"` instead of `"$MyVariable"`.
    ```powershell
    # Error
    Write-Verbose "$Result: $env:USERNAME_Will_Be_A_Pro"

    # Good
    Write-Verbose "${Result}: ${env:USERNAME}_Will_Be_A_Pro"
    ```
- Since PowerShell is a dynamically typed language, it won't return an empty array or an array with only one item, but either `$null` or the item on its own. See also [PowerShell doesn't return an empty array as an array](https://stackoverflow.com/questions/18476634/powershell-doesnt-return-an-empty-array-as-an-array). To return such an array, use the following code:
    ```powershell
    if ($Result.Length -le 1) {
        , $Result  # Force PowerShell to return $Result as array.
    } else {
        $Result  # $Result is an array anyway.
    }
    ```
- When using a `exit $ExitCode` statement in a script or function, be aware that if you dot-source and execute it (also when importing as module), the current console will be exited. To set an exit code, but not close the console, use the following code:
    ```powershell
    # Set the script/function exit code. Can be accessed with `$LASTEXITCODE` automatic variable.
    & "powershell.exe" "-NoLogo" "-NoProfile" "-NonInteractive" "-Command" "exit $ExitCode"

    Write-Host $LASTEXITCODE
    ```
