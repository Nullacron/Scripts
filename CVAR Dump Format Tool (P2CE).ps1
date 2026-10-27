# =============================================================================
# P2:CE & SAR CvarDump to CFG Converter Tool
# Compatible with Portal 2: Community Edition's 'cvar_dump' and SAR dumps.
# =============================================================================

param(
    [string]$Directory = ""
)

if ([string]::IsNullOrWhiteSpace($Directory)) {
    $Directory = (Get-Location).Path
}

# =============================================================================
# 1. INITIALIZATION & NATIVE TYPES
# =============================================================================

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
        ActiveFlags = activeFlags ?? new List<string>();
        HelpText = helpText ?? "";
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

# Source Engine Flag Normalization map (P2:CE short codes to canonical names)
$flagMap = @{
    'a'                     = 'ARCHIVE'
    'cheat'                 = 'CHEAT'
    'rep'                   = 'REPLICATED'
    'norecord'              = 'NORECORD'
    'cl'                    = 'CLIENT'
    'sv'                    = 'SERVER'
    'user'                  = 'USERINFO'
    'nf'                    = 'NOTIFY'
    'demo'                  = 'DEMO'
    'prot'                  = 'PROTECTED'
    'sp'                    = 'SINGLEPLAYER'
    'numeric'               = 'NUMERIC'
    'print'                 = 'PRINTABLEONLY'
    'ss'                    = 'SPLITSCREEN'
    'ss_added'              = 'SS_ADDED'
    'clientcmd_can_execute' = 'CLIENTCMD_CAN_EXECUTE'
    'server_can_execute'    = 'SERVER_CAN_EXECUTE'
    'log'                   = 'LOG'
}

# Ignored / DLL-only flags that shouldn't clutter sections or inline comments
$ignoredFlags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
[void]$ignoredFlags.Add('game')
[void]$ignoredFlags.Add('client')
[void]$ignoredFlags.Add('cl')
[void]$ignoredFlags.Add('sv')
[void]$ignoredFlags.Add('server')
[void]$ignoredFlags.Add('none')

function Get-ParsedItemFlags ($item) {
    $rawList = @()
    if ($null -ne $item.flags) {
        if ($item.flags -is [System.Collections.IEnumerable] -and $item.flags -isnot [string]) {
            $rawList = @($item.flags)
        } elseif ($item.flags -is [string]) {
            $rawList = $item.flags.Split(' ,|', [System.StringSplitOptions]::RemoveEmptyEntries)
        }
    } elseif ($null -ne $item.flagsStr) {
        $rawList = $item.flagsStr.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
    }

    $cleanList = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $rawList) {
        if ([string]::IsNullOrWhiteSpace($f)) { continue }
        $trimmed = $f.Trim()
        $lower = $trimmed.ToLowerInvariant()
        
        # Check against ignored DLL flags
        if ($ignoredFlags.Contains($lower) -or $ignoredFlags.Contains($trimmed)) {
            continue
        }

        # Normalize flag name
        $normalized = if ($flagMap.ContainsKey($lower)) { $flagMap[$lower] } else { $trimmed.ToUpperInvariant() }
        if (-not $cleanList.Contains($normalized)) {
            [void]$cleanList.Add($normalized)
        }
    }
    return $cleanList
}

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
$anySARDetected = $false

foreach ($file in $jsonFiles) {
    try {
        $rawContent = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        $items = $rawContent | ConvertFrom-Json
        $jsonCache[$file.FullName] = $items

        foreach ($item in $items) {
            # Check for SAR presence
            if (($null -ne $item.isSAR -and [bool]$item.isSAR) -or 
                ($item.name -and $item.name.StartsWith("sar_", [System.StringComparison]::OrdinalIgnoreCase))) {
                $anySARDetected = $true
            }

            $flags = Get-ParsedItemFlags $item
            foreach ($f in $flags) {
                [void]$baseDiscoveredFlags.Add($f)
            }
        }
    } catch {
        Write-Warning "Failed to parse '$($file.Name)' during flag discovery: $_"
    }
}

$discoveredFlags = [System.Collections.Generic.HashSet[string]]::new($baseDiscoveredFlags, [System.StringComparer]::OrdinalIgnoreCase)
$availableFlagsList = $discoveredFlags | Sort-Object

