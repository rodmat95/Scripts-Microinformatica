# ======================================================
# CONFIGURACIÓN
# ======================================================
$DominioCorrecto = "domibco.com.pe"
$DominioNetBIOS  = "DOMIBCO"
$UsuarioAEliminar = "mibanco"

$AdministradoresPermitidos = @(
    "Administrador",
    "AdmLocalSrvWindows"
)

$GrupoLocal = "Usuarios"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host " VALIDACIÓN INICIAL DEL ENTORNO"
Write-Host "======================================" -ForegroundColor Cyan

# ======================================================
# PASO 1 - VALIDAR DOMINIO
# ======================================================
$PropiedadesRed = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
$DominioActual = $PropiedadesRed.DomainName

if (:IsNullOrWhiteSpace($DominioActual)) {

    Write-Host "[CRÍTICO] El equipo no pertenece a un dominio." -ForegroundColor Red
    Write-Host "[FIN] Operación cancelada." -ForegroundColor Yellow
    exit
}

if ($DominioActual.ToLower() -ne $DominioCorrecto.ToLower()) {

    Write-Host "[CRÍTICO] Dominio incorrecto." -ForegroundColor Red
    Write-Host "Detectado : $DominioActual" -ForegroundColor Yellow
    Write-Host "Esperado  : $DominioCorrecto" -ForegroundColor Cyan
    Write-Host "[FIN] Operación cancelada." -ForegroundColor Yellow
    exit
}

Write-Host "[OK] Equipo unido al dominio correcto: $DominioActual" -ForegroundColor Green

# ======================================================
# PASO 2 - SOLICITAR Y VALIDAR CREDENCIALES
# ======================================================
Write-Host "`n[REQUERIDO] Ingrese credenciales de dominio" -ForegroundColor Cyan

try {

    $Credenciales = Get-Credential `
        -UserName "$DominioNetBIOS\$env:USERNAME" `
        -Message "Ingrese credenciales autorizadas"

    $LDAP = New-Object System.DirectoryServices.DirectoryEntry(
        "LDAP://$DominioNetBIOS",
        $Credenciales.UserName,
        $Credenciales.GetNetworkCredential().Password
    )

    $null = $LDAP.NativeObject

    Write-Host "[OK] Credenciales validadas correctamente." -ForegroundColor Green
}
catch {

    Write-Host "[CRÍTICO] Credenciales inválidas o sin acceso al dominio." -ForegroundColor Red
    Write-Host "[FIN] Operación cancelada." -ForegroundColor Yellow
    exit
}

# ======================================================
# PASO 3 - VALIDAR USUARIO EJECUTOR
# ======================================================
$UsuarioActual = $env:USERNAME

if ($AdministradoresPermitidos -notcontains $UsuarioActual) {

    Write-Host "[BLOQUEADO] Usuario no autorizado." -ForegroundColor Red
    Write-Host "Usuario actual: $UsuarioActual" -ForegroundColor Yellow
    Write-Host "Permitidos: $($AdministradoresPermitidos -join ', ')" -ForegroundColor Cyan
    Write-Host "[FIN] Operación cancelada." -ForegroundColor Yellow
    exit
}

Write-Host "[OK] Usuario autorizado: $UsuarioActual" -ForegroundColor Green

# ======================================================
# PASO 4 - ELIMINAR USUARIO LOCAL MIBANCO
# ======================================================
Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host " LIMPIEZA DE USUARIOS"
Write-Host "======================================" -ForegroundColor Cyan

try {

    Remove-LocalUser -Name $UsuarioAEliminar -ErrorAction Stop

    Write-Host "[OK] Usuario '$UsuarioAEliminar' eliminado." -ForegroundColor Green
}
catch {

    Write-Host "[INFO] Usuario '$UsuarioAEliminar' no existe o ya fue eliminado." -ForegroundColor Yellow
}

# ======================================================
# PASO 5 - VALIDACIÓN DE HOSTNAME
# ======================================================
$Hostname = $env:COMPUTERNAME.ToUpper()

if ($Hostname -like "L12*") {

    Write-Host "[INFO] Laptop detectada ($Hostname)." -ForegroundColor Cyan

    try {

        Remove-LocalGroupMember `
            -Group $GrupoLocal `
            -Member "DOMIBCO\Usuarios del dominio" `
            -ErrorAction Stop

        Remove-LocalGroupMember `
            -Group $GrupoLocal `
            -Member "S-1-5-11" `
            -ErrorAction Stop

        Write-Host "[OK] Usuarios removidos del grupo local." -ForegroundColor Green
    }
    catch {

        Write-Host "[INFO] Algunos miembros ya no existían en el grupo." -ForegroundColor Yellow
    }
}
elseif ($Hostname -like "P*") {

    Write-Host "[INFO] PC detectada. Sin cambios." -ForegroundColor Yellow
}
elseif ($Hostname -like "A12*") {

    Write-Host "[INFO] VM Azure detectada. Sin cambios." -ForegroundColor Yellow
}
elseif ($Hostname -like "V12*") {

    Write-Host "[INFO] VM OnPremise detectada. Sin cambios." -ForegroundColor Yellow
}
else {

    Write-Host "[ALERTA] Hostname no reconocido ($Hostname)." -ForegroundColor Yellow
}

# ======================================================
# PASO 6 - AGREGAR USUARIO DE DOMINIO
# ======================================================
$ComputerName = $env:COMPUTERNAME

$UsuarioRed = Read-Host "`nIngrese el ID del usuario de red"

try {

    $RutaLDAP = "LDAP://$DominioNetBIOS"

    $BuscadorAD = New-Object System.DirectoryServices.DirectorySearcher

    $BuscadorAD.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry(
        $RutaLDAP,
        $Credenciales.UserName,
        $Credenciales.GetNetworkCredential().Password
    )

    $BuscadorAD.Filter = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$UsuarioRed))"

    $ResultadoUsuario = $BuscadorAD.FindOne()

    if ($ResultadoUsuario -eq $null) {
        throw "El ID '$UsuarioRed' no existe en Active Directory."
    }

    $NombreCompleto = $ResultadoUsuario.Properties["displayname"][0]

    Write-Host ""
    Write-Host "---------------------------------------" -ForegroundColor Gray
    Write-Host "USUARIO ENCONTRADO" -ForegroundColor Green
    Write-Host "ID     : $UsuarioRed"
    Write-Host "Nombre : $NombreCompleto"
    Write-Host "---------------------------------------" -ForegroundColor Gray

    $Confirmacion = Read-Host "Presione O para continuar"

    if ($Confirmacion.ToUpper() -ne "O") {

        Write-Host "[CANCELADO] Operación cancelada." -ForegroundColor Yellow
        exit
    }

    $ContextoLocal = New-Object System.DirectoryServices.DirectoryEntry(
        "WinNT://$ComputerName/$GrupoLocal,group",
        $Credenciales.UserName,
        $Credenciales.GetNetworkCredential().Password
    )

    $RutaUsuarioRed = "WinNT://$DominioNetBIOS/$UsuarioRed"

    $ContextoLocal.Invoke("Add", $RutaUsuarioRed)

    Write-Host "[ÉXITO] Usuario agregado correctamente al grupo '$GrupoLocal'." -ForegroundColor Green
}
catch {

    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
}