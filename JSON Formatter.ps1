# --- Baked-in Engine Configuration ---
$commonOmitFlags = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('client', 'game'),
    [System.StringComparer]::OrdinalIgnoreCase
)

# --- UI Helpers ---

function Write-Banner {
    Clear-Host
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "                    SAR CVAR DUMP EXPORT TOOL" -ForegroundColor Yellow
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

# Generates deterministic keys for Order B (All '+' first, then all '-', then '_', then A-Z)
function Get-SortKey {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "9_empty" }
    $lower = $Name.ToLowerInvariant().Trim()

    if ($lower.StartsWith('+')) {
        return "0_+" + $lower.Substring(1)
    } elseif ($lower.StartsWith('-')) {
        return "1_-" + $lower.Substring(1)
    } elseif ($lower.StartsWith('_')) {
        return "2__" + $lower.Substring(1)
    } else {
        return "3_" + $lower
    }
}

function Sort-SourceEntries {
    param($EntryList)
    if ($null -eq $EntryList -or $EntryList.Count -le 1) { return $EntryList }

    return @($EntryList | Sort-Object -Property { Get-SortKey -Name $_.Name })
}

function Test-IsCompatibleJson {
    param([string]$FilePath)
    try {
        $raw = [System.IO.File]::ReadAllText($FilePath)
        $data = $raw | ConvertFrom-Json
        if ($data -is [System.Array] -and $data.Count -gt 0) {
            $first = $data[0]
            return ($null -ne $first.name -and $null -ne $first.isCommand -and $null -ne $first.flagsStr)
        }
    } catch {
        return $false
    }
    return $false
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

    if (-not [string]::IsNullOrWhiteSpace($Entry.MinMax)) {
        $cParts.Add($Entry.MinMax)
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

$allJsonFiles = Get-ChildItem -Path $workDir -Filter "*.json" -File
$compatibleFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

foreach ($file in $allJsonFiles) {
    if (Test-IsCompatibleJson -FilePath $file.FullName) {
        $compatibleFiles.Add($file)
    }
}

# --- Tutorial Fallback (If No Files Found) ---
if ($compatibleFiles.Count -eq 0) {
    Write-Host "`n[!] No compatible convar JSON dumps found in this directory." -ForegroundColor Red
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "            HOW TO GET 'cvars_all.json' USING SAR" -ForegroundColor Yellow
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  1. Launch Portal 2 with SourceAutoRecord (SAR) installed." -ForegroundColor White
    Write-Host "     (Verify SAR is loaded by checking console or typing: sar_about)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Open the developer console (~) and run:" -ForegroundColor White
    Write-Host "         sar_cvars_dump all" -ForegroundColor Green
    Write-Host ""
    Write-Host "  3. SAR will dump all cvars and commands into:" -ForegroundColor White
    Write-Host "         cvars_all.json" -ForegroundColor Green
    Write-Host "     Location: The base 'Portal 2' folder (NOT the 'portal2' subfolder)" -ForegroundColor Yellow
    Write-Host "     Example:  .../steamapps/common/Portal 2/cvars_all.json" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  4. Copy 'cvars_all.json' into the folder where this script is located:" -ForegroundColor White
    Write-Host "         $workDir" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  5. Re-run this script!" -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ""
    $null = Read-Host "Press Enter to exit..."
    exit 0
}

Write-Host "[+] Found $($compatibleFiles.Count) compatible dump file(s):" -ForegroundColor Green
foreach ($f in $compatibleFiles) {
    Write-Host "    - $($f.Name)" -ForegroundColor White
}

# Discover distinct flags
$discoveredFlags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($file in $compatibleFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
    foreach ($entry in $content) {
        if ($entry.flagsStr -and $entry.flagsStr -ne 'none') {
            foreach ($fl in ($entry.flagsStr -split '\s+')) {
                if (-not [string]::IsNullOrWhiteSpace($fl) -and $fl -ne 'none') {
                    [void]$discoveredFlags.Add($fl)
                }
            }
        }
    }
}
$sortedFlags = @($discoveredFlags | Sort-Object)

# --- Interactive Prompts ---

# 1. Output File Naming Scheme
Write-Step "1/6" "Output File Naming Scheme"
$namingOption = Prompt-Choice -Options @(
    "Use source file name as base (e.g., cvars_all_cheat_cvars.cfg)",
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
Write-Step "2/6" "ConCommands ('isCommand') Handling"
$ccomOption = Prompt-Choice -Options @(
    "Keep ConCommands and ConVars together",
    "Separate into different files ('_ccoms' and '_cvars')",
    "Completely exclude ConCommands (ConVars only)"
) -DefaultIndex 1

# 3. SAR Entries Handling
Write-Step "3/6" "SAR Entries ('isSAR') Handling"
$sarOption = Prompt-Choice -Options @(
    "Keep SAR and Engine/Game commands together",
    "Separate SAR entries into dedicated files ('_sar')",
    "Completely exclude SAR entries (Engine/Game only)",
    "Completely exclude Engine/Game entries (SAR only)"
) -DefaultIndex 1

# 4. Flag Routing / File Filtering
Write-Step "4/6" "Flag Routing / File Filtering"
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
                    [void]$selectedFlags.Add($tok)
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

# 5. Flag Categorization & Priority Bias
Write-Step "5/6" "Section Categorization and Priority Bias"
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

# 6. Inline Comments Option
Write-Step "6/6" "Inline Comments Formatting"
$includeComments = Prompt-YesNo -Message "Include inline comments ('// (flags) [min/max] helpStr')?" -Default $true

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
$sarDesc = switch ($sarOption) {
    1 { "Keep Together" }
    2 { "Split SAR into '_sar'" }
    3 { "Exclude SAR (Engine only)" }
    4 { "Exclude Engine (SAR only)" }
}
$flagActionDesc = switch ($flagActionOption) {
    1 { "None" }
    2 { "Exclude matching: $($selectedFlags -join ', ')" }
    3 { "Route matching to dedicated files: $($selectedFlags -join ', ')" }
}

Write-Host "  - Source Files     : $($compatibleFiles.Count) file(s)" -ForegroundColor White
Write-Host "  - Naming Scheme    : $namingDesc" -ForegroundColor White
Write-Host "  - ConCommands      : $ccomDesc" -ForegroundColor White
Write-Host "  - SAR Scope        : $sarDesc" -ForegroundColor White
Write-Host "  - Flag Routing     : $flagActionDesc" -ForegroundColor White
if ($enableCategorization) {
    $prioChain = ($priorityFlags | ForEach-Object { $_.ToUpperInvariant() }) -join " -> "
    Write-Host "  - Categorization   : Enabled ($prioChain -> OTHER)" -ForegroundColor White
    Write-Host "  - Omit Cat. Flag   : $(if ($omitCategoryFlag) { 'Yes' } else { 'No' })" -ForegroundColor White
} else {
    Write-Host "  - Categorization   : Disabled (Alphabetical list)" -ForegroundColor White
}
Write-Host "  - Symbol Sorting   : Order B (All '+' first, then all '-', then A-Z)" -ForegroundColor White
Write-Host "  - Inline Comments  : $(if ($includeComments) { 'Enabled (Aligned, common engine flags stripped)' } else { 'Omitted' })" -ForegroundColor White
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

Write-Host "`n[+] Processing dump data..." -ForegroundColor Yellow
$timer = [System.Diagnostics.Stopwatch]::StartNew()

$globalBuckets = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[PSCustomObject]]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

$totalParsedEntries = 0

foreach ($file in $compatibleFiles) {
    $rawItems = [System.IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
    $sourceBase = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $totalParsedEntries += $rawItems.Count

    foreach ($item in $rawItems) {
        if ($ccomOption -eq 3 -and $item.isCommand -eq $true) { continue }
        if ($sarOption -eq 3 -and $item.isSAR -eq $true) { continue }
        if ($sarOption -eq 4 -and $item.isSAR -ne $true) { continue }

        $itemFlags = [System.Collections.Generic.List[string]]::new()
        if ($item.flagsStr -and $item.flagsStr -ne 'none') {
            foreach ($fl in ($item.flagsStr -split '\s+')) {
                if (-not [string]::IsNullOrWhiteSpace($fl) -and $fl -ne 'none') {
                    $itemFlags.Add($fl.ToLowerInvariant())
                }
            }
        }

        if ($flagActionOption -eq 2) {
            $matched = $false
            foreach ($fl in $itemFlags) {
                if ($selectedFlags.Contains($fl)) { $matched = $true; break }
            }
            if ($matched) { continue }
        }

        $flagTag = ""
        if ($flagActionOption -eq 3) {
            foreach ($fl in $itemFlags) {
                if ($selectedFlags.Contains($fl)) {
                    $flagTag = $fl.ToLowerInvariant()
                    break
                }
            }
        }

        $sarTag = ""
        if ($sarOption -eq 2) {
            $sarTag = if ($item.isSAR) { "sar" } else { "engine" }
        }

        $typeTag = ""
        if ($ccomOption -eq 2) {
            $typeTag = if ($item.isCommand) { "ccoms" } else { "cvars" }
        }

        $effectiveBase = switch ($namingOption) {
            1 { $sourceBase }
            2 { "" }
            3 { $customBaseName }
        }

        $nameParts = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrWhiteSpace($effectiveBase)) { $nameParts.Add($effectiveBase) }
        if (-not [string]::IsNullOrWhiteSpace($flagTag))        { $nameParts.Add($flagTag) }
        if (-not [string]::IsNullOrWhiteSpace($sarTag))         { $nameParts.Add($sarTag) }
        if (-not [string]::IsNullOrWhiteSpace($typeTag))        { $nameParts.Add($typeTag) }

        if ($nameParts.Count -eq 0) { $nameParts.Add("cvars") }

        $targetFileName = ($nameParts -join "_") + ".cfg"

        $prefix = [string]$item.name
        if (-not $item.isCommand -and $null -ne $item.default) {
            $prefix += " `"$($item.default)`""
        }

        $minMaxText = ""
        $hasMin = $null -ne $item.min
        $hasMax = $null -ne $item.max
        if ($hasMin -and $hasMax) {
            $minMaxText = "[min. $($item.min) max. $($item.max)]"
        } elseif ($hasMin) {
            $minMaxText = "[min. $($item.min)]"
        } elseif ($hasMax) {
            $minMaxText = "[max. $($item.max)]"
        }

        $helpText = ""
        if (-not [string]::IsNullOrWhiteSpace($item.helpStr)) {
            $helpText = ($item.helpStr -replace "[\r\n]+", " ").Trim()
        }

        if (-not $globalBuckets.ContainsKey($targetFileName)) {
            $globalBuckets[$targetFileName] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }

        $entry = [PSCustomObject]@{
            Name    = [string]$item.name
            Prefix  = $prefix
            Flags   = $itemFlags
            MinMax  = $minMaxText
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

            # Apply Order B sorting
            $catEntries = Sort-SourceEntries -EntryList $rawCatEntries

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
        # Apply Order B sorting
        $sortedEntries = Sort-SourceEntries -EntryList $allEntries

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
