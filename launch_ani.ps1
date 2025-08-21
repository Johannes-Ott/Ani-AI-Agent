# Launch ANI AI Agent v32.3 (stabiler Launcher für Windows PowerShell 5.1)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# -----------------------------
# Pfade & Basis
# -----------------------------
try {
  $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
} catch {
  $ScriptRoot = (Get-Location).Path
}

$LogDir        = Join-Path $ScriptRoot 'logs'
$CfgDir        = Join-Path $ScriptRoot '.config'
$DocsDir       = Join-Path $ScriptRoot 'docs'
$SandboxDir    = Join-Path $ScriptRoot 'sandbox'
$Global:LogFile = Join-Path $LogDir 'launch_ani.log'
$LockFile      = Join-Path $ScriptRoot '.launcher.lock'

# Verzeichnisse sicherstellen
New-Item -ItemType Directory -Force -Path $LogDir,$CfgDir,$DocsDir,$SandboxDir | Out-Null

# -----------------------------
# Struktur-Check (nur WARN)
# -----------------------------
$expected = @('ani-desktop','workflows','logs','.config','docker-compose.yml','.env')
foreach ($item in $expected) {
  $p = Join-Path $ScriptRoot $item
  if (-not (Test-Path $p)) {
    Write-Host "WARN: '$item' fehlt unter $ScriptRoot"
  }
}

# -----------------------------
# Logging-Helfer
# -----------------------------
function Write-Log {
  param(
    [Parameter(Mandatory=$true)][string]$Message,
    [string]$Level = 'INFO'
  )
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  $line = "[$ts][$Level] $Message"
  Write-Host $line
  # Robust schreiben (Retry)
  for ($i=0; $i -lt 5; $i++) {
    try {
      $sw = New-Object System.IO.StreamWriter($Global:LogFile, $true, [System.Text.UTF8Encoding]::new($false))
      $sw.WriteLine($line)
      $sw.Dispose()
      break
    } catch {
      Start-Sleep -Milliseconds (150 * ($i + 1))
    }
  }
}

# -----------------------------
# Lock-Handling (altes Instance beenden)
# -----------------------------
if (Test-Path $LockFile) {
  try {
    $c = Get-Content $LockFile -Raw -ErrorAction SilentlyContinue
    if ($c -match 'PID=(\d+)') {
      $oldPid = [int]$Matches[1]
      Write-Log "Lock gefunden, beende alte PID=$oldPid ..." 'STEP'
      Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    Write-Log 'Lock entfernt.' 'STEP'
  } catch {}
}
"$(Get-Date -Format s) PID=$PID" | Out-File $LockFile -Encoding ascii -Force
Write-Log 'Launcher started v32.3'

# -----------------------------
# Docker Desktop sicherstellen
# -----------------------------
function Ensure-Docker {
  param([int]$TimeoutSec = 240)

  Write-Log 'Pruefe Docker Desktop...' 'STEP'
  try {
    docker info | Out-Null
    Write-Log 'Docker ist bereit.'
    return $true
  } catch {}

  # Dienst starten
  try {
    $svc = Get-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
      Write-Log 'Starte Dienst com.docker.service ...' 'STEP'
      Start-Service 'com.docker.service' -ErrorAction SilentlyContinue
    }
  } catch {}

  # GUI starten (falls noetig)
  try {
    $gui = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path $gui) {
      Write-Log 'Starte Docker Desktop GUI ...' 'STEP'
      Start-Process $gui | Out-Null
    }
  } catch {}

  # Linux-Engine & Kontext
  try { & wsl.exe -l -v | Out-Null } catch {}
  try {
    $cli = Join-Path $env:ProgramFiles 'Docker\Docker\DockerCli.exe'
    if (Test-Path $cli) { & $cli -SwitchLinuxEngine | Out-Null }
  } catch {}
  try { docker context use desktop-linux | Out-Null } catch {}

  # Warten bis bereit
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    try {
      docker info | Out-Null
      Write-Log 'Docker ist bereit.'
      return $true
    } catch {
      Start-Sleep -Seconds 3
    }
  }
  Write-Log 'Docker wurde nicht rechtzeitig bereit.' 'ERROR'
  return $false
}

if (-not (Ensure-Docker)) { exit 1 }

# -----------------------------
# .env laden (Prozess-Umgebung)
# -----------------------------
$ENV_V   = @{}
$EnvFile = Join-Path $ScriptRoot '.env'
if (Test-Path $EnvFile) {
  Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*#') { return }
    if ($_ -match '^\s*$') { return }
    if ($_ -match '^\s*([^=]+)=(.*)$') {
      $k = $Matches[1].Trim()
      $v = $Matches[2].Trim()
      $ENV_V[$k] = $v
      Set-Item -Path ("Env:{0}" -f $k) -Value $v
    }
  }
}

