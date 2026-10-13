if (-not ('SourceEngineCvarComparer' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;

public class CvarItem
{
    public string Name;
    public string LeftSide;
    public bool IsCmd;
    public List<string> ActiveFlags;
    public string HelpText;

    public CvarItem(string name, string leftSide, bool isCmd, List<string> activeFlags, string helpText)
    {
        Name = name;
        LeftSide = leftSide;
        IsCmd = isCmd;
        ActiveFlags = activeFlags;
        HelpText = helpText;
    }
}

public class SourceEngineCvarComparer : IComparer<string>, IComparer<CvarItem>
{
    public static readonly SourceEngineCvarComparer Instance = new SourceEngineCvarComparer();

    private static int GetCharRank(char c)
    {
        char lower = char.ToLowerInvariant(c);
        if (lower == '+') return 1;
        if (lower == '-') return 2;
        if (lower == '_') return 3;
        if (lower >= '0' && lower <= '9') return 10 + (lower - '0');
        if (lower >= 'a' && lower <= 'z') return 30 + (lower - 'a');
        return 100 + (int)lower;
    }

    public int Compare(string x, string y)
    {
        if (ReferenceEquals(x, y)) return 0;
        if (x == null) return -1;
        if (y == null) return 1;

        int len = Math.Min(x.Length, y.Length);
        for (int i = 0; i < len; i++)
        {
            char cx = char.ToLowerInvariant(x[i]);
            char cy = char.ToLowerInvariant(y[i]);
            if (cx != cy)
            {
                int rx = GetCharRank(cx);
                int ry = GetCharRank(cy);
                return rx.CompareTo(ry);
            }
        }
        return x.Length.CompareTo(y.Length);
    }

    public int Compare(CvarItem a, CvarItem b)
    {
        if (ReferenceEquals(a, b)) return 0;
        if (a == null) return -1;
        if (b == null) return 1;
        return Compare(a.Name, b.Name);
    }

    public static void Sort(List<CvarItem> items)
    {
        if (items != null) items.Sort(Instance);
    }
}
'@
}

$ignoredFlags = @('GAMEDLL', 'CLIENTDLL')

# 1. Discover CSV files
$csvFiles = Get-ChildItem -LiteralPath $Directory -Filter *.csv -File

if ($csvFiles.Count -eq 0) {
    Write-Warning "No .csv files found in: $Directory"
    Read-Host "`nPress Enter to exit"
    return
}

$hasMultipleFiles = ($csvFiles.Count -gt 1)

# 2. Fast header pre-scan using .NET streaming
$discoveredFlags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$csvTokenRegex = [regex]'(?<=^|,)(?:"(?<val>[^"]*(?:""[^"]*)*)"|(?<val>[^,]*))'

foreach ($file in $csvFiles) {
    $lineEnum = [System.IO.File]::ReadLines($file.FullName).GetEnumerator()
    if ($lineEnum.MoveNext() -and -not [string]::IsNullOrWhiteSpace($lineEnum.Current)) {
        $matches = $csvTokenRegex.Matches($lineEnum.Current)
        foreach ($m in $matches) {
            $h = $m.Groups['val'].Value.Replace('""', '"').Trim()
            if ($h -and $h -notin @('Name', 'Value') -and $h -notmatch '(?i)help' -and $h -notin $ignoredFlags) {
                [void]$discoveredFlags.Add($h)
            }
        }
    }
}

$availableFlagsList = $discoveredFlags | Sort-Object

# =========================================================================
# INTERACTIVE TERMINAL CONFIGURATION
# =========================================================================

Clear-Host
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "                    CvarList to CFG Converter                           " -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "Found $($csvFiles.Count) CSV file(s) in: $Directory`n"

# --- PROMPT 1: Output File Naming ---
Write-Host "[1] Output File Naming" -ForegroundColor Yellow
Write-Host "  1) Input File Name - Uses the CSV's base name (e.g., <input>_cvars.cfg)"
if ($hasMultipleFiles) {
    Write-Host "  2) Descriptor      - [DISABLED] Multiple CSV files detected; would cause overwrites" -ForegroundColor DarkGray
    Write-Host "  3) Custom Name     - Choose a custom name for each file"
} else {
    Write-Host "  2) Descriptor      - Uses only the category name (e.g., cvars.cfg, full.cfg)"
    Write-Host "  3) Custom Name     - Choose a custom name"
}

do {
    $namingChoice = Read-Host "`nSelect naming option (Default: 1)"
    if ([string]::IsNullOrWhiteSpace($namingChoice)) { $namingChoice = '1' }

    if ($hasMultipleFiles -and $namingChoice -eq '2') {
        Write-Warning "Option [2] is disabled when multiple CSV files are present to prevent overwrites."
        $namingChoice = $null
    }
} while ($namingChoice -notin @('1', '2', '3') -or [string]::IsNullOrWhiteSpace($namingChoice))

$customFileNames = @{}
if ($namingChoice -eq '3') {
    Write-Host "`n  Assign Custom Name(s):" -ForegroundColor DarkCyan
    foreach ($f in $csvFiles) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $promptLabel = if ($hasMultipleFiles) { "  Enter name for '$($f.Name)' (Default: '$base')" } else { "  Enter name (Default: '$base')" }
        $chosenCustom = (Read-Host $promptLabel).Trim()

        if ([string]::IsNullOrWhiteSpace($chosenCustom)) {
            $chosenCustom = $base
        } else {
            $chosenCustom = $chosenCustom -replace '\.cfg$', ''
        }

        $customFileNames[$f.FullName] = $chosenCustom
    }
}

