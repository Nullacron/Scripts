$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# 1. Locate folder and file
$workingDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Write-Host "========================================================" -ForegroundColor DarkCyan
Write-Host " Source Engine ConVar/ConCommand Formatter (JSON)" -ForegroundColor Cyan
Write-Host " Working Directory: $workingDir" -ForegroundColor Gray
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
Write-Host "[*] Reading and parsing JSON data..." -ForegroundColor Gray

$data = Get-Content -Raw -Encoding UTF8 $targetFile.FullName | ConvertFrom-Json

# Section definitions and aliases
$sections = [ordered]@{
    "notify"     = "NOTIFY"
    "cheat"      = "CHEATS"
    "replicated" = "REPLICATED"
    "archive"    = "ARCHIVE (Saved to config)"
    "general"    = "GENERAL"
}

$sectionFlagAliases = @{
    "notify"     = @("notify", "nf")
    "cheat"      = @("cheat", "cheats")
    "replicated" = @("replicated", "rep")
    "archive"    = @("archive", "a")
}

$commonFlagsToOmit = @(
    "client", "clientdll", "cl",
    "server", "serverdll", "sv",
    "game", "gamedll"
)

# 2. Pre-process items
$parsedConvars  = [System.Collections.Generic.List[object]]::new()
$parsedCommands = [System.Collections.Generic.List[object]]::new()

foreach ($item in $data) {
    $flagTokens = if ($item.flagsStr -and $item.flagsStr.Trim().ToLower() -ne "none") {
        $item.flagsStr.ToLower() -split '\s+'
    } else { 
        @() 
    }

    $obj = [PSCustomObject]@{
        name      = $item.name
        default   = $item.default
        flags     = $flagTokens
        helpStr   = $item.helpStr
    }

    if ($item.isCommand) {
        $parsedCommands.Add($obj)
    } else {
        $parsedConvars.Add($obj)
    }
}

Write-Host "[+] Loaded $($data.Count) total definitions:" -ForegroundColor Green
Write-Host "    - ConVars:     $($parsedConvars.Count)" -ForegroundColor Gray
Write-Host "    - ConCommands: $($parsedCommands.Count)" -ForegroundColor Gray

function Export-AlignedSectionedCfg {
    param(
        [System.Collections.Generic.List[object]]$items,
        [string]$outputPath,
        [bool]$isCommand,
        [string]$label
    )

    Write-Host "`n[*] Processing $label..." -ForegroundColor Cyan

    $buckets = [ordered]@{}
    foreach ($secKey in $sections.Keys) {
        $buckets[$secKey] = [System.Collections.Generic.List[object]]::new()
    }

    # Assign priority: Notify -> Cheats -> Replicated -> Archive -> General
    foreach ($item in $items) {
        $assigned = $false
        foreach ($secKey in @("notify", "cheat", "replicated", "archive")) {
            $aliases = $sectionFlagAliases[$secKey]
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

    # Log section breakdown
    Write-Host "    Categorization summary:" -ForegroundColor Gray
    foreach ($secKey in $sections.Keys) {
        $count = $buckets[$secKey].Count
        if ($count -gt 0) {
            Write-Host ("      [{0,-10}] {1,4} items" -f $sections[$secKey].Split(' ')[0], $count) -ForegroundColor DarkGray
        }
    }

    # Step 1: Pre-format items and determine maximum width
    $formattedBuckets = [ordered]@{}
    $maxBaseLen = 0

    foreach ($secKey in $sections.Keys) {
        $secItems = $buckets[$secKey] | Sort-Object { $_.name.ToLower() }
        $formattedList = [System.Collections.Generic.List[object]]::new()

        $omitList = @($commonFlagsToOmit)
        if ($secKey -ne "general") {
            $omitList += $sectionFlagAliases[$secKey]
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

    Write-Host "    Longest command string: $maxBaseLen chars (aligning '//' at column $($maxBaseLen + 3))" -ForegroundColor Gray

    # Step 2: Build output lines
    $outputLines = [System.Collections.Generic.List[string]]::new()

    foreach ($secKey in $sections.Keys) {
        $secList = $formattedBuckets[$secKey]

        if ($secList.Count -gt 0) {
            if ($outputLines.Count -gt 0) {
                $outputLines.Add("") 
            }
            $outputLines.Add("// ========================================================")
            $outputLines.Add("// " + $sections[$secKey])
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
    Write-Host "[+] Saved: $outputPath ($($outputLines.Count) lines)" -ForegroundColor Green
}

# Export both files
Export-AlignedSectionedCfg -items $parsedConvars  -outputPath "convars.cfg"     -isCommand $false -label "ConVars"
Export-AlignedSectionedCfg -items $parsedCommands -outputPath "concommands.cfg" -isCommand $true  -label "ConCommands"

$stopwatch.Stop()
$elapsedSec = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
Write-Host "`n========================================================" -ForegroundColor DarkCyan
Write-Host " All done in $elapsedSec seconds!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor DarkCyan
Write-Host ""
Read-Host "Press Enter to exit..."