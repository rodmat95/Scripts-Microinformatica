# Lista de equipos por contador       
$computers    = 4..18 | ForEach-Object { "A12AVD01-$_" }
$computersOLD     = @(
	'L12AUD75','L12AUD48','L12AUD90','L12AUD34'
)

# Componentes de la ruta
$shareRoot    = 'C$'
$relativePath = 'Kubectl-1.23.5'

# Encabezado
Write-Host "===== Configuración de PATH: $relativePath en $($computers.Count) equipos =====`n" -ForegroundColor Yellow

Invoke-Command -ComputerName $computers -ThrottleLimit 30 -ScriptBlock {
    param($pShareRoot, $pRelativePath)

    $hostname = $env:COMPUTERNAME
    $newPath  = "C:\$pRelativePath"
    $now      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    try {
        # Validar que exista la carpeta
        if (-not (Test-Path $newPath)) {
            throw "No existe la carpeta: $newPath"
        }

		# Obtener PATH actual (máquina)
		$currentPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")

		# Verificar si ya existe
		if ($currentPath -split ';' -contains $newPath) {
			$status = "YA_EXISTE"
			$changed = $false
		} else {
			# Agregar nueva ruta
			$updatedPath = "$currentPath;$newPath"

			[System.Environment]::SetEnvironmentVariable("Path", $updatedPath, "Machine")

			$status = "AGREGADO"
			$changed = $true
		}

		# Validación post-cambio
		$verifyPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
		$existsNow  = $verifyPath -split ';' -contains $newPath

        [pscustomobject]@{
            Equipo     = $hostname
            Ruta       = $newPath
            Accion     = $status
            Modificado = $changed
            Verificado = $existsNow
            Resultado  = if ($existsNow) { 'OK' } else { 'ERROR' }
            Fecha      = $now
        }

    } catch {
        [pscustomobject]@{
            Equipo     = $hostname
            Ruta       = $newPath
            Accion     = 'N/A'
            Modificado = $false
            Verificado = $false
            Resultado  = 'ERROR'
            Mensaje    = $_.Exception.Message
            Fecha      = $now
        }
    }

} -ArgumentList $shareRoot, $relativePath |
Format-Table -AutoSize