# --- PROMPT 2: Command Types ---
Write-Host "`n[2] Command Types" -ForegroundColor Yellow
Write-Host "  1) Both Combined     - Export everything into a single file"
Write-Host "  2) ConVariables Only - Export settings only; omit actions"
Write-Host "  3) ConCommands Only  - Export actions only; omit settings"
Write-Host "  4) Separate Files    - Export both into distinct files"
$typeChoice = Read-Host "`nSelect type option [1-4] (Default: 1)"
if ($typeChoice -notin @('1', '2', '3', '4')) { $typeChoice = '1' }

# --- PROMPT 3: Flag Handling ---
Write-Host "`n[3] Flag Handling" -ForegroundColor Yellow
Write-Host "  [3A] Flag Action" -ForegroundColor Yellow
Write-Host "    1) Keep All (Default)"
Write-Host "    2) Omit Flags"
Write-Host "    3) Separate Flags"
$flagAction = Read-Host "`nSelect action [1-3] (Default: 1)"
if ($flagAction -notin @('1', '2', '3')) { $flagAction = '1' }

$omitFlags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$separateFlags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$removeSeparatedFromMain = $true

if ($flagAction -in @('2', '3')) {
    Write-Host "`nAvailable Flags:" -ForegroundColor DarkCyan
    if ($availableFlagsList.Count -gt 0) {
        for ($i = 0; $i -lt $availableFlagsList.Count; $i++) {
            $numTag = ("[{0}]" -f ($i + 1)).PadRight(5)
            Write-Host ("  {0} {1}" -f $numTag, $availableFlagsList[$i]) -ForegroundColor Gray
        }
    } else {
        Write-Host "  (None detected)" -ForegroundColor Gray
    }

    $actionVerb = if ($flagAction -eq '2') { "OMIT" } else { "SEPARATE" }
    Write-Host "`n  [3B] Choose Flags" -ForegroundColor Yellow
    $selectedFlagsInput = Read-Host "Select flag(s) to $actionVerb (numbers or names)"

    if (-not [string]::IsNullOrWhiteSpace($selectedFlagsInput)) {
        $tokens = $selectedFlagsInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        $resolvedFlags = [System.Collections.Generic.List[string]]::new()

        foreach ($token in $tokens) {
            if ($token -match '^\d+$') {
                $idx = [int]$token - 1
                if ($idx -ge 0 -and $idx -lt $availableFlagsList.Count) {
                    $resolvedFlags.Add($availableFlagsList[$idx].ToUpperInvariant())
                }
            } else {
                $matched = $availableFlagsList | Where-Object { $_ -ieq $token } | Select-Object -First 1
                if ($matched) {
                    $resolvedFlags.Add($matched.ToUpperInvariant())
                }
            }
        }

        if ($flagAction -eq '2') {
            foreach ($f in $resolvedFlags) { [void]$omitFlags.Add($f) }
            Write-Host "  -> Omit: $($omitFlags -join ', ')" -ForegroundColor DarkGray
        } elseif ($flagAction -eq '3') {
            foreach ($f in $resolvedFlags) { [void]$separateFlags.Add($f) }
            Write-Host "  -> Separate: $($separateFlags -join ', ')" -ForegroundColor DarkGray

            $removeChoice = Read-Host "`nRemove separated flags from main file? (y/n) [Default: y]"
            if ($removeChoice.Trim().ToLower() -eq 'n') {
                $removeSeparatedFromMain = $false
            }
        }
    }
}

