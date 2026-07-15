# ======================================================
# CONFIGURACION
# ======================================================
$DominioCorrecto   = "domibco.com.pe"
$DominioNetBIOS    = "DOMIBCO"
$UsuarioAEliminar  = "mibanco"

$AdministradoresPermitidos = @(
    "Administrador",
    "AdmLocalSrvWindows"
)

$GrupoLocal = "Usuarios"

# ======================================================
# FUNCIONES UTILITARIAS
# ======================================================
function Write-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Write-Host "`n======================================" -ForegroundColor Cyan
    Write-Host " $Title"
    Write-Host "======================================" -ForegroundColor Cyan
}

function Exit-Error {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string[]]$Details = @()
    )

    Write-Host $Message -ForegroundColor Red

    foreach ($Detail in $Details) {
        Write-Host $Detail -ForegroundColor Yellow
    }

    Write-Host "[FIN] Operacion cancelada." -ForegroundColor Yellow
    exit 1
}

# ======================================================
# FUNCIONES DE DETECCION DE FASE
# ======================================================

# Devuelve el nombre de dominio actual (vacio si no hay dominio)
function Get-CurrentDomain {
    $Props = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
    return $Props.DomainName
}

# Devuelve el nombre del usuario actual (sin dominio ni ".\")
function Get-CurrentUser {
    return $env:USERNAME
}

# ======================================================
# FUNCIONES - FASE 1: SIN DOMINIO
# ======================================================

function Enable-LocalAdminForDomain {
    Write-Step -Title "HABILITANDO CUENTA ADMINISTRADOR LOCAL"

    try {
        Set-LocalUser -Name "Administrador" `
                      -PasswordNeverExpires $true `
                      -UserMayChangePassword $true `
                      -ErrorAction Stop

        Enable-LocalUser -Name "Administrador" -ErrorAction Stop

        $Password = ConvertTo-SecureString "12345678" -AsPlainText -Force
        Set-LocalUser -Name "Administrador" -Password $Password -ErrorAction Stop

        Write-Host "[OK] Cuenta 'Administrador' habilitada con contrasena temporal '12345678'." -ForegroundColor Green
    }
    catch {
        Exit-Error -Message "[CRITICO] No se pudo habilitar la cuenta Administrador: $($_.Exception.Message)"
    }

    # Validacion indispensable de la cuenta Administrador activa y su contrasena antes de continuar
    Write-Host "[INFO] Validando acceso y estado de la cuenta 'Administrador'..." -ForegroundColor Cyan
    try {
        $User = Get-LocalUser -Name "Administrador" -ErrorAction Stop
        if (-not $User.Enabled) {
            throw "La cuenta 'Administrador' esta deshabilitada."
        }

        # Validar la contraseña intentando enlazar via WinNT
        $DE = New-Object System.DirectoryServices.DirectoryEntry("WinNT://$env:COMPUTERNAME", "Administrador", "12345678")
        $null = $DE.NativeObject
        Write-Host "[OK] Validacion indispensable exitosa: Cuenta 'Administrador' activa y con la contrasena correcta (12345678)." -ForegroundColor Green
    }
    catch {
        Exit-Error -Message "[CRITICO] Error de validacion indispensable: La cuenta 'Administrador' no esta activa o no tiene la contrasena temporal '12345678'." -Details @(
            "Detalles: $($_.Exception.Message)",
            "No se puede continuar con la subida al dominio ni reiniciar el equipo por riesgo de bloqueo."
        )
    }
}

function Join-ComputerToDomain {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainFQDN
    )

    Write-Step -Title "SUBIR EQUIPO AL DOMINIO"

    $InputHostname = Read-Host "Ingrese el nuevo hostname para el equipo"
    $NuevoHostname = $InputHostname.ToUpper()

    Write-Host "[INFO] Hostname a asignar: $NuevoHostname" -ForegroundColor Cyan

    $CredDominio = Get-Credential `
        -UserName "$DomainFQDN\Administrador" `
        -Message "Ingrese la clave del Administrador del Dominio para unir '$NuevoHostname'"

    try {
        Add-Computer `
            -NewName $NuevoHostname `
            -DomainName $DomainFQDN `
            -Credential $CredDominio `
            -Force `
            -ErrorAction Stop

        Write-Host "[OK] Equipo '$NuevoHostname' unido al dominio '$DomainFQDN'." -ForegroundColor Green
        Write-Host "[INFO] El equipo se reiniciara para aplicar los cambios..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
        Restart-Computer -Force
    }
    catch {
        Exit-Error -Message "[CRITICO] No se pudo unir al dominio: $($_.Exception.Message)"
    }
}

