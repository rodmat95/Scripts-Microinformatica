# Contador de equipos por contador
$computers    = 4..18 | ForEach-Object { "A12AVD01-$_" }

<#
# Lista de equipos por contador
$computers     = @(
	'P12MIC02','P12MIC13','P12MIC04'
)
#>

# Componentes de la ruta
$localRoot     = 'C:\Temp' 
$relativePath  = 'npp.8.8.2.Installer.x64.exe'

# Encabezado
$nombre = Split-Path $relativePath -Leaf

Write-Host ""
Write-Host ('===== DESPLIEGUE DE INSTALACIÓN =====') -ForegroundColor Cyan
Write-Host ('Instalador : ' + $nombre) -ForegroundColor Yellow
Write-Host ('Equipos    : ' + $computers.Count) -ForegroundColor Gray
Write-Host ('Fecha      : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor Gray
Write-Host ('=====================================') -ForegroundColor Cyan
Write-Host ""

$resultados = Invoke-Command -ComputerName $computers -ThrottleLimit 30 -ScriptBlock {
    param($pLocalRoot, $pRelativePath)

    $hostname  = $env:COMPUTERNAME
	$installer = Join-Path $pLocalRoot $pRelativePath
	$now       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    try {
		if (-not (Test-Path $installer)) {
			throw ('No se encuentra el instalador: ' + $installer)
		}
        
		$ext = [System.IO.Path]::GetExtension($installer).ToLower()
		
		# Argumentos por Tipo
		$exeArgs = "/S"
		$msiArgs = "/qn /norestart ALLUSERS=1"
		
        # Swicher de Argumentos
		switch ($ext) {
			'.msi' {
				$installerArgs = "/i `"$installer`" $msiArgs"
				$file = "msiexec.exe"
			}

			'.exe' {
				$installerArgs = $exeArgs
				$file = $installer
			}

			default {
				throw "Tipo de archivo no soportado: $ext"
			}
		}

        # Ejecutar y esperar a que termine
		$proc = Start-Process -FilePath $file -ArgumentList $installerArgs -Wait -PassThru
		
		[pscustomobject]@{
			Equipo    = $hostname
			Tipo      = $ext
			Ruta      = $installer
			Comando = "$file $installerArgs"
			ExitCode  = $proc.ExitCode
			Resultado = switch ($proc.ExitCode) {
				0    { 'OK' }
				3010 { 'OK_REBOOT' }
				default { 'EXITCODE:' + $proc.ExitCode }
			}
			Fecha     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
		}
    } catch {
        [pscustomobject]@{
            Equipo    = $hostname
            Ruta      = $installer
            ExitCode  = $null
            Resultado = 'ERROR'
            Mensaje   = $_.Exception.Message
            Fecha     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
} -ArgumentList $localRoot, $relativePath `
  -ErrorAction SilentlyContinue -ErrorVariable errores

$erroresProcesados = foreach ($err in $errores) {
    [pscustomobject]@{
        Equipo    = $err.TargetObject
        Ruta      = $null
        ExitCode  = $null
        Resultado = 'SIN CONEXION'
        Mensaje   = $err.Exception.Message
        Fecha     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
}

$resultados + $erroresProcesados |
Select-Object Equipo, Tipo, Resultado, ExitCode, Ruta, Fecha |
Sort-Object Equipo |
Out-GridView -Title "Despliegue de Instalación"
#Format-Table -AutoSize