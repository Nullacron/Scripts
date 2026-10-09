# --- Baked-in Engine Configuration ---
# Pervasive Source engine DLL flags that clutter inline comments
$commonOmitFlags = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('clientdll', 'gamedll', 'client', 'game'),
    [System.StringComparer]::OrdinalIgnoreCase
)

# --- UI Helpers ---

function Write-Banner {
    Clear-Host
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "                    SOURCE CVARLIST FORMATTER" -ForegroundColor Yellow
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$StepNum, [string]$Title)
    Write-Host "`n[$StepNum] $Title" -ForegroundColor Yellow
}

function Prompt-Choice {
    param(
        [string[]]$Options,
        [int]$DefaultIndex = 1
    )
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $num = $i + 1
        $marker = if ($num -eq $DefaultIndex) { "*" } else { " " }
        Write-Host "  [$num]$marker $($Options[$i])" -ForegroundColor Gray
    }
    while ($true) {
        $raw = Read-Host "  Choose option [1-$($Options.Count)] (Default: $DefaultIndex)"
        if ([string]::IsNullOrWhiteSpace($raw)) { return $DefaultIndex }
        $val = 0
        if ([int]::TryParse($raw, [ref]$val) -and $val -ge 1 -and $val -le $Options.Count) {
            return $val
        }
        Write-Host "  [!] Invalid choice. Please enter 1-$($Options.Count)." -ForegroundColor Red
    }
}

function Prompt-YesNo {
    param(
        [string]$Message,
        [bool]$Default = $true
    )
    $defStr = if ($Default) { "Y/n" } else { "y/N" }
    while ($true) {
        $ans = Read-Host "  $Message [$defStr]"
        if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
        if ($ans -match '^(y|yes)$') { return $true }
        if ($ans -match '^(n|no)$')  { return $false }
        Write-Host "  [!] Please enter 'y' or 'n'." -ForegroundColor Red
    }
}

function Show-FlagsGrid {
    param([string[]]$FlagsList)
    $colWidth = 24
    $cols = 3
    for ($i = 0; $i -lt $FlagsList.Count; $i++) {
        $itemStr = "[$($i + 1)] $($FlagsList[$i])".PadRight($colWidth)
        Write-Host -NoNewline "  $itemStr" -ForegroundColor Cyan
        if (($i + 1) % $cols -eq 0 -or ($i + 1) -eq $FlagsList.Count) { Write-Host "" }
    }
    Write-Host ""
}

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# Safely imports Source engine CSV dumps, sanitizing empty header columns
function Import-SourceCvarCsv {
    param([string]$FilePath)
    try {
        $text = [System.IO.File]::ReadAllText($FilePath)
        $firstNewline = $text.IndexOf("`n")
        if ($firstNewline -lt 0) { return @() }

        $headerLine = $text.Substring(0, $firstNewline).TrimEnd("`r")
        $bodyText   = $text.Substring($firstNewline + 1)

        # Replace empty columns like ,," or ,, with dummy header names
        $counter = 1
        $pattern = ',(?=(,|$))|,""(?=(,|$))'
        $sanitizedHeader = [regex]::Replace($headerLine, $pattern, {
            $script:counter++
            return ",'EXTRA_COL_$($script:counter - 1)'"
        })

        $sanitizedContent = $sanitizedHeader + "`r`n" + $bodyText
        return ($sanitizedContent | ConvertFrom-Csv)
    } catch {
        return @()
    }
}

function Test-IsCompatibleCsv {
    param([string]$FilePath)
    try {
        $firstLine = (Get-Content -Path $FilePath -TotalCount 1)
        return ($firstLine -match '"Name"' -and $firstLine -match '"Value"' -and $firstLine -match '"Help Text"')
    } catch {
        return $false
    }
}

