# 1. Detectar el nombre correcto del grupo RDP (Español o Inglés)
$GrupoRDP = "Usuarios de escritorio remoto"
if (-not (net localgroup $GrupoRDP 2>$null)) {
    $GrupoRDP = "Remote Desktop Users"
}

# 2. Obtener usuarios del grupo RDP usando el comando compatible con Dominio
Write-Host "Obteniendo miembros del grupo de Escritorio Remoto..." -ForegroundColor Cyan
$UsuariosRDP = (net localgroup $GrupoRDP 2>$null) | 
    Where-Object { $_ -and $_ -notmatch '^(Alias|Comentario|Miembros|-|El comando completó|The command completed)' } | 
    ForEach-Object { 
        $Linea = $_.Trim()
        if ($Linea -like "*\*") { $Linea.Split('\')[-1] } else { $Linea }
    }

# 3. Lista blanca fija de sistema
$UsuariosFijos = @("administrador", "administrator", "admlocalsrvwindows", "homeuser", "default", "public")

# 4. Combinar listas de exclusión (Fijos + RDP) y pasar a minúsculas
$TotalUsuariosASalvar = $UsuariosFijos + $UsuariosRDP | ForEach-Object { $_.ToLower() }

Write-Host "Buscando todos los perfiles de usuario en el equipo..." -ForegroundColor Cyan
Write-Host "Usuarios protegidos detectados: $($TotalUsuariosASalvar -join ', ')`n" -ForegroundColor DarkCyan

# 5. Buscar y filtrar los perfiles
$PerfilesAEliminar = Get-CimInstance -ClassName Win32_UserProfile | Where-Object {
    $NombrePerfil = (Split-Path $_.LocalPath -Leaf).ToLower()
    
    $_.Special -eq $False -and 
    $_.LocalPath -notlike "*\Public" -and 
    $NombrePerfil -notin $TotalUsuariosASalvar
}

# 6. Validar si se encontraron perfiles e iniciar borrado directo
if ($Null -eq $PerfilesAEliminar -or $PerfilesAEliminar.Count -eq 0) {
    Write-Host "No se encontró ningún usuario elegible para eliminación (todos están protegidos)." -ForegroundColor Red
} else {
    foreach ($Perfil in $PerfilesAEliminar) {
        $Nombre = Split-Path $Perfil.LocalPath -Leaf
        $RutaFisica = $Perfil.LocalPath
        $UltimaConexion = if ($Perfil.LastUseTime) { $Perfil.LastUseTime.ToString("dd/MM/yyyy") } else { "Nunca" }
        
        Write-Host "Intentando eliminar perfil: $Nombre (Última vez: $UltimaConexion)..." -ForegroundColor Yellow
        
        try {
            # Intentar la desasociación limpia del perfil
            $Perfil | Remove-CimInstance
            
            # Pausa de un segundo para que el sistema procese la eliminación en disco
            Start-Sleep -Seconds 1
            
            # VALIDACIÓN REAL: Verificar si la carpeta del perfil aún existe
            if (Test-Path -Path $RutaFisica) {
                Write-Warning "No se pudo eliminar el perfil $Nombre. El usuario podría tener una sesión activa o archivos bloqueados."
            } else {
                Write-Host "¡Perfil $Nombre de dominio eliminado con éxito!`n" -ForegroundColor Green
            }
        } catch {
            Write-Warning "Error crítico al procesar el perfil $Nombre. Detalle: $($_.Exception.Message)"
        }
    }
}