# ======================================================
# FUNCIONES - FASE 2a: EN DOMINIO CON ADMINISTRADOR
# ======================================================

function Confirm-OUAndRestart {
    Write-Step -Title "VERIFICACION DE UBICACION EN ACTIVE DIRECTORY"

    Write-Host ""
    Write-Host "  ACCION REQUERIDA:" -ForegroundColor Yellow
    Write-Host "  Verifique que el equipo '$env:COMPUTERNAME' este ubicado" -ForegroundColor White
    Write-Host "  correctamente en la OU del Active Directory antes de continuar." -ForegroundColor White
    Write-Host ""
    Write-Host "  Una vez confirmada la ubicacion, el equipo se reiniciara" -ForegroundColor White
    Write-Host "  para que pueda iniciar sesion con AdmLocalSrvWindows." -ForegroundColor White
    Write-Host ""

    $Confirmacion = Read-Host "Escriba OK cuando el equipo este correctamente ubicado en la OU"

    if ($Confirmacion.ToUpper() -ne "OK") {
        Write-Host "[CANCELADO] No se confirmo la ubicacion en la OU. Operacion cancelada." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "[OK] Ubicacion confirmada. Reiniciando equipo..." -ForegroundColor Green
    Start-Sleep -Seconds 2
    Restart-Computer -Force
}

# ======================================================
# FUNCIONES - FASE 2b: EN DOMINIO CON AdmLocalSrvWindows
# ======================================================

function Test-Domain {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExpectedDomain
    )

    $DominioActual = Get-CurrentDomain

    if ([string]::IsNullOrWhiteSpace($DominioActual)) {
        Exit-Error -Message "[CRITICO] El equipo no pertenece a un dominio."
    }

    if ($DominioActual.ToLower() -ne $ExpectedDomain.ToLower()) {
        Exit-Error `
            -Message "[CRITICO] Dominio incorrecto." `
            -Details @(
                "Detectado : $DominioActual",
                "Esperado  : $ExpectedDomain"
            )
    }

    Write-Host "[OK] Equipo unido al dominio correcto: $DominioActual" -ForegroundColor Green
}

function Get-DomainCredential {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainNetBIOS
    )

    Write-Host "`n[REQUERIDO] Ingrese credenciales de dominio" -ForegroundColor Cyan

    try {
        $Credenciales = Get-Credential `
            -UserName "$DomainNetBIOS\$env:USERNAME" `
            -Message "Ingrese credenciales autorizadas"

        $LDAP = New-Object System.DirectoryServices.DirectoryEntry(
            "LDAP://$DomainNetBIOS",
            $Credenciales.UserName,
            $Credenciales.GetNetworkCredential().Password
        )

        $null = $LDAP.NativeObject

        Write-Host "[OK] Credenciales validadas correctamente." -ForegroundColor Green
        return $Credenciales
    }
    catch {
        Exit-Error -Message "[CRITICO] Credenciales invalidas o sin acceso al dominio."
    }
}

function Remove-DefaultLocalUser {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    try {
        Remove-LocalUser -Name $UserName -ErrorAction Stop
        Write-Host "[OK] Usuario '$UserName' eliminado." -ForegroundColor Green
    }
    catch {
        Write-Host "[INFO] Usuario '$UserName' no existe o ya fue eliminado." -ForegroundColor Yellow
    }
}

function Set-LocalAdminPassword {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$AllowedAdmins
    )

    $UsuarioLocal = Get-LocalUser |
        Where-Object { $AllowedAdmins -contains $_.Name } |
        Select-Object -First 1

    if ($null -eq $UsuarioLocal) {
        Exit-Error -Message "[CRITICO] Ninguno de los administradores permitidos existe en este equipo."
    }

    $NombreUsuario = $UsuarioLocal.Name
    Write-Host "[INFO] Administrador local encontrado: $NombreUsuario" -ForegroundColor Cyan

    $NuevaPassword = Read-Host -Prompt "Ingrese la nueva contrasena para '$NombreUsuario'" -AsSecureString

    try {
        Set-LocalUser -Name $NombreUsuario -Password $NuevaPassword -ErrorAction Stop
        Write-Host "[OK] Contrasena modificada correctamente para: $NombreUsuario" -ForegroundColor Green
    }
    catch {
        Exit-Error -Message "[CRITICO] No se pudo cambiar la contrasena. Ejecute el script como Administrador."
    }
}

