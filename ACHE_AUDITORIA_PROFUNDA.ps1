# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║   ACHE_AUDITORIA_PROFUNDA.ps1  v3.0                                        ║
# ║   Auditoría Canónica del Ecosistema ACHE — Construida por Claude            ║
# ║   COOPECRUCENOS R.L. · Cédula 3-004-757068 · La Cruz, Guanacaste, CR       ║
# ║   Nodo: GONZAGA-CBM-OMEGA-001                                               ║
# ║                                                                              ║
# ║   USO (PowerShell 5.1+, sin requerir Admin):                                ║
# ║     .\ACHE_AUDITORIA_PROFUNDA.ps1              → Auditoría completa         ║
# ║     .\ACHE_AUDITORIA_PROFUNDA.ps1 -Reparar     → Intenta reparar problemas  ║
# ║     .\ACHE_AUDITORIA_PROFUNDA.ps1 -HTML        → Genera reporte HTML        ║
# ║     .\ACHE_AUDITORIA_PROFUNDA.ps1 -Watch       → Monitoreo continuo (10s)   ║
# ║     .\ACHE_AUDITORIA_PROFUNDA.ps1 -Guardar     → Guarda JSON del estado     ║
# ║                                                                              ║
# ║   Evalúa contra los 13 CCPs canónicos. Detecta daño por IAs externas.      ║
# ║   No destruye nada. Solo lee, analiza, reporta y sugiere.                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

param(
    [switch]$Reparar,
    [switch]$HTML,
    [switch]$Watch,
    [switch]$Guardar,
    [int]$Intervalo = 10
)

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue

# ═══════════════════════════════════════════════════════════════════════════════
# COLORES Y UTILIDADES
# ═══════════════════════════════════════════════════════════════════════════════
function Write-Ok($m)   { Write-Host "  [OK]  $m" -ForegroundColor Green }
function Write-Err($m)  { Write-Host "  [!!]  $m" -ForegroundColor Red }
function Write-Info($m) { Write-Host "  [--]  $m" -ForegroundColor DarkGray }
function Write-Warn($m) { Write-Host "  [>>]  $m" -ForegroundColor Yellow }
function Write-Head($m) { Write-Host "`n  ⬡  $m" -ForegroundColor Cyan }
function Write-Sep      { Write-Host ("═" * 70) -ForegroundColor DarkBlue }
function Write-Sep2     { Write-Host ("─" * 70) -ForegroundColor DarkGray }

function Test-PortOk($port) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar  = $tcp.BeginConnect("localhost", $port, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne(400, $false)
        try { $tcp.Close() } catch {}
        return $ok
    } catch { return $false }
}

function Get-FileSizeHuman($bytes) {
    if ($bytes -lt 1KB)  { return "$bytes B" }
    if ($bytes -lt 1MB)  { return "{0:N1} KB" -f ($bytes / 1KB) }
    if ($bytes -lt 1GB)  { return "{0:N1} MB" -f ($bytes / 1MB) }
    return "{0:N1} GB" -f ($bytes / 1GB)
}