$PORT_N8N    = if ($ENV_V['PORT_N8N'])    { $ENV_V['PORT_N8N'] }    else { '5678' }
$PORT_OLLAMA = if ($ENV_V['PORT_OLLAMA']) { $ENV_V['PORT_OLLAMA'] } else { '11435' }
$N8N_URL     = if ($ENV_V['N8N_BASE_URL'])    { $ENV_V['N8N_BASE_URL'] }    else { "http://localhost:$PORT_N8N" }
$OLLAMA_URL  = if ($ENV_V['OLLAMA_BASE_URL']) { $ENV_V['OLLAMA_BASE_URL'] } else { "http://localhost:$PORT_OLLAMA" }

Write-Log "Ports selected n8n=$PORT_N8N ollama=$PORT_OLLAMA"

# -----------------------------
# Alt-Container mit gleichem Namen entfernen
# -----------------------------
foreach ($n in @('ollama','n8n')) {
  try {
    $cid = docker ps -a --filter "name=^/$n$" --format "{{.ID}}" 2>$null
    if ($cid) {
      Write-Log "Konflikt-Container '$n' gefunden ($cid), entferne..." 'STEP'
      docker rm -f $cid | Out-Null
    }
  } catch {}
}

# -----------------------------
# Compose up
# -----------------------------
Write-Log "docker compose --env-file '.env' up -d --remove-orphans" 'STEP'
Push-Location $ScriptRoot
try {
  & docker compose --env-file '.env' up -d --remove-orphans
  Write-Log 'docker compose up abgeschlossen.'
  & docker compose ps | ForEach-Object { Write-Log $_ }
} catch {
  Write-Log ("compose fehlgeschlagen: " + $_.Exception.Message) 'ERROR'
  throw
} finally {
  Pop-Location
}

# -----------------------------
# HTTP-Wartehelfer
# -----------------------------
function Wait-Http {
  param(
    [Parameter(Mandatory=$true)][string]$Url,
    [int]$TimeoutSec = 180
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    try {
      $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
      if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { return $true }
    } catch {}
    Start-Sleep -Seconds 2
  }
  return $false
}

if (Wait-Http "$OLLAMA_URL/api/tags" 180) { Write-Log "Ollama API erreichbar: $OLLAMA_URL" } else { Write-Log 'Ollama API nicht erreichbar' 'WARN' }
if (Wait-Http "$N8N_URL/healthz" 180)     { Write-Log "n8n ist bereit: $N8N_URL"          } else { Write-Log 'n8n-Healthz nicht erreichbar' 'WARN' }

# -----------------------------
# NPM-Helfer: npm.cmd bevorzugt, Fallback node + npm-cli.js
# -----------------------------
function Get-NpmCmdPath {
  $npmCmd = $null
  try { $npmCmd = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source } catch {}
  if (-not $npmCmd) {
    $cands = @(
      "$env:ProgramFiles\nodejs\npm.cmd",
      "$env:APPDATA\npm\npm.cmd"
    )
    foreach ($c in $cands) { if (Test-Path $c) { return $c } }
  }
  return $npmCmd
}

function Invoke-Npm {
  param(
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [Parameter(Mandatory=$true)][string[]]$Args
  )

  # Hilfslogger für lange Ausgaben
  function Write-LogLines([string]$Text, [string]$Level='INFO') {
    if (-not $Text) { return }
    foreach ($line in ($Text -split "`r?`n")) {
      if ($line -ne '') { Write-Log $line $Level }
    }
  }

  # 1) bevorzugt npm.cmd (umgeht npm.ps1)
  $npmCmd = $null
  try { $npmCmd = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source } catch {}
  if (-not $npmCmd) {
    $cands = @(
      "$env:ProgramFiles\nodejs\npm.cmd",
      "$env:APPDATA\npm\npm.cmd"
    )
    foreach ($c in $cands) { if (Test-Path $c) { $npmCmd = $c; break } }
  }

  if ($npmCmd) {
    Write-Log ('Running: "' + $npmCmd + '" ' + ($Args -join ' ')) 'STEP'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $npmCmd
    $psi.WorkingDirectory       = $WorkDir
    $psi.Arguments              = ($Args -join ' ')
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    Write-LogLines $stdout 'INFO'
    Write-LogLines $stderr 'WARN'

    if ($p.ExitCode -ne 0) {
      throw ("npm ExitCode " + $p.ExitCode)
    }
    return
  }

  # 2) Fallback: node + npm-cli.js
  $node = $null
  try { $node = (Get-Command node -ErrorAction SilentlyContinue).Source } catch {}
  if (-not $node) { throw 'Weder npm.cmd noch node gefunden. Bitte Node.js (inkl. npm) installieren.' }

  $npmCli = Join-Path $env:APPDATA 'npm\node_modules\npm\bin\npm-cli.js'
  if (-not (Test-Path $npmCli)) {
    $npmCliLocal = Join-Path $WorkDir 'node_modules\npm\bin\npm-cli.js'
    if (Test-Path $npmCliLocal) { $npmCli = $npmCliLocal }
  }
  if (-not (Test-Path $npmCli)) { throw 'npm-cli.js nicht gefunden (weder global noch lokal). npm bitte korrekt installieren.' }

  Write-Log ('Running: node "' + $npmCli + '" ' + ($Args -join ' ')) 'STEP'
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName               = $node
  $psi.WorkingDirectory       = $WorkDir
  $psi.Arguments              = ('"' + $npmCli + '" ' + ($Args -join ' '))
  $psi.UseShellExecute        = $false
  $psi.CreateNoWindow         = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()

  Write-LogLines $stdout 'INFO'
  Write-LogLines $stderr 'WARN'

  if ($p.ExitCode -ne 0) {
    throw ("npm ExitCode " + $p.ExitCode)
  }
}