function Invoke-HostnameConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainNetBIOS,

        [Parameter(Mandatory = $true)]
        [string]$LocalGroup
    )

    $Hostname = $env:COMPUTERNAME.ToUpper()

    if ($Hostname -like "L12*") {
        Write-Host "[INFO] Laptop detectada ($Hostname)." -ForegroundColor Cyan

        try {
            Remove-LocalGroupMember `
                -Group $LocalGroup `
                -Member "$DomainNetBIOS\Usuarios del dominio" `
                -ErrorAction Stop

            Remove-LocalGroupMember `
                -Group $LocalGroup `
                -Member "S-1-5-11" `
                -ErrorAction Stop

            Write-Host "[OK] Usuarios removidos del grupo local." -ForegroundColor Green
        }
        catch {
            Write-Host "[INFO] Algunos miembros ya no existian en el grupo." -ForegroundColor Yellow
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
}

function Get-DomainUser {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainNetBIOS,

        [Parameter(Mandatory = $true)]
        [pscredential]$Credential,

        [Parameter(Mandatory = $true)]
        [string]$UserId
    )

    $RutaLDAP    = "LDAP://$DomainNetBIOS"
    $BuscadorAD  = New-Object System.DirectoryServices.DirectorySearcher

    $BuscadorAD.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry(
        $RutaLDAP,
        $Credential.UserName,
        $Credential.GetNetworkCredential().Password
    )

    $BuscadorAD.Filter   = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$UserId))"
    $ResultadoUsuario    = $BuscadorAD.FindOne()

    if ($null -eq $ResultadoUsuario) {
        throw "El ID '$UserId' no existe en Active Directory."
    }

    [PSCustomObject]@{
        Id          = $UserId
        DisplayName = $ResultadoUsuario.Properties["displayname"][0]
    }
}

function Add-DomainUserToLocalGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainNetBIOS,

        [Parameter(Mandatory = $true)]
        [pscredential]$Credential,

        [Parameter(Mandatory = $true)]
        [string]$UserId,

        [Parameter(Mandatory = $true)]
        [string]$LocalGroup
    )

    $ContextoLocal = New-Object System.DirectoryServices.DirectoryEntry(
        "WinNT://$env:COMPUTERNAME/$LocalGroup,group",
        $Credential.UserName,
        $Credential.GetNetworkCredential().Password
    )

    $RutaUsuarioRed = "WinNT://$DomainNetBIOS/$UserId"
    $ContextoLocal.Invoke("Add", $RutaUsuarioRed)

    Write-Host "[EXITO] Usuario agregado correctamente al grupo '$LocalGroup'." -ForegroundColor Green
}

function Confirm-Operation {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$DomainUser
    )

    Write-Host ""
    Write-Host "---------------------------------------" -ForegroundColor Gray
    Write-Host "USUARIO ENCONTRADO" -ForegroundColor Green
    Write-Host "ID     : $($DomainUser.Id)"
    Write-Host "Nombre : $($DomainUser.DisplayName)"
    Write-Host "---------------------------------------" -ForegroundColor Gray

    $Confirmacion = Read-Host "¿Los datos son correctos? (S = Si / N = No, reingresar)"

    if ($Confirmacion.ToUpper() -eq "S") {
        return $true
    }
    else {
        Write-Host "[INFO] Se reingresara el ID del usuario de red." -ForegroundColor Yellow
        return $false
    }
}

# ======================================================
# MAIN - DETECCION DE FASE
# ======================================================

$DominioActual  = Get-CurrentDomain
$UsuarioActual  = Get-CurrentUser
$IsAdmin        = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host "`n======================================" -ForegroundColor Magenta
Write-Host " POST-IMAGE CONFIGURATION TOOL"
Write-Host " Equipo  : $env:COMPUTERNAME"
Write-Host " Usuario : $UsuarioActual"
Write-Host " Dominio : $(if ([string]::IsNullOrWhiteSpace($DominioActual)) { '(sin dominio)' } else { $DominioActual })"
Write-Host "======================================`n" -ForegroundColor Magenta

