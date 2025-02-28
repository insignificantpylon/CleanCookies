# Unattended version
$userProfile = $env:USERPROFILE
$searchDirs = @("$env:LOCALAPPDATA", "$env:APPDATA", "$env:PROGRAMFILES", "$env:PROGRAMFILES(x86)")
$browserPatterns = @{
    "Chrome"       = @("$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Network\Cookies")
    "Edge"         = @("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies")
    "Firefox"      = @("$env:APPDATA\Mozilla\Firefox\Profiles\*.default-release\cookies.sqlite")
    "Opera"        = @("$env:APPDATA\Opera Software\Opera Stable\Network\Cookies")
    "Brave"        = @("$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Network\Cookies")
    "Vivaldi"      = @("$env:LOCALAPPDATA\Vivaldi\User Data\Default\Network\Cookies")
    "UCBrowser"    = @("$env:LOCALAPPDATA\UCBrowser\User Data\Default\Network\Cookies")
    "Tor"          = @("$env:APPDATA\Tor Browser\Browser\TorBrowser\Data\Browser\profile.default\cookies.sqlite")
}
$trackingKeywords = @("track", "ads", "analytics", "doubleclick", "pixel", "marketing", "google-analytics", "facebook")

function Check-BrowserStatus {
    $browsers = @("chrome", "msedge", "firefox", "opera", "brave", "vivaldi", "ucbrowser", "tor")
    foreach ($browser in $browsers) {
        if (Get-Process -Name $browser -ErrorAction SilentlyContinue) {
            Write-Host "Warning: $browser is running. Deletion may fail."
        }
    }
}

function Find-BrowserCookieFiles {
    $detectedPaths = @()
    foreach ($browser in $browserPatterns.Keys) {
        foreach ($pathPattern in $browserPatterns[$browser]) {
            $resolvedPaths = Get-ChildItem -Path $pathPattern -ErrorAction SilentlyContinue
            foreach ($path in $resolvedPaths) {
                if (Test-Path $path.FullName) {
                    $detectedPaths += [PSCustomObject]@{ Browser = $browser; Path = $path.FullName }
                }
            }
        }
    }
    foreach ($dir in $searchDirs) {
        $potentialCookies = Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -match "Cookies|cookies\.sqlite" -and $_.Length -gt 0 }
        foreach ($file in $potentialCookies) {
            if (-not ($detectedPaths.Path -contains $file.FullName)) {
                $detectedPaths += [PSCustomObject]@{ Browser = "Unknown ($($file.Directory.Name))"; Path = $file.FullName }
            }
        }
    }
    return $detectedPaths
}

function Detect-TrackingCookies {
    param ($cookieFile)
    if (Test-Path $cookieFile) {
        Write-Host "Scanning: $cookieFile"
        if ($cookieFile -match "sqlite") {
            $cookieData = Get-Content -Path $cookieFile -ErrorAction SilentlyContinue
            $trackingCookies = @()
            foreach ($keyword in $trackingKeywords) {
                $matches = $cookieData | Select-String -Pattern $keyword -CaseSensitive
                if ($matches) { $trackingCookies += "Tracking cookie found: $matches" }
            }
            return $trackingCookies
        } else {
            $fileInfo = Get-Item $cookieFile
            if ($fileInfo.LastWriteTime -gt (Get-Date).AddDays(-7)) {
                return @("Potential tracking cookies detected (recent activity)")
            }
            return @()
        }
    }
    return @()
}

function Remove-TrackingCookies {
    param ($path)
    if (Test-Path $path) {
        Write-Host "Cleaning: $path"
        $backupPath = "$path.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $path -Destination $backupPath -Force -ErrorAction SilentlyContinue
        Write-Host "Backed up to: $backupPath"
        Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $path)) { Write-Host "Deleted: $path" } else { Write-Host "Failed: $path" }
    }
}

Check-BrowserStatus
$cookieFiles = Find-BrowserCookieFiles
foreach ($file in $cookieFiles) {
    $detectedCookies = Detect-TrackingCookies -cookieFile $file.Path
    if ($detectedCookies.Count -gt 0) {
        Write-Host "Detected in $($file.Browser): $detectedCookies"
        Remove-TrackingCookies -path $file.Path
    } else {
        Write-Host "No tracking cookies in $($file.Path)"
    }
}

Write-Host "Cleanup completed!"