function Format-EntryComment {
    param(
        $Entry,
        [string]$CategoryFlag,
        [bool]$OmitCategoryFlag,
        [System.Collections.Generic.HashSet[string]]$CommonOmitFlags
    )

    $cParts = [System.Collections.Generic.List[string]]::new()

    $displayFlags = [System.Collections.Generic.List[string]]::new()
    foreach ($fl in $Entry.Flags) {
        if ($CommonOmitFlags.Contains($fl)) { continue }
        if ($OmitCategoryFlag -and -not [string]::IsNullOrWhiteSpace($CategoryFlag) -and $fl -eq $CategoryFlag) {
            continue
        }
        $displayFlags.Add($fl)
    }

    if ($displayFlags.Count -gt 0) {
        $cParts.Add("(" + ($displayFlags -join ", ") + ")")
    }

    if (-not [string]::IsNullOrWhiteSpace($Entry.Help)) {
        $cParts.Add($Entry.Help)
    }

    if ($cParts.Count -gt 0) {
        return ($cParts -join " ")
    }
    return ""
}

# --- Initialization ---

Write-Banner

$workDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($workDir)) { $workDir = (Get-Location).Path }

Write-Host "[i] Scanning directory: $workDir" -ForegroundColor DarkGray

$allCsvFiles = Get-ChildItem -Path $workDir -Filter "*.csv" -File
$compatibleFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

foreach ($file in $allCsvFiles) {
    if (Test-IsCompatibleCsv -FilePath $file.FullName) {
        $compatibleFiles.Add($file)
    }
}

# --- Tutorial Fallback (If No Files Found) ---
if ($compatibleFiles.Count -eq 0) {
    Write-Host "`n[!] No compatible cvarlist CSV dumps found in this directory." -ForegroundColor Red
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "          HOW TO DUMP 'cvarlist.csv' IN VANILLA SOURCE" -ForegroundColor Yellow
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  1. Launch your Source game (Portal 2, Half-Life 2, TF2, CS:S, etc.)." -ForegroundColor White
    Write-Host "  2. Open the developer console (~) and enter:" -ForegroundColor White
    Write-Host "         cvarlist log cvarlist.csv" -ForegroundColor Green
    Write-Host ""
    Write-Host "  3. The engine creates 'cvarlist.csv' inside the game's MOD subfolder:" -ForegroundColor White
    Write-Host "     - Portal 2          : .../Portal 2/portal2/cvarlist.csv" -ForegroundColor Gray
    Write-Host "     - Half-Life 2       : .../Half-Life 2/hl2/cvarlist.csv" -ForegroundColor Gray
    Write-Host "     - Team Fortress 2   : .../Team Fortress 2/tf/cvarlist.csv" -ForegroundColor Gray
    Write-Host "     - Counter-Strike: S : .../Counter-Strike Source/cstrike/cvarlist.csv" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  4. Copy 'cvarlist.csv' into the folder where this script is located:" -ForegroundColor White
    Write-Host "         $workDir" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  5. Re-run this script!" -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ""
    $null = Read-Host "Press Enter to exit..."
    exit 0
}

Write-Host "[+] Found $($compatibleFiles.Count) compatible CSV dump file(s):" -ForegroundColor Green
foreach ($f in $compatibleFiles) {
    Write-Host "    - $($f.Name)" -ForegroundColor White
}

# Dynamically discover all flag columns across compatible CSVs
$discoveredFlags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($file in $compatibleFiles) {
    $rows = Import-SourceCvarCsv -FilePath $file.FullName
    if ($rows.Count -gt 0) {
        $cols = $rows[0].PSObject.Properties.Name
        foreach ($c in $cols) {
            if ($c -notin @('Name', 'Value', 'Help Text') -and $c -notmatch '^EXTRA_COL_') {
                [void]$discoveredFlags.Add($c.ToLowerInvariant())
            }
        }
    }
}
$sortedFlags = @($discoveredFlags | Sort-Object)

# --- Interactive Prompts ---

# 1. Output File Naming Scheme
Write-Step "1/5" "Output File Naming Scheme"
$namingOption = Prompt-Choice -Options @(
    "Use source file name as base (e.g., cvarlist_cheat_cvars.cfg)",
    "Descriptors only / No base name (e.g., ccoms.cfg, cheat_cvars.cfg)",
    "Specify a custom base name (e.g., mygame_cheat_cvars.cfg)"
) -DefaultIndex 1

