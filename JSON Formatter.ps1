# =========================================================================
# CONFIGURATION SETTINGS
# =========================================================================

# 1. Main Output File Names
$outputMainConvars  = "convars.cfg"
$outputMainCommands = "concommands.cfg"

# 2. Flag Exclusions & File Separations
# - $false -> Completely drops/ignores items with this flag.
# - $true  -> Extracts matching items into convars_<flag>.cfg & concommands_<flag>.cfg.
$flagsToIgnoreCompletely = [ordered]@{
    "developmentonly" = $false
    "hidden"          = $false
    "cheat"           = $true
}

# 3. Section Priority & Order (Top to Bottom)
# Unmatched items automatically fall into an internal GENERAL section.
$sectionConfig = [ordered]@{
    "notify"     = @{ Title = "NOTIFY";                    Aliases = @("notify", "nf") }
    "replicated" = @{ Title = "REPLICATED";                Aliases = @("replicated", "rep") }
    "archive"    = @{ Title = "ARCHIVE (Saved to config)"; Aliases = @("archive", "a") }
    "userinfo"   = @{ Title = "USER INFO";                 Aliases = @("userinfo", "user") }
}

# 4. Comment Options
$omitSectionFlagFromComments = $false

# =========================================================================
# SCRIPT EXECUTION ENGINE
# =========================================================================

$internalCommonFlagsToOmit = @(
    "client", "clientdll", "cl",
    "server", "serverdll", "sv",
    "game", "gamedll"
)

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$workingDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Write-Host "========================================================" -ForegroundColor DarkCyan
Write-Host " Source Engine Formatter (JSON)" -ForegroundColor Cyan
Write-Host " Directory: $workingDir" -ForegroundColor Gray
Write-Host "========================================================" -ForegroundColor DarkCyan

$targetFile = Get-ChildItem -Path $workingDir -File -Filter "*.json" | Select-Object -First 1

if (-not $targetFile) {
    Write-Host "[-] Error: No .json file found in $workingDir" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit..."
    return
}

$fileSizeKB = [math]::Round($targetFile.Length / 1KB, 2)
Write-Host "[+] Found: $($targetFile.Name) ($fileSizeKB KB)" -ForegroundColor Green

$data = Get-Content -Raw -Encoding UTF8 $targetFile.FullName | ConvertFrom-Json

$dropFlags      = [System.Collections.Generic.List[string]]::new()
$extractedFiles = [ordered]@{}

foreach ($key in $flagsToIgnoreCompletely.Keys) {
    $flagName       = $key.ToLower().Trim()
    $separateToFile = [bool]$flagsToIgnoreCompletely[$key]

    if ($separateToFile) {
        $extractedFiles[$flagName] = @{
            ConvarPath  = "convars_$flagName.cfg"
            CommandPath = "concommands_$flagName.cfg"
            Convars     = [System.Collections.Generic.List[object]]::new()
            Commands    = [System.Collections.Generic.List[object]]::new()
        }
    } else {
        $dropFlags.Add($flagName)
    }
}

$mainConvars   = [System.Collections.Generic.List[object]]::new()
$mainCommands  = [System.Collections.Generic.List[object]]::new()
$ignoredCount  = 0

foreach ($item in $data) {
    $flagTokens = if ($item.flagsStr -and $item.flagsStr.Trim().ToLower() -ne "none") {
        $item.flagsStr.ToLower() -split '\s+'
    } else { 
        @() 
    }

    $shouldDrop = $false
    foreach ($dropFlag in $dropFlags) {
        if ($flagTokens -contains $dropFlag) {
            $shouldDrop = $true
            break
        }
    }

    if ($shouldDrop) {
        $ignoredCount++
        continue
    }

    $obj = [PSCustomObject]@{
        name      = $item.name
        default   = $item.default
        flags     = $flagTokens
        helpStr   = $item.helpStr
    }

    $matchedExtractKey = $null
    foreach ($extKey in $extractedFiles.Keys) {
        if ($flagTokens -contains $extKey -or $flagTokens -contains ($extKey + "s")) {
            $matchedExtractKey = $extKey
            break
        }
    }

    if ($matchedExtractKey) {
        $target = $extractedFiles[$matchedExtractKey]
        if ($item.isCommand) {
            $target.Commands.Add($obj)
        } else {
            $target.Convars.Add($obj)
        }
        continue
    }

    if ($item.isCommand) {
        $mainCommands.Add($obj)
    } else {
        $mainConvars.Add($obj)
    }
}

Write-Host "[+] Loaded $($data.Count) definitions:" -ForegroundColor Green
Write-Host "    - Main:      $($mainConvars.Count) convars, $($mainCommands.Count) commands" -ForegroundColor Gray
foreach ($extKey in $extractedFiles.Keys) {
    $t = $extractedFiles[$extKey]
    Write-Host "    - Extracted: $($t.Convars.Count) convars, $($t.Commands.Count) commands -> '$extKey'" -ForegroundColor Cyan
}
if ($ignoredCount -gt 0) {
    Write-Host "    - Dropped:   $ignoredCount items ($($dropFlags -join ', '))" -ForegroundColor Yellow
}

