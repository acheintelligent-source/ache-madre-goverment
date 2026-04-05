#Requires -Version 5.1
# ╔══════════════════════════════════════════════════════════════════╗
# ║  ACHE GLOBAL STATUS v2.0 — Compatible PowerShell 5.1           ║
# ║  GONZAGA · COOPECRUCENOS R.L. · La Cruz, Guanacaste, CR        ║
# ║                                                                  ║
# ║  GUARDAR:   C:\Users\achei\ache_status.ps1                      ║
# ║  EJECUTAR:  .\ache_status.ps1                                   ║
# ║             .\ache_status.ps1 -Html                             ║
# ║             .\ache_status.ps1 -Fix                              ║
# ║             .\ache_status.ps1 -Watch                            ║
# ╚══════════════════════════════════════════════════════════════════╝
param(
    [switch]$Html,
    [switch]$Watch,
    [switch]$Fix,
    [int]$Interval = 5
)

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue

function WOk($m)   { Write-Host "  [OK]  $m" -ForegroundColor Green }
function WWarn($m) { Write-Host "  [!!]  $m" -ForegroundColor Yellow }
function WInfo($m) { Write-Host "   ..   $m" -ForegroundColor DarkGray }
function WSep      { Write-Host ("-" * 68) -ForegroundColor DarkBlue }
function WHead($m) { Write-Host "  $m" -ForegroundColor Cyan }

function HumanSize($bytes) {
    if ($null -eq $bytes) { return "0 B" }
    $b = [long]$bytes
    if ($b -lt 1024)        { return "$b B" }
    if ($b -lt 1048576)     { return "{0:N1} KB" -f ($b / 1024) }
    if ($b -lt 1073741824)  { return "{0:N1} MB" -f ($b / 1048576) }
    return "{0:N1} GB" -f ($b / 1073741824)
}

function TestPort($port) {
    try {
        $tcp  = New-Object System.Net.Sockets.TcpClient
        $conn = $tcp.BeginConnect("127.0.0.1", $port, $null, $null)
        $ok   = $conn.AsyncWaitHandle.WaitOne(400, $false)
        $tcp.Close()
        return $ok
    } catch { return $false }
}

$R = @{
    ts        = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    sistema   = @{}
    carpetas  = @()
    archivos  = @{}
    puertos   = @{}
    procesos  = @()
    dbs       = @()
    problemas = @()
    score     = 0
}

# ── BANNER ───────────────────────────────────────────────────────────
function ShowBanner {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  ACHE GLOBAL STATUS v2.0  —  PowerShell 5.1 Edition          ║" -ForegroundColor White
    Write-Host "║  COOPECRUCENOS R.L.  ·  La Cruz, Guanacaste, Costa Rica      ║" -ForegroundColor DarkGray
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "  $(Get-Date -Format 'dddd dd/MM/yyyy  HH:mm:ss')" -ForegroundColor DarkGray
    Write-Host ""
}

# ── 1. SISTEMA ───────────────────────────────────────────────────────
function ScanSistema {
    WSep; WHead "SISTEMA"; WSep
    $os    = [System.Environment]::OSVersion.VersionString
    $hname = [System.Environment]::MachineName
    $user  = [System.Environment]::UserName
    $psv   = $PSVersionTable.PSVersion.ToString()
    $cwd   = (Get-Location).Path

    $pyVer = "no instalado"
    try { $p = (& python --version 2>&1); if ($p) { $pyVer = $p.ToString().Trim() } } catch {}

    $nodeVer = "no instalado"
    try {
        $n = (& node --version 2>&1)
        if ($n -and ($n.ToString() -notmatch "error")) { $nodeVer = $n.ToString().Trim() }
    } catch {}

    $ip = "no determinada"
    try {
        $addrs = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName())
        foreach ($a in $addrs) {
            if ($a.AddressFamily -eq "InterNetwork") { $ip = $a.IPAddressToString; break }
        }
    } catch {}

    WOk "OS:         $os"
    WOk "Host:       $hname  |  Usuario: $user"
    WOk "PowerShell: $psv"
    WOk "Python:     $pyVer"
    WOk "Node.js:    $nodeVer"
    WOk "CWD:        $cwd"
    WOk "IP Local:   $ip"
    $R.sistema = @{ os=$os; host=$hname; user=$user; ps=$psv; python=$pyVer; node=$nodeVer; ip=$ip; cwd=$cwd }
    Write-Host ""
}