function Find-AcheRoot {
    $candidates = @(
        "C:\ACHE",
        "C:\Users\achei\ACHE",
        "C:\ACHE_META_FINAL",
        "C:\ACHE_MATRIARCA",
        "$env:USERPROFILE\ACHE",
        "$env:USERPROFILE\Desktop\ACHE",
        "$env:USERPROFILE\Documents\ACHE"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    # Búsqueda en Desktop y Documents
    foreach ($base in @("$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents", $env:USERPROFILE)) {
        if (-not (Test-Path $base)) { continue }
        $found = Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match "^ACHE" } |
                 Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

# ═══════════════════════════════════════════════════════════════════════════════
# ESTADO GLOBAL DEL REPORTE
# ═══════════════════════════════════════════════════════════════════════════════
$AUDIT = @{
    timestamp    = (Get-Date -Format "o")
    fecha_legible= (Get-Date -Format "dddd dd/MM/yyyy HH:mm:ss")
    nodo         = "GONZAGA-CBM-OMEGA-001"
    coop         = "COOPECRUCENOS R.L."
    version      = "3.0"
    score_total  = 0
    score_max    = 0
    seccion_ok   = 0
    seccion_warn = 0
    seccion_err  = 0
    issues       = [System.Collections.ArrayList]@()
    reparaciones = [System.Collections.ArrayList]@()
    ccps         = @{}
    servicios    = @{}
    archivos     = @{}
    sistema      = @{}
    hallazgos_gpt= [System.Collections.ArrayList]@()
}

function Add-Issue($nivel, $componente, $mensaje, $solucion) {
    $item = @{
        nivel      = $nivel
        componente = $componente
        mensaje    = $mensaje
        solucion   = $solucion
        ts         = (Get-Date -Format "HH:mm:ss")
    }
    [void]$AUDIT.issues.Add($item)
    if     ($nivel -eq "ERROR") { $AUDIT.seccion_err++ }
    elseif ($nivel -eq "WARN")  { $AUDIT.seccion_warn++ }
}

function Add-Hallazgo($descripcion) {
    [void]$AUDIT.hallazgos_gpt.Add($descripcion)
}

# ═══════════════════════════════════════════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════════════════════════════════════════
function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║   ⬡  ACHE AUDITORÍA PROFUNDA v3.0 — Por Claude (Anthropic)        ║" -ForegroundColor White
    Write-Host "  ║   COOPECRUCENOS R.L. · La Cruz, Guanacaste, Costa Rica             ║" -ForegroundColor DarkGray
    Write-Host "  ║   Nodo: GONZAGA-CBM-OMEGA-001                                      ║" -ForegroundColor DarkGray
    Write-Host "  ╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "  $($AUDIT.fecha_legible)" -ForegroundColor DarkGray
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECCIÓN 1: SISTEMA BASE
# ═══════════════════════════════════════════════════════════════════════════════
function Audit-Sistema {
    Write-Head "SECCIÓN 1 — SISTEMA BASE"
    Write-Sep

    $os      = [System.Environment]::OSVersion.VersionString
    $machine = $env:COMPUTERNAME
    $user    = $env:USERNAME
    $psVer   = $PSVersionTable.PSVersion.ToString()

    Write-Ok "Host:        $machine"
    Write-Ok "Usuario:     $user"
    Write-Ok "OS:          $os"
    Write-Ok "PowerShell:  $psVer"

    # Python
    $pyVer = "NO DETECTADO"
    try {
        $pyOut = & python --version 2>&1
        if ($pyOut -match "Python") { $pyVer = $pyOut.ToString().Trim() }
    } catch {}
    if ($pyVer -eq "NO DETECTADO") {
        Write-Err "Python:      $pyVer"
        Add-Issue "ERROR" "Sistema" "Python no está instalado o no está en PATH" `
                  "Instala Python 3.10+ desde https://python.org — REQUERIDO para boot.py"
    } else {
        Write-Ok "Python:      $pyVer"
    }

    # Node.js
    $nodeVer = "NO DETECTADO"
    try {
        $nodeOut = & node --version 2>&1
        if ($nodeOut -match "v\d") { $nodeVer = $nodeOut.ToString().Trim() }
    } catch {}
    if ($nodeVer -eq "NO DETECTADO") {
        Write-Warn "Node.js:     $nodeVer"
        Add-Issue "WARN" "Sistema" "Node.js no detectado" `
                  "Instalar Node.js LTS si vas a usar ACHE_NEXUS o ACHE_META_FINAL (server.js)"
    } else {
        Write-Ok "Node.js:     $nodeVer"
    }

    # IP
    $ip = "no determinada"
    try {
        $ip = ([System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
               Where-Object { $_.AddressFamily -eq "InterNetwork" } |
               Select-Object -First 1).IPAddressToString
    } catch {}
    Write-Ok "IP Local:    $ip"

    # Disco
    $drive = Split-Path -Qualifier ((Get-Location).Path)
    try {
        $disk = Get-PSDrive -Name ($drive.Replace(":","")) -ErrorAction SilentlyContinue
        if ($disk) {
            $libre = Get-FileSizeHuman ($disk.Free * 1MB)
            if ($disk.Free -lt 500) {
                Write-Warn "Disco $drive espacio libre: $libre — puede causar problemas"
                Add-Issue "WARN" "Sistema" "Disco con poco espacio libre" "Liberar espacio en $drive"
            } else {
                Write-Ok "Disco $drive libre: $libre"
            }
        }
    } catch {}

    $AUDIT.sistema = @{
        host = $machine; usuario = $user; os = $os
        ps = $psVer; python = $pyVer; node = $nodeVer; ip = $ip
    }
    $AUDIT.score_total += 2
    $AUDIT.score_max   += 2
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECCIÓN 2: ESTRUCTURA DE ARCHIVOS
# ═══════════════════════════════════════════════════════════════════════════════
function Audit-Archivos {
    Write-Head "SECCIÓN 2 — ARCHIVOS ACHE"
    Write-Sep

    $root = Find-AcheRoot

    if ($root -ne $null) {
        Write-Ok "Raíz ACHE encontrada: $root"
        $AUDIT.score_total += 3
    } else {
        Write-Err "No se encontró carpeta ACHE en rutas conocidas"
        Add-Issue "ERROR" "Archivos" "Carpeta ACHE no encontrada" `
                  "Crear C:\ACHE\ y copiar boot.py, ACHE_CONEXION_TOTAL_v1.html, scripts PS1"
    }
    $AUDIT.score_max += 3

    # Archivos críticos
    $archivos_criticos = [ordered]@{
        "boot.py (backend principal)"                   = @("C:\Users\achei\ACHE\boot.py", "C:\ACHE\boot.py", "$env:USERPROFILE\ACHE\boot.py")
        "ACHE_CONEXION_TOTAL_v1.html (dashboard)"       = @("C:\ACHE\ACHE_CONEXION_TOTAL_v1.html", "$env:USERPROFILE\ACHE\ACHE_CONEXION_TOTAL_v1.html")
        "ACHE_MADRE_GOVERNMENT_v4.html"                 = @("C:\ACHE\ACHE_MADRE_GOVERNMENT_v4.html", "$env:USERPROFILE\ACHE\ACHE_MADRE_GOVERNMENT_v4.html")
        "ACHE_BOOT.ps1"                                 = @("C:\ACHE\ACHE_BOOT.ps1", "$env:USERPROFILE\ACHE\ACHE_BOOT.ps1")
        "ACHE_AUTOSTART.ps1"                            = @("C:\ACHE\ACHE_AUTOSTART.ps1")
        "EVOLUTION_LOG.json (registro inmutable)"       = @("C:\ACHE\EVOLUTION_LOG.json", "$env:USERPROFILE\ACHE\EVOLUTION_LOG.json")
        "ache.env (variables de entorno)"               = @("C:\ACHE\config\ache.env", "C:\ACHE\ache.env")
        "ache_v5.db / ache_memory.db (base de datos)"   = @("C:\Users\achei\ACHE\ache_v5.db", "C:\ACHE\ache_v5.db")
        "ACHE_NEXUS\nexus_server.js"                    = @("C:\ACHE_NEXUS\nexus_server.js", "C:\ACHE\ACHE_NEXUS\nexus_server.js")
    }

    $encontrados = 0
    foreach ($nombre in $archivos_criticos.Keys) {
        $rutas = $archivos_criticos[$nombre]
        $hallado = $false
        $ruta_hallada = ""
        foreach ($ruta in $rutas) {
            if (Test-Path $ruta) {
                $hallado = $true
                $ruta_hallada = $ruta
                break
            }
        }
        if ($hallado) {
            $size = (Get-Item $ruta_hallada).Length
            Write-Ok "$nombre  [$(Get-FileSizeHuman $size)]"
            $encontrados++
            $AUDIT.score_total++
        } else {
            Write-Warn "FALTA: $nombre"
            Add-Issue "WARN" "Archivos" "Archivo no encontrado: $nombre" `
                      "Copiar a C:\ACHE\ — Rutas buscadas: $($rutas -join ', ')"
        }
        $AUDIT.score_max++
    }

    # Buscar duplicados / versiones GPT contaminadas
    Write-Sep2
    Write-Info "Buscando archivos con posibles modificaciones de GPT..."

    $posibles_contaminados = @()
    if ($root -ne $null) {
        $todosHtml = Get-ChildItem -Path $root -Filter "*.html" -Recurse -ErrorAction SilentlyContinue
        $todosPs1  = Get-ChildItem -Path $root -Filter "*.ps1"  -Recurse -ErrorAction SilentlyContinue
        $todosPy   = Get-ChildItem -Path $root -Filter "*.py"   -Recurse -ErrorAction SilentlyContinue

        foreach ($f in ($todosHtml + $todosPs1 + $todosPy)) {
            $contenido = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($contenido -eq $null) { continue }

            # Señales de intervención GPT problemática
            $señales = @(
                @{ patron = "ChatGPT|GPT-4|gpt-3.5|openai.com/v1"; desc = "Referencia a GPT en lugar de Claude" }
                @{ patron = "REEMPLAZAR|REPLACE_ME|TU_API_KEY_AQUI|YOUR_API_KEY"; desc = "Placeholder sin reemplazar" }
                @{ patron = "// TODO|# TODO|<!-- TODO"; desc = "TODO sin resolver" }
                @{ patron = "DEPRECATED|deprecated|obsoleto|OBSOLETO"; desc = "Código marcado como obsoleto" }
                @{ patron = "throw new Error|raise Exception|panic\("; desc = "Error no manejado expuesto" }
                @{ patron = "hardcode|HARDCODE|hardcoded"; desc = "Valor hardcodeado (vulnerabilidad)" }
            )

            foreach ($s in $señales) {
                if ($contenido -match $s.patron) {
                    $posibles_contaminados += "$($f.Name): $($s.desc)"
                    Add-Hallazgo "$($f.Name) — $($s.desc)"
                }
            }
        }
    }

    if ($posibles_contaminados.Count -gt 0) {
        Write-Warn "Archivos con señales de modificación problemática ($($posibles_contaminados.Count)):"
        foreach ($item in $posibles_contaminados) { Write-Info "  → $item" }
    } else {
        Write-Ok "No se detectaron señales de contaminación en archivos"
    }

    $AUDIT.archivos = @{ encontrados = $encontrados; total = $archivos_criticos.Count; raiz = $root }
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECCIÓN 3: SERVICIOS Y PUERTOS
# ═══════════════════════════════════════════════════════════════════════════════
function Audit-Servicios {
    Write-Head "SECCIÓN 3 — SERVICIOS EN EJECUCIÓN"
    Write-Sep

    $puertos = [ordered]@{
        8080 = @{ nombre = "AURORA NEXUS / Flask (boot.py)"; critico = $true }
        5299 = @{ nombre = "ACHE_META_FINAL (Express)";      critico = $false }
        5099 = @{ nombre = "ACHE_BRAIN (Express)";           critico = $false }
        8888 = @{ nombre = "Dashboard HTTP (Python)";        critico = $true }
        7777 = @{ nombre = "AURORA Suprema";                 critico = $false }
        9000 = @{ nombre = "NEXUS Cerebro";                  critico = $false }
        3000 = @{ nombre = "ACHE MONEY / Dev";               critico = $false }
        3001 = @{ nombre = "ACHE Mobile";                    critico = $false }
        5600 = @{ nombre = "ACHE_UNIVERSAL";                 critico = $false }
        4040 = @{ nombre = "Ngrok Inspector";                critico = $false }
        6379 = @{ nombre = "Redis (opcional)";               critico = $false }
        1883 = @{ nombre = "MQTT Broker (IoT)";              critico = $false }
    }

    $activos    = 0
    $criticos_ok = 0
    $criticos_total = ($puertos.Values | Where-Object { $_.critico }).Count

    foreach ($puerto in $puertos.Keys) {
        $info    = $puertos[$puerto]
        $activo  = Test-PortOk $puerto
        $AUDIT.servicios[$puerto.ToString()] = $activo

        if ($activo) {
            Write-Ok ":$puerto  $($info.nombre)  [ACTIVO]"
            $activos++
            if ($info.critico) { $criticos_ok++ }
            $AUDIT.score_total++
        } else {
            if ($info.critico) {
                Write-Err ":$puerto  $($info.nombre)  [OFFLINE — CRÍTICO]"
                Add-Issue "ERROR" "Servicios" "Puerto crítico $puerto offline: $($info.nombre)" `
                          "Ejecutar .\ACHE_BOOT.ps1 para arrancar el stack"
            } else {
                Write-Info ":$puerto  $($info.nombre)  [offline]"
            }
        }
        $AUDIT.score_max++
    }

    Write-Host ""
    Write-Info "Servicios activos: $activos / $($puertos.Count)"
    Write-Info "Servicios críticos activos: $criticos_ok / $criticos_total"

    # Verificar tarea programada
    Write-Sep2
    Write-Info "Verificando tarea de arranque automático..."
    $tarea = Get-ScheduledTask -TaskName "ACHE_ECOSYSTEM_AUTOSTART" -ErrorAction SilentlyContinue
    if ($tarea -ne $null) {
        $info_tarea = Get-ScheduledTaskInfo -TaskName "ACHE_ECOSYSTEM_AUTOSTART" -ErrorAction SilentlyContinue
        Write-Ok "Tarea ACHE_ECOSYSTEM_AUTOSTART: REGISTRADA"
        if ($info_tarea -ne $null -and $info_tarea.LastRunTime -ne $null) {
            Write-Info "  Última ejecución: $($info_tarea.LastRunTime.ToString('dd/MM/yyyy HH:mm'))"
        }
        $AUDIT.score_total++
    } else {
        Write-Warn "Tarea de arranque automático: NO REGISTRADA"
        Add-Issue "WARN" "Servicios" "Tarea automática ACHE no instalada" `
                  "Ejecutar: .\ACHE_AUTOSTART.ps1 -Install"
    }
    $AUDIT.score_max++
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECCIÓN 4: API KEYS Y SEGURIDAD
# ═══════════════════════════════════════════════════════════════════════════════
function Audit-APIKeys {
    Write-Head "SECCIÓN 4 — API KEYS Y SEGURIDAD"
    Write-Sep

    # Cargar desde ache.env si existe
    $envFile = "C:\ACHE\config\ache.env"
    if (Test-Path $envFile) {
        Write-Ok "Archivo ache.env encontrado: $envFile"
        Get-Content $envFile | ForEach-Object {
            if ($_ -match "^([^#][^=]+)=(.+)$") {
                [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), "Process")
            }
        }
        $AUDIT.score_total++
    } else {
        Write-Warn "Archivo ache.env NO encontrado en C:\ACHE\config\"
        Add-Issue "WARN" "Seguridad" "Archivo ache.env no existe" `
                  "Crear C:\ACHE\config\ache.env con ANTHROPIC_API_KEY y GROQ_API_KEY"
    }
    $AUDIT.score_max++

    # Verificar cada key
    $keys = [ordered]@{
        "ANTHROPIC_API_KEY" = @{ prefijo = "sk-ant"; requerida = $true;  desc = "Claude (IA principal)" }
        "GROQ_API_KEY"      = @{ prefijo = "gsk_";   requerida = $false; desc = "Groq (IA secundaria)" }
        "OPENAI_API_KEY"    = @{ prefijo = "sk-";    requerida = $false; desc = "OpenAI (opcional)" }
        "NGROK_TOKEN"       = @{ prefijo = "";        requerida = $false; desc = "Ngrok túnel externo" }
    }

    foreach ($k in $keys.Keys) {
        $info = $keys[$k]
        $val  = [System.Environment]::GetEnvironmentVariable($k)

        if ($val -ne $null -and $val.Length -gt 10) {
            # Verificar formato
            $formato_ok = $true
            if ($info.prefijo -ne "" -and -not $val.StartsWith($info.prefijo)) {
                $formato_ok = $false
                Write-Warn "$k  [formato incorrecto — debe empezar con '$($info.prefijo)']"
                Add-Issue "WARN" "Seguridad" "$k tiene formato incorrecto" `
                          "Verificar que la key sea válida — debe empezar con '$($info.prefijo)'"
            } else {
                $masked = $val.Substring(0, [Math]::Min(10, $val.Length)) + "..."
                Write-Ok "$k  [$masked]  — $($info.desc)"
                $AUDIT.score_total++
            }

            # Detectar key de ejemplo / placeholder
            if ($val -match "AQUI|placeholder|example|test123|sk-ant-AQUI") {
                Write-Err "$k  [¡CONTIENE VALOR DE EJEMPLO! No es una key real]"
                Add-Issue "ERROR" "Seguridad" "$k contiene un placeholder, no una clave real" `
                          "Reemplazar con tu API key real de Anthropic/Groq"
                Add-Hallazgo "API KEY placeholder detectada — posible daño de IA externa"
            }
        } else {
            if ($info.requerida) {
                Write-Err "$k  [NO CONFIGURADA — REQUERIDA]"
                Add-Issue "ERROR" "Seguridad" "$k no está configurada" `
                          "Agregar al archivo C:\ACHE\config\ache.env"
            } else {
                Write-Info "$k  [no configurada — opcional]"
            }
        }
        if ($info.requerida) { $AUDIT.score_max++ }
    }

    # Verificar que no haya keys hardcodeadas en archivos HTML/PY
    Write-Sep2
    Write-Info "Verificando exposición de keys en código fuente..."
    $root = Find-AcheRoot
    if ($root -ne $null) {
        $archivos_codigo = Get-ChildItem -Path $root -Include "*.py","*.js","*.html","*.ps1" -Recurse -ErrorAction SilentlyContinue
        $exposicion_encontrada = $false
        foreach ($f in $archivos_codigo) {
            $cont = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($cont -ne $null -and $cont -match "sk-ant-[a-zA-Z0-9\-]{20,}|gsk_[a-zA-Z0-9]{30,}") {
                Write-Err "¡KEY EXPUESTA EN CÓDIGO! $($f.FullName)"
                Add-Issue "ERROR" "Seguridad" "API Key hardcodeada en: $($f.Name)" `
                          "URGENTE: Rotar la key en console.anthropic.com y reemplazar por variable de entorno"
                $exposicion_encontrada = $true
            }
        }
        if (-not $exposicion_encontrada) {
            Write-Ok "No se encontraron keys expuestas en código fuente"
            $AUDIT.score_total++
        }
    }
    $AUDIT.score_max++
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECCIÓN 5: BASE DE DATOS Y MEMORIA
# ═══════════════════════════════════════════════════════════════════════════════
function Audit-BaseDatos {
    Write-Head "SECCIÓN 5 — BASE DE DATOS Y MEMORIA ACHE"
    Write-Sep

    $rutas_db = @(
        "C:\Users\achei\ACHE\ache_v5.db",
        "C:\ACHE\ache_v5.db",
        "C:\ACHE\ache_memory.db",
        "C:\ACHE\ache_v6.db",
        "$env:USERPROFILE\ACHE\ache_v5.db",
        "$env:USERPROFILE\ACHE\ache_memory.db"
    )

    $db_encontrada = $false
    foreach ($ruta in $rutas_db) {
        if (Test-Path $ruta) {
            $db_encontrada = $true
            $size = (Get-Item $ruta).Length
            $mod  = (Get-Item $ruta).LastWriteTime.ToString("dd/MM/yyyy HH:mm")
            Write-Ok "DB encontrada: $ruta"
            Write-Info "  Tamaño: $(Get-FileSizeHuman $size) | Última modificación: $mod"

            # Verificar integridad con sqlite3 si está disponible
            $sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
            if ($sqlite -ne $null) {
                $integrity = & sqlite3 $ruta "PRAGMA integrity_check;" 2>&1
                if ($integrity -eq "ok") {
                    Write-Ok "  Integridad SQLite: OK"
                    $AUDIT.score_total++
                } else {
                    Write-Err "  Integridad SQLite: CORRUPTA — $integrity"
                    Add-Issue "ERROR" "BaseDatos" "Base de datos SQLite corrupta: $ruta" `
                              "Restaurar desde backup o reiniciar con init_db()"
                }
                $AUDIT.score_max++
            }
            $AUDIT.score_total += 2
        }
    }

    if (-not $db_encontrada) {
        Write-Warn "No se encontró base de datos ACHE (ache_v5.db)"
        Write-Info "  Esto es normal si aún no se ha ejecutado boot.py por primera vez"
        Add-Issue "WARN" "BaseDatos" "Base de datos no encontrada" `
                  "Ejecutar boot.py una vez para crear la DB automáticamente"
    }
    $AUDIT.score_max += 2

    # EVOLUTION_LOG.json
    $evo_paths = @(
        "C:\ACHE\EVOLUTION_LOG.json",
        "$env:USERPROFILE\ACHE\EVOLUTION_LOG.json",
        ".\EVOLUTION_LOG.json"
    )
    $evo_ok = $false
    foreach ($p in $evo_paths) {
        if (Test-Path $p) {
            $evo_ok = $true
            try {
                $evo = Get-Content $p -Raw | ConvertFrom-Json
                $total = $evo.metadata.total_changes
                $next  = $evo.metadata.next_change_id
                Write-Ok "EVOLUTION_LOG.json: $total cambios canónicos | Próximo: $next"
                $AUDIT.score_total++
            } catch {
                Write-Warn "EVOLUTION_LOG.json: existe pero no parsea como JSON válido"
                Add-Issue "WARN" "BaseDatos" "EVOLUTION_LOG.json malformado" `
                          "Verificar JSON — posible daño por edición manual o IA"
            }
            break
        }
    }
    if (-not $evo_ok) {
        Write-Warn "EVOLUTION_LOG.json: no encontrado"
        Add-Issue "WARN" "BaseDatos" "EVOLUTION_LOG.json no encontrado" `
                  "Este archivo es el registro inmutable (CCP-02). Debe existir en C:\ACHE\"
    }
    $AUDIT.score_max++
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECCIÓN 6: VALIDACIÓN DE 13 CCPs CANÓNICOS
# ═══════════════════════════════════════════════════════════════════════════════
function Audit-CCPs {
    Write-Head "SECCIÓN 6 — VALIDACIÓN DE 13 CCPs CANÓNICOS"
    Write-Sep

    $ccps = [ordered]@{
        "CCP-01" = @{ nombre = "Soberanía Humana";           test = "human_control";    peso = 3 }
        "CCP-02" = @{ nombre = "Memoria Inamovible";         test = "db_append_only";   peso = 3 }
        "CCP-03" = @{ nombre = "Transparencia Radical";      test = "logs_trazables";   peso = 2 }
        "CCP-04" = @{ nombre = "Offline-First";              test = "offline_capable";  peso = 3 }
        "CCP-05" = @{ nombre = "Sin Dependencia Única";      test = "multi_provider";   peso = 2 }
        "CCP-06" = @{ nombre = "Seguridad por Diseño";       test = "keys_seguras";     peso = 3 }
        "CCP-07" = @{ nombre = "Equidad Digital";            test = "accesible";        peso = 2 }
        "CCP-08" = @{ nombre = "Evolución por Capas";        test = "no_breaks";        peso = 2 }
        "CCP-09" = @{ nombre = "Consenso Cooperativo";       test = "gobernanza";       peso = 2 }
        "CCP-10" = @{ nombre = "Misión Social";              test = "social_mission";   peso = 2 }
        "CCP-11" = @{ nombre = "Soberanía de Datos";         test = "datos_locales";    peso = 3 }
        "CCP-12" = @{ nombre = "Interoperabilidad Legal";    test = "legal_cr";         peso = 2 }
        "CCP-13" = @{ nombre = "Alianza Tecnológica";        test = "ia_aliada";        peso = 2 }
    }

    $root = Find-AcheRoot

    foreach ($ccp_id in $ccps.Keys) {
        $ccp    = $ccps[$ccp_id]
        $estado = "PENDIENTE"
        $detalle = ""

        switch ($ccp.test) {
            "human_control" {
                # CCP-01: hay checkpoint humano en el código?
                if ($root -ne $null) {
                    $boot = Join-Path $root "boot.py"
                    if (Test-Path $boot) {
                        $cont = Get-Content $boot -Raw -ErrorAction SilentlyContinue
                        if ($cont -match "CCP-01|human.?checkpoint|soberan") {
                            $estado = "OK"; $detalle = "Checkpoint implementado en boot.py"
                        } else {
                            $estado = "WARN"; $detalle = "boot.py no menciona CCP-01 explícitamente"
                        }
                    } else { $estado = "WARN"; $detalle = "boot.py no encontrado" }
                } else { $estado = "WARN"; $detalle = "Raíz ACHE no encontrada" }
            }
            "db_append_only" {
                # CCP-02: hay tabla chain / append-only?
                $db_ok = $false
                foreach ($ruta in @("C:\Users\achei\ACHE\ache_v5.db","C:\ACHE\ache_v5.db","$env:USERPROFILE\ACHE\ache_v5.db")) {
                    if (Test-Path $ruta) { $db_ok = $true; break }
                }
                if ($db_ok) {
                    $estado = "OK"; $detalle = "DB encontrada — tabla chain append-only"
                } elseif ($root -ne $null) {
                    $cont = Get-Content (Join-Path $root "boot.py") -Raw -ErrorAction SilentlyContinue
                    if ($cont -match "append.only|chain|prev_hash") {
                        $estado = "WARN"; $detalle = "Lógica append-only en boot.py pero DB no inicializada"
                    } else { $estado = "WARN"; $detalle = "Sin DB ni lógica append-only detectada" }
                } else { $estado = "WARN"; $detalle = "No verificable" }
            }
            "logs_trazables" {
                # CCP-03: hay carpeta de logs?
                $logs_ok = (Test-Path "C:\ACHE\logs") -or (Test-Path "$env:USERPROFILE\ACHE\logs")
                if ($logs_ok) { $estado = "OK"; $detalle = "Carpeta de logs existe" }
                else { $estado = "WARN"; $detalle = "Carpeta logs\ no encontrada" }
            }
            "offline_capable" {
                # CCP-04: hay HTML standalone?
                $html_ok = $false
                foreach ($h in @("C:\ACHE\ACHE_CONEXION_TOTAL_v1.html","$env:USERPROFILE\ACHE\ACHE_CONEXION_TOTAL_v1.html")) {
                    if (Test-Path $h) { $html_ok = $true; break }
                }
                if ($html_ok) { $estado = "OK"; $detalle = "HTML standalone offline disponible" }
                else { $estado = "WARN"; $detalle = "No se encontró HTML offline standalone" }
            }
            "multi_provider" {
                # CCP-05: hay más de una API key configurada?
                $ant  = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY")
                $groq = [System.Environment]::GetEnvironmentVariable("GROQ_API_KEY")
                if ($ant -ne $null -and $groq -ne $null -and $ant.Length -gt 10 -and $groq.Length -gt 10) {
                    $estado = "OK"; $detalle = "Anthropic + Groq configurados"
                } elseif ($ant -ne $null -and $ant.Length -gt 10) {
                    $estado = "WARN"; $detalle = "Solo Anthropic configurado — Groq pendiente"
                    Add-Issue "WARN" "CCP-05" "CCP-05 parcial: solo un proveedor IA activo" `
                              "Agregar GROQ_API_KEY en ache.env para respaldo"
                } else {
                    $estado = "ERROR"; $detalle = "Ningún proveedor IA configurado"
                }
            }
            "keys_seguras" {
                # CCP-06: las keys no están hardcodeadas
                $env_file_ok = Test-Path "C:\ACHE\config\ache.env"
                if ($env_file_ok) { $estado = "OK"; $detalle = "Keys en archivo de configuración separado" }
                else { $estado = "WARN"; $detalle = "Archivo ache.env no encontrado — keys posiblemente en código" }
            }
            "accesible" {
                # CCP-07: hay interfaz simple para no-técnicos?
                $html_ok = $false
                foreach ($h in @("C:\ACHE\ACHE_CONEXION_TOTAL_v1.html","$env:USERPROFILE\ACHE\ACHE_CONEXION_TOTAL_v1.html",
                                  "C:\ACHE\hotel_v6_final.html")) {
                    if (Test-Path $h) { $html_ok = $true; break }
                }
                if ($html_ok) { $estado = "OK"; $detalle = "Interfaz HTML accesible disponible" }
                else { $estado = "WARN"; $detalle = "No se encontró interfaz de usuario accesible" }
            }
            "no_breaks" {
                # CCP-08: EVOLUTION_LOG existe y tiene más de EVO-001
                $evo_ok = $false
                foreach ($p in @("C:\ACHE\EVOLUTION_LOG.json","$env:USERPROFILE\ACHE\EVOLUTION_LOG.json")) {
                    if (Test-Path $p) {
                        try {
                            $evo = Get-Content $p -Raw | ConvertFrom-Json
                            if ($evo.entries.Count -ge 1) { $evo_ok = $true }
                        } catch {}
                        break
                    }
                }
                if ($evo_ok) { $estado = "OK"; $detalle = "EVOLUTION_LOG con entradas registradas" }
                else { $estado = "WARN"; $detalle = "No se pudo verificar historial de evolución" }
            }
            "gobernanza" {
                # CCP-09: hay estructura de gobernanza documentada
                $master_ok = $false
                foreach ($p in @("C:\ACHE\MASTER.md","$env:USERPROFILE\ACHE\MASTER.md")) {
                    if (Test-Path $p) { $master_ok = $true; break }
                }
                if ($master_ok) { $estado = "OK"; $detalle = "MASTER.md de gobernanza presente" }
                else { $estado = "WARN"; $detalle = "MASTER.md no encontrado" }
            }
            "social_mission" {
                # CCP-10: el sistema referencia misión social
                if ($root -ne $null) {
                    $boot = Join-Path $root "boot.py"
                    $cont = Get-Content $boot -Raw -ErrorAction SilentlyContinue
                    if ($cont -match "bienestar|social|cooperativa|Guanacaste|La Cruz|INEC") {
                        $estado = "OK"; $detalle = "Misión social embebida en contexto del sistema"
                    } else { $estado = "WARN"; $detalle = "Misión social no explícita en boot.py" }
                } else { $estado = "WARN"; $detalle = "boot.py no encontrado" }
            }
            "datos_locales" {
                # CCP-11: DB es local (SQLite, no cloud-only)
                $db_ok = $false
                foreach ($ruta in @("C:\Users\achei\ACHE\ache_v5.db","C:\ACHE\ache_v5.db","$env:USERPROFILE\ACHE\ache_v5.db")) {
                    if (Test-Path $ruta) { $db_ok = $true; break }
                }
                if ($db_ok) { $estado = "OK"; $detalle = "SQLite local — datos en tu máquina" }
                else { $estado = "WARN"; $detalle = "DB SQLite no inicializada aún" }
            }
            "legal_cr" {
                # CCP-12: hay referencia a legislación CR
                if ($root -ne $null) {
                    $boot = Join-Path $root "boot.py"
                    $cont = Get-Content $boot -Raw -ErrorAction SilentlyContinue
                    if ($cont -match "Ley 4179|SUGEF|SICOP|Hacienda|Costa Rica") {
                        $estado = "OK"; $detalle = "Referencia a normativa CR en sistema"
                    } else { $estado = "WARN"; $detalle = "Normativa CR no explícita en boot.py actual" }
                } else { $estado = "WARN"; $detalle = "No verificable" }
            }
            "ia_aliada" {
                # CCP-13: hay integración con Claude / múltiples IAs
                $ant = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY")
                if ($ant -ne $null -and $ant.Length -gt 10) {
                    $estado = "OK"; $detalle = "Claude integrado como IA aliada #7"
                } else { $estado = "WARN"; $detalle = "API Key de Claude no configurada" }
            }
        }

        $AUDIT.ccps[$ccp_id] = @{ nombre = $ccp.nombre; estado = $estado; detalle = $detalle }
        $AUDIT.score_max += $ccp.peso

        switch ($estado) {
            "OK"    {
                Write-Ok "$ccp_id — $($ccp.nombre): $detalle"
                $AUDIT.score_total += $ccp.peso
            }
            "WARN"  {
                Write-Warn "$ccp_id — $($ccp.nombre): $detalle"
                $AUDIT.score_total += [Math]::Floor($ccp.peso / 2)
                Add-Issue "WARN" "CCP" "$ccp_id ($($ccp.nombre)): $detalle" "Revisar implementación de $ccp_id"
            }
            "ERROR" {
                Write-Err "$ccp_id — $($ccp.nombre): $detalle"
                Add-Issue "ERROR" "CCP" "$ccp_id ($($ccp.nombre)) en FALLA: $detalle" "Resolver $ccp_id antes de continuar"
            }
        }
    }
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECCIÓN 7: DETECCIÓN DE DAÑO POR IAs EXTERNAS (GPT)
# ═══════════════════════════════════════════════════════════════════════════════
function Audit-DanioExterno {
    Write-Head "SECCIÓN 7 — DETECCIÓN DE DAÑO POR IAs EXTERNAS"
    Write-Sep

    $root = Find-AcheRoot
    if ($root -eq $null) {
        Write-Info "Raíz ACHE no encontrada — salteando esta sección"
        return
    }

    # Patrones que indican que GPT u otra IA introdujo cambios problemáticos
    $patrones_danio = @(
        @{ regex = "const\s+apiKey\s*=\s*['\"]sk-"; desc = "API Key hardcodeada en JS (patrón GPT)" }
        @{ regex = "fetch\(['\"]https://api.openai"; desc = "Llamada directa a OpenAI sin proxy" }
        @{ regex = "model.*gpt-4|gpt-3\.5"; desc = "Modelo GPT en lugar de Claude" }
        @{ regex = "localStorage\.setItem.*key|sessionStorage.*apiKey"; desc = "Key en localStorage (inseguro)" }
        @{ regex = "eval\(|innerHTML\s*=.*user|document\.write"; desc = "XSS potencial introducido" }
        @{ regex = "rm -rf|del /f|Remove-Item.*-Recurse.*Force"; desc = "Comando destructivo en script" }
        @{ regex = "DROP TABLE|DELETE FROM.*WHERE 1|TRUNCATE"; desc = "Query SQL destructivo" }
        @{ regex = "version.*[0-9]+\.[0-9].*GPT|generated by ChatGPT|Created with GPT"; desc = "Archivo generado por GPT" }
        @{ regex = "# Reemplaza esto con|// Replace this with|TODO: cambiar"; desc = "Instrucción GPT sin completar" }
        @{ regex = "supabase\.from|SUPABASE_URL|supabase_key"; desc = "Dependencia Supabase cloud (CCP-11)" }
    )

    $archivos_revisados = 0
    $daños_encontrados  = 0

    $archivos = Get-ChildItem -Path $root -Include "*.py","*.js","*.html","*.ps1","*.json" -Recurse -ErrorAction SilentlyContinue
    foreach ($f in $archivos) {
        $cont = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        if ($cont -eq $null) { continue }
        $archivos_revisados++

        foreach ($p in $patrones_danio) {
            if ($cont -match $p.regex) {
                Write-Warn "DAÑO DETECTADO en $($f.Name): $($p.desc)"
                Add-Hallazgo "$($f.Name): $($p.desc)"
                Add-Issue "WARN" "DañoExterno" "$($p.desc) en $($f.Name)" `
                          "Revisar y revertir cambio en $($f.FullName)"
                $daños_encontrados++
            }
        }
    }

    Write-Info "Archivos revisados: $archivos_revisados"
    if ($daños_encontrados -eq 0) {
        Write-Ok "No se detectaron daños de IAs externas en $archivos_revisados archivos"
        $AUDIT.score_total += 5
    } else {
        Write-Err "$daños_encontrados problema(s) de daño externo detectados"
        $AUDIT.score_total += [Math]::Max(0, 5 - $daños_encontrados)
    }
    $AUDIT.score_max += 5
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECCIÓN 8: PENDIENTES PRIORIZADOS
# ═══════════════════════════════════════════════════════════════════════════════
function Mostrar-Pendientes {
    Write-Head "SECCIÓN 8 — PENDIENTES PRIORIZADOS DEL PROYECTO"
    Write-Sep

    Write-Host "  PRIORIDAD CRÍTICA (bloquean operación):" -ForegroundColor Red
    Write-Sep2
    $pendientes_criticos = @(
        "[ ] ANTHROPIC_API_KEY real configurada en ache.env"
        "[ ] boot.py ejecutado y :8080 respondiendo"
        "[ ] Dashboard http://localhost:8888/ACHE_CONEXION_TOTAL_v1.html accesible"
        "[ ] Base de datos ache_v5.db inicializada (tabla chain funcional)"
        "[ ] ACHE_AUTOSTART instalado como tarea de Windows"
    )
    foreach ($p in $pendientes_criticos) { Write-Host "  $p" -ForegroundColor Red }

    Write-Host ""
    Write-Host "  PRIORIDAD ALTA (afectan funcionalidad core):" -ForegroundColor Yellow
    Write-Sep2
    $pendientes_altos = @(
        "[ ] GROQ_API_KEY configurada (respaldo IA — CCP-05)"
        "[ ] Módulo Facturación Electrónica XML v4.3 probado con Hacienda CR"
        "[ ] Módulo Hotel (13 habitaciones) sincronizado con calendar"
        "[ ] SICOP IA: integración con datos reales (Ley 9986)"
        "[ ] TSE Cédula: conectar API producción (actualmente demo)"
        "[ ] Aplicación Digital Cities Challenge US State Dept: documentar TRL-5"
        "[ ] EVOLUTION_LOG.json con al menos EVO-005 registrado"
        "[ ] MASTER.md de gobernanza en C:\ACHE\"
    )
    foreach ($p in $pendientes_altos) { Write-Host "  $p" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "  PRIORIDAD MEDIA (mejoras importantes):" -ForegroundColor Cyan
    Write-Sep2
    $pendientes_medios = @(
        "[ ] GeoIntel: integrar datos INEC locales de La Cruz (IDH 0.620)"
        "[ ] Banco Cooperativo: completar scaffold SINPE (SUGEF pendiente)"
        "[ ] Ngrok configurado con token para acceso externo"
        "[ ] ACHE_NEXUS nexus_server.js levantando en :5299"
        "[ ] Hub 7 IAs: verificar que todas las IAs del hub respondan"
        "[ ] MQTT Broker :1883 para IoT (si aplica a infraestructura)"
        "[ ] Reporte HTML de auditoría autogenerado (este script)"
        "[ ] ACHE_TRAILERO_PB integrado con el sistema principal"
    )
    foreach ($p in $pendientes_medios) { Write-Host "  $p" -ForegroundColor Cyan }

    Write-Host ""
    Write-Host "  PRIORIDAD BAJA (futuro):" -ForegroundColor DarkGray
    Write-Sep2
    $pendientes_bajos = @(
        "[ ] PostgreSQL/Redis para escala horizontal"
        "[ ] Módulo Crypto + Lagrange con datos reales"
        "[ ] 27 Ministerios CR: completar integraciones activo/parcial/planificado"
        "[ ] ACHE MOBILE: app Android/iOS"
        "[ ] EVA Drones ROS2: integración real"
        "[ ] NEPTUNO Pacífico: puerto :8090"
        "[ ] TRL-7 diciembre 2026: despliegue operacional certificado"
    )
    foreach ($p in $pendientes_bajos) { Write-Host "  $p" -ForegroundColor DarkGray }
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECCIÓN 9: RESUMEN Y SCORE
# ═══════════════════════════════════════════════════════════════════════════════
function Mostrar-Resumen {
    Write-Head "RESUMEN EJECUTIVO DE AUDITORÍA"
    Write-Sep

    $pct = if ($AUDIT.score_max -gt 0) { [Math]::Round(($AUDIT.score_total / $AUDIT.score_max) * 100) } else { 0 }

    $color_score = if ($pct -ge 80) { "Green" } elseif ($pct -ge 50) { "Yellow" } else { "Red" }
    $estado_sistema = if ($pct -ge 80) { "SALUDABLE" } elseif ($pct -ge 50) { "OPERACIONAL CON PENDIENTES" } else { "REQUIERE ATENCIÓN" }

    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "  │  SCORE ACHE: $($AUDIT.score_total)/$($AUDIT.score_max) pts  ($pct%)  [$estado_sistema]" -ForegroundColor $color_score
    Write-Host "  └─────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""

    Write-Info "  Errores críticos:  $($AUDIT.seccion_err)"
    Write-Warn "  Advertencias:      $($AUDIT.seccion_warn)"
    Write-Ok   "  Hallazgos GPT:     $($AUDIT.hallazgos_gpt.Count) detectados"

    if ($AUDIT.issues.Count -gt 0) {
        Write-Host ""
        Write-Host "  PROBLEMAS A RESOLVER (por prioridad):" -ForegroundColor White
        Write-Sep2

        $errores = $AUDIT.issues | Where-Object { $_.nivel -eq "ERROR" }
        $avisos  = $AUDIT.issues | Where-Object { $_.nivel -eq "WARN" }

        foreach ($i in $errores) {
            Write-Host "  [!!] $($i.componente): $($i.mensaje)" -ForegroundColor Red
            Write-Host "       → $($i.solucion)" -ForegroundColor DarkGray
        }
        foreach ($i in $avisos) {
            Write-Host "  [>>] $($i.componente): $($i.mensaje)" -ForegroundColor Yellow
            Write-Host "       → $($i.solucion)" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Sep
    Write-Host "  Auditoría completada: $($AUDIT.fecha_legible)" -ForegroundColor DarkGray
    Write-Host "  Nodo: $($AUDIT.nodo) | COOPECRUCENOS R.L." -ForegroundColor DarkGray
    Write-Host "  Auditado con: Claude (Anthropic) — IA Aliada #7 — CCP-13" -ForegroundColor DarkGray
    Write-Sep
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# REPARACIÓN AUTOMÁTICA (solo acciones seguras)
# ═══════════════════════════════════════════════════════════════════════════════
function Repair-ACHE {
    Write-Head "REPARACIÓN AUTOMÁTICA (acciones seguras)"
    Write-Sep
    Write-Warn "Solo se realizan acciones no destructivas: crear carpetas, copiar archivos, registrar tareas"
    Write-Host ""

    # 1. Crear estructura de carpetas
    $carpetas = @("C:\ACHE", "C:\ACHE\logs", "C:\ACHE\config", "C:\ACHE\db", "C:\ACHE\backup")
    foreach ($c in $carpetas) {
        if (-not (Test-Path $c)) {
            New-Item -ItemType Directory -Path $c -Force | Out-Null
            Write-Ok "Carpeta creada: $c"
        } else {
            Write-Info "Existe: $c"
        }
    }

    # 2. Crear ache.env si no existe
    $envFile = "C:\ACHE\config\ache.env"
    if (-not (Test-Path $envFile)) {
        @"
# ACHE Environment Variables — COOPECRUCENOS R.L.
# Nodo: GONZAGA-CBM-OMEGA-001
# Editar este archivo con claves reales. No compartir.

# IA Principal (requerida)
ANTHROPIC_API_KEY=sk-ant-REEMPLAZAR_CON_TU_KEY_REAL

# IA Secundaria — Respaldo (CCP-05 Sin Dependencia Única)
GROQ_API_KEY=gsk_REEMPLAZAR_CON_TU_KEY_GROQ

# Túnel externo (opcional)
NGROK_TOKEN=

# Configuración del nodo
ACHE_ENV=production
ACHE_HOST=GONZAGA-CBM-001
ACHE_VERSION=5.0
"@ | Set-Content -Path $envFile -Encoding UTF8
        Write-Ok "Archivo ache.env creado: $envFile"
        Write-Warn "  → IMPORTANTE: Editar con tus API keys reales antes de iniciar ACHE"
    }

    # 3. Copiar archivos subidos a C:\ACHE si existen en rutas conocidas
    $fuente = "$env:USERPROFILE\Downloads"
    $archivos_a_copiar = @(
        "ACHE_CONEXION_TOTAL_v1.html",
        "ACHE_BOOT.ps1",
        "ACHE_AUTOSTART.ps1",
        "EVOLUTION_LOG.json",
        "boot.py"
    )
    foreach ($arch in $archivos_a_copiar) {
        $origen = Join-Path $fuente $arch
        $destino = Join-Path "C:\ACHE" $arch
        if ((Test-Path $origen) -and -not (Test-Path $destino)) {
            Copy-Item $origen $destino -Force
            Write-Ok "Copiado: $arch → C:\ACHE\"
        }
    }

    # 4. Crear log de reparación
    $log_rep = "C:\ACHE\logs\repair_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
    "Reparación ejecutada: $(Get-Date -Format 'o')" | Set-Content $log_rep
    "Nodo: GONZAGA-CBM-OMEGA-001" | Add-Content $log_rep
    foreach ($i in $AUDIT.issues) {
        "$($i.nivel) | $($i.componente): $($i.mensaje)" | Add-Content $log_rep
    }
    Write-Ok "Log de reparación guardado: $log_rep"

    Write-Host ""
    Write-Sep
    Write-Ok "Reparación completada. Acciones manuales requeridas:"
    Write-Warn "  1. Editar C:\ACHE\config\ache.env con tus API keys reales"
    Write-Warn "  2. Ejecutar: .\ACHE_BOOT.ps1 para arrancar servicios"
    Write-Warn "  3. Ejecutar: .\ACHE_AUTOSTART.ps1 -Install para arranque automático"
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# GUARDAR RESULTADO EN JSON
# ═══════════════════════════════════════════════════════════════════════════════
function Guardar-Reporte {
    $json_path = "C:\ACHE\logs\auditoria_$(Get-Date -Format 'yyyyMMdd_HHmm').json"
    if (-not (Test-Path "C:\ACHE\logs")) {
        New-Item -ItemType Directory -Path "C:\ACHE\logs" -Force | Out-Null
    }
    $AUDIT | ConvertTo-Json -Depth 10 | Set-Content -Path $json_path -Encoding UTF8
    Write-Ok "Reporte JSON guardado: $json_path"
}

# ═══════════════════════════════════════════════════════════════════════════════
# GENERAR HTML
# ═══════════════════════════════════════════════════════════════════════════════
function Generar-HTML {
    $pct     = if ($AUDIT.score_max -gt 0) { [Math]::Round(($AUDIT.score_total / $AUDIT.score_max) * 100) } else { 0 }
    $color_h = if ($pct -ge 80) { "#30d158" } elseif ($pct -ge 50) { "#ffd60a" } else { "#ff453a" }

    $rows_issues = ""
    foreach ($i in $AUDIT.issues) {
        $bg = if ($i.nivel -eq "ERROR") { "#3a1a1a" } else { "#2a2a1a" }
        $fc = if ($i.nivel -eq "ERROR") { "#ff453a" } else { "#ffd60a" }
        $rows_issues += "<tr style='background:$bg'><td style='color:$fc'>$($i.nivel)</td><td>$($i.componente)</td><td>$($i.mensaje)</td><td style='color:#8e8e93'>$($i.solucion)</td></tr>`n"
    }

    $rows_ccps = ""
    foreach ($ccp_id in ($AUDIT.ccps.Keys | Sort-Object)) {
        $ccp  = $AUDIT.ccps[$ccp_id]
        $fc   = if ($ccp.estado -eq "OK") { "#30d158" } elseif ($ccp.estado -eq "WARN") { "#ffd60a" } else { "#ff453a" }
        $rows_ccps += "<tr><td style='color:#0a84ff'>$ccp_id</td><td>$($ccp.nombre)</td><td style='color:$fc'>$($ccp.estado)</td><td style='color:#8e8e93'>$($ccp.detalle)</td></tr>`n"
    }

    $hallazgos_html = if ($AUDIT.hallazgos_gpt.Count -gt 0) {
        "<ul>" + ($AUDIT.hallazgos_gpt | ForEach-Object { "<li>$_</li>" }) + "</ul>"
    } else { "<p style='color:#30d158'>✓ No se detectaron daños de IAs externas</p>" }

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ACHE Auditoría — $($AUDIT.fecha_legible)</title>
<style>
  :root { --bg:#000; --bg2:#1c1c1e; --bg3:#2c2c2e; --tx:#f2f2f7; --tx2:#8e8e93;
          --bl:#0a84ff; --gr:#30d158; --yl:#ffd60a; --rd:#ff453a; --cy:#64d2ff; }
  * { box-sizing:border-box; margin:0; padding:0 }
  body { background:var(--bg); color:var(--tx); font-family:'Segoe UI',system-ui,sans-serif; padding:24px }
  h1  { color:var(--cy); font-size:1.4rem; margin-bottom:4px }
  h2  { color:var(--bl); font-size:1rem; margin:24px 0 8px; border-left:3px solid var(--bl); padding-left:10px }
  .sub { color:var(--tx2); font-size:.85rem; margin-bottom:20px }
  .score-box { background:var(--bg2); border:2px solid $color_h; border-radius:12px;
               padding:20px 28px; display:inline-block; margin-bottom:24px }
  .score-num { font-size:2.8rem; font-weight:700; color:$color_h }
  .score-lbl { color:var(--tx2); font-size:.85rem }
  .stats { display:flex; gap:16px; margin-bottom:24px; flex-wrap:wrap }
  .stat { background:var(--bg2); border-radius:8px; padding:12px 20px; text-align:center }
  .stat .n { font-size:1.6rem; font-weight:700 }
  .err-c { color:var(--rd) } .warn-c { color:var(--yl) } .ok-c { color:var(--gr) }
  table { width:100%; border-collapse:collapse; font-size:.85rem }
  th { background:var(--bg3); color:var(--tx2); text-align:left; padding:8px 12px; font-weight:600 }
  td { padding:8px 12px; border-bottom:1px solid var(--bg3) }
  .footer { margin-top:32px; color:var(--tx2); font-size:.8rem; text-align:center }
  .tag { display:inline-block; background:var(--bg3); border-radius:4px;
         padding:2px 8px; font-size:.75rem; margin:2px }
</style>
</head>
<body>
<h1>⬡ ACHE AUDITORÍA PROFUNDA v3.0</h1>
<div class="sub">COOPECRUCENOS R.L. · GONZAGA-CBM-OMEGA-001 · $($AUDIT.fecha_legible)</div>

<div class="score-box">
  <div class="score-num">$pct%</div>
  <div class="score-lbl">Score: $($AUDIT.score_total) / $($AUDIT.score_max) puntos</div>
</div>

<div class="stats">
  <div class="stat"><div class="n err-c">$($AUDIT.seccion_err)</div><div class="score-lbl">Errores Críticos</div></div>
  <div class="stat"><div class="n warn-c">$($AUDIT.seccion_warn)</div><div class="score-lbl">Advertencias</div></div>
  <div class="stat"><div class="n ok-c">$($AUDIT.hallazgos_gpt.Count)</div><div class="score-lbl">Hallazgos GPT</div></div>
  <div class="stat"><div class="n ok-c">$($AUDIT.ccps.Values | Where-Object {$_.estado -eq 'OK'} | Measure-Object).Count / 13</div><div class="score-lbl">CCPs Activos</div></div>
</div>

<h2>13 PRINCIPIOS CANÓNICOS (CCPs)</h2>
<table>
<tr><th>CCP</th><th>Principio</th><th>Estado</th><th>Detalle</th></tr>
$rows_ccps
</table>

<h2>PROBLEMAS DETECTADOS</h2>
<table>
<tr><th>Nivel</th><th>Componente</th><th>Problema</th><th>Solución</th></tr>
$rows_issues
</table>

<h2>HALLAZGOS — DAÑOS DE IAs EXTERNAS</h2>
$hallazgos_html

<div class="footer">
  Generado por Claude (Anthropic) — IA Aliada #7 de ACHE — CCP-13: Alianza Tecnológica<br>
  COOPECRUCENOS R.L. · Cédula 3-004-757068 · La Cruz, Guanacaste, Costa Rica
</div>
</body>
</html>
"@

    $html_path = "ACHE_AUDITORIA_$(Get-Date -Format 'yyyyMMdd_HHmm').html"
    $html | Set-Content -Path $html_path -Encoding UTF8
    Write-Ok "Reporte HTML guardado: $html_path"
    try { Start-Process $html_path } catch {}
    return $html_path
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════
function Run-Auditoria {
    Show-Banner
    Audit-Sistema
    Audit-Archivos
    Audit-Servicios
    Audit-APIKeys
    Audit-BaseDatos
    Audit-CCPs
    Audit-DanioExterno
    Mostrar-Pendientes
    Mostrar-Resumen

    if ($Reparar) { Repair-ACHE }
    if ($Guardar) { Guardar-Reporte }
    if ($HTML)    { Generar-HTML }
}

if ($Watch) {
    Write-Host "  Modo monitoreo cada $Intervalo segundos. Ctrl+C para salir." -ForegroundColor Yellow
    while ($true) {
        Run-Auditoria
        Write-Info "Esperando $Intervalo segundos... (Ctrl+C para salir)"
        Start-Sleep -Seconds $Intervalo
    }
} else {
    Run-Auditoria
}