$customBaseName = ""
if ($namingOption -eq 3) {
    while ([string]::IsNullOrWhiteSpace($customBaseName)) {
        $customBaseName = (Read-Host "  Enter custom base name").Trim()
    }
}

# 2. ConCommands Handling
Write-Step "2/5" "ConCommands ('cmd') Handling"
$ccomOption = Prompt-Choice -Options @(
    "Keep ConCommands and ConVars together",
    "Separate into different files ('_ccoms' and '_cvars')",
    "Completely exclude ConCommands (ConVars only)"
) -DefaultIndex 1

# 3. Flag Routing / File Filtering
Write-Step "3/5" "Flag Routing / File Filtering"
$flagActionOption = Prompt-Choice -Options @(
    "Do not filter or route flags to separate files",
    "Exclude entries containing specified flags entirely",
    "Route entries containing specified flags into their own file(s)"
) -DefaultIndex 1

$selectedFlags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

if ($flagActionOption -ne 1) {
    Write-Host "`n  Available Flags in Dataset ($($sortedFlags.Count)):" -ForegroundColor Yellow
    Show-FlagsGrid -FlagsList $sortedFlags

    while ($true) {
        $inputFlags = Read-Host "  Enter flag numbers or names to select (comma-separated, e.g. 1, 4, cheat)"
        if (-not [string]::IsNullOrWhiteSpace($inputFlags)) {
            $tokens = $inputFlags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            foreach ($tok in $tokens) {
                $idx = 0
                if ([int]::TryParse($tok, [ref]$idx) -and $idx -ge 1 -and $idx -le $sortedFlags.Count) {
                    [void]$selectedFlags.Add($sortedFlags[$idx - 1])
                } elseif ($discoveredFlags.Contains($tok)) {
                    [void]$selectedFlags.Add($tok.ToLowerInvariant())
                } else {
                    Write-Host "  [!] Warning: Flag '$tok' not found, skipping." -ForegroundColor Yellow
                }
            }
            if ($selectedFlags.Count -gt 0) {
                Write-Host "  [OK] Active flag filter: $($selectedFlags -join ', ')" -ForegroundColor Green
                break
            }
        }
        Write-Host "  [!] Please select at least one flag." -ForegroundColor Red
    }
}

# 4. Flag Categorization & Priority Bias
Write-Step "4/5" "Section Categorization and Priority Bias"
$enableCategorization = Prompt-YesNo -Message "Categorize output files into banner sections by flag priority?" -Default $true
$priorityFlags        = [System.Collections.Generic.List[string]]::new()
$omitCategoryFlag     = $false

if ($enableCategorization) {
    Write-Host "`n  Available Flags for Categorization:" -ForegroundColor Yellow
    Show-FlagsGrid -FlagsList $sortedFlags

    while ($true) {
        Write-Host "  Enter flags in PRIORITY order (left-to-right, e.g. replicated, archive, cheat):" -ForegroundColor Cyan
        $inputPrio = Read-Host "  Priority Flags"
        if (-not [string]::IsNullOrWhiteSpace($inputPrio)) {
            $pTokens = $inputPrio -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            foreach ($tok in $pTokens) {
                $idx = 0
                if ([int]::TryParse($tok, [ref]$idx) -and $idx -ge 1 -and $idx -le $sortedFlags.Count) {
                    $matchedFlag = $sortedFlags[$idx - 1].ToLowerInvariant()
                    if (-not $priorityFlags.Contains($matchedFlag)) { $priorityFlags.Add($matchedFlag) }
                } elseif ($discoveredFlags.Contains($tok)) {
                    $matchedFlag = $tok.ToLowerInvariant()
                    if (-not $priorityFlags.Contains($matchedFlag)) { $priorityFlags.Add($matchedFlag) }
                } else {
                    Write-Host "  [!] Warning: Flag '$tok' not found, skipping." -ForegroundColor Yellow
                }
            }
            if ($priorityFlags.Count -gt 0) {
                break
            }
        }
        Write-Host "  [!] Please specify at least one valid priority flag." -ForegroundColor Red
    }

    $omitCategoryFlag = Prompt-YesNo -Message "Omit the section's flag from each command's comment? (e.g. REPLICATED section won't show 'replicated')" -Default $true
}