function Export-AlignedSectionedCfg {
    param(
        [System.Collections.Generic.List[object]]$items,
        [string]$outputPath,
        [bool]$isCommand,
        [string]$label,
        [hashtable]$customSectionMap = $null,
        [array]$extraOmitFlags = @()
    )

    Write-Host "`n[*] Writing $outputPath ($label)..." -ForegroundColor Cyan

    $activeSections = [ordered]@{}
    if ($customSectionMap) {
        foreach ($k in $customSectionMap.Keys) { $activeSections[$k] = $customSectionMap[$k] }
    } else {
        foreach ($k in $sectionConfig.Keys) { $activeSections[$k] = $sectionConfig[$k] }
        $activeSections["general"] = @{ Title = "GENERAL"; Aliases = @() }
    }

    $buckets = [ordered]@{}
    foreach ($secKey in $activeSections.Keys) {
        $buckets[$secKey] = [System.Collections.Generic.List[object]]::new()
    }

    foreach ($item in $items) {
        $assigned = $false
        foreach ($secKey in $activeSections.Keys) {
            if ($secKey -eq "general") { continue }
            $aliases = $activeSections[$secKey].Aliases
            foreach ($alias in $aliases) {
                if ($item.flags -contains $alias) {
                    $buckets[$secKey].Add($item)
                    $assigned = $true
                    break
                }
            }
            if ($assigned) { break }
        }
        if (-not $assigned) {
            $buckets["general"].Add($item)
        }
    }

    if (-not $customSectionMap) {
        foreach ($secKey in $activeSections.Keys) {
            $count = $buckets[$secKey].Count
            if ($count -gt 0) {
                $tag = $activeSections[$secKey].Title.Split(' ')[0]
                Write-Host ("    [{0,-10}] {1,4} items" -f $tag, $count) -ForegroundColor DarkGray
            }
        }
    }

    $formattedBuckets = [ordered]@{}
    $maxBaseLen = 0

    foreach ($secKey in $activeSections.Keys) {
        $secItems = $buckets[$secKey] | Sort-Object { $_.name.ToLower() }
        $formattedList = [System.Collections.Generic.List[object]]::new()

        $omitList = @($internalCommonFlagsToOmit)
        if ($extraOmitFlags) { $omitList += $extraOmitFlags }
        if ($omitSectionFlagFromComments -and $secKey -ne "general" -and $activeSections[$secKey].Aliases) {
            $omitList += $activeSections[$secKey].Aliases
        }

        foreach ($item in $secItems) {
            $filteredFlags = foreach ($f in $item.flags) {
                if ($omitList -notcontains $f) { $f }
            }

            $flagsPart = if ($filteredFlags) {
                "({0})" -f ($filteredFlags -join ', ')
            } else {
                $null
            }

            $helpPart = if (-not [string]::IsNullOrWhiteSpace($item.helpStr)) {
                ($item.helpStr -replace "`r", "" -replace "`n", "\n" -replace "`t", "\t").Trim()
            } else {
                $null
            }

            $comment = if ($flagsPart -and $helpPart) {
                "// $flagsPart $helpPart"
            } elseif ($flagsPart) {
                "// $flagsPart"
            } elseif ($helpPart) {
                "// $helpPart"
            } else {
                $null
            }

            $base = if ($isCommand) { 
                $item.name 
            } else { 
                '{0} "{1}"' -f $item.name, $item.default 
            }

            if ($comment -and $base.Length -gt $maxBaseLen) {
                $maxBaseLen = $base.Length
            }

            $formattedList.Add([PSCustomObject]@{
                Base    = $base
                Comment = $comment
            })
        }
        $formattedBuckets[$secKey] = $formattedList
    }

    $outputLines = [System.Collections.Generic.List[string]]::new()

    foreach ($secKey in $activeSections.Keys) {
        $secList = $formattedBuckets[$secKey]

        if ($secList.Count -gt 0) {
            if ($outputLines.Count -gt 0) {
                $outputLines.Add("") 
            }
            $outputLines.Add("// ========================================================")
            $outputLines.Add("// " + $activeSections[$secKey].Title)
            $outputLines.Add("// ========================================================")

            foreach ($entry in $secList) {
                if ($entry.Comment) {
                    $outputLines.Add($entry.Base.PadRight($maxBaseLen + 2) + $entry.Comment)
                } else {
                    $outputLines.Add($entry.Base)
                }
            }
        }
    }

    $outputLines | Set-Content -Encoding UTF8 $outputPath
    Write-Host "[+] Saved $outputPath ($($outputLines.Count) lines)" -ForegroundColor Green
}

Export-AlignedSectionedCfg -items $mainConvars  -outputPath $outputMainConvars  -isCommand $false -label "Main ConVars"
Export-AlignedSectionedCfg -items $mainCommands -outputPath $outputMainCommands -isCommand $true  -label "Main ConCommands"

foreach ($extKey in $extractedFiles.Keys) {
    $t = $extractedFiles[$extKey]
    $singleSectionMap = [ordered]@{ "general" = @{ Title = $extKey.ToUpper(); Aliases = @() } }
    $extraOmits = @($extKey, ($extKey + "s"))

    Export-AlignedSectionedCfg -items $t.Convars  -outputPath $t.ConvarPath  -isCommand $false -label "$($extKey.ToUpper()) ConVars"     -customSectionMap $singleSectionMap -extraOmitFlags $extraOmits
    Export-AlignedSectionedCfg -items $t.Commands -outputPath $t.CommandPath -isCommand $true  -label "$($extKey.ToUpper()) ConCommands" -customSectionMap $singleSectionMap -extraOmitFlags $extraOmits
}

$stopwatch.Stop()
$elapsedSec = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
Write-Host "`n========================================================" -ForegroundColor DarkCyan
Write-Host " Completed in $elapsedSec seconds!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor DarkCyan
Write-Host ""
Read-Host "Press Enter to exit..."
