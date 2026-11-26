<#
  Updates the local ConvrgeForever addon folder from the "latest" GitHub
  release, which .github/workflows/release.yml rebuilds on every push to main.

  Does nothing when the installed copy is already current, so it is cheap to
  run on a schedule (Install-AutoUpdate.ps1 sets that up). Saved variables live
  in WTF\, not in the addon folder, so replacing the folder loses no settings.

  Log and state: %LOCALAPPDATA%\ConvrgeForever-Sync\
#>
param(
    [string]$AddonDir = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\ConvrgeForever',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Repo      = 'stephenszpak/ConvrgeForever'
$StateDir  = Join-Path $env:LOCALAPPDATA 'ConvrgeForever-Sync'
$StateFile = Join-Path $StateDir 'installed.txt'
$LogFile   = Join-Path $StateDir 'sync.log'
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Write-Log([string]$Message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message" | Add-Content -Path $LogFile
    Write-Host $Message
}

$work = $null
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'ConvrgeForever-Sync'; 'Accept' = 'application/vnd.github+json' }

    # The workflow deletes and recreates the release, so it can be missing for
    # a few seconds; the next scheduled run picks it up.
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/latest" -Headers $headers
    $asset = $release.assets | Where-Object { $_.name -eq 'ConvrgeForever.zip' } | Select-Object -First 1
    if (-not $asset) { throw 'The latest release has no ConvrgeForever.zip yet.' }

    $version   = [string]$asset.id
    $commit    = if ($release.body -match 'Built from (\w+)') { $Matches[1] } else { '?' }
    $installed = if (Test-Path $StateFile) { (Get-Content $StateFile -Raw).Trim() } else { '' }
    $tocExists = Test-Path (Join-Path $AddonDir 'ConvrgeForever.toc')

    if (-not $Force -and $version -eq $installed -and $tocExists) { return }

    if (Test-Path (Join-Path $AddonDir '.git')) {
        throw "$AddonDir is a git clone; not overwriting it. Use 'git pull' there instead."
    }

    $work = Join-Path ([IO.Path]::GetTempPath()) ("cf-sync-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $work | Out-Null
    $zip = Join-Path $work 'ConvrgeForever.zip'
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -Headers @{ 'User-Agent' = 'ConvrgeForever-Sync' } -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath (Join-Path $work 'x')

    $src = Join-Path $work 'x\ConvrgeForever'
    if (-not (Test-Path (Join-Path $src 'ConvrgeForever.toc'))) { throw 'Downloaded zip has no ConvrgeForever\ConvrgeForever.toc.' }

    # Swap the folder contents. WoW only reads addon files at login or /reload,
    # so this is safe with the game open; /reload afterwards to load them.
    if (Test-Path $AddonDir) { Remove-Item -Path $AddonDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Split-Path $AddonDir -Parent) | Out-Null
    Copy-Item -Path $src -Destination $AddonDir -Recurse -Force

    Set-Content -Path $StateFile -Value $version
    Write-Log "Updated ConvrgeForever to $commit."
}
catch {
    Write-Log "Update failed: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($work -and (Test-Path $work)) { Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue }
}