# 5. Inline Comments Option
Write-Step "5/5" "Inline Comments Formatting"
$includeComments = Prompt-YesNo -Message "Include inline comments ('// (flags) helpStr')?" -Default $true

# --- Finalized Options Summary ---

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "                      FINALIZED CONFIGURATION" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Cyan

$namingDesc = switch ($namingOption) {
    1 { "Source File Base Name (<source>_...)" }
    2 { "Descriptor-Only (e.g., cheat_cvars.cfg)" }
    3 { "Custom Base Name ('$customBaseName')" }
}
$ccomDesc = switch ($ccomOption) {
    1 { "Keep Together" }
    2 { "Split into '_ccoms' and '_cvars'" }
    3 { "Exclude ConCommands (ConVars only)" }
}
$flagActionDesc = switch ($flagActionOption) {
    1 { "None" }
    2 { "Exclude matching: $($selectedFlags -join ', ')" }
    3 { "Route matching to dedicated files: $($selectedFlags -join ', ')" }
}

Write-Host "  - Source Files     : $($compatibleFiles.Count) file(s)" -ForegroundColor White
Write-Host "  - Naming Scheme    : $namingDesc" -ForegroundColor White
Write-Host "  - ConCommands      : $ccomDesc" -ForegroundColor White
Write-Host "  - Flag Routing     : $flagActionDesc" -ForegroundColor White
if ($enableCategorization) {
    $prioChain = ($priorityFlags | ForEach-Object { $_.ToUpperInvariant() }) -join " -> "
    Write-Host "  - Categorization   : Enabled ($prioChain -> OTHER)" -ForegroundColor White
    Write-Host "  - Omit Cat. Flag   : $(if ($omitCategoryFlag) { 'Yes' } else { 'No' })" -ForegroundColor White
} else {
    Write-Host "  - Categorization   : Disabled (Alphabetical list)" -ForegroundColor White
}
Write-Host "  - Inline Comments  : $(if ($includeComments) { 'Enabled (Aligned, gamedll/clientdll stripped)' } else { 'Omitted' })" -ForegroundColor White
Write-Host "  - Output Directory : $workDir" -ForegroundColor White
Write-Host "======================================================================" -ForegroundColor Cyan

$proceed = Prompt-YesNo -Message "Proceed with export using these settings?" -Default $true
if (-not $proceed) {
    Write-Host "`n[!] Export cancelled by user." -ForegroundColor Red
    Write-Host ""
    $null = Read-Host "Press Enter to exit..."
    exit 0
}

# --- Conversion Phase ---

Write-Host "`n[+] Processing CSV dump data..." -ForegroundColor Yellow
$timer = [System.Diagnostics.Stopwatch]::StartNew()

$globalBuckets = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[PSCustomObject]]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

$totalParsedEntries = 0