# --------------------------------------------------
# FASE 1 - Sin dominio (Requiere privilegios de Administrador)
# --------------------------------------------------
if ([string]::IsNullOrWhiteSpace($DominioActual)) {
    if ($IsAdmin) {
        Write-Host "[FASE 1] Equipo sin dominio detectado. Ejecutando con privilegios de Administrador." -ForegroundColor Yellow

        Enable-LocalAdminForDomain
        Join-ComputerToDomain -DomainFQDN $DominioCorrecto

        # El script no continua: Join-ComputerToDomain reinicia el equipo
        exit 0
    }
    else {
        Exit-Error `
            -Message "[BLOQUEADO] El equipo no tiene dominio y el script no se esta ejecutando con privilegios de Administrador." `
            -Details @(
                "Usuario actual : $UsuarioActual",
                "Accion         : Ejecute la consola de PowerShell como Administrador y vuelva a intentar."
            )
    }
}

# A partir de aqui el equipo SI esta en dominio
if ($DominioActual.ToLower() -ne $DominioCorrecto.ToLower()) {
    Exit-Error `
        -Message "[CRITICO] El equipo pertenece a un dominio incorrecto." `
        -Details @(
            "Detectado : $DominioActual",
            "Esperado  : $DominioCorrecto"
        )
}

# --------------------------------------------------
# FASE 2a - En dominio con Administrador
# --------------------------------------------------
if ($UsuarioActual -eq "Administrador") {

    Write-Host "[FASE 2a] Equipo en dominio. Usuario: Administrador" -ForegroundColor Cyan

    # Recien aqui (ya validado el usuario Administrador) se puede eliminar el usuario mibanco
    Write-Step -Title "LIMPIEZA DE USUARIOS"
    Remove-DefaultLocalUser -UserName $UsuarioAEliminar

    Confirm-OUAndRestart

    # El script no continua: Confirm-OUAndRestart reinicia el equipo
    exit 0
}

# --------------------------------------------------
# FASE 2b - En dominio con AdmLocalSrvWindows
# --------------------------------------------------
if ($UsuarioActual -eq "AdmLocalSrvWindows") {

    Write-Host "[FASE 2b] Equipo en dominio. Usuario: AdmLocalSrvWindows" -ForegroundColor Green
    Write-Host "[INFO] Iniciando proceso de configuracion post-imagen...`n" -ForegroundColor White

    Write-Step -Title "VALIDACION INICIAL DEL ENTORNO"
    Test-Domain -ExpectedDomain $DominioCorrecto
    $Credenciales = Get-DomainCredential -DomainNetBIOS $DominioNetBIOS

    Write-Step -Title "LIMPIEZA DE USUARIOS"
    Remove-DefaultLocalUser -UserName $UsuarioAEliminar

    Write-Step -Title "CONFIGURACION DE CONTRASENA LOCAL"
    Set-LocalAdminPassword -AllowedAdmins $AdministradoresPermitidos

    Write-Step -Title "VALIDACION DE HOSTNAME"
    Invoke-HostnameConfiguration -DomainNetBIOS $DominioNetBIOS -LocalGroup $GrupoLocal

    Write-Step -Title "AGREGAR USUARIO DE DOMINIO"

    $UsuarioConfirmado = $false

    do {
        $UsuarioRed = Read-Host "`nIngrese el ID del usuario de red"

        try {
            $UsuarioDominio = Get-DomainUser `
                -DomainNetBIOS $DominioNetBIOS `
                -Credential $Credenciales `
                -UserId $UsuarioRed

            $UsuarioConfirmado = Confirm-Operation -DomainUser $UsuarioDominio
        }
        catch {
            Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "[INFO] Intente nuevamente con un ID valido." -ForegroundColor Yellow
        }
    } while (-not $UsuarioConfirmado)

    try {
        Add-DomainUserToLocalGroup `
            -DomainNetBIOS $DominioNetBIOS `
            -Credential $Credenciales `
            -UserId $UsuarioDominio.Id `
            -LocalGroup $GrupoLocal
    }
    catch {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`n[FIN] Configuracion post-imagen completada exitosamente." -ForegroundColor Green
    exit 0
}

# --------------------------------------------------
# Usuario en dominio pero no reconocido
# --------------------------------------------------
Exit-Error `
    -Message "[BLOQUEADO] Usuario en dominio no reconocido para este proceso." `
    -Details @(
        "Usuario actual : $UsuarioActual",
        "Esperados      : Administrador, AdmLocalSrvWindows"
    )
