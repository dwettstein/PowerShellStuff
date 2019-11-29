# PowerShell Quick Style Guide

This guide is intended to be a short overview of [The PowerShell Best Practices and Style Guide](https://poshcode.gitbooks.io/powershell-practice-and-style/).

Author(s): David Wettstein

This work is licensed under the [Creative Commons Attribution-ShareAlike 4.0 International License](https://creativecommons.org/licenses/by-sa/4.0/). All attributions and credits for [The PowerShell Best Practices and Style Guide](https://poshcode.gitbooks.io/powershell-practice-and-style/) go to Don Jones, Matt Penny, Carlos Perez, Joel Bennett and the PowerShell Community.

If you rather search a cheat sheet, I recommend the PDF from Warren Frame: [PowerShell Cheat Sheet](powershell-cheat-sheet.pdf)
<br/>(Source: [PowerShell Cheat Sheet](http://ramblingcookiemonster.github.io/images/Cheat-Sheets/powershell-cheat-sheet.pdf), all credits go to [Warren Frame](http://ramblingcookiemonster.github.io/).)


## Table of Contents

- [PowerShell Quick Style Guide](#powershell-quick-style-guide)
  - [Table of Contents](#table-of-contents)
- [Style Guide](#style-guide)
  - [Code Layout and Formatting](#code-layout-and-formatting)
  - [Function Structure](#function-structure)
  - [Documentation and Comments](#documentation-and-comments)
  - [Naming Conventions](#naming-conventions)


# Style Guide


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
- Follow either the _Stroustrup_ or the _One True Brace Style (1TBS or OTBS)_ brace style
    - Write the opening brace always on the same line and the closing brace on a new line!
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
    [string] $ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $Result = & "$ScriptPath\Invoke-AnotherScript.ps1" -Param1 "Value"
    ```
- Avoid using `~`, instead use `$env:USERPROFILE`.

Read the full page [Naming Conventions](https://poshcode.gitbooks.io/powershell-practice-and-style/Style-Guide/Naming-Conventions.html) for more information.