# --- PROMPT 4: Flag Sectioning (y/n) ---
Write-Host "`n[4] Flag Sectioning" -ForegroundColor Yellow
$secChoice = Read-Host "Categorize commands by flag? (y/n) [Default: n]"
$enableSectioning = ($secChoice.Trim().ToLower() -in @('y', 'yes'))

$sectionFlagOrder = [System.Collections.Generic.List[string]]::new()
$omitSectionFlagFromComment = $true

if ($enableSectioning) {
    Write-Host "`nAvailable Flags:" -ForegroundColor DarkCyan
    if ($availableFlagsList.Count -gt 0) {
        for ($i = 0; $i -lt $availableFlagsList.Count; $i++) {
            $numTag = ("[{0}]" -f ($i + 1)).PadRight(5)
            Write-Host ("  {0} {1}" -f $numTag, $availableFlagsList[$i]) -ForegroundColor Gray
        }
    } else {
        Write-Host "  (None detected)" -ForegroundColor Gray
    }

    $secInput = Read-Host "`nSelect section order (numbers or names, e.g. '1, 4' or 'REPLICATED, ARCHIVE')"
    if (-not [string]::IsNullOrWhiteSpace($secInput)) {
        $tokens = $secInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        foreach ($token in $tokens) {
            $matchedFlag = $null
            if ($token -match '^\d+$') {
                $idx = [int]$token - 1
                if ($idx -ge 0 -and $idx -lt $availableFlagsList.Count) {
                    $matchedFlag = $availableFlagsList[$idx].ToUpperInvariant()
                }
            } else {
                $matched = $availableFlagsList | Where-Object { $_ -ieq $token } | Select-Object -First 1
                if ($matched) {
                    $matchedFlag = $matched.ToUpperInvariant()
                }
            }

            if ($matchedFlag -and -not $sectionFlagOrder.Contains($matchedFlag)) {
                $sectionFlagOrder.Add($matchedFlag)
            }
        }
        if ($sectionFlagOrder.Count -gt 0) {
            Write-Host "  -> Priority: $($sectionFlagOrder -join ' -> ') -> OTHER" -ForegroundColor DarkGray

            $omitSecPrompt = Read-Host "`nOmit section's flag from comments inside that section? (y/n) [Default: y]"
            if ($omitSecPrompt.Trim().ToLower() -eq 'n') {
                $omitSectionFlagFromComment = $false
            }
        }
    }
}

Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host "                     Starting Batch Conversion                          " -ForegroundColor Cyan
Write-Host "========================================================================`n" -ForegroundColor Cyan

# =========================================================================
# HELPER FUNCTIONS
# =========================================================================