# -----------------------------
# package.json / Scripts prüfen
# -----------------------------
function Has-NpmScript {
  param(
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [Parameter(Mandatory=$true)][string]$ScriptName
  )
  $pkgPath = Join-Path $WorkDir 'package.json'
  if (-not (Test-Path $pkgPath)) { return $false }
  try {
    $json = Get-Content $pkgPath -Raw | ConvertFrom-Json
    return ($json.scripts.$ScriptName -ne $null -and $json.scripts.$ScriptName -ne '')
  } catch {
    Write-Log ('Konnte package.json nicht lesen: ' + $_.Exception.Message) 'WARN'
    return $false
  }
}

function Verify-ElectronEntry {
  param([Parameter(Mandatory=$true)][string]$WorkDir)
  $pkgPath = Join-Path $WorkDir 'package.json'
  if (-not (Test-Path $pkgPath)) { return $false }
  try {
    $json  = Get-Content $pkgPath -Raw | ConvertFrom-Json
    $entry = $json.main
    if (-not $entry -or $entry -eq '') {
      Write-Log "In package.json fehlt 'main'. Erwartet z. B. 'src/main.js'." 'ERROR'
      return $false
    }
    $entryPath = Join-Path $WorkDir $entry
    if (-not (Test-Path $entryPath)) {
      Write-Log ('Electron-Entry nicht gefunden: ' + $entryPath) 'ERROR'
      return $false
    }
    return $true
  } catch {
    Write-Log ('Konnte package.json nicht lesen/prüfen: ' + $_.Exception.Message) 'WARN'
    return $false
  }
}

# -----------------------------
# App starten (synchron, mit Logging)
# -----------------------------
function Start-Desktop-Wait {
  param([Parameter(Mandatory=$true)][string]$Rel)

  $appPath = Join-Path $ScriptRoot $Rel
  $pkg     = Join-Path $appPath 'package.json'
  if (-not (Test-Path $pkg)) {
    Write-Log ('Kein package.json unter: ' + $appPath + ' – App wird hier nicht gestartet.') 'WARN'
    return $false
  }

  Write-Log ('Desktop-App wird gestartet... (Pfad: ' + $appPath + ')')
  Push-Location $appPath
  try {
    # Dependencies
    if (Test-Path 'package-lock.json') {
      if (-not (Test-Path 'node_modules')) {
        Write-Log 'npm ci'
        Invoke-Npm -WorkDir $appPath -Args @('ci')
      } else {
        Write-Log 'npm install'
        Invoke-Npm -WorkDir $appPath -Args @('install')
      }
    } else {
      Write-Log 'npm install'
      Invoke-Npm -WorkDir $appPath -Args @('install')
    }

    # Pruefungen
    if (-not (Verify-ElectronEntry -WorkDir $appPath)) {
      Write-Log 'Abbruch: Electron-Entry fehlt/ungueltig.' 'ERROR'
      return $false
    }
    if (-not (Has-NpmScript -WorkDir $appPath -ScriptName 'start')) {
      Write-Log 'Abbruch: In package.json fehlt ein "start"-Script (z. B. "start": "electron .").' 'ERROR'
      return $false
    }

    # Start synchron (Block bis App schliesst)
    Write-Log 'npm run start (synchron; Log folgt unten)'
    Invoke-Npm -WorkDir $appPath -Args @('run','start')
    Write-Log 'npm run start ist beendet (App geschlossen).'
    return $true
  } catch {
    Write-Log ('Desktop-Start fehlgeschlagen: ' + $_.Exception.Message) 'ERROR'
    return $false
  } finally {
    Pop-Location
  }
}

# -----------------------------
# Hauptablauf: App starten, dann ggf. Cleanup
# -----------------------------
$didRunApp = $false

if (Start-Desktop-Wait 'ani-desktop') {
  $didRunApp = $true
}
elseif (Start-Desktop-Wait 'ani-desktop\ani-desktop') {
  $didRunApp = $true
}
else {
  Write-Log "Keine lauffaehige App-Struktur gefunden (kein gueltiger package.json-Pfad mit 'start'-Script)." 'WARN'
}

if ($didRunApp) {
  try {
    Write-Log 'docker compose down --remove-orphans' 'STEP'
    Push-Location $ScriptRoot
    & docker compose down --remove-orphans
    Pop-Location
    Write-Log 'Docker-Services heruntergefahren.'
  } catch {
    Write-Log ('Fehler beim compose down: ' + $_.Exception.Message) 'WARN'
  }
}

try {
  if (Test-Path $LockFile) { Remove-Item $LockFile -Force -ErrorAction SilentlyContinue }
  Write-Log 'Lock entfernt, Launcher beendet.'
} catch {}

Write-Host 'Fertig. Dieses Fenster kannst du schliessen.'