# ── 2. CARPETAS ──────────────────────────────────────────────────────
function ScanCarpetas {
    WSep; WHead "CARPETAS ACHE DETECTADAS"; WSep
    $kws = @("ACHE","AURORA","NEXUS","EVA","NEPTUNO","GONZAGA","COOPECRUCENOS",
             "TRAILERO","GENESIS","SUPREMA","UNIVERSAL","MATRIARCA","BRAIN",
             "CONSCIENTIA","PACIFICA","META","FASE","MOTHER","TRINIT","MATRIX")
    $roots = @("C:\Users\$env:USERNAME","$env:USERPROFILE","$env:USERPROFILE\Desktop","$env:USERPROFILE\Documents","C:\")
    $found = New-Object System.Collections.ArrayList
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        try {
            $dirs = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue
            foreach ($d in $dirs) {
                $hit = $false
                foreach ($kw in $kws) { if ($d.Name -like "*$kw*") { $hit = $true; break } }
                if ($hit -and ($found -notcontains $d.FullName)) { $null = $found.Add($d.FullName) }
            }
        } catch {}
    }
    if ($found.Count -gt 0) {
        foreach ($f in ($found | Sort-Object)) {
            if (-not (Test-Path $f)) { continue }
            $cnt = (Get-ChildItem -Path $f -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
            $sumObj = Get-ChildItem -Path $f -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
            $sz = 0
            if ($sumObj.Sum) { $sz = $sumObj.Sum }
            WOk $f
            WInfo "     $cnt archivos  |  $(HumanSize $sz)"
            $R.carpetas += @{ path=$f; archivos=$cnt; bytes=$sz }
        }
        Write-Host ""
        WOk "$($found.Count) carpetas ACHE encontradas"
    } else {
        WWarn "Sin carpetas ACHE detectadas en rutas estandar"
        $R.problemas += "Sin carpetas ACHE"
    }
    Write-Host ""
}

# ── 3. ARCHIVOS CLAVE ────────────────────────────────────────────────
function ScanArchivos {
    WSep; WHead "ARCHIVOS CLAVE ACHE"; WSep
    $buscar = [ordered]@{
        "Backend"   = @("boot.py","server.js","nexus.py","ache_universal.py","main.py","app.py")
        "Frontends" = @("ACHE_v6.html","ACHE_NEXUS.html","hotel_v6_final.html","ACHE_TRAILERO_PB_v1.html","ACHE_GENESIS.html","nexus-bridge.html","index.html","aurora-suprema.tsx")
        "Memoria"   = @("memory.json","ache_memory.db","ache_v6.db","ache_universal.db")
        "Genoma"    = @("ache_genome.json","MASTER.md","config.json","genome.json")
        "Scripts"   = @("ache_status.ps1","CREAR_ACHE_v6.ps1","ACHE_MASTER.ps1","guardian.js","evolution.js","install.sh")
    }
    $base = "C:\Users\$env:USERNAME"
    $allF = Get-ChildItem -Path $base -Recurse -File -ErrorAction SilentlyContinue -Depth 4
    $total = 0
    foreach ($cat in $buscar.Keys) {
        $hits = New-Object System.Collections.ArrayList
        foreach ($nombre in $buscar[$cat]) {
            $ms = $allF | Where-Object { $_.Name -ieq $nombre }
            foreach ($m in $ms) { if ($hits -notcontains $m.FullName) { $null = $hits.Add($m) } }
        }
        if ($hits.Count -gt 0) {
            Write-Host "  [$cat]" -ForegroundColor Yellow
            foreach ($h in $hits) {
                WOk "  $($h.Name)"
                WInfo "     $($h.DirectoryName)  |  $(HumanSize $h.Length)  |  $($h.LastWriteTime.ToString('dd/MM/yy HH:mm'))"
                $total++
                if (-not $R.archivos.ContainsKey($cat)) { $R.archivos[$cat] = @() }
                $R.archivos[$cat] += $h.Name
            }
        } else {
            Write-Host "  [$cat]" -ForegroundColor DarkGray; WInfo "  Sin archivos"
        }
        Write-Host ""
    }
    WInfo "Total archivos clave: $total"
    Write-Host ""
}

# ── 4. PUERTOS ───────────────────────────────────────────────────────
function ScanPuertos {
    WSep; WHead "PUERTOS / SERVICIOS ACHE"; WSep
    $puertos = [ordered]@{
        8080 = "NEXUS Flask (principal)"
        5099 = "ACHE BRAIN (Node)"
        5600 = "ACHE UNIVERSAL (Node)"
        5700 = "ACHE FASE9 (Node)"
        5299 = "ACHE META (Node+ngrok)"
        7777 = "AURORA Suprema"
        9000 = "NEXUS Cerebro"
        9999 = "ACHE CENTRAL"
        3000 = "Frontend / MONEY"
        3001 = "ACHE Mobile"
        4040 = "ngrok Web UI"
        5177 = "ACHE META v1"
        1883 = "MQTT Broker"
        5601 = "Nodo 1"
        5602 = "Nodo 2"
    }
    $activos = 0
    foreach ($p in $puertos.Keys) {
        $lbl = $puertos[$p]
        $abierto = TestPort $p
        if ($abierto) {
            WOk  (":$p  ->  $lbl  [ACTIVO]")
            $activos++
            $R.puertos["$p"] = @{ label=$lbl; status="ACTIVO" }
        } else {
            WInfo (":$p  ->  $lbl  [offline]")
            $R.puertos["$p"] = @{ label=$lbl; status="offline" }
        }
    }
    Write-Host ""
    if ($activos -gt 0) { WOk "$activos servicio(s) activos" }
    else { WWarn "Ningun servicio activo"; $R.problemas += "Sin puertos activos" }
    Write-Host ""
}

# ── 5. PROCESOS ──────────────────────────────────────────────────────
function ScanProcesos {
    WSep; WHead "PROCESOS ACTIVOS"; WSep
    $kws   = @("python","node","uvicorn","flask","ngrok","mosquitto","npm")
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $n = $_.Name.ToLower()
        $hit = $false
        foreach ($k in $kws) { if ($n -like "*$k*") { $hit = $true; break } }
        $hit
    }
    if ($procs) {
        foreach ($p in $procs) {
            $mem = HumanSize $p.WorkingSet64
            $cpu = "?"
            try { $cpu = "{0:N1}s" -f $p.TotalProcessorTime.TotalSeconds } catch {}
            WOk ("PID {0,6}  {1,-18}  RAM: {2,-10}  CPU: {3}" -f $p.Id, $p.Name, $mem, $cpu)
            $R.procesos += @{ pid=$p.Id; name=$p.Name }
        }
    } else {
        WWarn "Sin procesos Python/Node detectados"
        $R.problemas += "Sin procesos ACHE"
    }
    Write-Host ""
}

