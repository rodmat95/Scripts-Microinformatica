$basePath = "C:\Users"

# Obtener todas las carpetas que coincidan con TEMP.DOMIBCO.*
$folders = Get-ChildItem -Path $basePath -Directory -Filter "TEMP.DOMIBCO.*"

foreach ($folder in $folders) {
    Write-Host "Procesando: $($folder.FullName)"

    try {
        # Intentar eliminar completamente la carpeta
        Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
        Write-Host "Eliminada: $($folder.FullName)" -ForegroundColor Green
    }
    catch {
        Write-Warning "No se pudo eliminar completamente la carpeta: $($folder.FullName)"
        Write-Host "Intentando eliminar solo el contenido interno..."

        try {
            # Eliminar solo contenido interior
            Get-ChildItem -Path $folder.FullName -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Contenido eliminado: $($folder.FullName)" -ForegroundColor Yellow
        }
        catch {
            Write-Host "No se pudo eliminar el contenido de: $($folder.FullName)" -ForegroundColor Red
        }
    }
}

Write-Host "Proceso finalizado."