function Get-OutputFileName {
    param(
        [string]$NamingOption,
        [string]$InputBaseName,
        [string]$CustomName,
        [string]$Descriptor,
        [string]$FlagName = ""
    )

    $parts = [System.Collections.Generic.List[string]]::new()

    switch ($NamingOption) {
        '1' {
            $parts.Add($InputBaseName)
            $parts.Add($Descriptor)
        }
        '2' {
            $parts.Add($Descriptor)
        }
        '3' {
            $parts.Add($CustomName)
            $parts.Add($Descriptor)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($FlagName)) {
        $parts.Add($FlagName.ToLowerInvariant())
    }

    return ($parts -join '_') + ".cfg"
}

function Get-EntryComment {
    param(
        [CvarItem]$Entry,
        [string]$SectionName = "",
        [bool]$OmitSectionFlag = $false
    )

    $displayFlags = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $Entry.ActiveFlags) {
        if ($OmitSectionFlag -and -not [string]::IsNullOrWhiteSpace($SectionName) -and $SectionName -ine 'OTHER' -and $f -ieq $SectionName) {
            continue
        }
        $displayFlags.Add($f)
    }

    $hasFlags = ($displayFlags.Count -gt 0)
    $hasHelp = (-not [string]::IsNullOrEmpty($Entry.HelpText))

    if ($hasFlags -and $hasHelp) {
        return "($($displayFlags -join ', ')) $($Entry.HelpText)"
    } elseif ($hasFlags -and -not $hasHelp) {
        return "($($displayFlags -join ', '))"
    } elseif (-not $hasFlags -and $hasHelp) {
        return $Entry.HelpText
    } else {
        return ""
    }
}