# ── 6. BASES DE DATOS ────────────────────────────────────────────────
function ScanDatabases {
    WSep; WHead "MEMORIA / BASES DE DATOS"; WSep
    $jsons = Get-ChildItem -Path "C:\Users\$env:USERNAME" -Recurse -Filter "memory.json" -ErrorAction SilentlyContinue -Depth 4
    if ($jsons) {
        Write-Host "  [memory.json]" -ForegroundColor Yellow
        foreach ($j in $jsons) {
            $cnt = 0
            try {
                $d = Get-Content $j.FullName -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($d) { $cnt = @($d).Count }
            } catch {}
            WOk "$($j.Directory.Name)\$($j.Name)  —  $cnt entradas  |  $(HumanSize $j.Length)"
        }
    }
    $dbs = Get-ChildItem -Path "C:\Users\$env:USERNAME" -Recurse -Filter "*.db" -ErrorAction SilentlyContinue -Depth 4
    if ($dbs) {
        Write-Host "  [SQLite .db]" -ForegroundColor Yellow
        foreach ($db in $dbs) {
            WOk "$($db.Directory.Name)\$($db.Name)  |  $(HumanSize $db.Length)"
            $R.dbs += @{ path=$db.FullName; size=$db.Length }
        }
    }
    if (-not $jsons -and -not $dbs) {
        WWarn "Sin bases de datos encontradas"
        $R.problemas += "Sin DB encontrada"
    }
    Write-Host ""
}

