param(
  [Parameter(Mandatory=$true)][string]$CurrentVersion,
  [Parameter(Mandatory=$true)][int]$ProcessId,
  [Parameter(Mandatory=$true)][string]$AppPath
)

$ErrorActionPreference = "Stop"
$repo = "salehkhalaf213-stack/wasla-studio-windows-app"
$manifestUrl = "https://github.com/$repo/releases/download/preview-latest/portable-latest.json"
$workRoot = Join-Path $env:TEMP "QENTRIVO-PortableUpdate"
$logRoot = Join-Path $env:LOCALAPPDATA "QENTRIVO"
$logPath = Join-Path $logRoot "portable-updater.log"
$lockPath = Join-Path $workRoot "update.lock"

function Write-UpdateLog([string]$Message) {
  try {
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
    Add-Content -Path $logPath -Value "$(Get-Date -Format o) $Message" -Encoding UTF8
  } catch {}
}

try {
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
  $lock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
} catch {
  exit 0
}

try {
  $manifest = Invoke-RestMethod -Uri $manifestUrl -Headers @{ "User-Agent" = "QENTRIVO-Portable-Updater" } -TimeoutSec 20
  if (-not $manifest.version -or -not $manifest.url -or -not $manifest.sha256) {
    throw "Portable update manifest is incomplete."
  }

  if ([version]$manifest.version -le [version]$CurrentVersion) {
    exit 0
  }

  Write-UpdateLog "Update $($manifest.version) is available."
  $downloadZip = Join-Path $workRoot "QENTRIVO-Portable-update.zip"
  $extractDir = Join-Path $workRoot "extracted"

  if (Test-Path $downloadZip) { Remove-Item $downloadZip -Force }
  if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
  Invoke-WebRequest -Uri $manifest.url -OutFile $downloadZip -Headers @{ "User-Agent" = "QENTRIVO-Portable-Updater" } -TimeoutSec 180

  $actualHash = (Get-FileHash -Path $downloadZip -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualHash -ne ([string]$manifest.sha256).ToLowerInvariant()) {
    throw "Downloaded ZIP failed SHA-256 verification."
  }

  Expand-Archive -Path $downloadZip -DestinationPath $extractDir -Force
  $newExe = Join-Path $extractDir "QENTRIVO.exe"
  if (-not (Test-Path $newExe)) { throw "The downloaded package does not contain QENTRIVO.exe." }

  $resolvedApp = (Resolve-Path -LiteralPath $AppPath).Path
  $appDirectory = Split-Path -Parent $resolvedApp
  $backupPath = Join-Path $appDirectory ("QENTRIVO.exe.backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
  $stagedExe = Join-Path $appDirectory "QENTRIVO.exe.update"

  $deadline = (Get-Date).AddMinutes(3)
  while (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
    if ((Get-Date) -gt $deadline) { throw "QENTRIVO did not close in time; update was cancelled." }
    Start-Sleep -Seconds 2
  }

  Copy-Item -LiteralPath $newExe -Destination $stagedExe -Force
  Move-Item -LiteralPath $resolvedApp -Destination $backupPath
  try {
    Move-Item -LiteralPath $stagedExe -Destination $resolvedApp
    Write-UpdateLog "Installed portable version $($manifest.version). Backup: $backupPath"
    Start-Process -FilePath $resolvedApp -WorkingDirectory $appDirectory
  } catch {
    if (Test-Path $resolvedApp) { Remove-Item -LiteralPath $resolvedApp -Force }
    if (Test-Path $backupPath) { Move-Item -LiteralPath $backupPath -Destination $resolvedApp }
    throw
  }
} catch {
  Write-UpdateLog "Update not applied: $($_.Exception.Message)"
} finally {
  if ($lock) { $lock.Dispose() }
  Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}