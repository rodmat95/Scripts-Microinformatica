#requires -version 5.1
#Editor: Rodrigo Ortiz

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Agresivo,        # Acciones extra: hibernación OFF, ReservedStorage OFF, DISM component cleanup
    [switch]$Forzar,           # Suprime confirmaciones
    [switch]$NoCleanMgr,       # NO ejecutar CleanMgr
    [switch]$NoBCDNumProc,     # NO aplicar bcdedit numproc
    [switch]$NoTempDomibco,    # NO limpiar usuarios TEMP
    [switch]$NoOfficeCache,    # NO limpiar OfficeFileCache
    [switch]$NoOstReport       # NO generar reporte de OST grandes
)

# ========================= BASICO =========================
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Stop-ServiceSafe([string]$Name){
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if($null -ne $svc -and $svc.Status -ne 'Stopped'){
        try { Stop-Service -Name $Name -Force -ErrorAction Stop; Write-Host "Servicio detenido: $Name" -ForegroundColor Yellow }
        catch { Write-Warning ("No se pudo detener {0}: {1}" -f $Name, $_.Exception.Message) }
    }
}

function Start-ServiceSafe([string]$Name){
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if($null -ne $svc -and $svc.Status -ne 'Running'){
        try { Start-Service -Name $Name -ErrorAction Stop; Write-Host "Servicio iniciado: $Name" -ForegroundColor Yellow }
        catch { Write-Warning ("No se pudo iniciar {0}: {1}" -f $Name, $_.Exception.Message) }
    }
}

function Remove-PathSafe([string]$Path){
    if(Test-Path -LiteralPath $Path){
        try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop }
        catch {
            try { Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Remove-Item -Recurse -Force -ErrorAction Stop } catch {}
        }
    }
}