# ── 7. API KEYS ──────────────────────────────────────────────────────
function ScanApiKeys {
    WSep; WHead "API KEYS"; WSep
    $vars = @(
        @{ n="ANTHROPIC_API_KEY";  l="Claude / AURORA" }
        @{ n="OPENAI_API_KEY";     l="OpenAI" }
        @{ n="GROQ_API_KEY";       l="Groq (gratis)" }
        @{ n="OPENROUTER_API_KEY"; l="OpenRouter" }
    )
    $hay = $false
    foreach ($v in $vars) {
        $val = [System.Environment]::GetEnvironmentVariable($v.n)
        if ($val) {
            $len  = $val.Length
            $pre  = $val.Substring(0, [Math]::Min(8, $len))
            $suf  = if ($len -gt 4) { $val.Substring($len - 4) } else { "***" }
            WOk ("{0,-28}  {1}  [{2}...{3}]" -f $v.n, $v.l, $pre, $suf)
            $hay = $true
        } else {
            WWarn ("{0,-28}  {1}  [NO CONFIGURADA]" -f $v.n, $v.l)
        }
    }
    if (-not $hay) {
        Write-Host ""
        WWarn "Sin API Keys en variables de entorno"
        WInfo 'Configurar: [System.Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY","sk-ant-...","User")'
        $R.problemas += "Sin API Keys en entorno"
    }
    Write-Host ""
}

# ── 8. RESUMEN ───────────────────────────────────────────────────────
function MostrarResumen {
    Write-Host ("=" * 68) -ForegroundColor Cyan
    WHead "RESUMEN — ECOSISTEMA ACHE · GONZAGA · PCL-phi-1618"
    Write-Host ("=" * 68) -ForegroundColor Cyan
    Write-Host ""

    $fOk  = $R.carpetas.Count -gt 0
    $aOk  = $R.archivos.Count -gt 0
    $pOk  = ($R.puertos.Values | Where-Object { $_.status -eq "ACTIVO" } | Measure-Object).Count -gt 0
    $prOk = $R.procesos.Count -gt 0
    $dOk  = $R.dbs.Count -gt 0

    $score = 0
    if ($fOk)                       { $score += 2 }
    if ($aOk)                       { $score += 2 }
    if ($pOk)                       { $score += 2 }
    if ($prOk)                      { $score += 2 }
    if ($dOk)                       { $score += 1 }
    if ($R.problemas.Count -eq 0)   { $score += 1 }
    $R.score = $score

    $bar   = ("#" * $score) + ("-" * (10 - $score))
    $color = if ($score -ge 7) { "Green" } elseif ($score -ge 4) { "Yellow" } else { "Red" }
    Write-Host "  Salud ACHE:  [$bar]  $score/10" -ForegroundColor $color
    Write-Host ""

    $nAct = ($R.puertos.Values | Where-Object { $_.status -eq "ACTIVO" } | Measure-Object).Count

    $tabla = @(
        @{ l="Carpetas ACHE";     ok=$fOk;  d="$($R.carpetas.Count) encontradas" }
        @{ l="Archivos clave";   ok=$aOk;  d="$($R.archivos.Keys.Count) categorias" }
        @{ l="Servicios activos";ok=$pOk;  d="$nAct puertos respondiendo" }
        @{ l="Procesos";         ok=$prOk; d="$($R.procesos.Count) procesos" }
        @{ l="Bases de datos";   ok=$dOk;  d="$($R.dbs.Count) archivos DB" }
    )
    foreach ($row in $tabla) {
        $ic = if ($row.ok) { "[OK]" } else { "[--]" }
        $st = if ($row.ok) { "OK   " } else { "FALTA" }
        $c  = if ($row.ok) { "Green" } else { "Red" }
        Write-Host "  " -NoNewline
        Write-Host $ic -ForegroundColor $c -NoNewline
        Write-Host ("  {0,-24}  " -f $row.l) -NoNewline
        Write-Host $st -ForegroundColor $c -NoNewline
        Write-Host "  $($row.d)" -ForegroundColor DarkGray
    }
    Write-Host ""

    Write-Host "  SERVICIOS ONLINE:" -ForegroundColor Green
    foreach ($p in $R.puertos.Keys) {
        if ($R.puertos[$p].status -eq "ACTIVO") {
            Write-Host "      :$p  ->  $($R.puertos[$p].label)" -ForegroundColor Green
        }
    }
    Write-Host ""

    if ($R.problemas.Count -gt 0) {
        Write-Host "  PROBLEMAS:" -ForegroundColor Yellow
        foreach ($pr in $R.problemas) { WWarn "  $pr" }
        Write-Host ""
    }

    Write-Host "  PROXIMOS PASOS:" -ForegroundColor Cyan
    if (-not $pOk)  { WInfo "  -> node C:\ACHE_CENTRAL\central.js  (servidor unificado)" }
    $ak = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY")
    if (-not $ak)   { WInfo '  -> [System.Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY","sk-ant-...","User")' }
    WInfo "  -> .\ache_status.ps1 -Fix    (crea ACHE_CENTRAL y dependencias)"
    WInfo "  -> .\ache_status.ps1 -Html   (genera reporte HTML)"
    Write-Host ""
}