function Write-CfgFile {
    param(
        [string]$FilePath,
        [System.Collections.Generic.List[CvarItem]]$Entries,
        [System.Collections.Generic.List[string]]$SectionFlags,
        [bool]$OmitSectionFlag = $false,
        [int]$FileNamePadding = 0
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($null -eq $Entries -or $Entries.Count -eq 0) { 
        return @{ Count = 0; Categories = @{} }
    }

    # Calculate longest left side in a single fast loop
    $maxLen = 0
    foreach ($e in $Entries) {
        if ($e.LeftSide.Length -gt $maxLen) {
            $maxLen = $e.LeftSide.Length
        }
    }

    $outputLines = [System.Collections.Generic.List[string]]::new($Entries.Count + 16)
    $categoryDistribution = [ordered]@{}
    $isSectioned = $false

    # Sectioned output mode
    if ($SectionFlags -and $SectionFlags.Count -gt 0) {
        $buckets = [ordered]@{}
        foreach ($sf in $SectionFlags) {
            $buckets[$sf] = [System.Collections.Generic.List[CvarItem]]::new()
        }
        $buckets['OTHER'] = [System.Collections.Generic.List[CvarItem]]::new()

        # Ordering bias: First matching flag claims the command
        foreach ($entry in $Entries) {
            $claimed = $false
            foreach ($sf in $SectionFlags) {
                if ($entry.ActiveFlags.Contains($sf)) {
                    [void]$buckets[$sf].Add($entry)
                    $claimed = $true
                    break
                }
            }
            if (-not $claimed) {
                [void]$buckets['OTHER'].Add($entry)
            }
        }

        # Check if at least ONE named section flag matched commands
        $namedSectionsPopulated = 0
        foreach ($sf in $SectionFlags) {
            if ($buckets[$sf].Count -gt 0) {
                $namedSectionsPopulated++
            }
        }

        if ($namedSectionsPopulated -gt 0) {
            $isSectioned = $true
            foreach ($sectionName in $buckets.Keys) {
                $bList = $buckets[$sectionName]
                if ($bList.Count -eq 0) { continue }

                $categoryDistribution[$sectionName] = $bList.Count

                if ($outputLines.Count -gt 0) {
                    $outputLines.Add("")
                }

                $outputLines.Add("// ====================")
                $outputLines.Add("// $sectionName")
                $outputLines.Add("// ====================")
                $outputLines.Add("")

                # Compiled C# sort (<1ms execution)
                [SourceEngineCvarComparer]::Sort($bList)

                foreach ($e in $bList) {
                    $commentBody = Get-EntryComment -Entry $e -SectionName $sectionName -OmitSectionFlag $OmitSectionFlag
                    if (-not [string]::IsNullOrEmpty($commentBody)) {
                        $padded = $e.LeftSide.PadRight($maxLen)
                        $outputLines.Add("$padded // $commentBody")
                    } else {
                        $outputLines.Add($e.LeftSide)
                    }
                }
            }
        }
    }

    # Flat list mode (either sectioning disabled or no named flags matched)
    if (-not $isSectioned) {
        [SourceEngineCvarComparer]::Sort($Entries)

        foreach ($e in $Entries) {
            $commentBody = Get-EntryComment -Entry $e -SectionName "" -OmitSectionFlag $false
            if (-not [string]::IsNullOrEmpty($commentBody)) {
                $padded = $e.LeftSide.PadRight($maxLen)
                $outputLines.Add("$padded // $commentBody")
            } else {
                $outputLines.Add($e.LeftSide)
            }
        }
    }

    # Save as UTF-8 without BOM
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($FilePath, $outputLines, $utf8NoBom)
    $sw.Stop()

    $fileInfo = Get-Item -LiteralPath $FilePath
    $sizeKb = [math]::Round($fileInfo.Length / 1KB, 1)
    $timeMs = $sw.ElapsedMilliseconds

    $actualFileName = [System.IO.Path]::GetFileName($FilePath)
    $paddedFileName = if ($FileNamePadding -gt 0) { $actualFileName.PadRight($FileNamePadding) } else { $actualFileName }

    Write-Host ("  [Wrote] {0}  ({1} entries, {2} KB) in {3}ms" -f `
        $paddedFileName, `
        $Entries.Count, `
        "$sizeKb", `
        $timeMs) -ForegroundColor Green

    if ($categoryDistribution.Count -gt 0) {
        $catParts = foreach ($k in $categoryDistribution.Keys) { "{0}: {1}" -f $k, $categoryDistribution[$k] }
        Write-Host ("          Categories: {0}" -f ($catParts -join ' | ')) -ForegroundColor DarkGray
    } elseif ($SectionFlags -and $SectionFlags.Count -gt 0) {
        Write-Host ("          Categories: Uncategorized (no matching flags)") -ForegroundColor DarkGray
    }

    return @{ Count = $Entries.Count; Categories = $categoryDistribution }
}

# =========================================================================
# CONVERSION PROCESS & TELEMETRY
# =========================================================================

$totalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$totalFilesWritten = 0
$totalEntriesWritten = 0
$totalRawEncountered = 0
$totalOmittedByFlag = 0
$totalOmittedByType = 0
$totalSeparatedCount = 0
$globalCategoryTotals = [ordered]@{}

$fileIndex = 0

foreach ($file in $csvFiles) {
    $fileIndex++
    $fileSw = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Host ("------------------------------------------------------------------------") -ForegroundColor DarkGray
    Write-Host ("File [{0}/{1}]: {2}" -f $fileIndex, $csvFiles.Count, $file.Name) -ForegroundColor Yellow
    Write-Host ("------------------------------------------------------------------------") -ForegroundColor DarkGray

    $rawContent = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $firstLineBreak = [regex]::Match($rawContent, "\r?\n")
    if (-not $firstLineBreak.Success) {
        Write-Warning "  [!] File '$($file.Name)' is empty or invalid. Skipping."
        continue
    }

    $headerLine = $rawContent.Substring(0, $firstLineBreak.Index)
    $bodyContent = $rawContent.Substring($firstLineBreak.Index + $firstLineBreak.Length)

    # Fast header parsing
    $headerMatches = $csvTokenRegex.Matches($headerLine)
    $headers = [System.Collections.Generic.List[string]]::new()
    $emptyCount = 0

    foreach ($m in $headerMatches) {
        $val = $m.Groups['val'].Value.Replace('""', '"').Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $emptyCount++
            $val = "__EMPTY_COL_${emptyCount}__"
        }
        $headers.Add($val)
    }

    # Fast StringBuilder header reconstruction
    $headerBuilder = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $headers.Count; $i++) {
        if ($i -gt 0) { [void]$headerBuilder.Append(',') }
        [void]$headerBuilder.Append('"').Append($headers[$i].Replace('"', '""')).Append('"')
    }
    $sanitizedCsv = $headerBuilder.ToString() + "`r`n" + $bodyContent
    $records = $sanitizedCsv | ConvertFrom-Csv

    # Identify dynamic columns
    $nameCol = $headers | Where-Object { $_ -ieq 'Name' } | Select-Object -First 1
    $valueCol = $headers | Where-Object { $_ -ieq 'Value' } | Select-Object -First 1
    $helpCol = $headers | Where-Object { $_ -match '(?i)help' } | Select-Object -First 1

    if (-not $nameCol) { $nameCol = $headers[0] }
    if (-not $valueCol) { $valueCol = $headers[1] }
    if (-not $helpCol) { $helpCol = $headers[-1] }

    $flagCols = $headers | Where-Object {
        $_ -ne $nameCol -and
        $_ -ne $valueCol -and
        $_ -ne $helpCol -and
        $_ -notmatch '^__EMPTY_COL_\d+__$' -and
        $_ -notin $ignoredFlags
    }

    $parsedEntries = [System.Collections.Generic.List[CvarItem]]::new($records.Count)
    $rawCvarCount = 0
    $rawCcomCount = 0
    $fileOmittedByFlag = 0
    $omittedFlagCounts = @{}

    foreach ($row in $records) {
        $rawName = $row.$nameCol
        if ([string]::IsNullOrWhiteSpace($rawName)) { continue }

        $name = $rawName.Trim()
        # Fast string check instead of Regex
        if ($name.StartsWith("'") -and $name.EndsWith("'") -and $name.Length -ge 2) {
            $name = $name.Substring(1, $name.Length - 2)
        }

        $rawVal = $row.$valueCol
        $val = if ($rawVal) { $rawVal.Trim() } else { "" }
        $isCmd = ($val -ieq 'cmd')

        if ($isCmd) { $rawCcomCount++ } else { $rawCvarCount++ }

        $activeFlags = [System.Collections.Generic.List[string]]::new()
        foreach ($col in $flagCols) {
            $cellVal = $row.$col
            if (-not [string]::IsNullOrWhiteSpace($cellVal)) {
                $trimmed = $cellVal.Trim()
                $flag = if ($trimmed -in @('1', 'true', 'yes')) { $col } else { $trimmed }
                if ($flag -notin $ignoredFlags) {
                    $activeFlags.Add($flag)
                }
            }
        }

        $omittedByThisFlag = $null
        foreach ($f in $activeFlags) {
            if ($omitFlags.Contains($f)) {
                $omittedByThisFlag = $f
                break
            }
        }

        if ($null -ne $omittedByThisFlag) {
            $fileOmittedByFlag++
            if (-not $omittedFlagCounts.ContainsKey($omittedByThisFlag)) {
                $omittedFlagCounts[$omittedByThisFlag] = 0
            }
            $omittedFlagCounts[$omittedByThisFlag]++
            continue
        }

        # Guarded regex replacement
        $rawHelp = $row.$helpCol
        $helpText = ""
        if (-not [string]::IsNullOrWhiteSpace($rawHelp)) {
            $helpText = ($rawHelp -replace '\r?\n', ' ' -replace '\s+', ' ').Trim()
        }

        $leftSide = if ($isCmd) { $name } else { '{0} "{1}"' -f $name, $val }

        $parsedEntries.Add([CvarItem]::new($name, $leftSide, $isCmd, $activeFlags, $helpText))
    }

    $rawTotal = $rawCvarCount + $rawCcomCount
    $totalRawEncountered += $rawTotal
    $totalOmittedByFlag += $fileOmittedByFlag

    # Step Telemetry
    Write-Host ("  [+] Parsed Content    : {0} entries in {1}ms" -f $rawTotal, $fileSw.ElapsedMilliseconds) -ForegroundColor DarkGray
    Write-Host ("  [+] Breakdown         : {0} ConVars, {1} ConCommands" -f $rawCvarCount, $rawCcomCount) -ForegroundColor DarkGray

    if ($fileOmittedByFlag -gt 0) {
        $flagDetailParts = foreach ($k in $omittedFlagCounts.Keys) { "{0}: {1}" -f $k, $omittedFlagCounts[$k] }
        Write-Host ("  [+] Omitted (Flags)   : {0} entries ({1})" -f $fileOmittedByFlag, ($flagDetailParts -join ', ')) -ForegroundColor Yellow
    }

    # Single-pass loop partitioning (Replaces pipeline Where-Object overhead)
    $cvars = [System.Collections.Generic.List[CvarItem]]::new($parsedEntries.Count)
    $ccoms = [System.Collections.Generic.List[CvarItem]]::new($parsedEntries.Count)
    foreach ($entry in $parsedEntries) {
        if ($entry.IsCmd) { [void]$ccoms.Add($entry) } else { [void]$cvars.Add($entry) }
    }

    $groups = [System.Collections.Generic.List[PSCustomObject]]::new()
    $fileOmittedByType = 0

    switch ($typeChoice) {
        '1' {
            $groups.Add([PSCustomObject]@{ Descriptor = 'full'; Entries = $parsedEntries })
        }
        '2' {
            $fileOmittedByType = $ccoms.Count
            $groups.Add([PSCustomObject]@{ Descriptor = 'cvars'; Entries = $cvars })
        }
        '3' {
            $fileOmittedByType = $cvars.Count
            $groups.Add([PSCustomObject]@{ Descriptor = 'ccoms'; Entries = $ccoms })
        }
        '4' {
            $groups.Add([PSCustomObject]@{ Descriptor = 'cvars'; Entries = $cvars })
            $groups.Add([PSCustomObject]@{ Descriptor = 'ccoms'; Entries = $ccoms })
        }
    }

    $totalOmittedByType += $fileOmittedByType
    if ($fileOmittedByType -gt 0) {
        $typeOmittedDesc = if ($typeChoice -eq '2') { "ConCommands" } else { "ConVariables" }
        Write-Host ("  [+] Omitted (Type)    : {0} {1}" -f $fileOmittedByType, $typeOmittedDesc) -ForegroundColor Yellow
    }

    if ($sectionFlagOrder.Count -gt 0) {
        $secInfo = "$($sectionFlagOrder -join ' -> ') -> OTHER"
        if ($omitSectionFlagFromComment) { $secInfo += " (omitting flag from comments)" }
        Write-Host ("  [+] Section Priority  : {0}" -f $secInfo) -ForegroundColor DarkGray
    }

    $inputBase = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $activeCustomName = if ($customFileNames.ContainsKey($file.FullName)) { $customFileNames[$file.FullName] } else { $inputBase }

    # Pre-plan target files for dynamic padding with single-pass flag separation
    $plannedFiles = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($grp in $groups) {
        $mainList = [System.Collections.Generic.List[CvarItem]]::new($grp.Entries)

        if ($separateFlags.Count -gt 0) {
            foreach ($flagToSeparate in $separateFlags) {
                $flagEntries = [System.Collections.Generic.List[CvarItem]]::new()
                foreach ($entry in $grp.Entries) {
                    if ($entry.ActiveFlags.Contains($flagToSeparate)) {
                        [void]$flagEntries.Add($entry)
                    }
                }

                if ($flagEntries.Count -gt 0) {
                    $flagFileName = Get-OutputFileName -NamingOption $namingChoice -InputBaseName $inputBase `
                                                       -CustomName $activeCustomName -Descriptor $grp.Descriptor `
                                                       -FlagName $flagToSeparate
                    $plannedFiles.Add([PSCustomObject]@{
                        FileName = $flagFileName
                        FilePath = Join-Path $Directory $flagFileName
                        Entries  = $flagEntries
                    })
                }
            }

            if ($removeSeparatedFromMain) {
                $filtered = [System.Collections.Generic.List[CvarItem]]::new($mainList.Count)
                foreach ($item in $mainList) {
                    $hasSep = $false
                    foreach ($sf in $separateFlags) {
                        if ($item.ActiveFlags.Contains($sf)) {
                            $hasSep = $true
                            break
                        }
                    }
                    if (-not $hasSep) { [void]$filtered.Add($item) }
                }
                $mainList = $filtered
            }
        }

        if ($mainList.Count -gt 0) {
            $mainFileName = Get-OutputFileName -NamingOption $namingChoice -InputBaseName $inputBase `
                                               -CustomName $activeCustomName -Descriptor $grp.Descriptor
            $plannedFiles.Add([PSCustomObject]@{
                FileName = $mainFileName
                FilePath = Join-Path $Directory $mainFileName
                Entries  = $mainList
            })
        }
    }

    # Dynamic filename width
    $maxFileLen = 0
    foreach ($pf in $plannedFiles) {
        if ($pf.FileName.Length -gt $maxFileLen) {
            $maxFileLen = $pf.FileName.Length
        }
    }

    Write-Host "`n  Writing Config Files:" -ForegroundColor Cyan

    foreach ($pf in $plannedFiles) {
        $result = Write-CfgFile -FilePath $pf.FilePath `
                               -Entries $pf.Entries `
                               -SectionFlags $sectionFlagOrder `
                               -OmitSectionFlag $omitSectionFlagFromComment `
                               -FileNamePadding $maxFileLen

        if ($result.Count -gt 0) {
            $totalFilesWritten++
            $totalEntriesWritten += $result.Count
            foreach ($cat in $result.Categories.Keys) {
                if (-not $globalCategoryTotals.Contains($cat)) { $globalCategoryTotals[$cat] = 0 }
                $globalCategoryTotals[$cat] += $result.Categories[$cat]
            }
        }
    }
    Write-Host ""
}

$totalStopwatch.Stop()

# =========================================================================
# DETAILED SUMMARY METRICS
# =========================================================================

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "                           Conversion Summary                           " -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ("  CSV Files Processed      : {0}" -f $csvFiles.Count) -ForegroundColor Gray

$typeOmittedDesc = if ($typeChoice -eq '2') { "ConCommands" } elseif ($typeChoice -eq '3') { "ConVariables" } else { "" }
if ($totalOmittedByType -gt 0) {
    Write-Host ("  Raw Entries Encountered  : {0} ({1} {2} omitted by type)" -f $totalRawEncountered, $totalOmittedByType, $typeOmittedDesc) -ForegroundColor Gray
} else {
    Write-Host ("  Raw Entries Encountered  : {0} (0 omitted by type)" -f $totalRawEncountered) -ForegroundColor Gray
}

if ($omitFlags.Count -gt 0) {
    Write-Host ("  Entries Omitted by Flag  : {0} ({1})" -f $totalOmittedByFlag, ($omitFlags -join ', ')) -ForegroundColor Yellow
}

if ($separateFlags.Count -gt 0) {
    Write-Host ("  Entries Separated (Flag) : {0} ({1})" -f $totalSeparatedCount, ($separateFlags -join ', ')) -ForegroundColor Cyan
}

if ($globalCategoryTotals.Count -gt 0) {
    $catSummary = foreach ($k in $globalCategoryTotals.Keys) { "{0}: {1}" -f $k, $globalCategoryTotals[$k] }
    Write-Host ("  Categories Distributed   : {0}" -f ($catSummary -join ' | ')) -ForegroundColor Cyan
}

Write-Host ("  CFG Files Generated      : {0}" -f $totalFilesWritten) -ForegroundColor Green
Write-Host ("  Total Entries Written    : {0}" -f $totalEntriesWritten) -ForegroundColor Green
Write-Host ("  Total Execution Time     : {0}s ({1}ms)" -f `
    [math]::Round($totalStopwatch.Elapsed.TotalSeconds, 2), `
    $totalStopwatch.ElapsedMilliseconds) -ForegroundColor Gray
Write-Host "========================================================================`n" -ForegroundColor Cyan

Read-Host "Press Enter to exit"