# =============== LIMPIEZA POR ANTIGÜEDAD ==================
function Remove-FilesByAge {
    param(
        [string[]]$Patterns,
        [int]$Days
    )

    $basePath = "C:\Users"
    $exclude = '\\(Desktop|Escritorio)\\'
    $limitDate = (Get-Date).AddDays(-$Days)

    $profiles = Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notin @('Public','Default','Default User','All Users') -and
        -not ($_.Name.StartsWith('WDAGUtilityAccount'))
    }

    foreach ($pattern in $Patterns) {

        Write-Host "Buscando $pattern > $Days días" -ForegroundColor Yellow

        foreach ($profile in $profiles) {

            Get-ChildItem -Path $profile.FullName -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
            Where-Object {
                $_.LastWriteTime -lt $limitDate -and
                $_.FullName -notmatch $exclude
            } |
            ForEach-Object {
                Write-Host "Eliminando: $($_.FullName)" -ForegroundColor DarkYellow
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# ===================== CACHE USUARIO ======================
function Clear-UserTempAndCaches {
    Write-Host "Limpieza de temporales por usuarios..." -ForegroundColor Cyan

    $userRoots = Get-ChildItem -Directory 'C:\Users' -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notin @('Public','Default','Default User','All Users') -and
        -not ($_.Name.StartsWith('WDAGUtilityAccount'))
    }

    foreach($u in $userRoots){

        $paths = @(
            (Join-Path -Path $u.FullName -ChildPath 'AppData\Local\Temp\*')

            # Chrome
            (Join-Path -Path $u.FullName -ChildPath 'AppData\Local\Google\Chrome\User Data\Default\Cache\*')
            (Join-Path -Path $u.FullName -ChildPath 'AppData\Local\Google\Chrome\User Data\Default\Code Cache\*')
            (Join-Path -Path $u.FullName -ChildPath 'AppData\Local\Google\Chrome\User Data\Default\GPUCache\*')
            (Join-Path -Path $u.FullName -ChildPath 'AppData\Local\Google\Chrome\User Data\Default\Service Worker\CacheStorage\*')

            # Edge
            (Join-Path -Path $u.FullName -ChildPath 'AppData\Local\Microsoft\Edge\User Data\Default\Cache\*')
            (Join-Path -Path $u.FullName -ChildPath 'AppData\Local\Microsoft\Edge\User Data\Default\Cache\Cache_Data\*')
            (Join-Path -Path $u.FullName -ChildPath 'AppData\Local\Microsoft\Edge\User Data\Default\Code Cache\*')
            (Join-Path -Path $u.FullName -ChildPath 'AppData\Local\Microsoft\Edge\User Data\Default\GPUCache\*')
            (Join-Path -Path $u.FullName -ChildPath 'AppData\Local\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage\*')
        )
        foreach($p in $paths){

            try { Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue }
            catch { }
        }
    }
}

# ===================== OFFICE CACHE =======================
function Clear-OfficeFileCache {
    Write-Host "Limpieza de OfficeFileCache (Office 16.0)..." -ForegroundColor Cyan

    # (Opcional) cerrar apps de Office para evitar archivos bloqueados
    $officeProcs = @('winword','excel','powerpnt','outlook','onenote','msaccess')
    foreach($p in $officeProcs){
        Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    $userRoots = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notin @('Public','Default','Default User','All Users') -and
        -not ($_.Name.StartsWith('WDAGUtilityAccount'))
    }

    foreach ($u in $userRoots) {

        $cachePath = Join-Path -Path $u.FullName -ChildPath "AppData\Local\Microsoft\Office\16.0\OfficeFileCache"

        if (Test-Path -LiteralPath $cachePath) {
            try {
                # Borra SOLO el contenido, no la carpeta base
                Remove-Item -LiteralPath (Join-Path -Path $cachePath -ChildPath '*') -Recurse -Force -ErrorAction Stop
                Write-Host ("Cache Office limpiada: {0}" -f $cachePath) -ForegroundColor Green
            }
            catch {
                Write-Warning ("No se pudo limpiar: {0}. Detalle: {1}" -f $cachePath, $_.Exception.Message)
            }
        }
    }

    Write-Host "Limpieza de OfficeFileCache completada." -ForegroundColor Cyan
}

# ================ LIMPIEZA DE COMPONENTES =================
function Invoke-StoreCleanup {
    Write-Host "DISM: Analizando Component Store (AnalyzeComponentStore)..." -ForegroundColor Yellow

    # Capturamos la salida como texto para detectar si recomienda limpieza
    $analysisText = (& dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 | Out-String)

    # Detectar recomendación en EN y ES (simple y efectivo)
    $recommended = $false
    if ($analysisText -match '(?im)Component Store Cleanup Recommended\s*:\s*Yes') { $recommended = $true }
    elseif ($analysisText -match '(?im)Recomendad\w*\s*:\s*S[ií]') { $recommended = $true }

    if ($recommended) {
        Write-Host "DISM: Se recomienda limpieza. Ejecutando StartComponentCleanup..." -ForegroundColor Yellow
        & dism.exe /Online /Cleanup-Image /StartComponentCleanup | Out-Host
        Write-Host "DISM: StartComponentCleanup finalizado." -ForegroundColor Green
    }
    else {
        Write-Host "DISM: No se recomienda limpieza. Se omite StartComponentCleanup." -ForegroundColor DarkGray
    }
}

# ======================= REPORTE OST ======================
function Show-OutlookOst {
    [CmdletBinding()]
    param(
        [string]$BaseUsersPath = 'C:\Users',
        [int]$ThresholdGB = 50,
        [switch]$SoloCriticos,   # si lo activas, solo muestra >= ThresholdGB
        [switch]$PassThru        # si lo activas, además devuelve los objetos
    )

    Write-Host ("Revisando OST de Outlook (umbral: {0} GB)..." -f $ThresholdGB) -ForegroundColor Cyan

    $excludeProfiles = @('Public','Default','Default User','All Users')

    $profileDirs = Get-ChildItem -Path $BaseUsersPath -Directory -ErrorAction SilentlyContinue | Where-Object {
        $excludeProfiles -notcontains $_.Name -and
        -not ($_.Name.StartsWith('WDAGUtilityAccount'))
    }

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($dir in $profileDirs) {
        $outlookPath = Join-Path -Path $dir.FullName -ChildPath 'AppData\Local\Microsoft\Outlook'

        if (Test-Path -LiteralPath $outlookPath) {
            Get-ChildItem -Path $outlookPath -Filter '*.ost' -File -ErrorAction SilentlyContinue | ForEach-Object {
                $sizeGB = [math]::Round($_.Length / 1GB, 3)

                $obj = [pscustomobject]@{
                    UsuarioPerfil = $dir.Name
                    TamanoGB      = $sizeGB
                    Ruta          = $_.FullName
                    SuperaUmbral  = ($sizeGB -ge $ThresholdGB)
                }

                $results.Add($obj) | Out-Null
            }
        }
    }

    if ($results.Count -eq 0) {
        Write-Host "No se encontraron archivos OST en perfiles de usuario." -ForegroundColor DarkGray
        if($PassThru){ return @() }
        return
    }

    # Selección para mostrar
    $toShow = $results | Sort-Object TamanoGB -Descending
    if($SoloCriticos){
        $toShow = $toShow | Where-Object SuperaUmbral
    }

    if(-not $toShow -or $toShow.Count -eq 0){
        Write-Host ("No hay OST que superen o igualen {0} GB." -f $ThresholdGB) -ForegroundColor Green
    }
    else {
        Write-Host "`n=== REPORTE OST (ordenado por tamaño) ===" -ForegroundColor Cyan
        $toShow |
            Select-Object TamanoGB, Ruta, SuperaUmbral |
            Format-Table -AutoSize | Out-Host

        # Warnings solo para críticos (para que salte en log)
        $criticos = $results | Where-Object SuperaUmbral | Sort-Object TamanoGB -Descending
        foreach($c in $criticos){
            Write-Warning ("OST grande detectado (>= {0} GB): Perfil={1} Tamaño={2} GB Ruta={3}" -f $ThresholdGB, $c.UsuarioPerfil, $c.TamanoGB, $c.Ruta)
        }
    }

    if($PassThru){
        return $results
    }
}

# ===================== USUARIOS TEMP ======================
function Clear-TempDomibcoFolders {
    $basePath = 'C:\Users'
    $pattern  = 'TEMP.DOMIBCO.*'

    Write-Host ("Limpieza de carpetas temporales de sesión: {0}\{1}" -f $basePath, $pattern) -ForegroundColor Cyan

    $folders = Get-ChildItem -Path $basePath -Directory -Filter $pattern -Force -ErrorAction SilentlyContinue

    if(-not $folders -or $folders.Count -eq 0){
        Write-Host "No se encontraron carpetas TEMP.DOMIBCO.*" -ForegroundColor DarkGray
        return
    }

    foreach ($folder in $folders) {
        Write-Host ("Procesando: {0}" -f $folder.FullName) -ForegroundColor Cyan

        try {
            Remove-Item -LiteralPath $folder.FullName -Recurse -Force -ErrorAction Stop
            Write-Host ("Eliminada: {0}" -f $folder.FullName) -ForegroundColor Green
        }
        catch {
            Write-Warning ("No se pudo eliminar completamente la carpeta: {0}. Motivo: {1}" -f $folder.FullName, $_.Exception.Message)
            Write-Host "Intentando eliminar solo el contenido interno..." -ForegroundColor Yellow

            try {
                Get-ChildItem -LiteralPath $folder.FullName -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

                Write-Host ("Contenido eliminado: {0}" -f $folder.FullName) -ForegroundColor Yellow
            }
            catch {
                Write-Warning ("No se pudo eliminar el contenido de: {0}. Motivo: {1}" -f $folder.FullName, $_.Exception.Message)
            }
        }
    }

    Write-Host "Limpieza TEMP.DOMIBCO.* finalizada." -ForegroundColor Cyan
}

# ================ USUARIOS POR ANTIGÜEDAD =================
function Remove-InactiveProfiles {
    [CmdletBinding()]
    param (
        # Parámetro para agregar usuarios extra (opcional)
        [string[]]$UsuariosExtra = @(),
        [int]$MesesInactividad = 6
    )

    # 1. Lista blanca fija de sistema
    $UsuariosFijos = @("administrador", "admlocalsrvwindows", "homeuser")
    
    # 2. Combinar ambas listas en una sola lista de exclusión
    $UsuariosExtraLimpios = $UsuariosExtra | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $TotalUsuariosASalvar = $UsuariosFijos + $UsuariosExtraLimpios

    # 3. Calcular la fecha límite
    $FechaLimite = (Get-Date).AddMonths(-$MesesInactividad)
    Write-Host "Buscando perfiles sin actividad desde antes de: $($FechaLimite.ToString('dd/MM/yyyy'))`n" -ForegroundColor Cyan

    # 4. Buscar y filtrar los perfiles
    $PerfilesAEliminar = Get-CimInstance -ClassName Win32_UserProfile | Where-Object {
        $_.Special -eq $False -and 
        $_.LocalPath -notlike "*\Public" -and 
        # Aquí se evalúa la lista combinada completa
        (Split-Path $_.LocalPath -Leaf) -notin $TotalUsuariosASalvar -and 
        ($_.LastUseTime -lt $FechaLimite -or $_.LastUseTime -eq $Null)
    }

    # 5. Validar si se encontraron perfiles
    if ($Null -eq $PerfilesAEliminar -or $PerfilesAEliminar.Count -eq 0) {
        Write-Host "No se encontró ningún usuario sin actividad de $MesesInactividad meses." -ForegroundColor Red
    } else {
        # 6. Proceder a eliminar de forma segura
        foreach ($Perfil in $PerfilesAEliminar) {
            $Nombre = Split-Path $Perfil.LocalPath -Leaf
            $UltimaConexion = if ($Perfil.LastUseTime) { $Perfil.LastUseTime.ToString("dd/MM/yyyy") } else { "Nunca" }
            
            Write-Host "Eliminando perfil inactivo: $Nombre (Última vez: $UltimaConexion)..." -ForegroundColor Yellow
            
            # Ejecuta la eliminación
            $Perfil | Remove-CimInstance
            Write-Host "¡Perfil $Nombre eliminado con éxito!`n" -ForegroundColor Green
        }
    }
}

# =================== LIMPIAR USUARIOS =====================
function Invoke-CleanUserProfiles {
    function Get-Size($Path) {
        try {
            $sum = (Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum

            if ($null -eq $sum) { return 0 }

            return :Round(($sum / 1MB), 2)
        }
        catch {
            return 0
        }
    }

    $Usuarios = Get-CimInstance Win32_UserProfile |
        Where-Object { $_.LocalPath -like "C:\Users\*" -and $_.Special -eq $false } |
        ForEach-Object { Get-Item $_.LocalPath }

    foreach ($User in $Usuarios) {

        $Usuario = $User.Name
        $RaizUser = $User.FullName
        $TotalLiberado = 0

        Write-Host "`n===== $Usuario =====" -ForegroundColor Cyan

        # CARPETAS PERSONALES
        $CarpetasPers = @("Documents","Downloads","Pictures","Videos")
        $ExtBasura = ".tmp",".log",".old",".exe",".msi"

        foreach ($c in $CarpetasPers) {
            $RutaC = "$RaizUser\$c"

            if (Test-Path $RutaC) {
                $pesoAntes = Get-Size $RutaC

                $Archivos = Get-ChildItem $RutaC -Recurse -File -ErrorAction SilentlyContinue |
                            Where-Object { $_.Extension -in $ExtBasura }

                foreach ($f in $Archivos) {
                    if ($f -is [System.IO.FileInfo]) {

                        $sizeMB = :Round(($f.Length / 1MB), 2)
                        $TotalLiberado += $sizeMB

                        Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
                    }
                }

                $pesoDespues = Get-Size $RutaC
                Write-Host "$c : $pesoAntes MB -> $pesoDespues MB"
            }
        }

        # APPDATA LOCAL
        $AppDataLocal = "$RaizUser\AppData\Local"

        if (Test-Path $AppDataLocal) {
            $Programas = Get-ChildItem $AppDataLocal -Directory

            foreach ($Prog in $Programas) {
                $pesoProg = Get-Size $Prog.FullName

                if ($pesoProg -gt 1) {
                    Write-Host "Programa: $($Prog.Name) -> $pesoProg MB"

                    $Basura = Get-ChildItem $Prog.FullName -Directory -Recurse -ErrorAction SilentlyContinue |
                              Where-Object { $_.Name -match "Cache|Logs|Temp|CrashDumps" }

                    foreach ($b in $Basura) {
                        $pBasura = Get-Size $b.FullName

                        if ($pBasura -gt 0.1) {
                            $TotalLiberado += $pBasura
                            Remove-Item $b.FullName -Recurse -Force -ErrorAction SilentlyContinue
                            Write-Host "   [X] $($b.Name) ($pBasura MB)" -ForegroundColor Red
                        }
                    }
                }
            }
        }
        Write-Host "TOTAL LIBERADO: $TotalLiberado MB" -ForegroundColor Green
    }
}

# ==========================================================
function Set-CleanMgrSageSet {
    # Configura StateFlags1337 = 2 en categorías de CleanMgr
    $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $subkeys = @(
        'Previous Installations','Active Setup Temp Folders','BranchCache','Downloaded Program Files',
        'GameNewsFiles','GameStatisticsFiles','GameUpdateFiles','Internet Cache Files',
        'Memory Dump Files','Offline Pages Files','Old ChkDsk Files','Recycle Bin',
        'Service Pack Cleanup','Setup Log Files','System error memory dump files','System error minidump files',
        'Temporary Files','Temporary Setup Files','Temporary Sync Files','Thumbnail Cache',
        'Update Cleanup','Upgrade Discarded Files','User file versions','Windows Defender',
        'Windows Error Reporting Archive Files','Windows Error Reporting Queue Files',
        'Windows Error Reporting System Archive Files','Windows Error Reporting System Queue Files',
        'Windows ESD installation files','Windows Upgrade Log Files'
    )
    foreach($k in $subkeys){
        $path = Join-Path $base $k
        if(Test-Path $path){
            try { New-ItemProperty -Path $path -Name 'StateFlags1337' -Value 2 -PropertyType DWord -Force | Out-Null } catch {}
        }
    }
}

# ----------------------------------------------------------
# ========================= INICIO =========================
# ----------------------------------------------------------
if(-not (Test-Admin)){
    Write-Error "Ejecute este script en una consola de PowerShell **como Administrador**."
    exit 1
}

if ($Forzar) {
    $ConfirmPreference = 'None'
    Write-Host "Modo FORZADO activado (sin confirmaciones)" -ForegroundColor Yellow
}

$ComputerName = $env:COMPUTERNAME
Write-Host "Equipo: $ComputerName" -ForegroundColor Green

# Transcript (log)
$logDir = 'C:\Windows\Temp\CleanupLogs'
if(-not (Test-Path $logDir)){ New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logPath = Join-Path $logDir ("Cleanup_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $logPath -ErrorAction SilentlyContinue | Out-Null
Write-Host "Log: $logPath" -ForegroundColor DarkGray

# Espacio inicial
$initialFree = (Get-PSDrive -Name C).Free

try {
    # --- bcdedit numproc (POR DEFECTO: ON) ---
    if(-not $NoBCDNumProc){
        try{
            # Equivalente a %NUMBER_OF_PROCESSORS% (procesadores lógicos)
            $numproc = [int]$env:NUMBER_OF_PROCESSORS
            if($numproc -gt 0){
                Write-Host "Aplicando bcdedit numproc = $numproc (por defecto)..." -ForegroundColor Yellow
                bcdedit /set {current} numproc $numproc | Out-Null
            } else {
                Write-Warning "No se pudo determinar NUMBER_OF_PROCESSORS; se omite bcdedit."
            }
        } catch { Write-Warning "bcdedit numproc falló: $($_.Exception.Message)" }
    } else {
        Write-Host "Omitiendo bcdedit numproc (NoBCDNumProc)." -ForegroundColor DarkGray
    }

    # --- Limpieza por Perfil ---
    if ($ComputerName -match "ADN|EDN|EDR|ABS|EBS|ECP|RBS|RP") {

        Remove-FilesByAge @("*.ost","*.ost.corrupt") 7
        Remove-FilesByAge @("*.pdf","*.jpg","*.png") 60
        Remove-FilesByAge @("*.zip","*.crdownload") 2

    }
    elseif ($ComputerName -match "JBS|JN|GA") {

        Remove-FilesByAge @("*.ost") 15
        Remove-FilesByAge @("*.pdf","*.jpg") 180

    }

    # --- Papelera de reciclaje (todos los usuarios) ---
    Write-Host "Vaciando Papelera de reciclaje..." -ForegroundColor Cyan
    try { 
		Clear-RecycleBin -Force -ErrorAction SilentlyContinue
		Get-ChildItem "C:\$Recycle.Bin" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
	} catch {}

    # --- Detener servicios relacionados con Windows Update / ConfigMgr ---
    'CcmExec','bits','wuauserv','appidsvc' | ForEach-Object { Stop-ServiceSafe $_ }

    # --- Limpiezas de sistema ---
    Write-Host "Limpieza de carpetas de sistema..." -ForegroundColor Cyan
    Remove-PathSafe -Path "$env:SystemRoot\SoftwareDistribution\Download"
    #! Remove-PathSafe -Path "$env:SystemRoot\SoftwareDistribution\*"
    if($Agresivo){
        Remove-PathSafe "$env:SystemRoot\Prefetch\*"
    }
    Remove-PathSafe -Path "$env:SystemRoot\Temp\*"
    Remove-PathSafe -Path "$env:SystemRoot\Logs\*"
    Remove-PathSafe -Path "$env:SystemRoot\ccmcache\*"
    Remove-PathSafe -Path "C:\ProgramData\Microsoft\Diagnosis\*"
    Remove-PathSafe -Path "C:\Windows\ccmcache\*"
    Remove-PathSafe -Path "C:\swsetup"
    
    # --- Limpiezas de apps específicas ---
    Remove-PathSafe -Path "C:\Mibanco\Aplicativos\Cliente\KBSeguridad\"
    Remove-PathSafe -Path "C:\Mibanco\Aplicativos\Cliente\GlobalProtect\"

    # --- Limpiezas de Topaz dinámico ---
	Get-ChildItem -Path C:\ -Directory -Depth 1 -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^Topaz' } |
    ForEach-Object { Remove-PathSafe $_.FullName }

    # --- Cerrar navegadores y limpiar temporales/cachés por usuario ---
    Write-Host "Cerrando procesos de navegadores..." -ForegroundColor Cyan
    foreach($p in 'chrome','msedge'){ Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
    Clear-UserTempAndCaches

    # --- Limpieza OfficeFileCache ---
    if(-not $NoOfficeCache){
        Clear-OfficeFileCache
    } else {
        Write-Host "Omitiendo limpieza OfficeFileCache (NoOfficeCache)." -ForegroundColor DarkGray
    }

    # --- Reporte OST ---
    if(-not $NoOstReport){
        Show-OutlookOst -ThresholdGB 50
    } else {
        Write-Host "Omitiendo reporte de OST (NoOstReport)." -ForegroundColor DarkGray
    }

    # --- Limpieza de usuarios TEMP ---
    if(-not $NoTempDomibco){
        Clear-TempDomibcoFolders
    } else {
        Write-Host "Omitiendo limpieza de carpetas temporales de sesión (NoTempDomibco)" -ForegroundColor DarkGray
    }

    # --- Limpieza de usuarios OLD ---
    Remove-InactiveProfiles -UsuariosExtra "" -MesesInactividad 6

	# --- Limpiar archivos de Usuarios ---
	Invoke-CleanUserProfiles

    # --- Reiniciar servicios ---
    'bits','wuauserv','appidsvc','CcmExec' | ForEach-Object { Start-ServiceSafe $_ }

    # --- Desactivar telemetría (solo detener) ---
    Stop-ServiceSafe 'DiagTrack'

    # --- CleanMgr (POR DEFECTO: ON) ---
    if(-not $NoCleanMgr){
        Write-Host "Configurando CleanMgr..." -ForegroundColor Yellow
        Set-CleanMgrSageSet
        $cleanmgr = "$env:SystemRoot\System32\cleanmgr.exe"
        if(Test-Path $cleanmgr){
            Write-Host "Ejecutando CleanMgr /sagerun:1337..." -ForegroundColor Yellow
            Start-Process -FilePath $cleanmgr -ArgumentList '/sagerun:1337' -Wait -WindowStyle Hidden
        } else {
            Write-Warning "CleanMgr no encontrado en este equipo."
        }
    } else {
        Write-Host "Omitiendo CleanMgr (NoCleanMgr)." -ForegroundColor DarkGray
    }

    # --- AnalyzeComponentStore > StartComponentCleanup  ---
    Invoke-StoreCleanup

    # --- Acciones agresivas (opcional) ---
    if($Agresivo){
        Write-Host "Aplicando acciones agresivas (ReservedStorage OFF, hibernación OFF, DISM cleanup)..." -ForegroundColor Yellow
        try { dism.exe /Online /Set-ReservedStorageState /State:Disabled | Out-Null } catch { Write-Warning "No se pudo desactivar ReservedStorage." }
        try { powercfg.exe /hibernate off | Out-Null } catch { Write-Warning "No se pudo desactivar hibernación." }
        try { Dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet | Out-Null } catch { Write-Warning "DISM StartComponentCleanup falló." }
    }

} finally {
    $finalFree = (Get-PSDrive -Name C).Free
    $freedMB = [math]::Round(($finalFree - $initialFree) / 1MB, 2)

    if($freedMB -ge 0){
        Write-Host ("Espacio liberado aproximado: {0} MB" -f $freedMB) -ForegroundColor Green
    } else {
        Write-Host ("Cambio de espacio libre: {0} MB (negativo = consumo durante ejecución)" -f $freedMB) -ForegroundColor Yellow
    }

    Write-Host "`n$computer`n$computer`n" -ForegroundColor Green
    Write-Host "La limpieza ha finalizado. Se recomienda **reiniciar** el equipo." -ForegroundColor Cyan
    Stop-Transcript | Out-Null
}

# SIG # Begin signature block
# MIIb4wYJKoZIhvcNAQcCoIIb1DCCG9ACAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUV1ZyVCWNLDuGe8OSaHw+OIr6
# wvigghZOMIIDEDCCAfigAwIBAgIQOxXWzv310LtNUY9OArWLhjANBgkqhkiG9w0B
# AQUFADAgMR4wHAYDVQQDDBVGaXJtYSBTY3JpcHRzIFNPUE9SVEUwHhcNMjYwMTIy
# MjA0ODAyWhcNMjcwMTIyMjEwODAyWjAgMR4wHAYDVQQDDBVGaXJtYSBTY3JpcHRz
# IFNPUE9SVEUwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC3CzEDZmK3
# jNiRy1i+w1aXKaxbqtPyJfvBDBKzCBCDMbSmlNv0Y2ceDvD5kvBkUbdRStqzUzDR
# tjja//8SpKMYDM8gB+Jh8E03DdqSn6Np1QEZtQhRc1oK7xA7LOyV1pTIJQAsumZy
# LQ6sW5rLBljVg71Mwzo05iJRaxOcnafa2wEkfEUe6ifbxjbnJxy704TyPH2KfNXw
# YefdxIBH5q4CkqalnpeHO8QCMEmi1j9kwxHvxXXubsNG8Lf5tEqQ0kPSeW34gRZb
# DOAvr9KaMeyXVqOj0y+ShXz/s/ZtEmJGMU2xiZ7I7n/XIfAH+3nhcA4E/F212RHk
# Ate8IQJg53uBAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggr
# BgEFBQcDAzAdBgNVHQ4EFgQUSqR57IxubDQmBYikR51iOg0KrbAwDQYJKoZIhvcN
# AQEFBQADggEBAH3zz/fBHec2lhe0uYMNq1/GxQ88huA1fwy2hhjQyaS5FqEDH6NN
# zDqKC9f9T01HCvfMTp80FbdenBwgO1x5zlvSSQeI19RWenyMz/4IT55NlpLtFnyf
# sRdN6Q0KGBpdSkJzxSrcxgJWyXgQjtokpzht5nbRfl+0yQtOqEiBWazcLzkFOW0B
# qUpZs8cIfpp4+LV5bgc7iShCnG6x0oxvh43Xl/aAyGSY0puC6bETrw0TrOuH3T7M
# W1Rb8LVVnH8whL/vpEsAVtx6xlx9ISFwNgQd3RhGaLvhbU5L8H+wO709Y6sWtsWg
# jX8Rzs6E6WbGvTyLDzg7qhBBohiPo7GihO0wggWNMIIEdaADAgECAhAOmxiO+dAt
# 5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAwMDBa
# Fw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lD
# ZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
# ggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3E
# MB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKy
# unWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsF
# xl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU1
# 5zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJB
# MtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObUR
# WBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6
# nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxB
# YKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5S
# UUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+x
# q4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6MIIB
# NjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwP
# TzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8EBAMC
# AYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdp
# Y2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNv
# bS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0
# aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENB
# LmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCgv0Nc
# Vec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQTSnov
# Lbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh65Zy
# oUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSwuKFW
# juyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPF
# mCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjDTZ9z
# twGpn1eqXijiuZQwgga0MIIEnKADAgECAhANx6xXBf8hmS5AQyIMOkmGMA0GCSqG
# SIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMx
# GTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRy
# dXN0ZWQgUm9vdCBHNDAeFw0yNTA1MDcwMDAwMDBaFw0zODAxMTQyMzU5NTlaMGkx
# CzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4
# RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYg
# MjAyNSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC0eDHTCphB
# cr48RsAcrHXbo0ZodLRRF51NrY0NlLWZloMsVO1DahGPNRcybEKq+RuwOnPhof6p
# vF4uGjwjqNjfEvUi6wuim5bap+0lgloM2zX4kftn5B1IpYzTqpyFQ/4Bt0mAxAHe
# HYNnQxqXmRinvuNgxVBdJkf77S2uPoCj7GH8BLuxBG5AvftBdsOECS1UkxBvMgEd
# gkFiDNYiOTx4OtiFcMSkqTtF2hfQz3zQSku2Ws3IfDReb6e3mmdglTcaarps0wjU
# jsZvkgFkriK9tUKJm/s80FiocSk1VYLZlDwFt+cVFBURJg6zMUjZa/zbCclF83bR
# VFLeGkuAhHiGPMvSGmhgaTzVyhYn4p0+8y9oHRaQT/aofEnS5xLrfxnGpTXiUOeS
# LsJygoLPp66bkDX1ZlAeSpQl92QOMeRxykvq6gbylsXQskBBBnGy3tW/AMOMCZIV
# NSaz7BX8VtYGqLt9MmeOreGPRdtBx3yGOP+rx3rKWDEJlIqLXvJWnY0v5ydPpOjL
# 6s36czwzsucuoKs7Yk/ehb//Wx+5kMqIMRvUBDx6z1ev+7psNOdgJMoiwOrUG2Zd
# SoQbU2rMkpLiQ6bGRinZbI4OLu9BMIFm1UUl9VnePs6BaaeEWvjJSjNm2qA+sdFU
# eEY0qVjPKOWug/G6X5uAiynM7Bu2ayBjUwIDAQABo4IBXTCCAVkwEgYDVR0TAQH/
# BAgwBgEB/wIBADAdBgNVHQ4EFgQU729TSunkBnx6yuKQVvYv1Ensy04wHwYDVR0j
# BBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0
# cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0
# cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8E
# PDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVz
# dGVkUm9vdEc0LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEw
# DQYJKoZIhvcNAQELBQADggIBABfO+xaAHP4HPRF2cTC9vgvItTSmf83Qh8WIGjB/
# T8ObXAZz8OjuhUxjaaFdleMM0lBryPTQM2qEJPe36zwbSI/mS83afsl3YTj+IQhQ
# E7jU/kXjjytJgnn0hvrV6hqWGd3rLAUt6vJy9lMDPjTLxLgXf9r5nWMQwr8Myb9r
# EVKChHyfpzee5kH0F8HABBgr0UdqirZ7bowe9Vj2AIMD8liyrukZ2iA/wdG2th9y
# 1IsA0QF8dTXqvcnTmpfeQh35k5zOCPmSNq1UH410ANVko43+Cdmu4y81hjajV/gx
# dEkMx1NKU4uHQcKfZxAvBAKqMVuqte69M9J6A47OvgRaPs+2ykgcGV00TYr2Lr3t
# y9qIijanrUR3anzEwlvzZiiyfTPjLbnFRsjsYg39OlV8cipDoq7+qNNjqFzeGxcy
# tL5TTLL4ZaoBdqbhOhZ3ZRDUphPvSRmMThi0vw9vODRzW6AxnJll38F0cuJG7uEB
# YTptMSbhdhGQDpOXgpIUsWTjd6xpR6oaQf/DJbg3s6KCLPAlZ66RzIg9sC+NJpud
# /v4+7RWsWCiKi9EOLLHfMR2ZyJ/+xhCx9yHbxtl5TPau1j/1MIDpMPx0LckTetiS
# uEtQvLsNz3Qbp7wGWqbIiOWCnb5WqxL3/BAPvIXKUjPSxyZsq8WhbaM2tszWkPZP
# ubdcMIIG7TCCBNWgAwIBAgIQCoDvGEuN8QWC0cR2p5V0aDANBgkqhkiG9w0BAQsF
# ADBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNV
# BAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hB
# MjU2IDIwMjUgQ0ExMB4XDTI1MDYwNDAwMDAwMFoXDTM2MDkwMzIzNTk1OVowYzEL
# MAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJE
# aWdpQ2VydCBTSEEyNTYgUlNBNDA5NiBUaW1lc3RhbXAgUmVzcG9uZGVyIDIwMjUg
# MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANBGrC0Sxp7Q6q5gVrMr
# V7pvUf+GcAoB38o3zBlCMGMyqJnfFNZx+wvA69HFTBdwbHwBSOeLpvPnZ8ZN+vo8
# dE2/pPvOx/Vj8TchTySA2R4QKpVD7dvNZh6wW2R6kSu9RJt/4QhguSssp3qome7M
# rxVyfQO9sMx6ZAWjFDYOzDi8SOhPUWlLnh00Cll8pjrUcCV3K3E0zz09ldQ//nBZ
# ZREr4h/GI6Dxb2UoyrN0ijtUDVHRXdmncOOMA3CoB/iUSROUINDT98oksouTMYFO
# nHoRh6+86Ltc5zjPKHW5KqCvpSduSwhwUmotuQhcg9tw2YD3w6ySSSu+3qU8DD+n
# igNJFmt6LAHvH3KSuNLoZLc1Hf2JNMVL4Q1OpbybpMe46YceNA0LfNsnqcnpJeIt
# K/DhKbPxTTuGoX7wJNdoRORVbPR1VVnDuSeHVZlc4seAO+6d2sC26/PQPdP51ho1
# zBp+xUIZkpSFA8vWdoUoHLWnqWU3dCCyFG1roSrgHjSHlq8xymLnjCbSLZ49kPmk
# 8iyyizNDIXj//cOgrY7rlRyTlaCCfw7aSUROwnu7zER6EaJ+AliL7ojTdS5PWPsW
# eupWs7NpChUk555K096V1hE0yZIXe+giAwW00aHzrDchIc2bQhpp0IoKRR7YufAk
# prxMiXAJQ1XCmnCfgPf8+3mnAgMBAAGjggGVMIIBkTAMBgNVHRMBAf8EAjAAMB0G
# A1UdDgQWBBTkO/zyMe39/dfzkXFjGVBDz2GM6DAfBgNVHSMEGDAWgBTvb1NK6eQG
# fHrK4pBW9i/USezLTjAOBgNVHQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYB
# BQUHAwgwgZUGCCsGAQUFBwEBBIGIMIGFMCQGCCsGAQUFBzABhhhodHRwOi8vb2Nz
# cC5kaWdpY2VydC5jb20wXQYIKwYBBQUHMAKGUWh0dHA6Ly9jYWNlcnRzLmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEy
# NTYyMDI1Q0ExLmNydDBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vY3JsMy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hB
# MjU2MjAyNUNBMS5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcB
# MA0GCSqGSIb3DQEBCwUAA4ICAQBlKq3xHCcEua5gQezRCESeY0ByIfjk9iJP2zWL
# pQq1b4URGnwWBdEZD9gBq9fNaNmFj6Eh8/YmRDfxT7C0k8FUFqNh+tshgb4O6Lgj
# g8K8elC4+oWCqnU/ML9lFfim8/9yJmZSe2F8AQ/UdKFOtj7YMTmqPO9mzskgiC3Q
# YIUP2S3HQvHG1FDu+WUqW4daIqToXFE/JQ/EABgfZXLWU0ziTN6R3ygQBHMUBaB5
# bdrPbF6MRYs03h4obEMnxYOX8VBRKe1uNnzQVTeLni2nHkX/QqvXnNb+YkDFkxUG
# tMTaiLR9wjxUxu2hECZpqyU1d0IbX6Wq8/gVutDojBIFeRlqAcuEVT0cKsb+zJNE
# suEB7O7/cuvTQasnM9AWcIQfVjnzrvwiCZ85EE8LUkqRhoS3Y50OHgaY7T/lwd6U
# Arb+BOVAkg2oOvol/DJgddJ35XTxfUlQ+8Hggt8l2Yv7roancJIFcbojBcxlRcGG
# 0LIhp6GvReQGgMgYxQbV1S3CrWqZzBt1R9xJgKf47CdxVRd/ndUlQ05oxYy2zRWV
# FjF7mcr4C34Mj3ocCVccAvlKV9jEnstrniLvUxxVZE/rptb7IRE2lskKPIJgbaP5
# t2nGj/ULLi49xTcBZU8atufk+EMF/cWuiC7POGT75qaL6vdCvHlshtjdNXOCIUjs
# arfNZzGCBP8wggT7AgEBMDQwIDEeMBwGA1UEAwwVRmlybWEgU2NyaXB0cyBTT1BP
# UlRFAhA7FdbO/fXQu01Rj04CtYuGMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEM
# MQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQB
# gjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBTdAT2Qfqph5gAP
# WFZL6d9asMmvkTANBgkqhkiG9w0BAQEFAASCAQBjw4zTj4mnUEIDd5MpGNHh9ulP
# Y3v8HDrLVAGd+zGZ/xWME5qqn6l3KPID4yvbadw6BibJC3kOJ+0QN0XIcIq9dG2y
# 66CWpcc66kjGaW03qKMWuo998OJ3F4MXeMFUfIRmTR4fBMm4o2hxMOvCczb6IJGe
# TNdLQWCNe0nmLb5AH/v3XEc/Roxd9JD/HDAtiUyfKPFExQv2km1lsolrfHteammr
# KDVRFvuRxRvJyrWgIE6oc7NmmBmBVzmgqruyXBDQQ6S2SwqVeqW5u9KUszvIAddh
# FKm75JJQaQYN00a2infZmAbnhL7dOORPhvih9uLNlj13TnonqxXtPcGUForkoYID
# JjCCAyIGCSqGSIb3DQEJBjGCAxMwggMPAgEBMH0waTELMAkGA1UEBhMCVVMxFzAV
# BgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVk
# IEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENBMQIQCoDvGEuN
# 8QWC0cR2p5V0aDANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG
# 9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI2MDIwNDE3NDg1NlowLwYJKoZIhvcNAQkE
# MSIEIMvsxgfYyPey9CFZ6KyMwOmqso6zbaCIBtieRZD5+xg/MA0GCSqGSIb3DQEB
# AQUABIICAC4nE0iLpuV4ukwxHPUlDzwTM/w8UIne63Gd0506W12xu76au+eZ5+sM
# 17zud8wOWiUAv+3b0VNdM2CG/Pgojvk1VackTNop055oJsmv15bt4ML/bdbR51uL
# w/BolxNu1SVzTf8UYDA9PhpCDP6d5KlTQ7LwwiZwr2iqroAQlPlsxXIPrW85w0Yc
# Bk4yz2dZ1l/n9INcxCrerA/Y8Ge0Q4wKfYnDYsgerkTMl0yZbrcH89b/DuwQkT0d
# Zp+j3wB1B14La6KdFWJDd0WifWsv6dxgo3j3sNpN8Hu1b7vN5SwShYAQnv7pOMr3
# bdDXvZhNMRYbf8MJR7lXiNcbcEsiIQs3fCMD7+WQ27BDHsnT5FI/uifyN1tvb7tp
# jQ86k5GJhoLdvQWYqN6kPXPTMcQt+1L2yoTGdjIGBGoIFjYsyeaUvniFTV+czWrq
# ZAfuZfkKLwZrjchBgOSx8xtAqE4VTuZsX+t67ikm/ESLzGNyVEeZZ9L46+B6Ewuu
# LlaARHM3s32N8SeaGU5r74uXJfVToF20LKAjsC7DUo+x8TyVrrc9vUK/Q+1HyDAy
# /DswUdysfdpZkdFShLxFJuNK4WP8sR5js15aI5sZ4v6PCnkIYu25W07xTw2YiwjN
# l45f7peT3pEIJpV7EWPA3i4QVMdI0T5EpPczKEaspVevpRd3R2ei
# SIG # End signature block