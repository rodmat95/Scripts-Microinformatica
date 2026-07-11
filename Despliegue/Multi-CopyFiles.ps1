# Contador de equipos por contador
$computers    = 4..18 | ForEach-Object { "A12AVD01-$_" }

<#
# Lista de equipos por contador
$computers     = @(
	'P12MIC02','P12MIC13','P12MIC04'
)
#>

# Origen LOCAL
$sourcePath = 'D:\0. Empaquetado\Notepad++\npp.8.8.2.Installer.x64.exe'   # archivo o carpeta

# Ruta destino
$shareRoot    = 'C$'
$relativePath = 'Temp'   # '' = raíz | 'Tools' = subcarpeta

# Encabezado
$nombre = Split-Path $sourcePath -Leaf
Write-Host "===== Copiado de $nombre a $($computers.Count) equipos =====`n" -ForegroundColor Cyan

$resultados = foreach ($pc in $computers) {
    $itemName = Split-Path $sourcePath -Leaf

	# Construcción dinámica del destino
	if (-not $relativePath) {
		$destRoot = "\\$pc\$shareRoot"
	} else {
		$destRoot = "\\$pc\$shareRoot\$relativePath"
	}

    $destPath = Join-Path $destRoot $itemName
    $now      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    try {
        # Validación origen
        if (-not (Test-Path $sourcePath)) {
            throw "No existe origen LOCAL: $sourcePath"
        }

        # Validación acceso remoto
        if (-not (Test-Path "\\$pc\$shareRoot")) {
            throw "No acceso a \\$pc\$shareRoot"
        }

        # Crear carpeta destino si aplica
        if (-not (Test-Path $destRoot)) {
            New-Item -Path $destRoot -ItemType Directory -Force | Out-Null
        }

        # Detectar tipo
        $isDirectory = (Get-Item $sourcePath).PSIsContainer

        if ($isDirectory) {
            # Carpeta → robocopy
            $cmd = "robocopy `"$sourcePath`" `"$destPath`" /E /Z /R:2 /W:2 /NFL /NDL"
            $proc = Start-Process cmd.exe -ArgumentList "/c $cmd" -Wait -PassThru
            $exit = $proc.ExitCode

            $ok = ($exit -le 7)

        } else {
            # Archivo → Copy-Item
            Copy-Item -Path $sourcePath -Destination $destPath -Force -ErrorAction Stop
            $exit = 0
            $ok   = $true
        }

        # Verificación
        $exists = Test-Path $destPath

        [pscustomobject]@{
            Equipo     = $pc
            Origen     = $sourcePath
            Destino    = $destPath
            Tipo       = if ($isDirectory) { 'Carpeta' } else { 'Archivo' }
            ExitCode   = $exit
            Verificado = $exists
            Resultado  = if ($ok -and $exists) { 'OK' } else { 'ERROR' }
            Fecha      = $now
        }

    } catch {
        [pscustomobject]@{
            Equipo     = $pc
            Origen     = $sourcePath
            Destino    = $destRoot
            Tipo       = 'N/A'
            ExitCode   = $null
            Verificado = $false
            Resultado  = 'ERROR'
            Mensaje    = $_.Exception.Message
            Fecha      = $now
        }
    }
}

$resultados | Out-GridView -Title "Despliegue de Archivos"
#Format-Table -AutoSize