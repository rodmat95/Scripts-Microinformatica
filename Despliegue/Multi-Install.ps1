# Lista de equipos por contador       
$computers    = 129..148 | ForEach-Object { "A12AVD01-$_" }
$computersOLD     = @(
	'L12AUD75','L12AUD48','L12AUD90','L12AUD34'
)

# Componentes de la ruta
$shareRoot     = 'C$' 
$relativePath  = 'python-3.12.8-amd64.exe'
$installArgs   = '/quiet InstallAllUsers=1 PrependPath=1 Include_test=0'

# Encabezado
$nombre = Split-Path $relativePath -Leaf

Write-Host ""
Write-Host ('===== DESPLIEGUE DE INSTALACIÃ“N =====') -ForegroundColor Cyan
Write-Host ('Instalador : ' + $nombre) -ForegroundColor Yellow
Write-Host ('Equipos    : ' + $computers.Count) -ForegroundColor Gray
Write-Host ('Argumentos : ' + $installArgs) -ForegroundColor Gray
Write-Host ('Fecha      : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor Gray
Write-Host ('=====================================') -ForegroundColor Cyan
Write-Host ""

$resultados = Invoke-Command -ComputerName $computers -ThrottleLimit 30 -ScriptBlock {
    param($pShareRoot, $pRelativePath, $pInstallArgs)

    $hostname  = $env:COMPUTERNAME
	$installer = '\\' + $hostname + '\' + $pShareRoot + '\' + $pRelativePath
	$now        = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    try {
        if (-not (Test-Path $installer)) {
            throw ('No se encuentra el instalador: ' + $installer)
        }
        # Ejecutar y esperar a que termine
        $proc = Start-Process -FilePath $installer -ArgumentList $pInstallArgs -Wait -PassThru -Verb RunAs
        [pscustomobject]@{
            Equipo    = $hostname
            Ruta      = $installer
            ExitCode  = $proc.ExitCode
			Resultado = if ($proc.ExitCode -eq 0) { 'OK' } else { 'EXITCODE:' + $proc.ExitCode }
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
} -ArgumentList $shareRoot, $relativePath, $installArgs `
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
Select-Object * -ExcludeProperty PSComputerName |
Sort-Object Equipo |
Format-Table -AutoSize
