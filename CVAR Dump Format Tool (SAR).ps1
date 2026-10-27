# =============================================================================
# 1. INITIALIZATION & NATIVE TYPES
# =============================================================================

if ([string]::IsNullOrWhiteSpace($Directory)) {
    $Directory = (Get-Location).Path
}

if (-not ('SourceEngineCvarComparer' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;

public class CvarItem
{
    public string Name;
    public string LeftSide;
    public bool IsCmd;
    public bool IsSAR;
    public List<string> ActiveFlags;
    public string HelpText;

    public CvarItem(string name, string leftSide, bool isCmd, bool isSAR, List<string> activeFlags, string helpText)
    {
        Name = name;
        LeftSide = leftSide;
        IsCmd = isCmd;
        IsSAR = isSAR;
        ActiveFlags = activeFlags;
        HelpText = helpText;
    }

    public string GetComment(string sectionName, bool omitSectionFlag, string fileOmittedFlag = null)
    {
        List<string> display = null;
        if (ActiveFlags != null && ActiveFlags.Count > 0)
        {
            int count = ActiveFlags.Count;
            for (int i = 0; i < count; i++)
            {
                string f = ActiveFlags[i];
                if (omitSectionFlag && !string.IsNullOrEmpty(sectionName) && 
                    !sectionName.Equals("OTHER", StringComparison.OrdinalIgnoreCase) && 
                    f.Equals(sectionName, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                if (!string.IsNullOrEmpty(fileOmittedFlag) && 
                    f.Equals(fileOmittedFlag, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                if (display == null) display = new List<string>(count);
                display.Add(f);
            }
        }

        bool hasFlags = display != null && display.Count > 0;
        bool hasHelp = !string.IsNullOrEmpty(HelpText);

        if (hasFlags && hasHelp)
            return "(" + string.Join(", ", display) + ") " + HelpText;
        if (hasFlags)
            return "(" + string.Join(", ", display) + ")";
        if (hasHelp)
            return HelpText;
        return "";
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

$ignoredFlags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
[void]$ignoredFlags.Add('game')
[void]$ignoredFlags.Add('client')
[void]$ignoredFlags.Add('none')

# =============================================================================
# 2. FILE DISCOVERY & PRE-SCAN
# =============================================================================

$jsonFiles = Get-ChildItem -LiteralPath $Directory -Filter *.json -File

if ($jsonFiles.Count -eq 0) {
    Write-Warning "No .json files found in: $Directory"
    Read-Host "`nPress Enter to exit"
    return
}

$hasMultipleFiles = ($jsonFiles.Count -gt 1)
$baseDiscoveredFlags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$jsonCache = @{}

foreach ($file in $jsonFiles) {
    try {
        $rawContent = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        $items = $rawContent | ConvertFrom-Json
        $jsonCache[$file.FullName] = $items

        foreach ($item in $items) {
            if ($item.flagsStr) {
                $tokens = $item.flagsStr.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
                foreach ($t in $tokens) {
                    $clean = $t.Trim()
                    if ($clean -and -not $ignoredFlags.Contains($clean)) {
                        [void]$baseDiscoveredFlags.Add($clean.ToUpperInvariant())
                    }
                }
            }
        }
    } catch {
        Write-Warning "Failed to parse '$($file.Name)' during flag discovery: $_"
    }
}

$discoveredFlags = [System.Collections.Generic.HashSet[string]]::new($baseDiscoveredFlags, [System.StringComparer]::OrdinalIgnoreCase)
$availableFlagsList = $discoveredFlags | Sort-Object

# =============================================================================
# 3. INTERACTIVE CONFIGURATION
# =============================================================================

function Show-ConfigurationHeader {
    param(
        [int]$UpToStep,
        [bool]$ShowCommandsHint = $true
    )

    Clear-Host
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "                SAR JSON CvarDump to CFG Converter                      " -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "Found $($jsonFiles.Count) JSON file(s) in: $Directory" -ForegroundColor Gray
    if ($ShowCommandsHint) {
        Write-Host "Commands: Type 'back' to go to previous option | 'reset' to restart from step 1`n" -ForegroundColor DarkGray
    } else {
        Write-Host ""
    }

    if ($UpToStep -gt 1 -and $namingSummary) {
        Write-Host "  [1] Output File Naming : " -NoNewline -ForegroundColor DarkGray
        Write-Host $namingSummary -ForegroundColor White
    }
    if ($UpToStep -gt 2 -and $typeSummary) {
        Write-Host "  [2] Command Types      : " -NoNewline -ForegroundColor DarkGray
        Write-Host $typeSummary -ForegroundColor White
    }
    if ($UpToStep -gt 3 -and $sarSummary) {
        Write-Host "  [3] SAR Plugin Scope   : " -NoNewline -ForegroundColor DarkGray
        Write-Host $sarSummary -ForegroundColor White
    }
    if ($UpToStep -gt 4 -and $flagSummary) {
        Write-Host "  [4] Flag Handling      : " -NoNewline -ForegroundColor DarkGray
        Write-Host $flagSummary -ForegroundColor White
    }
    if ($UpToStep -gt 5 -and $sectionSummary) {
        Write-Host "  [5] Flag Sectioning    : " -NoNewline -ForegroundColor DarkGray
        Write-Host $sectionSummary -ForegroundColor White
    }
    if ($UpToStep -gt 1) {
        Write-Host ""
    }
}

$currentStep = 1
$step3Sub = 1
$step4Sub = 1
$step5Sub = 1

$namingChoice = '1'
$customFileNames = @{}
$namingSummary = $null

$typeChoice = '1'
$typeSummary = $null

$sarChoice = '1'
$tagSarFlag = $false
$sarSummary = $null

$flagAction = '1'
$omitFlags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$separateFlags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$flagSummary = $null

$enableSectioning = $false
$sectionFlagOrder = [System.Collections.Generic.List[string]]::new()
$omitSectionFlagFromComment = $true

$sepSectionMode = '1'
$sepFileSectionConfig = @{}
$customSepIndividually = $false
$activeCustomSepFlagIndex = 0
$sectionSummary = $null

while ($currentStep -le 5) {

    # [Step 1] Output File Naming
    if ($currentStep -eq 1) {
        Show-ConfigurationHeader -UpToStep 1

        Write-Host "[1] Output File Naming" -ForegroundColor Yellow
        Write-Host "  1) Input File Name - Uses the JSON's base name (e.g., <input>_cvars.cfg)"
        if ($hasMultipleFiles) {
            Write-Host "  2) Descriptor      - [DISABLED] Multiple JSON files detected; would cause overwrites" -ForegroundColor DarkGray
            Write-Host "  3) Custom Name     - Choose a custom name for each file"
        } else {
            Write-Host "  2) Descriptor      - Uses only the category name (e.g., cvars.cfg, full.cfg)"
            Write-Host "  3) Custom Name     - Choose a custom name"
        }

        $rawInput = (Read-Host "`nSelect naming option (Default: 1)").Trim()

        if ($rawInput -in @('back', 'b')) {
            Write-Warning "Already at the first step."
            Start-Sleep -Milliseconds 800
            continue
        }
        if ($rawInput -in @('reset', 'r')) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($rawInput)) { $rawInput = '1' }

        if ($hasMultipleFiles -and $rawInput -eq '2') {
            Write-Warning "Option [2] is disabled when multiple JSON files are present to prevent overwrites."
            Start-Sleep -Milliseconds 1200
            continue
        }

        if ($rawInput -notin @('1', '2', '3')) {
            continue
        }

        $namingChoice = $rawInput
        $customFileNames = @{}
        $namingCancelled = $false

        if ($namingChoice -eq '3') {
            Write-Host "`n  Assign Custom Name(s):" -ForegroundColor DarkCyan
            foreach ($f in $jsonFiles) {
                $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                $promptLabel = if ($hasMultipleFiles) { "  Enter name for '$($f.Name)' (Default: '$base')" } else { "  Enter name (Default: '$base')" }
                $chosenCustom = (Read-Host $promptLabel).Trim()

                if ($chosenCustom -in @('back', 'b')) {
                    $namingCancelled = $true
                    break
                }
                if ($chosenCustom -in @('reset', 'r')) {
                    $currentStep = 1
                    $namingCancelled = $true
                    break
                }

                if ([string]::IsNullOrWhiteSpace($chosenCustom)) {
                    $chosenCustom = $base
                } else {
                    $chosenCustom = $chosenCustom -replace '\.cfg$', ''
                }
                $customFileNames[$f.FullName] = $chosenCustom
            }

            if ($namingCancelled) {
                continue
            }
            $namingSummary = "Custom Name(s)"
        } elseif ($namingChoice -eq '2') {
            $namingSummary = "Descriptor Only"
        } else {
            $namingSummary = "Input File Name"
        }

        $currentStep = 2
        continue
    }

    # [Step 2] Command Types
    if ($currentStep -eq 2) {
        Show-ConfigurationHeader -UpToStep 2

        Write-Host "[2] Command Types" -ForegroundColor Yellow
        Write-Host "  1) Both Combined     - Export everything into a single file"
        Write-Host "  2) ConVariables Only - Export settings only; omit actions"
        Write-Host "  3) ConCommands Only  - Export actions only; omit settings"
        Write-Host "  4) Separate Files    - Export both into distinct files"

        $rawInput = (Read-Host "`nSelect type option [1-4] (Default: 1)").Trim()

        if ($rawInput -in @('back', 'b')) {
            $currentStep = 1
            continue
        }
        if ($rawInput -in @('reset', 'r')) {
            $currentStep = 1
            $namingSummary = $null
            $typeSummary = $null
            $sarSummary = $null
            $flagSummary = $null
            $sectionSummary = $null
            continue
        }

        if ([string]::IsNullOrWhiteSpace($rawInput)) { $rawInput = '1' }
        if ($rawInput -notin @('1', '2', '3', '4')) { continue }

        $typeChoice = $rawInput
        switch ($typeChoice) {
            '1' { $typeSummary = "Both Combined" }
            '2' { $typeSummary = "ConVariables Only" }
            '3' { $typeSummary = "ConCommands Only" }
            '4' { $typeSummary = "Separate Files" }
        }

        $currentStep = 3
        $step3Sub = 1
        continue
    }

    # [Step 3] SAR Plugin Scope
    if ($currentStep -eq 3) {
        Show-ConfigurationHeader -UpToStep 3

        if ($step3Sub -eq 1) {
            Write-Host "[3] SAR Plugin Scope" -ForegroundColor Yellow
            Write-Host "  1) Keep All (Default)     - Include both standard Game and SAR commands"
            Write-Host "  2) Game Only              - Exclude SAR plugin commands"
            Write-Host "  3) SAR Only               - Exclude standard Game commands"
            Write-Host "  4) Separate Files         - Export Game and SAR commands into distinct files"

            $rawInput = (Read-Host "`nSelect SAR option [1-4] (Default: 1)").Trim()

            if ($rawInput -in @('back', 'b')) {
                $currentStep = 2
                continue
            }
            if ($rawInput -in @('reset', 'r')) {
                $currentStep = 1
                $step3Sub = 1
                $namingSummary = $null
                $typeSummary = $null
                $sarSummary = $null
                $flagSummary = $null
                $sectionSummary = $null
                continue
            }

            if ([string]::IsNullOrWhiteSpace($rawInput)) { $rawInput = '1' }
            if ($rawInput -notin @('1', '2', '3', '4')) { continue }

            $sarChoice = $rawInput
            if ($sarChoice -in @('1', '4')) {
                $step3Sub = 2
                continue
            } else {
                $tagSarFlag = $false
                [void]$discoveredFlags.Remove('SAR')
                $availableFlagsList = $discoveredFlags | Sort-Object

                $sarSummary = if ($sarChoice -eq '2') { "Game Only" } else { "SAR Only" }
                $currentStep = 4
                $step4Sub = 1
                continue
            }
        }
        elseif ($step3Sub -eq 2) {
            Write-Host "[3] SAR Plugin Scope" -ForegroundColor Yellow
            $scopeLabel = if ($sarChoice -eq '1') { "Keep All" } else { "Separate Files" }
            Write-Host ("  Scope Selection : {0}" -f $scopeLabel) -ForegroundColor Gray

            $rawInput = (Read-Host "`nTag SAR commands with 'SAR' flag in comments/sections? (y/n) [Default: y]").Trim()

            if ($rawInput -in @('back', 'b')) {
                $step3Sub = 1
                continue
            }
            if ($rawInput -in @('reset', 'r')) {
                $currentStep = 1
                $step3Sub = 1
                $namingSummary = $null
                $typeSummary = $null
                $sarSummary = $null
                $flagSummary = $null
                $sectionSummary = $null
                continue
            }

            $tagSarFlag = ($rawInput.ToLower() -notin @('n', 'no'))
            if ($tagSarFlag) {
                [void]$discoveredFlags.Add('SAR')
            } else {
                [void]$discoveredFlags.Remove('SAR')
            }
            $availableFlagsList = $discoveredFlags | Sort-Object

            $tagNote = if ($tagSarFlag) { " (Tagged SAR)" } else { "" }
            $sarSummary = "{0}{1}" -f $scopeLabel, $tagNote

            $currentStep = 4
            $step4Sub = 1
            continue
        }
    }

    # [Step 4] Flag Handling
    if ($currentStep -eq 4) {
        Show-ConfigurationHeader -UpToStep 4

        if ($step4Sub -eq 1) {
            Write-Host "[4] Flag Handling" -ForegroundColor Yellow
            Write-Host "  [4A] Flag Action" -ForegroundColor Yellow
            Write-Host "    1) Keep All (Default)"
            Write-Host "    2) Omit Flags"
            Write-Host "    3) Separate Flags"

            $rawInput = (Read-Host "`nSelect action [1-3] (Default: 1)").Trim()

            if ($rawInput -in @('back', 'b')) {
                $currentStep = 3
                $step3Sub = if ($sarChoice -in @('1', '4')) { 2 } else { 1 }
                continue
            }
            if ($rawInput -in @('reset', 'r')) {
                $currentStep = 1
                $step4Sub = 1
                $namingSummary = $null
                $typeSummary = $null
                $sarSummary = $null
                $flagSummary = $null
                $sectionSummary = $null
                continue
            }

            if ([string]::IsNullOrWhiteSpace($rawInput)) { $rawInput = '1' }
            if ($rawInput -notin @('1', '2', '3')) { continue }

            $flagAction = $rawInput
            $omitFlags.Clear()
            $separateFlags.Clear()

            if ($flagAction -eq '1') {
                $flagSummary = "Keep All"
                $currentStep = 5
                $step5Sub = 1
                continue
            } else {
                $step4Sub = 2
                continue
            }
        }
        elseif ($step4Sub -eq 2) {
            Write-Host "[4] Flag Handling" -ForegroundColor Yellow
            $actionName = if ($flagAction -eq '2') { "Omit Flags" } else { "Separate Flags" }
            Write-Host ("  [4A] Action: {0}" -f $actionName) -ForegroundColor Gray

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
            Write-Host "`n  [4B] Choose Flags" -ForegroundColor Yellow
            $rawInput = (Read-Host "Select flag(s) to $actionVerb (numbers or names)").Trim()

            if ($rawInput -in @('back', 'b')) {
                $step4Sub = 1
                continue
            }
            if ($rawInput -in @('reset', 'r')) {
                $currentStep = 1
                $step4Sub = 1
                $namingSummary = $null
                $typeSummary = $null
                $sarSummary = $null
                $flagSummary = $null
                $sectionSummary = $null
                continue
            }

            $omitFlags.Clear()
            $separateFlags.Clear()

            if (-not [string]::IsNullOrWhiteSpace($rawInput)) {
                $tokens = $rawInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
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
                    $flagSummary = "Omit ($($omitFlags -join ', '))"
                } elseif ($flagAction -eq '3') {
                    foreach ($f in $resolvedFlags) { [void]$separateFlags.Add($f) }
                    $flagSummary = "Separate ($($separateFlags -join ', '))"
                }
            } else {
                $flagSummary = if ($flagAction -eq '2') { "Omit (None)" } else { "Separate (None)" }
            }

            $currentStep = 5
            $step5Sub = 1
            continue
        }
    }

    # [Step 5] Flag Sectioning
    if ($currentStep -eq 5) {
        Show-ConfigurationHeader -UpToStep 5
        $separateFlagsList = @($separateFlags)

        # 5.1: Main files categorization enable
        if ($step5Sub -eq 1) {
            Write-Host "[5] Flag Sectioning" -ForegroundColor Yellow
            $promptLabel = if ($separateFlagsList.Count -gt 0) { "Categorize main commands by flag? (y/n) [Default: n]" } else { "Categorize commands by flag? (y/n) [Default: n]" }
            $rawInput = (Read-Host $promptLabel).Trim()

            if ($rawInput -in @('back', 'b')) {
                $currentStep = 4
                $step4Sub = if ($flagAction -in @('2', '3')) { 2 } else { 1 }
                continue
            }
            if ($rawInput -in @('reset', 'r')) {
                $currentStep = 1
                $step5Sub = 1
                $namingSummary = $null
                $typeSummary = $null
                $sarSummary = $null
                $flagSummary = $null
                $sectionSummary = $null
                continue
            }

            $enableSectioning = ($rawInput.ToLower() -in @('y', 'yes'))
            if (-not $enableSectioning) {
                $sectionFlagOrder.Clear()
                if ($separateFlagsList.Count -gt 0) {
                    $step5Sub = 4
                    continue
                } else {
                    $sectionSummary = "None (Flat List)"
                    $currentStep = 6
                    continue
                }
            } else {
                $step5Sub = 2
                continue
            }
        }

        # 5.2: Main files section order
        elseif ($step5Sub -eq 2) {
            Write-Host "[5] Flag Sectioning" -ForegroundColor Yellow
            Write-Host "  Categorize main files by flag: Yes" -ForegroundColor Gray

            Write-Host "`nAvailable Flags:" -ForegroundColor DarkCyan
            if ($availableFlagsList.Count -gt 0) {
                for ($i = 0; $i -lt $availableFlagsList.Count; $i++) {
                    $numTag = ("[{0}]" -f ($i + 1)).PadRight(5)
                    Write-Host ("  {0} {1}" -f $numTag, $availableFlagsList[$i]) -ForegroundColor Gray
                }
            } else {
                Write-Host "  (None detected)" -ForegroundColor Gray
            }

            $orderPrompt = if ($separateFlagsList.Count -gt 0) { "`nSelect section order for main files (e.g. '1, 4' or 'REPLICATED, ARCHIVE')" } else { "`nSelect section order (e.g. '1, 4' or 'REPLICATED, ARCHIVE')" }
            $rawInput = (Read-Host $orderPrompt).Trim()

            if ($rawInput -in @('back', 'b')) {
                $step5Sub = 1
                continue
            }
            if ($rawInput -in @('reset', 'r')) {
                $currentStep = 1
                $step5Sub = 1
                $namingSummary = $null
                $typeSummary = $null
                $sarSummary = $null
                $flagSummary = $null
                $sectionSummary = $null
                continue
            }

            $sectionFlagOrder.Clear()
            if (-not [string]::IsNullOrWhiteSpace($rawInput)) {
                $tokens = $rawInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
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
            }

            if ($sectionFlagOrder.Count -gt 0) {
                $step5Sub = 3
                continue
            } else {
                $enableSectioning = $false
                if ($separateFlagsList.Count -gt 0) {
                    $step5Sub = 4
                    continue
                } else {
                    $sectionSummary = "None (No flags selected)"
                    $currentStep = 6
                    continue
                }
            }
        }

        # 5.3: Main files comment omission
        elseif ($step5Sub -eq 3) {
            Write-Host "[5] Flag Sectioning" -ForegroundColor Yellow
            Write-Host "  Categorize main files: Yes" -ForegroundColor Gray
            Write-Host ("  Main Priority Order  : {0} -> OTHER" -f ($sectionFlagOrder -join ' -> ')) -ForegroundColor Gray

            $rawInput = (Read-Host "`nOmit section's flag from comments inside that section? (y/n) [Default: y]").Trim()

            if ($rawInput -in @('back', 'b')) {
                $step5Sub = 2
                continue
            }
            if ($rawInput -in @('reset', 'r')) {
                $currentStep = 1
                $step5Sub = 1
                $namingSummary = $null
                $typeSummary = $null
                $sarSummary = $null
                $flagSummary = $null
                $sectionSummary = $null
                continue
            }

            if ($rawInput.ToLower() -eq 'n') {
                $omitSectionFlagFromComment = $false
            } else {
                $omitSectionFlagFromComment = $true
            }

            if ($separateFlagsList.Count -gt 0) {
                $step5Sub = 4
                continue
            } else {
                $omitNote = if ($omitSectionFlagFromComment) { ", omit flag from comments" } else { "" }
                $sectionSummary = "Sectioned ($($sectionFlagOrder -join ' -> ') -> OTHER$omitNote)"
                $currentStep = 6
                continue
            }
        }

        # 5.4: Separated files sectioning mode choice
        elseif ($step5Sub -eq 4) {
            Write-Host "[5] Flag Sectioning" -ForegroundColor Yellow
            $mainStatusDesc = if ($enableSectioning) { "$($sectionFlagOrder -join ' -> ') -> OTHER" } else { "Flat List" }
            Write-Host ("  Main Files Sectioning : {0}" -f $mainStatusDesc) -ForegroundColor Gray

            Write-Host "`n  [5B] Separated Files Sectioning ($($separateFlagsList -join ', '))" -ForegroundColor Yellow
            $inheritLabel = if ($enableSectioning) { "Same as Main (Inherit section order)" } else { "Same as Main (Flat List)" }
            Write-Host ("    1) {0} [Default]" -f $inheritLabel)
            Write-Host "    2) Flat List (No sectioning in separated files)"
            Write-Host "    3) Custom Sectioning (Choose custom sections for separated files)"

            $rawInput = (Read-Host "`nSelect separated files sectioning option [1-3] (Default: 1)").Trim()

            if ($rawInput -in @('back', 'b')) {
                $step5Sub = if ($enableSectioning) { 3 } else { 1 }
                continue
            }
            if ($rawInput -in @('reset', 'r')) {
                $currentStep = 1
                $step5Sub = 1
                $namingSummary = $null
                $typeSummary = $null
                $sarSummary = $null
                $flagSummary = $null
                $sectionSummary = $null
                continue
            }

            if ([string]::IsNullOrWhiteSpace($rawInput)) { $rawInput = '1' }
            if ($rawInput -notin @('1', '2', '3')) { continue }

            $sepSectionMode = $rawInput
            $sepFileSectionConfig = @{}

            if ($sepSectionMode -eq '1') {
                foreach ($sf in $separateFlagsList) {
                    $filteredMainFlags = [System.Collections.Generic.List[string]]::new()
                    foreach ($flagItem in $sectionFlagOrder) {
                        if ($flagItem -ine $sf) { [void]$filteredMainFlags.Add($flagItem) }
                    }

                    $sepFileSectionConfig[$sf] = [PSCustomObject]@{
                        SectionFlags    = $filteredMainFlags
                        OmitSectionFlag = $omitSectionFlagFromComment
                        Mode            = "Inherited"
                    }
                }
                $mainDesc = if ($enableSectioning) { "Sectioned ($($sectionFlagOrder -join ' -> '))" } else { "Flat" }
                $sepDesc = if ($enableSectioning) { "Inherited" } else { "Flat" }
                $sectionSummary = "{0} | Separated: {1}" -f $mainDesc, $sepDesc
                $currentStep = 6
                continue
            }
            elseif ($sepSectionMode -eq '2') {
                foreach ($sf in $separateFlagsList) {
                    $sepFileSectionConfig[$sf] = [PSCustomObject]@{
                        SectionFlags    = [System.Collections.Generic.List[string]]::new()
                        OmitSectionFlag = $false
                        Mode            = "Flat"
                    }
                }
                $mainDesc = if ($enableSectioning) { "Sectioned ($($sectionFlagOrder -join ' -> '))" } else { "Flat" }
                $sectionSummary = "{0} | Separated: Flat" -f $mainDesc
                $currentStep = 6
                continue
            }
            elseif ($sepSectionMode -eq '3') {
                if ($separateFlagsList.Count -gt 1) {
                    $step5Sub = 5
                    continue
                } else {
                    $customSepIndividually = $false
                    $activeCustomSepFlagIndex = 0
                    $step5Sub = 6
                    continue
                }
            }
        }

        # 5.5: Multiple separated flags - individual configuration choice
        elseif ($step5Sub -eq 5) {
            Write-Host "[5] Flag Sectioning" -ForegroundColor Yellow
            Write-Host "  Separated Files Mode : Custom Sectioning" -ForegroundColor Gray

            $rawInput = (Read-Host "`nConfigure each separated file individually? (y/n) [Default: n]").Trim()

            if ($rawInput -in @('back', 'b')) {
                $step5Sub = 4
                continue
            }
            if ($rawInput -in @('reset', 'r')) {
                $currentStep = 1
                $step5Sub = 1
                $namingSummary = $null
                $typeSummary = $null
                $sarSummary = $null
                $flagSummary = $null
                $sectionSummary = $null
                continue
            }

            $customSepIndividually = ($rawInput.ToLower() -in @('y', 'yes'))
            $activeCustomSepFlagIndex = 0
            $step5Sub = 6
            continue
        }

        # 5.6: Custom section order for separated file(s)
        elseif ($step5Sub -eq 6) {
            Write-Host "[5] Flag Sectioning" -ForegroundColor Yellow

            $targetName = if ($customSepIndividually) { $separateFlagsList[$activeCustomSepFlagIndex] } else { ($separateFlagsList -join ', ') }
            Write-Host ("  Custom Sectioning for: [{0}]" -f $targetName) -ForegroundColor DarkCyan

            $availableForSep = $availableFlagsList | Where-Object {
                if ($customSepIndividually) { $_ -ine $separateFlagsList[$activeCustomSepFlagIndex] } else { $true }
            }

            Write-Host "`nAvailable Flags:" -ForegroundColor DarkCyan
            if ($availableForSep.Count -gt 0) {
                for ($i = 0; $i -lt $availableForSep.Count; $i++) {
                    $numTag = ("[{0}]" -f ($i + 1)).PadRight(5)
                    Write-Host ("  {0} {1}" -f $numTag, $availableForSep[$i]) -ForegroundColor Gray
                }
            } else {
                Write-Host "  (None detected)" -ForegroundColor Gray
            }

            $rawInput = (Read-Host "`nSelect section order for [$targetName] (e.g. '1, 4' or 'REPLICATED, ARCHIVE')").Trim()

            if ($rawInput -in @('back', 'b')) {
                if ($customSepIndividually -and $activeCustomSepFlagIndex -gt 0) {
                    $activeCustomSepFlagIndex--
                    $step5Sub = 7
                    continue
                } elseif ($separateFlagsList.Count -gt 1) {
                    $step5Sub = 5
                    continue
                } else {
                    $step5Sub = 4
                    continue
                }
            }
            if ($rawInput -in @('reset', 'r')) {
                $currentStep = 1
                $step5Sub = 1
                $namingSummary = $null
                $typeSummary = $null
                $sarSummary = $null
                $flagSummary = $null
                $sectionSummary = $null
                continue
            }

            $tempCustomOrder = [System.Collections.Generic.List[string]]::new()
            if (-not [string]::IsNullOrWhiteSpace($rawInput)) {
                $tokens = $rawInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
                foreach ($token in $tokens) {
                    $matchedFlag = $null
                    if ($token -match '^\d+$') {
                        $idx = [int]$token - 1
                        if ($idx -ge 0 -and $idx -lt $availableForSep.Count) {
                            $matchedFlag = $availableForSep[$idx].ToUpperInvariant()
                        }
                    } else {
                        $matched = $availableForSep | Where-Object { $_ -ieq $token } | Select-Object -First 1
                        if ($matched) {
                            $matchedFlag = $matched.ToUpperInvariant()
                        }
                    }

                    if ($matchedFlag -and -not $tempCustomOrder.Contains($matchedFlag)) {
                        $tempCustomOrder.Add($matchedFlag)
                    }
                }
            }

            $activeCustomOrder = $tempCustomOrder
            $step5Sub = 7
            continue
        }

        # 5.7: Custom comment omission for separated file(s)
        elseif ($step5Sub -eq 7) {
            Write-Host "[5] Flag Sectioning" -ForegroundColor Yellow
            $targetName = if ($customSepIndividually) { $separateFlagsList[$activeCustomSepFlagIndex] } else { ($separateFlagsList -join ', ') }
            $orderDesc = if ($activeCustomOrder.Count -gt 0) { "$($activeCustomOrder -join ' -> ') -> OTHER" } else { "Flat List" }
            Write-Host ("  Target File(s) : [{0}]" -f $targetName) -ForegroundColor Gray
            Write-Host ("  Section Order  : {0}" -f $orderDesc) -ForegroundColor Gray

            $activeCustomOmit = $true
            if ($activeCustomOrder.Count -gt 0) {
                $rawInput = (Read-Host "`nOmit section's flag from comments inside that section? (y/n) [Default: y]").Trim()

                if ($rawInput -in @('back', 'b')) {
                    $step5Sub = 6
                    continue
                }
                if ($rawInput -in @('reset', 'r')) {
                    $currentStep = 1
                    $step5Sub = 1
                    $namingSummary = $null
                    $typeSummary = $null
                    $sarSummary = $null
                    $flagSummary = $null
                    $sectionSummary = $null
                    continue
                }

                if ($rawInput.ToLower() -eq 'n') {
                    $activeCustomOmit = $false
                }
            }

            if ($customSepIndividually) {
                $currentFlagKey = $separateFlagsList[$activeCustomSepFlagIndex]
                $sepFileSectionConfig[$currentFlagKey] = [PSCustomObject]@{
                    SectionFlags    = $activeCustomOrder
                    OmitSectionFlag = $activeCustomOmit
                    Mode            = "Custom"
                }

                if ($activeCustomSepFlagIndex -lt ($separateFlagsList.Count - 1)) {
                    $activeCustomSepFlagIndex++
                    $step5Sub = 6
                    continue
                }
            } else {
                foreach ($sf in $separateFlagsList) {
                    $filteredForSingle = [System.Collections.Generic.List[string]]::new()
                    foreach ($flagItem in $activeCustomOrder) {
                        if ($flagItem -ine $sf) { [void]$filteredForSingle.Add($flagItem) }
                    }

                    $sepFileSectionConfig[$sf] = [PSCustomObject]@{
                        SectionFlags    = $filteredForSingle
                        OmitSectionFlag = $activeCustomOmit
                        Mode            = "Custom"
                    }
                }
            }

            $mainDesc = if ($enableSectioning) { "Sectioned ($($sectionFlagOrder -join ' -> '))" } else { "Flat" }
            $sepDescParts = foreach ($k in $sepFileSectionConfig.Keys) {
                $cfg = $sepFileSectionConfig[$k]
                if ($cfg.SectionFlags.Count -gt 0) {
                    "{0}: {1}" -f $k, ($cfg.SectionFlags -join '->')
                } else {
                    "{0}: Flat" -f $k
                }
            }
            $sectionSummary = "{0} | Separated: Custom ({1})" -f $mainDesc, ($sepDescParts -join ', ')
            $currentStep = 6
            continue
        }
    }
}

Show-ConfigurationHeader -UpToStep 6 -ShowCommandsHint $false

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "                     Starting Batch Conversion                          " -ForegroundColor Cyan
Write-Host "========================================================================`n" -ForegroundColor Cyan

# =============================================================================
# 4. CORE ENGINE & FILE WRITERS
# =============================================================================

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

function Write-CfgFile {
    param(
        [string]$FilePath,
        [System.Collections.Generic.List[CvarItem]]$Entries,
        [System.Collections.Generic.List[string]]$SectionFlags,
        [bool]$OmitSectionFlag = $false,
        [int]$FileNamePadding = 0,
        [string]$FileOmittedFlag = ""
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($null -eq $Entries -or $Entries.Count -eq 0) { 
        return @{ Count = 0; Categories = @{} }
    }

    $maxLen = 0
    foreach ($e in $Entries) {
        if ($e.LeftSide.Length -gt $maxLen) {
            $maxLen = $e.LeftSide.Length
        }
    }

    $outputLines = [System.Collections.Generic.List[string]]::new($Entries.Count + 16)
    $categoryDistribution = [ordered]@{}
    $isSectioned = $false

    if ($SectionFlags -and $SectionFlags.Count -gt 0) {
        $buckets = [ordered]@{}
        foreach ($sf in $SectionFlags) {
            $buckets[$sf] = [System.Collections.Generic.List[CvarItem]]::new()
        }
        $buckets['OTHER'] = [System.Collections.Generic.List[CvarItem]]::new()

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

                [SourceEngineCvarComparer]::Sort($bList)

                foreach ($e in $bList) {
                    $commentBody = $e.GetComment($sectionName, $OmitSectionFlag, $FileOmittedFlag)
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

    if (-not $isSectioned) {
        [SourceEngineCvarComparer]::Sort($Entries)

        foreach ($e in $Entries) {
            $commentBody = $e.GetComment("", $false, $FileOmittedFlag)
            if (-not [string]::IsNullOrEmpty($commentBody)) {
                $padded = $e.LeftSide.PadRight($maxLen)
                $outputLines.Add("$padded // $commentBody")
            } else {
                $outputLines.Add($e.LeftSide)
            }
        }
    }

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

# =============================================================================
# 5. EXECUTION PIPELINE
# =============================================================================

$totalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$totalFilesWritten = 0
$totalEntriesWritten = 0
$totalRawEncountered = 0
$totalRawCvars = 0
$totalRawCcoms = 0
$totalRawGame = 0
$totalRawSar = 0
$totalOmittedByFlag = 0
$totalOmittedByType = 0
$totalOmittedBySar = 0
$totalSeparatedCount = 0
$globalCategoryTotals = [ordered]@{}
$globalOmittedFlagCounts = [ordered]@{}
$globalSeparatedFlagCounts = [ordered]@{}
$generatedFileReports = [System.Collections.Generic.List[PSCustomObject]]::new()

$fileIndex = 0

foreach ($file in $jsonFiles) {
    $fileIndex++
    $fileSw = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Host ("------------------------------------------------------------------------") -ForegroundColor DarkGray
    Write-Host ("File [{0}/{1}]: {2}" -f $fileIndex, $jsonFiles.Count, $file.Name) -ForegroundColor Yellow
    Write-Host ("------------------------------------------------------------------------") -ForegroundColor DarkGray

    $records = $jsonCache[$file.FullName]
    if ($null -eq $records) {
        Write-Warning "  [!] No valid records found for '$($file.Name)'. Skipping."
        continue
    }

    $parsedEntries = [System.Collections.Generic.List[CvarItem]]::new($records.Count)
    $rawCvarCount = 0
    $rawCcomCount = 0
    $rawGameCount = 0
    $rawSarCount  = 0
    $fileOmittedByFlag = 0
    $fileOmittedBySar  = 0
    $omittedFlagCounts = @{}

    foreach ($row in $records) {
        if ([string]::IsNullOrWhiteSpace($row.name)) { continue }

        $name = $row.name.Trim()
        if ($name.StartsWith("'") -and $name.EndsWith("'") -and $name.Length -ge 2) {
            $name = $name.Substring(1, $name.Length - 2)
        }

        $isCmd = [bool]$row.isCommand
        $isSar = [bool]$row.isSAR
        $val = if (-not $isCmd -and $null -ne $row.default) { $row.default.ToString().Trim() } else { "" }

        if ($isCmd) { $rawCcomCount++ } else { $rawCvarCount++ }
        if ($isSar) { $rawSarCount++  } else { $rawGameCount++ }

        if ($sarChoice -eq '2' -and $isSar) {
            $fileOmittedBySar++
            continue
        }
        if ($sarChoice -eq '3' -and -not $isSar) {
            $fileOmittedBySar++
            continue
        }

        $activeFlags = [System.Collections.Generic.List[string]]::new()
        if ($row.flagsStr) {
            $tokens = $row.flagsStr.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
            foreach ($t in $tokens) {
                $clean = $t.Trim()
                if ($clean -and -not $ignoredFlags.Contains($clean)) {
                    $activeFlags.Add($clean.ToUpperInvariant())
                }
            }
        }

        if ($tagSarFlag -and $isSar) {
            $activeFlags.Add('SAR')
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

            if (-not $globalOmittedFlagCounts.Contains($omittedByThisFlag)) {
                $globalOmittedFlagCounts[$omittedByThisFlag] = 0
            }
            $globalOmittedFlagCounts[$omittedByThisFlag]++
            continue
        }

        $helpText = ""
        if (-not [string]::IsNullOrWhiteSpace($row.helpStr)) {
            $helpText = ($row.helpStr.Trim() -replace '\s+', ' ')
        }

        $leftSide = if ($isCmd) { $name } else { '{0} "{1}"' -f $name, $val }

        $parsedEntries.Add([CvarItem]::new($name, $leftSide, $isCmd, $isSar, $activeFlags, $helpText))
    }

    $rawTotal = $rawCvarCount + $rawCcomCount
    $totalRawEncountered += $rawTotal
    $totalRawCvars += $rawCvarCount
    $totalRawCcoms += $rawCcomCount
    $totalRawGame  += $rawGameCount
    $totalRawSar   += $rawSarCount
    $totalOmittedByFlag += $fileOmittedByFlag
    $totalOmittedBySar  += $fileOmittedBySar

    Write-Host ("  [+] Parsed Content    : {0} entries in {1}ms" -f $rawTotal, $fileSw.ElapsedMilliseconds) -ForegroundColor DarkGray
    Write-Host ("  [+] Breakdown         : {0} ConVars, {1} ConCommands ({2} Game, {3} SAR)" -f $rawCvarCount, $rawCcomCount, $rawGameCount, $rawSarCount) -ForegroundColor DarkGray

    if ($fileOmittedBySar -gt 0) {
        $sarOmittedDesc = if ($sarChoice -eq '2') { "SAR commands" } else { "Game commands" }
        Write-Host ("  [+] Omitted (Scope)   : {0} {1}" -f $fileOmittedBySar, $sarOmittedDesc) -ForegroundColor Yellow
    }

    if ($fileOmittedByFlag -gt 0) {
        $flagDetailParts = foreach ($k in $omittedFlagCounts.Keys) { "{0}: {1}" -f $k, $omittedFlagCounts[$k] }
        Write-Host ("  [+] Omitted (Flags)   : {0} entries ({1})" -f $fileOmittedByFlag, ($flagDetailParts -join ', ')) -ForegroundColor Yellow
    }

    $cvars = [System.Collections.Generic.List[CvarItem]]::new($parsedEntries.Count)
    $ccoms = [System.Collections.Generic.List[CvarItem]]::new($parsedEntries.Count)
    foreach ($entry in $parsedEntries) {
        if ($entry.IsCmd) { [void]$ccoms.Add($entry) } else { [void]$cvars.Add($entry) }
    }

    $typeGroups = [System.Collections.Generic.List[PSCustomObject]]::new()
    $fileOmittedByType = 0

    switch ($typeChoice) {
        '1' {
            $typeGroups.Add([PSCustomObject]@{ Descriptor = 'full'; Entries = $parsedEntries })
        }
        '2' {
            $fileOmittedByType = $ccoms.Count
            $typeGroups.Add([PSCustomObject]@{ Descriptor = 'cvars'; Entries = $cvars })
        }
        '3' {
            $fileOmittedByType = $cvars.Count
            $typeGroups.Add([PSCustomObject]@{ Descriptor = 'ccoms'; Entries = $ccoms })
        }
        '4' {
            $typeGroups.Add([PSCustomObject]@{ Descriptor = 'cvars'; Entries = $cvars })
            $typeGroups.Add([PSCustomObject]@{ Descriptor = 'ccoms'; Entries = $ccoms })
        }
    }

    $totalOmittedByType += $fileOmittedByType
    if ($fileOmittedByType -gt 0) {
        $typeOmittedDesc = if ($typeChoice -eq '2') { "ConCommands" } else { "ConVariables" }
        Write-Host ("  [+] Omitted (Type)    : {0} {1}" -f $fileOmittedByType, $typeOmittedDesc) -ForegroundColor Yellow
    }

    $groups = [System.Collections.Generic.List[PSCustomObject]]::new()
    if ($sarChoice -eq '4') {
        foreach ($tg in $typeGroups) {
            $gameList = [System.Collections.Generic.List[CvarItem]]::new()
            $sarList  = [System.Collections.Generic.List[CvarItem]]::new()
            foreach ($item in $tg.Entries) {
                if ($item.IsSAR) { [void]$sarList.Add($item) }
                else { [void]$gameList.Add($item) }
            }
            if ($gameList.Count -gt 0) {
                $groups.Add([PSCustomObject]@{ Descriptor = "game_$($tg.Descriptor)"; Entries = $gameList })
            }
            if ($sarList.Count -gt 0) {
                $groups.Add([PSCustomObject]@{ Descriptor = "sar_$($tg.Descriptor)"; Entries = $sarList })
            }
        }
    } else {
        $groups = $typeGroups
    }

    $inputBase = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $activeCustomName = if ($customFileNames.ContainsKey($file.FullName)) { $customFileNames[$file.FullName] } else { $inputBase }

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
                    $totalSeparatedCount += $flagEntries.Count
                    if (-not $globalSeparatedFlagCounts.Contains($flagToSeparate)) {
                        $globalSeparatedFlagCounts[$flagToSeparate] = 0
                    }
                    $globalSeparatedFlagCounts[$flagToSeparate] += $flagEntries.Count

                    $flagFileName = Get-OutputFileName -NamingOption $namingChoice -InputBaseName $inputBase `
                                                       -CustomName $activeCustomName -Descriptor $grp.Descriptor `
                                                       -FlagName $flagToSeparate

                    $sepFlagsForFile = [System.Collections.Generic.List[string]]::new()
                    $sepOmitForFile = $false

                    if ($sepFileSectionConfig.ContainsKey($flagToSeparate)) {
                        $sepCfg = $sepFileSectionConfig[$flagToSeparate]
                        $sepFlagsForFile = $sepCfg.SectionFlags
                        $sepOmitForFile  = $sepCfg.OmitSectionFlag
                    } elseif ($enableSectioning) {
                        foreach ($flagItem in $sectionFlagOrder) {
                            if ($flagItem -ine $flagToSeparate) { [void]$sepFlagsForFile.Add($flagItem) }
                        }
                        $sepOmitForFile  = $omitSectionFlagFromComment
                    }

                    $plannedFiles.Add([PSCustomObject]@{
                        FileName        = $flagFileName
                        FilePath        = Join-Path $Directory $flagFileName
                        Entries         = $flagEntries
                        OmittedFlag     = $flagToSeparate
                        Role            = "Separated [$flagToSeparate]"
                        SectionFlags    = $sepFlagsForFile
                        OmitSectionFlag = $sepOmitForFile
                    })
                }
            }

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

        if ($mainList.Count -gt 0) {
            $mainFileName = Get-OutputFileName -NamingOption $namingChoice -InputBaseName $inputBase `
                                               -CustomName $activeCustomName -Descriptor $grp.Descriptor
            $plannedFiles.Add([PSCustomObject]@{
                FileName        = $mainFileName
                FilePath        = Join-Path $Directory $mainFileName
                Entries         = $mainList
                OmittedFlag     = ""
                Role            = "Main ($($grp.Descriptor))"
                SectionFlags    = $sectionFlagOrder
                OmitSectionFlag = $omitSectionFlagFromComment
            })
        }
    }

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
                               -SectionFlags $pf.SectionFlags `
                               -OmitSectionFlag $pf.OmitSectionFlag `
                               -FileNamePadding $maxFileLen `
                               -FileOmittedFlag $pf.OmittedFlag

        if ($result.Count -gt 0) {
            $totalFilesWritten++
            $totalEntriesWritten += $result.Count

            $fInfo = Get-Item -LiteralPath $pf.FilePath
            $generatedFileReports.Add([PSCustomObject]@{
                FileName   = $pf.FileName
                Entries    = $result.Count
                SizeKB     = [math]::Round($fInfo.Length / 1KB, 1)
                Role       = $pf.Role
                Categories = $result.Categories
            })

            foreach ($cat in $result.Categories.Keys) {
                if (-not $globalCategoryTotals.Contains($cat)) { $globalCategoryTotals[$cat] = 0 }
                $globalCategoryTotals[$cat] += $result.Categories[$cat]
            }
        }
    }
    Write-Host ""
}

$totalStopwatch.Stop()

# =============================================================================
# 6. CONVERSION REPORT
# =============================================================================

$totalBytesWritten = ($generatedFileReports | Measure-Object -Property SizeKB -Sum).Sum
$totalTimeSec = [math]::Round($totalStopwatch.Elapsed.TotalSeconds, 2)
$throughput = if ($totalStopwatch.ElapsedMilliseconds -gt 0) {
    [int][math]::Round(($totalRawEncountered / $totalStopwatch.ElapsedMilliseconds) * 1000)
} else { 0 }

$retentionRate = if ($totalRawEncountered -gt 0) {
    [math]::Round(($totalEntriesWritten / $totalRawEncountered) * 100, 1)
} else { 0 }

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "                             CONVERSION REPORT                                  " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

Write-Host "  STATUS       : " -NoNewline -ForegroundColor DarkGray
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host "  TIME ELAPSED : " -NoNewline -ForegroundColor DarkGray
Write-Host ("{0}s ({1} ms)" -f $totalTimeSec, $totalStopwatch.ElapsedMilliseconds) -NoNewline -ForegroundColor White
Write-Host ("  |  THROUGHPUT: {0:N0} entries/sec" -f $throughput) -ForegroundColor DarkGray

Write-Host "`n-- [INPUT & FILTERING FUNNEL] --------------------------------------------------" -ForegroundColor Yellow
Write-Host "  * Source JSONs Scanned  : " -NoNewline -ForegroundColor DarkGray
Write-Host ("{0} file(s)" -f $jsonFiles.Count) -ForegroundColor White

Write-Host "  * Raw Entries Detected  : " -NoNewline -ForegroundColor DarkGray
Write-Host ("{0:N0}" -f $totalRawEncountered) -NoNewline -ForegroundColor White
Write-Host (" ({0:N0} ConVars, {1:N0} ConCommands [{2:N0} Game, {3:N0} SAR])" -f $totalRawCvars, $totalRawCcoms, $totalRawGame, $totalRawSar) -ForegroundColor DarkGray

if ($totalOmittedBySar -gt 0) {
    $sarOmittedDesc = if ($sarChoice -eq '2') { "SAR commands" } else { "Game commands" }
    Write-Host "  * Excluded (By Scope)   : " -NoNewline -ForegroundColor DarkGray
    Write-Host ("{0:N0} {1}" -f $totalOmittedBySar, $sarOmittedDesc) -ForegroundColor Yellow
}

if ($totalOmittedByType -gt 0) {
    $typeLabel = if ($typeChoice -eq '2') { "ConCommands" } else { "ConVariables" }
    Write-Host "  * Excluded (By Type)    : " -NoNewline -ForegroundColor DarkGray
    Write-Host ("{0:N0} {1}" -f $totalOmittedByType, $typeLabel) -ForegroundColor Yellow
}

if ($totalOmittedByFlag -gt 0) {
    $flagBreakdown = foreach ($k in $globalOmittedFlagCounts.Keys) { "{0}: {1}" -f $k, $globalOmittedFlagCounts[$k] }
    Write-Host "  * Excluded (By Flag)    : " -NoNewline -ForegroundColor DarkGray
    Write-Host ("{0:N0} entries " -f $totalOmittedByFlag) -NoNewline -ForegroundColor Yellow
    Write-Host ("({0})" -f ($flagBreakdown -join ', ')) -ForegroundColor DarkGray
}

if ($totalSeparatedCount -gt 0) {
    $sepBreakdown = foreach ($k in $globalSeparatedFlagCounts.Keys) { "{0}: {1}" -f $k, $globalSeparatedFlagCounts[$k] }
    Write-Host "  * Flag-Separated Entries: " -NoNewline -ForegroundColor DarkGray
    Write-Host ("{0:N0} entries " -f $totalSeparatedCount) -NoNewline -ForegroundColor Cyan
    Write-Host ("({0})" -f ($sepBreakdown -join ', ')) -ForegroundColor DarkGray
}

Write-Host "  * Net Retained Entries  : " -NoNewline -ForegroundColor DarkGray
Write-Host ("{0:N0}" -f $totalEntriesWritten) -NoNewline -ForegroundColor Green
Write-Host (" ({0}% of raw records written)" -f $retentionRate) -ForegroundColor DarkGray

if ($generatedFileReports.Count -gt 0) {
    Write-Host "`n-- [GENERATED ARTIFACTS] -------------------------------------------------------" -ForegroundColor Yellow

    $longestName = 18
    foreach ($rep in $generatedFileReports) {
        if ($rep.FileName.Length -gt $longestName) { $longestName = $rep.FileName.Length }
    }

    $col1Width = $longestName + 2
    $headerStr = "  {0}{1}{2}  {3}" -f `
        "FILE NAME".PadRight($col1Width), `
        "ENTRIES".PadLeft(10), `
        "SIZE".PadLeft(12), `
        "ROLE / TYPE"

    Write-Host $headerStr -ForegroundColor DarkCyan
    Write-Host ("  " + ("-" * ($headerStr.Length - 2))) -ForegroundColor DarkGray

    foreach ($rep in $generatedFileReports) {
        $entryFmt = ("{0:N0}" -f $rep.Entries).PadLeft(10)
        $sizeFmt  = ("{0:N1} KB" -f $rep.SizeKB).PadLeft(12)
        $nameFmt  = $rep.FileName.PadRight($col1Width)

        Write-Host ("  {0}" -f $nameFmt) -NoNewline -ForegroundColor White
        Write-Host $entryFmt -NoNewline -ForegroundColor Green
        Write-Host $sizeFmt -NoNewline -ForegroundColor Gray
        Write-Host ("  {0}" -f $rep.Role) -ForegroundColor DarkCyan

        if ($rep.Categories -and $rep.Categories.Count -gt 0) {
            $catParts = foreach ($k in $rep.Categories.Keys) { "{0}: {1:N0}" -f $k, $rep.Categories[$k] }
            Write-Host ("    Sections -> {0}" -f ($catParts -join ' | ')) -ForegroundColor DarkGray
        }
    }

    Write-Host ("  " + ("-" * ($headerStr.Length - 2))) -ForegroundColor DarkGray
    $totalCountFmt = ("{0:N0}" -f $totalEntriesWritten).PadLeft(10)
    $totalSizeFmt  = ("{0:N1} KB" -f $totalBytesWritten).PadLeft(12)
    Write-Host ("  {0}{1}{2}  [Total {3} file(s)]" -f `
        "TOTAL".PadRight($col1Width), `
        $totalCountFmt, `
        $totalSizeFmt, `
        $totalFilesWritten) -ForegroundColor Cyan

    if ($globalCategoryTotals.Count -gt 0) {
        $globalCatParts = foreach ($k in $globalCategoryTotals.Keys) { "{0}: {1:N0}" -f $k, $globalCategoryTotals[$k] }
        Write-Host ("  Global Sections : {0}" -f ($globalCatParts -join ' | ')) -ForegroundColor DarkCyan
    }
}

Write-Host "`n================================================================================" -ForegroundColor Cyan
Read-Host "Press Enter to exit"
