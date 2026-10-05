# Input JSON file path and output text file path
$inputPath  = ".\Apple Music Library Tracks.json"
$outputPath = ".\Formatted_Library_Tracks.txt"

if (-not (Test-Path $inputPath)) {
    Write-Error "Could not find file at '$inputPath'. Please check the path and try again."
    exit
}

# Read and parse the JSON file
$tracks = Get-Content -Path $inputPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Step 1: Discover the "Anchor Date" (the latest time any song was ever played)
$playedDates = foreach ($t in $tracks) {
    if ($t.PSObject.Properties['Last Played Date'] -and $t.'Last Played Date') {
        [DateTime]$t.'Last Played Date'
    }
}

if ($playedDates.Count -eq 0) {
    Write-Warning "No 'Last Played Date' found across any tracks. Using current time."
    $anchorDate = [DateTime]::UtcNow
} else {
    $anchorDate = ($playedDates | Measure-Object -Maximum).Maximum
}

Write-Host "Detected account loss anchor date: $($anchorDate.ToString('yyyy-MM-dd HH:mm:ss')) UTC" -ForegroundColor Yellow

$evaluatedTracks = [System.Collections.Generic.List[PSCustomObject]]::new()
$excludedCount = 0

foreach ($track in $tracks) {
    $score = 0
    $hasLastPlayed = ($track.PSObject.Properties['Last Played Date'] -and $track.'Last Played Date')
    $yearMonth = "Never Played"

    # --- FACTOR 1: Proximity to the Account Loss Anchor Date (Primary Factor: up to 55%) ---
    if ($hasLastPlayed) {
        $lastPlayedDt = [DateTime]$track.'Last Played Date'
        $yearMonth = $lastPlayedDt.ToString("yyyy-MM")
        $daysBeforeLoss = ($anchorDate - $lastPlayedDt).TotalDays

        if ($daysBeforeLoss -le 7) {
            $score += 55   # Played in the final week before access was lost
        } elseif ($daysBeforeLoss -le 30) {
            $score += 40   # Played in the final month
        } elseif ($daysBeforeLoss -le 90) {
            $score += 25   # Played within the last 3 months
        } elseif ($daysBeforeLoss -le 180) {
            $score += 15   # Played within 6 months
        } else {
            $score += 5    # Played long ago
        }
    } else {
        $score += 0        # Never played adds 0 timeline weight
    }

    # --- FACTOR 2: Main Library vs. Playlist-Only (Secondary: up to 25%) ---
    $isPlaylistOnly = $true
    if ($track.PSObject.Properties['Playlist Only Track']) {
        $isPlaylistOnly = [bool]$track.'Playlist Only Track'
    } else {
        $isPlaylistOnly = $false
    }

    if (-not $isPlaylistOnly) {
        $score += 25       # Explicitly saved to library
    } else {
        $score += 5        # Only existed inside a playlist
    }

    # --- FACTOR 3: Favorited / Liked vs. Banned (Secondary: +20% / -75%) ---
    $isFavorited = ($track.PSObject.Properties['Favorite Status - Track'] -and $track.'Favorite Status - Track' -eq $true) -or
                   ($track.PSObject.Properties['Track Like Rating'] -and $track.'Track Like Rating' -eq 'liked')
    $isBanned    = ($track.PSObject.Properties['Track Like Rating'] -and $track.'Track Like Rating' -eq 'banned')

    if ($isFavorited) {
        $score += 20
    }
    if ($isBanned) {
        $score -= 75       # Disliked/banned tracks get filtered out
    }

    # --- FACTOR 4: Play Volume & Skip Ratio (Secondary: up to +15% / -25%) ---
    $playCount = if ($track.PSObject.Properties['Track Play Count']) { [int]$track.'Track Play Count' } else { 0 }
    $skipCount = if ($track.PSObject.Properties['Skip Count']) { [int]$track.'Skip Count' } else { 0 }

    if ($playCount -gt 0) {
        if ($playCount -ge 20) {
            $score += 15   # Heavily rotated staple track
        } elseif ($playCount -ge 5) {
            $score += 10
        } else {
            $score += 5
        }
    } else {
        if ($skipCount -gt 0) {
            $score -= 25   # Skipped past without ever playing
        } else {
            $score -= 10   # Stale track with 0 plays
        }
    }

    # Clamp between 0% and 100%
    $score = [Math]::Max(0, [Math]::Min(100, $score))

    # --- Filter out tracks under 25% ---
    if ($score -lt 25) {
        $excludedCount++
        continue
    }

    $title  = $track.Title
    $artist = $track.Artist

    $evaluatedTracks.Add([PSCustomObject]@{
        Score     = $score
        Title     = $title
        Artist    = $artist
        YearMonth = $yearMonth
        Line      = "($score%) $title - $artist : $yearMonth"
    })
}

# Sort descending by Possibility %, then alphabetically by Title
$sortedLines = $evaluatedTracks | 
    Sort-Object -Property @{ Expression = "Score"; Descending = $true }, @{ Expression = "Title"; Descending = $false } | 
    Select-Object -ExpandProperty Line

# Write directly to the output file
$sortedLines | Set-Content -Path $outputPath -Encoding UTF8

Write-Host "Done!" -ForegroundColor Green
Write-Host "Tracks included (>= 25%): $($sortedLines.Count)" -ForegroundColor Cyan
Write-Host "Tracks excluded (< 25%):  $excludedCount" -ForegroundColor Yellow
Write-Host "Output written to: $outputPath"