foreach ($file in $compatibleFiles) {
    $rows = Import-SourceCvarCsv -FilePath $file.FullName
    $sourceBase = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $totalParsedEntries += $rows.Count

    if ($rows.Count -eq 0) { continue }

    # Identify flag columns dynamically
    $flagCols = [System.Collections.Generic.List[string]]::new()
    foreach ($col in $rows[0].PSObject.Properties.Name) {
        if ($col -notin @('Name', 'Value', 'Help Text') -and $col -notmatch '^EXTRA_COL_') {
            $flagCols.Add($col)
        }
    }

    foreach ($item in $rows) {
        if ([string]::IsNullOrWhiteSpace($item.Name)) { continue }

        # Strip wrapping single-quotes from names like "'-alt1'" -> "-alt1"
        $cmdName = [string]$item.Name.Trim().Trim("'")
        $valTrim = if ($item.Value) { [string]$item.Value.Trim() } else { "" }
        $isCommand = ($valTrim -eq "cmd")

        if ($ccomOption -eq 3 -and $isCommand) { continue }

        # Extract active flags for this row
        $itemFlags = [System.Collections.Generic.List[string]]::new()
        foreach ($fc in $flagCols) {
            $fVal = $item.$fc
            if (-not [string]::IsNullOrWhiteSpace($fVal)) {
                $itemFlags.Add($fc.ToLowerInvariant())
            }
        }

        # Flag exclusion (Prompt 3)
        if ($flagActionOption -eq 2) {
            $matched = $false
            foreach ($fl in $itemFlags) {
                if ($selectedFlags.Contains($fl)) { $matched = $true; break }
            }
            if ($matched) { continue }
        }

        # Build filename tags (Prompt 3)
        $flagTag = ""
        if ($flagActionOption -eq 3) {
            foreach ($fl in $itemFlags) {
                if ($selectedFlags.Contains($fl)) {
                    $flagTag = $fl.ToLowerInvariant()
                    break
                }
            }
        }

        $typeTag = ""
        if ($ccomOption -eq 2) {
            $typeTag = if ($isCommand) { "ccoms" } else { "cvars" }
        }

        $effectiveBase = switch ($namingOption) {
            1 { $sourceBase }
            2 { "" }
            3 { $customBaseName }
        }

        $nameParts = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrWhiteSpace($effectiveBase)) { $nameParts.Add($effectiveBase) }
        if (-not [string]::IsNullOrWhiteSpace($flagTag))        { $nameParts.Add($flagTag) }
        if (-not [string]::IsNullOrWhiteSpace($typeTag))        { $nameParts.Add($typeTag) }

        if ($nameParts.Count -eq 0) { $nameParts.Add("cvars") }

        $targetFileName = ($nameParts -join "_") + ".cfg"

        # Build Prefix: `name "default"` (commands omit default)
        $prefix = $cmdName
        if (-not $isCommand) {
            $prefix += " `"$valTrim`""
        }

        # Sanitize help text
        $helpText = ""
        if (-not [string]::IsNullOrWhiteSpace($item.'Help Text')) {
            $helpText = ($item.'Help Text' -replace "[\r\n]+", " ").Trim()
        }

        if (-not $globalBuckets.ContainsKey($targetFileName)) {
            $globalBuckets[$targetFileName] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }

        $entry = [PSCustomObject]@{
            Name    = $cmdName
            Prefix  = $prefix
            Flags   = $itemFlags
            Help    = $helpText
            Comment = ""
        }
        $globalBuckets[$targetFileName].Add($entry)
    }
}

# --- File Writing Phase ---

$summaryList = [System.Collections.Generic.List[PSObject]]::new()
$totalExportedEntries = 0

foreach ($pair in $globalBuckets.GetEnumerator()) {
    $outPath    = [System.IO.Path]::Combine($workDir, $pair.Key)
    $allEntries = $pair.Value
    $fileLines  = [System.Collections.Generic.List[string]]::new()
    $maxLen     = 0
    $totalExportedEntries += $allEntries.Count

    if ($enableCategorization) {
        $categoryMap = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[PSCustomObject]]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

        foreach ($pFl in $priorityFlags) {
            $categoryMap[$pFl] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
        $categoryMap["OTHER"] = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($entry in $allEntries) {
            $assigned = $false
            foreach ($pFl in $priorityFlags) {
                if ($entry.Flags -contains $pFl) {
                    $categoryMap[$pFl].Add($entry)
                    $assigned = $true
                    break
                }
            }
            if (-not $assigned) {
                $categoryMap["OTHER"].Add($entry)
            }
        }

        # Pre-format comments and compute uniform alignment width across the file
        foreach ($catKey in $categoryMap.Keys) {
            $flagForCat = if ($catKey -eq "OTHER") { "" } else { $catKey }
            foreach ($e in $categoryMap[$catKey]) {
                if ($includeComments) {
                    $e.Comment = Format-EntryComment -Entry $e -CategoryFlag $flagForCat -OmitCategoryFlag $omitCategoryFlag -CommonOmitFlags $commonOmitFlags

                    if (-not [string]::IsNullOrWhiteSpace($e.Comment) -and $e.Prefix.Length -gt $maxLen) {
                        $maxLen = $e.Prefix.Length
                    }
                } else {
                    $e.Comment = ""
                }
            }
        }

        $orderedKeys = [System.Collections.Generic.List[string]]::new($priorityFlags)
        $orderedKeys.Add("OTHER")

        $firstSection = $true
        foreach ($catKey in $orderedKeys) {
            $rawCatEntries = $categoryMap[$catKey]
            if ($rawCatEntries.Count -eq 0) { continue }

            $catEntries = @($rawCatEntries | Sort-Object -Property Name)

            if (-not $firstSection) { $fileLines.Add("") }
            $firstSection = $false

            $fileLines.Add("// =================")
            $fileLines.Add("// $($catKey.ToUpperInvariant())")
            $fileLines.Add("// =================")

            foreach ($e in $catEntries) {
                if ($includeComments -and -not [string]::IsNullOrWhiteSpace($e.Comment)) {
                    $fileLines.Add($e.Prefix.PadRight($maxLen + 2) + "// " + $e.Comment)
                } else {
                    $fileLines.Add($e.Prefix)
                }
            }
        }
    } else {
        $sortedEntries = @($allEntries | Sort-Object -Property Name)

        foreach ($e in $sortedEntries) {
            if ($includeComments) {
                $e.Comment = Format-EntryComment -Entry $e -CategoryFlag "" -OmitCategoryFlag $false -CommonOmitFlags $commonOmitFlags

                if (-not [string]::IsNullOrWhiteSpace($e.Comment) -and $e.Prefix.Length -gt $maxLen) {
                    $maxLen = $e.Prefix.Length
                }
            } else {
                $e.Comment = ""
            }
        }

        foreach ($e in $sortedEntries) {
            if ($includeComments -and -not [string]::IsNullOrWhiteSpace($e.Comment)) {
                $fileLines.Add($e.Prefix.PadRight($maxLen + 2) + "// " + $e.Comment)
            } else {
                $fileLines.Add($e.Prefix)
            }
        }
    }

    [System.IO.File]::WriteAllLines($outPath, $fileLines, [System.Text.Encoding]::UTF8)

    $fileInfo = Get-Item -Path $outPath
    $summaryList.Add([PSCustomObject]@{
        OutputFile = $pair.Key
        Entries    = $allEntries.Count
        Size       = (Format-FileSize -Bytes $fileInfo.Length)
    })
}

$timer.Stop()

# --- Execution Metrics & Summary ---

Write-Host "`n[OK] Export Completed Successfully!" -ForegroundColor Green
$summaryList | Format-Table -AutoSize OutputFile, Entries, Size

$elapsedFormatted = if ($timer.ElapsedMilliseconds -ge 1000) {
    "{0:N2}s" -f ($timer.ElapsedMilliseconds / 1000.0)
} else {
    "$($timer.ElapsedMilliseconds)ms"
}

Write-Host "Performance Metrics:" -ForegroundColor Yellow
Write-Host "  - Total Raw Entries Read    : $totalParsedEntries" -ForegroundColor White
Write-Host "  - Total Filtered Entries Out: $totalExportedEntries" -ForegroundColor White
Write-Host "  - Output Files Created      : $($globalBuckets.Count)" -ForegroundColor White
Write-Host "  - Total Elapsed Time        : $elapsedFormatted" -ForegroundColor Green
Write-Host "  - Output Directory          : $workDir`n" -ForegroundColor Cyan

# --- Prevent Window from Auto-Closing ---
Write-Host ""
$null = Read-Host "Press Enter to exit..."