# ── 9. FIX ───────────────────────────────────────────────────────────
function ModoFix {
    WSep; WHead "MODO FIX"; WSep
    Write-Host ""

    # Carpetas base
    foreach ($c in @("memory","modules","static","logs")) {
        if (-not (Test-Path $c)) {
            New-Item -ItemType Directory -Path $c -Force | Out-Null
            WOk "Carpeta creada: $c"
        } else { WOk "Carpeta OK: $c" }
    }
    Write-Host ""

    # Python packages
    $pkgs = @("fastapi","uvicorn","requests","anthropic","websockets")
    foreach ($pkg in $pkgs) {
        $chk = "import $pkg; print('ok')" | python 2>$null
        if ($chk -ne "ok") {
            WInfo "Instalando $pkg..."
            & python -m pip install $pkg --quiet 2>&1 | Out-Null
            WOk "$pkg instalado"
        } else { WOk "Python $pkg OK" }
    }
    Write-Host ""

    # Genoma
    if (-not (Test-Path "ache_genome.json")) {
        $g = @{
            version="1.0"; creado=(Get-Date -Format "o"); entidad="COOPECRUCENOS R.L."
            cedula="3-004-757068"; celula="GONZAGA-CBM-Omega-001"; referencia="PCL-phi-1618"
            lugar="La Cruz, Guanacaste, Costa Rica"
            ccps=@(
                @{id=1;n="SQLite append-only";r="nunca DELETE/UPDATE"}
                @{id=2;n="SHA-256 inmutable";r="cada evento tiene hash"}
                @{id=3;n="Modo advisory";r="ACHE propone, humano decide"}
                @{id=4;n="Offline-first";r="funciona sin internet"}
                @{id=5;n="Sin vendor lock-in";r="no dependencia unica"}
                @{id=6;n="MASTER.md manda";r="constitucion del sistema"}
                @{id=7;n="Transparencia total";r="todo auditable"}
                @{id=8;n="Dignidad humana";r="personas primero siempre"}
                @{id=9;n="Cooperativismo";r="beneficio colectivo"}
                @{id=10;n="Soberania digital";r="codigo propio y abierto"}
                @{id=11;n="Resiliencia";r="el sistema sobrevive fallos"}
            )
        }
        $g | ConvertTo-Json -Depth 5 | Out-File "ache_genome.json" -Encoding UTF8
        WOk "Genoma creado: ache_genome.json (11 CCPs)"
    } else { WOk "Genoma ya existe" }
    Write-Host ""

    # Servidor central
    $central = "C:\ACHE_CENTRAL"
    if (-not (Test-Path $central)) { New-Item -ItemType Directory -Path $central -Force | Out-Null }

    $pkg_json = '{"name":"ache-central","version":"1.0.0","main":"central.js","dependencies":{"express":"^4.18.2"}}'
    $pkg_json | Out-File "$central\package.json" -Encoding UTF8

    $server_js = @'
const express = require('express');
const path    = require('path');
const fs      = require('fs');
const http    = require('http');

const app  = express();
const PORT = 9999;
const HOME = process.env.USERPROFILE || 'C:/Users/achei';

app.use(express.json());

const HTML_DIRS = [
  HOME + '/ACHE', HOME + '/ACHE-SUPREMA', HOME + '/ACHE_NEXUS',
  HOME + '/ACHE_UNIVERSAL', HOME + '/ACHE-MADRE_v314',
  'C:/ACHE_FASE9', 'C:/ACHE_META_FINAL', 'C:/ACHE_UNIVERSAL',
  HOME + '/ACHE_V14', HOME + '/ACHE_PROD', __dirname
];

function checkPort(port, cb) {
  const req = http.get({ hostname:'127.0.0.1', port, path:'/', timeout:400 }, () => cb(true));
  req.on('error', () => cb(false));
  req.on('timeout', () => { req.destroy(); cb(false); });
}

app.get('/module/:name', (req, res) => {
  const name = req.params.name;
  for (const dir of HTML_DIRS) {
    const f = path.join(dir, name);
    if (fs.existsSync(f)) return res.sendFile(f);
  }
  res.status(404).send('Modulo no encontrado: ' + name);
});

app.get('/estado', (req, res) => {
  const ports = [8080, 5099, 5600, 5700, 5299, 7777, 9000];
  const results = {};
  let pending = ports.length;
  ports.forEach(p => {
    checkPort(p, ok => {
      results[p] = ok ? 'ACTIVO' : 'offline';
      if (--pending === 0) res.json({ sistema:'ACHE CENTRAL', ts:new Date().toISOString(), puertos:results });
    });
  });
});

app.get('/', (req, res) => res.send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8">
<title>ACHE CENTRAL</title>
<style>
body{background:#020a0d;color:#cfe8f4;font-family:'Courier New',monospace;padding:24px;margin:0}
h1{color:#00e5ff;font-size:16px;letter-spacing:3px;margin-bottom:4px}
.sub{font-size:10px;color:#4a7090;margin-bottom:20px}
.card{background:#0a2030;border:1px solid #1a4060;border-radius:8px;padding:14px;margin:8px 0;cursor:pointer;transition:border-color .15s}
.card:hover{border-color:#00e5ff}
.badge{display:inline-block;padding:2px 7px;border-radius:4px;font-size:9px;margin-left:6px}
.on{background:rgba(34,197,94,.15);color:#22c55e;border:1px solid rgba(34,197,94,.3)}
.off{background:rgba(74,112,144,.1);color:#4a7090;border:1px solid rgba(74,112,144,.2)}
#estado{margin-top:16px;font-size:10px;color:#4a7090;background:#0a2030;border:1px solid #1a4060;border-radius:6px;padding:12px}
</style></head><body>
<h1>ACHE CENTRAL · GONZAGA</h1>
<div class="sub">COOPECRUCENOS R.L. · 3-004-757068 · La Cruz, Guanacaste · PCL-phi-1618</div>
<div class="card" onclick="open('http://localhost:8080','_blank')"><b style="color:#00e5ff">NEXUS Flask :8080</b><span class="badge on">ACTIVO</span> — Backend Python principal</div>
<div class="card" onclick="open('http://localhost:5099','_blank')"><b style="color:#00e5ff">ACHE BRAIN :5099</b><span class="badge on">ACTIVO</span> — Node.js</div>
<div class="card" onclick="open('http://localhost:5600','_blank')"><b style="color:#00e5ff">ACHE UNIVERSAL :5600</b><span class="badge on">ACTIVO</span> — Node + 5 nodos</div>
<div class="card" onclick="open('http://localhost:5700','_blank')"><b style="color:#00e5ff">ACHE FASE9 :5700</b><span class="badge on">ACTIVO</span> — Node + guardian</div>
<div class="card" onclick="open('http://localhost:5299','_blank')"><b style="color:#00e5ff">ACHE META :5299</b><span class="badge on">ACTIVO</span> — Node + ngrok</div>
<div class="card" onclick="open('/module/hotel_v6_final.html','_blank')"><b style="color:#ffd740">Hotel COOPECRUCENOS</b> — Sistema hotelero</div>
<div class="card" onclick="open('/module/ACHE_TRAILERO_PB_v1.html','_blank')"><b style="color:#ffd740">ACHE Trailero</b> — Aduana Penas Blancas</div>
<div class="card" onclick="open('/module/ACHE_NEXUS.html','_blank')"><b style="color:#ffd740">NEXUS Frontend</b></div>
<div class="card" onclick="open('/module/ACHE_MADRE_GOVERNMENT_v4__2___1_.html','_blank')"><b style="color:#ffd740">ACHE MADRE GOVERNMENT</b></div>
<button onclick="fetch('/estado').then(r=>r.json()).then(d=>{document.getElementById('estado').innerText=JSON.stringify(d,null,2)})"
  style="margin-top:12px;background:rgba(0,229,255,.1);border:1px solid #00e5ff;color:#00e5ff;padding:7px 14px;border-radius:6px;cursor:pointer;font-family:inherit;font-size:11px">
  Ver estado del ecosistema
</button>
<pre id="estado">Pulsa el boton para ver el estado en tiempo real...</pre>
</body></html>`));

app.listen(PORT, () => console.log('ACHE CENTRAL activo: http://localhost:' + PORT));
'@

    $server_js | Out-File "$central\central.js" -Encoding UTF8

    Push-Location $central
    cmd /c "npm install --quiet" 2>&1 | Out-Null
    Pop-Location

    WOk "ACHE CENTRAL creado en: $central"
    Write-Host ""
    Write-Host "  LISTO. Ejecuta esto para iniciar:" -ForegroundColor Green
    WInfo "  Start-Process powershell -ArgumentList 'node C:\ACHE_CENTRAL\central.js'"
    WInfo "  Start-Process 'http://localhost:9999'"
    Write-Host ""
}

# ── 10. HTML ─────────────────────────────────────────────────────────
function ExportarHtml {
    $ts   = Get-Date -Format "yyyyMMdd_HHmmss"
    $file = "$env:USERPROFILE\ache_status_$ts.html"

    $portRows = ""
    foreach ($p in $R.puertos.Keys) {
        $v   = $R.puertos[$p]
        $cls = if ($v.status -eq "ACTIVO") { "ok" } else { "off" }
        $portRows += "<tr class='$cls'><td>:$p</td><td>$($v.label)</td><td>$($v.status)</td></tr>"
    }
    $dbRows = ""
    foreach ($db in $R.dbs) {
        $n = Split-Path $db.path -Leaf
        $dbRows += "<tr><td>$n</td><td>$(HumanSize $db.size)</td></tr>"
    }
    if (-not $dbRows) { $dbRows = "<tr><td colspan='2'>Sin DBs</td></tr>" }
    $iss = ""
    foreach ($i in $R.problemas) { $iss += "<li class='err'>$i</li>" }
    if (-not $iss) { $iss = "<li class='ok'>Sin problemas</li>" }
    $sc  = $R.score
    $bar = ("#" * $sc) + ("-" * (10 - $sc))
    $col = if ($sc -ge 7) { "#22c55e" } elseif ($sc -ge 4) { "#f59e0b" } else { "#ef4444" }

    $html = "<!DOCTYPE html><html lang='es'><head><meta charset='UTF-8'><title>ACHE Status $ts</title>"
    $html += "<style>:root{--bg:#020a0d;--card:#0a2030;--bdr:#1a4060;--cyan:#00e5ff;--grn:#22c55e;--amb:#f59e0b;--red:#ef4444;--mut:#4a7090}"
    $html += "*{margin:0;padding:0;box-sizing:border-box}body{font-family:'Courier New',monospace;background:var(--bg);color:#cfe8f4;padding:24px}"
    $html += "h1{font-size:16px;color:var(--cyan);letter-spacing:3px;margin-bottom:4px}.sub{font-size:10px;color:var(--mut);margin-bottom:20px}"
    $html += ".grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px}"
    $html += ".card{background:var(--card);border:1px solid var(--bdr);border-radius:8px;padding:14px}h2{font-size:9px;color:var(--amb);letter-spacing:2px;text-transform:uppercase;margin-bottom:10px}"
    $html += "table{width:100%;border-collapse:collapse;font-size:10px}td{padding:4px 6px;border-bottom:1px solid rgba(26,64,96,.4)}"
    $html += "tr.ok td{color:var(--grn)}tr.off td{color:var(--mut)}.ok{color:var(--grn)}.err{color:var(--red)}"
    $html += "ul{list-style:none;font-size:10px}li{padding:3px 0;border-bottom:1px solid rgba(26,64,96,.3)}"
    $html += ".bar{font-size:18px;color:$col;letter-spacing:2px;margin:6px 0}.sc{font-size:10px;color:var(--mut)}</style></head><body>"
    $html += "<h1>ACHE GLOBAL STATUS</h1>"
    $html += "<div class='sub'>COOPECRUCENOS R.L. · 3-004-757068 · La Cruz, Guanacaste · PCL-phi-1618 · $($R.ts)</div>"
    $html += "<div class='card' style='margin-bottom:14px'><h2>Salud del Ecosistema</h2>"
    $html += "<div class='bar'>[$bar] $sc/10</div>"
    $html += "<div class='sc'>Host: $($R.sistema.host) · PS: $($R.sistema.ps) · Python: $($R.sistema.python) · Node: $($R.sistema.node) · IP: $($R.sistema.ip)</div></div>"
    $html += "<div class='grid'>"
    $html += "<div class='card'><h2>Puertos / Servicios</h2><table><tr><th>Puerto</th><th>Servicio</th><th>Estado</th></tr>$portRows</table></div>"
    $html += "<div class='card'><h2>Bases de Datos</h2><table><tr><th>Archivo</th><th>Tamano</th></tr>$dbRows</table></div>"
    $html += "<div class='card'><h2>Problemas</h2><ul>$iss</ul></div></div>"
    $html += "</body></html>"

    $html | Out-File $file -Encoding UTF8
    WOk "HTML: $file"
    try { Start-Process $file } catch {}
}

# ── WATCH ────────────────────────────────────────────────────────────
function ModoWatch($seg) {
    Write-Host "  WATCH — cada ${seg}s  (Ctrl+C para salir)" -ForegroundColor Magenta
    try {
        while ($true) {
            Clear-Host; ShowBanner
            $R.puertos = @{}; $R.procesos = @()
            ScanPuertos; ScanProcesos
            Write-Host "  Siguiente en ${seg}s..." -ForegroundColor DarkGray
            Start-Sleep -Seconds $seg
        }
    } catch { Write-Host "  Watch terminado." -ForegroundColor DarkGray }
}

# ── MAIN ─────────────────────────────────────────────────────────────
ShowBanner
if ($Watch) { ModoWatch $Interval; exit }

ScanSistema
ScanCarpetas
ScanArchivos
ScanPuertos
ScanProcesos
ScanDatabases
ScanApiKeys
MostrarResumen

if ($Fix)  { ModoFix }
if ($Html) { ExportarHtml }

$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$rpt = "$env:USERPROFILE\ache_report_$ts.json"
$R | ConvertTo-Json -Depth 4 | Out-File $rpt -Encoding UTF8
WInfo "Reporte guardado: $rpt"
Write-Host ""
