param ([switch]$Delete)

# 1. Entrada de usuario
$Usuario = ""
while ([string]::IsNullOrWhiteSpace($Usuario)) {
    $Usuario = Read-Host "`n>>> Digita el nombre del usuario"
}

$RaizUser = "C:\Users\$Usuario"
$LogFile = "$env:USERPROFILE\Desktop\Reporte_Limpieza_$Usuario.txt"

if (-not (Test-Path $RaizUser)) { 
    Write-Host "[!] Usuario no encontrado en C:\Users\" -ForegroundColor Red
    return 
}

$TotalLiberado = 0

# Función para obtener tamaño en MB
function Get-Size($Path) {
    $items = Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue
    if ($items) {
        $sum = ($items | Measure-Object -Property Length -Sum).Sum
        return [math]::Round($sum / 1MB, 2)
    }
    return 0
}

# Configuración de textos
$Modo = "MODO CONSULTA"
$TextoResultado = "POTENCIAL A LIBERAR: "
if ($Delete) {
    $Modo = "MODO ELIMINACIÓN"
    $TextoResultado = "LIBERADO REAL: "
}

"REPORTE $Modo - $Usuario - $(Get-Date)" | Out-File $LogFile
"================================================" | Out-File $LogFile -Append

# 2. LIMPIEZA / CONSULTA CARPETAS PERSONALES
Write-Host "`n--- CARPETAS PERSONALES ---" -ForegroundColor Cyan
$CarpetasPers = @("Documents", "Downloads", "Pictures", "Videos")
# Extensiones que se borrarán en personales si se usa -Delete
$ExtBasura = "*.tmp", "*.log", "*.old", "*.exe", "*.msi" 

foreach ($c in $CarpetasPers) {
    $RutaC = "$RaizUser\$c"
    if (Test-Path $RutaC) {
        $pesoAntes = Get-Size $RutaC
        
        if ($Delete) {
            # Buscar archivos basura específicos
            $ArchivosBasura = Get-ChildItem $RutaC -Include $ExtBasura -Recurse -ErrorAction SilentlyContinue
            foreach ($f in $ArchivosBasura) {
                $TotalLiberado += ([math]::Round($f.Length / 1MB, 2))
                Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            }
            $pesoDespues = Get-Size $RutaC
            $msg = "$c : Se redujo de $pesoAntes MB a $pesoDespues MB"
        } else {
            $msg = "$c : $pesoAntes MB"
        }
        
        Write-Host "[i] $msg"
        $msg | Out-File $LogFile -Append
    }
}

# 3. DETALLE POR PROGRAMA (AppData\Local)
Write-Host "`n--- DETALLE APPDATA\LOCAL ---" -ForegroundColor Cyan
$AppDataLocal = "$RaizUser\AppData\Local"
if (Test-Path $AppDataLocal) {
    $Programas = Get-ChildItem $AppDataLocal -Directory
    foreach ($Prog in $Programas) {
        $pesoProg = Get-Size $Prog.FullName
        if ($pesoProg -gt 1) {
            Write-Host "Programa: $($Prog.Name) -> $pesoProg MB"
            
            $Basura = Get-ChildItem $Prog.FullName -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "Cache|Logs|Temp|CrashDumps" }
            foreach ($b in $Basura) {
                $pBasura = Get-Size $b.FullName
                if ($pBasura -gt 0.1) {
                    if ($Delete) {
                        $TotalLiberado += $pBasura
                        Get-ChildItem $b.FullName -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                        $lBasura = "   [X] ELIMINADO: $($b.Name) ($pBasura MB)"
                        Write-Host $lBasura -ForegroundColor Red
                    } else {
                        $lBasura = "   [!] BASURA: $($b.Name) ($pBasura MB)"
                        Write-Host $lBasura -ForegroundColor Gray
                    }
                    $lBasura | Out-File $LogFile -Append
                }
            }
        }
    }
}

# Resumen final
$ResumenFinal = "`nTOTAL ESPACIO $TextoResultado $TotalLiberado MB"
Write-Host $ResumenFinal -ForegroundColor Green
$ResumenFinal | Out-File $LogFile -Append

Write-Host "`n[LISTO] Reporte en el Escritorio." -ForegroundColor Cyan
Write-Host "Presiona Enter para finalizar..."
Read-Host