# =============================================================================
# 3. INTERACTIVE CONFIGURATION WIZARD
# =============================================================================

function Show-ConfigurationHeader {
    param(
        [int]$UpToStep,
        [bool]$ShowCommandsHint = $true
    )

    Clear-Host
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "             P2:CE / SAR CvarDump to CFG Converter                      " -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "Found $($jsonFiles.Count) JSON file(s) in: $Directory" -ForegroundColor Gray
    if ($ShowCommandsHint) {
        Write-Host "Commands: Type 'back' to go to previous option | 'reset' to restart from step 1`n" -ForegroundColor DarkGray
    } else {
        Write-Host ""
    }

    if ($UpToStep -gt 1 -and $namingSummary) {
        Write-Host " [1] Output File Naming : " -NoNewline -ForegroundColor DarkGray
        Write-Host $namingSummary -ForegroundColor White
    }
    if ($UpToStep -gt 2 -and $typeSummary) {
        Write-Host " [2] Command Types      : " -NoNewline -ForegroundColor DarkGray
        Write-Host $typeSummary -ForegroundColor White
    }
    if ($UpToStep -gt 3 -and $sarSummary) {
        Write-Host " [3] Scope / Plugin     : " -NoNewline -ForegroundColor DarkGray
        Write-Host $sarSummary -ForegroundColor White
    }
    if ($UpToStep -gt 4 -and $flagSummary) {
        Write-Host " [4] Flag Handling      : " -NoNewline -ForegroundColor DarkGray
        Write-Host $flagSummary -ForegroundColor White
    }
    if ($UpToStep -gt 5 -and $sectionSummary) {
        Write-Host " [5] Flag Sectioning    : " -NoNewline -ForegroundColor DarkGray
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
            Write-Host "  2) Descriptor      - [DISABLED] Multiple JSON files detected" -ForegroundColor DarkGray
            Write-Host "  3) Custom Name     - Choose a custom base name"
        } else {
            Write-Host "  2) Descriptor      - Uses only category/flag name (e.g., cvars.cfg, cheat.cfg)"
            Write-Host "  3) Custom Name     - Choose a custom base name"
        }

        $rawInput = (Read-Host "`nSelect naming option (Default: 1)").Trim()

        if ($rawInput -in @('back', 'b')) {
            Write-Warning "Already at the first step."
            Start-Sleep -Milliseconds 700
            continue
        }
        if ($rawInput -in @('reset', 'r')) { continue }

        if ([string]::IsNullOrWhiteSpace($rawInput)) { $rawInput = '1' }

        if ($hasMultipleFiles -and $rawInput -eq '2') {
            Write-Warning "Option [2] is disabled when multiple JSON files are present."
            Start-Sleep -Milliseconds 1000
            continue
        }

        if ($rawInput -notin @('1', '2', '3')) { continue }

        $namingChoice = $rawInput
        $customFileNames = @{}
        $namingCancelled = $false

        if ($namingChoice -eq '3') {
            Write-Host "`n Assign Custom Name(s):" -ForegroundColor DarkCyan
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

            if ($namingCancelled) { continue }
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
        Write-Host "  1) Both Combined      - Export variables and commands into one file"
        Write-Host "  2) ConVariables Only  - Export settings and variables only"
        Write-Host "  3) ConCommands Only   - Export commands/actions only"
        Write-Host "  4) Separate Files     - Export into distinct _cvars.cfg and _cmds.cfg"

        $rawInput = (Read-Host "`nSelect type option [1-4] (Default: 1)").Trim()

        if ($rawInput -in @('back', 'b')) { $currentStep = 1; continue }
        if ($rawInput -in @('reset', 'r')) {
            $currentStep = 1; $namingSummary = $null; $typeSummary = $null; continue
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
        # If no SAR commands exist in the dump, auto-set and move on
        if (-not $anySARDetected) {
            $sarChoice = '1'
            $tagSarFlag = $false
            $sarSummary = "Game Only (No SAR Detected)"
            $currentStep = 4
            $step4Sub = 1
            continue
        }

        Show-ConfigurationHeader -UpToStep 3

        if ($step3Sub -eq 1) {
            Write-Host "[3] SAR Plugin Scope" -ForegroundColor Yellow
            Write-Host "  1) Keep All (Default) - Include standard Game and SAR commands"
            Write-Host "  2) Game Only          - Exclude SAR commands"
            Write-Host "  3) SAR Only           - Exclude standard Game commands"
            Write-Host "  4) Separate Files     - Split Game and SAR into separate files"

            $rawInput = (Read-Host "`nSelect scope option [1-4] (Default: 1)").Trim()

            if ($rawInput -in @('back', 'b')) { $currentStep = 2; continue }
            if ($rawInput -in @('reset', 'r')) { $currentStep = 1; continue }

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
        } elseif ($step3Sub -eq 2) {
            Write-Host "[3] SAR Plugin Scope" -ForegroundColor Yellow
            $scopeLabel = if ($sarChoice -eq '1') { "Keep All" } else { "Separate Files" }
            Write-Host ("  Scope Selection : {0}" -f $scopeLabel) -ForegroundColor Gray

            $rawInput = (Read-Host "`nTag SAR commands with 'SAR' flag in comments/sections? (y/n) [Default: y]").Trim()

            if ($rawInput -in @('back', 'b')) { $step3Sub = 1; continue }
            if ($rawInput -in @('reset', 'r')) { $currentStep = 1; continue }

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
            Write-Host "  1) Keep All (Default)"
            Write-Host "  2) Omit Flags       - Omit commands matching chosen flags"
            Write-Host "  3) Separate Flags   - Extract commands matching chosen flags into own files"

            $rawInput = (Read-Host "`nSelect action [1-3] (Default: 1)").Trim()

            if ($rawInput -in @('back', 'b')) {
                $currentStep = if ($anySARDetected) { 3 } else { 2 }
                continue
            }
            if ($rawInput -in @('reset', 'r')) { $currentStep = 1; continue }

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
        } elseif ($step4Sub -eq 2) {
            Write-Host "[4] Flag Handling" -ForegroundColor Yellow
            $actionName = if ($flagAction -eq '2') { "Omit Flags" } else { "Separate Flags" }
            Write-Host ("  Action: {0}" -f $actionName) -ForegroundColor Gray

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
            $rawInput = (Read-Host "`nSelect flag(s) to $actionVerb (comma-separated numbers or names)").Trim()

            if ($rawInput -in @('back', 'b')) { $step4Sub = 1; continue }
            if ($rawInput -in @('reset', 'r')) { $currentStep = 1; continue }

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

        # 5.1 Enable sectioning
        if ($step5Sub -eq 1) {
            Write-Host "[5] Flag Sectioning" -ForegroundColor Yellow
            $promptLabel = if ($separateFlagsList.Count -gt 0) { "Categorize main commands by flag? (y/n) [Default: n]" } else { "Categorize commands by flag? (y/n) [Default: n]" }
            $rawInput = (Read-Host $promptLabel).Trim()

            if ($rawInput -in @('back', 'b')) {
                $currentStep = 4
                $step4Sub = if ($flagAction -in @('2', '3')) { 2 } else { 1 }
                continue
            }
            if ($rawInput -in @('reset', 'r')) { $currentStep = 1; continue }

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

        # 5.2 Section Order
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

            $rawInput = (Read-Host "`nSelect section order (e.g. '1, 3' or 'ARCHIVE, CHEAT')").Trim()

            if ($rawInput -in @('back', 'b')) { $step5Sub = 1; continue }
            if ($rawInput -in @('reset', 'r')) { $currentStep = 1; continue }

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

        # 5.3 Omit Section Flag from Comments
        elseif ($step5Sub -eq 3) {
            Write-Host "[5] Flag Sectioning" -ForegroundColor Yellow
            Write-Host ("  Main Priority Order: {0} -> OTHER" -f ($sectionFlagOrder -join ' -> ')) -ForegroundColor Gray

            $rawInput = (Read-Host "`nOmit section's flag from comments inside that section? (y/n) [Default: y]").Trim()

            if ($rawInput -in @('back', 'b')) { $step5Sub = 2; continue }
            if ($rawInput -in @('reset', 'r')) { $currentStep = 1; continue }

            $omitSectionFlagFromComment = ($rawInput.ToLower() -notin @('n', 'no'))

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

        # 5.4 Separated Files Sectioning
        elseif ($step5Sub -eq 4) {
            Write-Host "[5] Flag Sectioning" -ForegroundColor Yellow
            $mainStatusDesc = if ($enableSectioning) { "$($sectionFlagOrder -join ' -> ') -> OTHER" } else { "Flat List" }
            Write-Host ("  Main Files Sectioning: {0}" -f $mainStatusDesc) -ForegroundColor Gray

            Write-Host "`n [5B] Separated Files Sectioning ($($separateFlagsList -join ', '))" -ForegroundColor Yellow
            $inheritLabel = if ($enableSectioning) { "Same as Main (Inherit section order)" } else { "Same as Main (Flat List)" }
            Write-Host ("  1) {0} [Default]" -f $inheritLabel)
            Write-Host "  2) Flat List (No sectioning in separated files)"

            $rawInput = (Read-Host "`nSelect separated files sectioning option [1-2] (Default: 1)").Trim()

            if ($rawInput -in @('back', 'b')) {
                $step5Sub = if ($enableSectioning) { 3 } else { 1 }
                continue
            }
            if ($rawInput -in @('reset', 'r')) { $currentStep = 1; continue }

            if ([string]::IsNullOrWhiteSpace($rawInput)) { $rawInput = '1' }

            $sepFileSectionConfig = @{}
            if ($rawInput -eq '1') {
                foreach ($sf in $separateFlagsList) {
                    $filtered = [System.Collections.Generic.List[string]]::new()
                    foreach ($f in $sectionFlagOrder) {
                        if ($f -ine $sf) { [void]$filtered.Add($f) }
                    }
                    $sepFileSectionConfig[$sf] = [PSCustomObject]@{
                        SectionFlags    = $filtered
                        OmitSectionFlag = $omitSectionFlagFromComment
                    }
                }
                $mainDesc = if ($enableSectioning) { "Sectioned ($($sectionFlagOrder -join ' -> '))" } else { "Flat" }
                $sectionSummary = "{0} | Separated: Inherited" -f $mainDesc
            } else {
                foreach ($sf in $separateFlagsList) {
                    $sepFileSectionConfig[$sf] = [PSCustomObject]@{
                        SectionFlags    = [System.Collections.Generic.List[string]]::new()
                        OmitSectionFlag = $false
                    }
                }
                $mainDesc = if ($enableSectioning) { "Sectioned ($($sectionFlagOrder -join ' -> '))" } else { "Flat" }
                $sectionSummary = "{0} | Separated: Flat" -f $mainDesc
            }

            $currentStep = 6
            continue
        }
    }
}

Show-ConfigurationHeader -UpToStep 6 -ShowCommandsHint $false

# =============================================================================
# 4. PROCESSING & GENERATION ENGINE
# =============================================================================

Write-Host "Processing files..." -ForegroundColor Cyan

function Format-SectionedCfg {
    param(
        [System.Collections.Generic.List[CvarItem]]$Items,
        [System.Collections.Generic.List[string]]$SectionOrder,
        [bool]$OmitSectionFlag,
        [string]$FileOmittedFlag = $null
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    if ($Items.Count -eq 0) { return $lines }

    # Compute overall padding for clean column alignment
    $maxLen = 0
    foreach ($item in $Items) {
        if ($item.LeftSide.Length -gt $maxLen) {
            $maxLen = $item.LeftSide.Length
        }
    }

    if ($SectionOrder -and $SectionOrder.Count -gt 0) {
        $assigned = [System.Collections.Generic.HashSet[CvarItem]]::new()

        foreach ($secFlag in $SectionOrder) {
            $secItems = [System.Collections.Generic.List[CvarItem]]::new()
            foreach ($item in $Items) {
                if (-not $assigned.Contains($item) -and $item.ActiveFlags.Contains($secFlag)) {
                    $secItems.Add($item)
                    [void]$assigned.Add($item)
                }
            }

            if ($secItems.Count -gt 0) {
                [SourceEngineCvarComparer]::Sort($secItems)
                if ($lines.Count -gt 0) { $lines.Add("") }
                $lines.Add("// =============================================================================")
                $lines.Add("// $secFlag")
                $lines.Add("// =============================================================================")
                $lines.Add("")

                foreach ($it in $secItems) {
                    $comment = $it.GetComment($secFlag, $OmitSectionFlag, $FileOmittedFlag)
                    if ([string]::IsNullOrEmpty($comment)) {
                        $lines.Add($it.LeftSide)
                    } else {
                        $lines.Add(("{0} // {1}" -f $it.LeftSide.PadRight($maxLen), $comment))
                    }
                }
            }
        }

        # OTHER Section
        $otherItems = [System.Collections.Generic.List[CvarItem]]::new()
        foreach ($item in $Items) {
            if (-not $assigned.Contains($item)) {
                $otherItems.Add($item)
            }
        }

        if ($otherItems.Count -gt 0) {
            [SourceEngineCvarComparer]::Sort($otherItems)
            if ($lines.Count -gt 0) { $lines.Add("") }
            $lines.Add("// =============================================================================")
            $lines.Add("// OTHER")
            $lines.Add("// =============================================================================")
            $lines.Add("")

            foreach ($it in $otherItems) {
                $comment = $it.GetComment("OTHER", $false, $FileOmittedFlag)
                if ([string]::IsNullOrEmpty($comment)) {
                    $lines.Add($it.LeftSide)
                } else {
                    $lines.Add(("{0} // {1}" -f $it.LeftSide.PadRight($maxLen), $comment))
                }
            }
        }
    } else {
        # Flat list
        [SourceEngineCvarComparer]::Sort($Items)
        foreach ($it in $Items) {
            $comment = $it.GetComment("", $false, $FileOmittedFlag)
            if ([string]::IsNullOrEmpty($comment)) {
                $lines.Add($it.LeftSide)
            } else {
                $lines.Add(("{0} // {1}" -f $it.LeftSide.PadRight($maxLen), $comment))
            }
        }
    }

    return $lines
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$totalFilesCreated = 0

foreach ($file in $jsonFiles) {
    $rawItems = $jsonCache[$file.FullName]
    if (-not $rawItems) { continue }

    $baseName = switch ($namingChoice) {
        '1' { [System.IO.Path]::GetFileNameWithoutExtension($file.Name) }
        '2' { "" }
        '3' { $customFileNames[$file.FullName] }
    }

    # Convert raw JSON items to typed CvarItem objects
    $allItems = [System.Collections.Generic.List[CvarItem]]::new()
    foreach ($r in $rawItems) {
        $name = [string]$r.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $isCmd = $false
        if ($null -ne $r.isCmd) {
            $isCmd = [bool]$r.isCmd
        } elseif ($r.type -ieq "command" -or $r.type -ieq "cmd") {
            $isCmd = $true
        }

        $isSAR = $false
        if ($null -ne $r.isSAR) {
            $isSAR = [bool]$r.isSAR
        } elseif ($name.StartsWith("sar_", [System.StringComparison]::OrdinalIgnoreCase)) {
            $isSAR = $true
        }

        $activeFlags = Get-ParsedItemFlags $r
        if ($tagSarFlag -and $isSAR -and -not $activeFlags.Contains('SAR')) {
            $activeFlags.Add('SAR')
        }

        # Sanitize multiline help text
        $help = ""
        if ($null -ne $r.help) {
            $help = ($r.help -replace '[\r\n]+', ' ' -replace '\s+', ' ').Trim()
        }

        $leftSide = $name
        if ($null -ne $r.default -and -not [string]::IsNullOrWhiteSpace([string]$r.default)) {
            $leftSide = "$name `"$($r.default)`""
        }

        $itemObj = [CvarItem]::new($name, $leftSide, $isCmd, $isSAR, $activeFlags, $help)
        $allItems.Add($itemObj)
    }

    # SAR Scope partitions
    $sarBatches = @{}
    switch ($sarChoice) {
        '1' { $sarBatches[""] = $allItems }
        '2' { $sarBatches[""] = $allItems | Where-Object { -not $_.IsSAR } }
        '3' { $sarBatches["sar"] = $allItems | Where-Object { $_.IsSAR } }
        '4' {
            $sarBatches["game"] = $allItems | Where-Object { -not $_.IsSAR }
            $sarBatches["sar"]  = $allItems | Where-Object { $_.IsSAR }
        }
    }

    foreach ($sarKey in $sarBatches.Keys) {
        $scopeItems = [System.Collections.Generic.List[CvarItem]]::new([CvarItem[]]$sarBatches[$sarKey])
        if ($scopeItems.Count -eq 0) { continue }

        # Command Type partitions
        $typeBatches = @{}
        switch ($typeChoice) {
            '1' { $typeBatches[""] = $scopeItems }
            '2' { $typeBatches["cvars"] = $scopeItems | Where-Object { -not $_.IsCmd } }
            '3' { $typeBatches["cmds"]  = $scopeItems | Where-Object { $_.IsCmd } }
            '4' {
                $typeBatches["cvars"] = $scopeItems | Where-Object { -not $_.IsCmd }
                $typeBatches["cmds"]  = $scopeItems | Where-Object { $_.IsCmd }
            }
        }

        foreach ($typeKey in $typeBatches.Keys) {
            $currItems = [System.Collections.Generic.List[CvarItem]]::new([CvarItem[]]$typeBatches[$typeKey])
            if ($currItems.Count -eq 0) { continue }

            # Flag Handling: Omit Flags
            if ($flagAction -eq '2' -and $omitFlags.Count -gt 0) {
                $filtered = [System.Collections.Generic.List[CvarItem]]::new()
                foreach ($it in $currItems) {
                    $hasOmit = $false
                    foreach ($f in $it.ActiveFlags) {
                        if ($omitFlags.Contains($f)) { $hasOmit = $true; break }
                    }
                    if (-not $hasOmit) { $filtered.Add($it) }
                }
                $currItems = $filtered
            }

            # Flag Handling: Separate Flags
            if ($flagAction -eq '3' -and $separateFlags.Count -gt 0) {
                foreach ($sepFlag in $separateFlags) {
                    $sepItems = [System.Collections.Generic.List[CvarItem]]::new()
                    foreach ($it in $currItems) {
                        if ($it.ActiveFlags.Contains($sepFlag)) {
                            $sepItems.Add($it)
                        }
                    }

                    if ($sepItems.Count -gt 0) {
                        $sepCfg = $sepFileSectionConfig[$sepFlag]
                        $secFlags = if ($sepCfg) { $sepCfg.SectionFlags } else { [System.Collections.Generic.List[string]]::new() }
                        $omitFlag = if ($sepCfg) { $sepCfg.OmitSectionFlag } else { $false }

                        $fileParts = @()
                        if ($baseName) { $fileParts += $baseName }
                        if ($sarKey)   { $fileParts += $sarKey }
                        if ($typeKey)  { $fileParts += $typeKey }
                        $fileParts += $sepFlag.ToLowerInvariant()
                        $outFileName = ($fileParts -join "_") + ".cfg"
                        $outPath = [System.IO.Path]::Combine($Directory, $outFileName)

                        $cfgLines = Format-SectionedCfg -Items $sepItems -SectionOrder $secFlags -OmitSectionFlag $omitFlag -FileOmittedFlag $sepFlag
                        [System.IO.File]::WriteAllLines($outPath, $cfgLines, $utf8NoBom)
                        Write-Host "  -> Created: $outFileName ($($sepItems.Count) items)" -ForegroundColor Green
                        $totalFilesCreated++
                    }
                }

                # Filter separated flags out of main file
                $remainingItems = [System.Collections.Generic.List[CvarItem]]::new()
                foreach ($it in $currItems) {
                    $hasSep = $false
                    foreach ($f in $it.ActiveFlags) {
                        if ($separateFlags.Contains($f)) { $hasSep = $true; break }
                    }
                    if (-not $hasSep) { $remainingItems.Add($it) }
                }
                $currItems = $remainingItems
            }

            # Main File Export
            if ($currItems.Count -gt 0) {
                $fileParts = @()
                if ($baseName) { $fileParts += $baseName }
                if ($sarKey)   { $fileParts += $sarKey }
                if ($typeKey)  { $fileParts += $typeKey }
                if ($fileParts.Count -eq 0) { $fileParts += "cvars" }

                $outFileName = ($fileParts -join "_") + ".cfg"
                $outPath = [System.IO.Path]::Combine($Directory, $outFileName)

                $cfgLines = Format-SectionedCfg -Items $currItems -SectionOrder $sectionFlagOrder -OmitSectionFlag $omitSectionFlagFromComment
                [System.IO.File]::WriteAllLines($outPath, $cfgLines, $utf8NoBom)
                Write-Host "  -> Created: $outFileName ($($currItems.Count) items)" -ForegroundColor Green
                $totalFilesCreated++
            }
        }
    }
}

Write-Host "`nSuccessfully finished! Generated $totalFilesCreated file(s)." -ForegroundColor Cyan
Read-Host "Press Enter to exit"