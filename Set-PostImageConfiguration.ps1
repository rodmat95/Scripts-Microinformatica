# ======================================================
# CONFIGURACION
# ======================================================
$DominioCorrecto = "domibco.com.pe"
$DominioNetBIOS = "DOMIBCO"
$UsuarioAEliminar = "mibanco"

$AdministradoresPermitidos = @(
    "Administrador",
    "AdmLocalSrvWindows"
)

$GrupoLocal = "Usuarios"

# ======================================================
# FUNCIONES
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

function Get-CurrentDomainName {
    $PropiedadesRed = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
    return $PropiedadesRed.DomainName
}

function Test-CurrentLocalUser {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExpectedUser
    )

    $UsuarioActual = $env:USERNAME
    $IdentidadActual = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $UsuarioLocalEsperado = "$env:COMPUTERNAME\$ExpectedUser"

    return (
        $UsuarioActual.ToLower() -eq $ExpectedUser.ToLower() -and
        $IdentidadActual.ToLower() -eq $UsuarioLocalEsperado.ToLower()
    )
}

function Set-DefaultLocalAdministratorState {
    $Password = ConvertTo-SecureString "12345678" -AsPlainText -Force

    Set-LocalUser -Name "Administrador" `
        -PasswordNeverExpires $true `
        -UserMayChangePassword $true

    Enable-LocalUser -Name "Administrador"
    Set-LocalUser -Name "Administrador" -Password $Password

    Write-Host "[OK] Cuenta local 'Administrador' habilitada y configurada." -ForegroundColor Green
}

function Invoke-DomainJoinConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainName
    )

    $InputHostname = Read-Host "Introduce el nuevo hostname para el equipo"
    $NuevoHostname = $InputHostname.ToUpper()

    if ([string]::IsNullOrWhiteSpace($NuevoHostname)) {
        Exit-Error -Message "[CRITICO] El hostname no puede estar vacio."
    }

    $Credenciales = Get-Credential `
        -UserName "$DomainName\Administrador" `
        -Message "Introduce la clave del Administrador del Dominio para unir el equipo $NuevoHostname"

    Add-Computer -NewName $NuevoHostname `
        -DomainName $DomainName `
        -Credential $Credenciales `
        -Restart
}

function Invoke-PreDomainMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainName,

        [Parameter(Mandatory = $true)]
        [string]$RequiredLocalUser
    )

    Write-Step -Title "MODALIDAD 1 - EQUIPO FUERA DE DOMINIO"

    if (-not (Test-CurrentLocalUser -ExpectedUser $RequiredLocalUser)) {
        Exit-Error `
            -Message "[BLOQUEADO] El equipo no esta en dominio, pero el usuario actual no es .\$RequiredLocalUser." `
            -Details @(
                "Usuario actual: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)",
                "Usuario requerido: $env:COMPUTERNAME\$RequiredLocalUser"
            )
    }

    Write-Host "[OK] Equipo fuera de dominio y usuario local .\$RequiredLocalUser validado." -ForegroundColor Green
    Set-DefaultLocalAdministratorState
    Invoke-DomainJoinConfiguration -DomainName $DomainName
}

function Confirm-ActiveDirectoryOUPlacement {
    Write-Host "Valide que el equipo este ubicado correctamente en la OU del Active Directory." -ForegroundColor Yellow
    $Confirmacion = Read-Host "Presione O para reiniciar el equipo"

    if ($Confirmacion.ToUpper() -ne "O") {
        Write-Host "[CANCELADO] Reinicio cancelado por el usuario." -ForegroundColor Yellow
        exit 0
    }

    Restart-Computer -Force
}

function Test-Domain {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExpectedDomain
    )

    $PropiedadesRed = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
    $DominioActual = $PropiedadesRed.DomainName

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

function Test-AuthorizedUser {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$AllowedUsers
    )

    $UsuarioActual = $env:USERNAME

    if ($AllowedUsers -notcontains $UsuarioActual) {
        Exit-Error `
            -Message "[BLOQUEADO] Usuario no autorizado." `
            -Details @(
                "Usuario actual: $UsuarioActual",
                "Permitidos: $($AllowedUsers -join ', ')"
            )
    }

    Write-Host "[OK] Usuario autorizado: $UsuarioActual" -ForegroundColor Green
}


function Set-AllowedLocalAdministratorPassword {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$AllowedAdministrators
    )

    $UsuarioEncontrado = Get-LocalUser |
        Where-Object { $AllowedAdministrators -contains $_.Name } |
        Select-Object -First 1

    if ($UsuarioEncontrado) {
        $UsuarioNombre = $UsuarioEncontrado.Name
        $Password = Read-Host -Prompt "Introduce la nueva contraseña para $UsuarioNombre" -AsSecureString

        try {
            Set-LocalUser -Name $UsuarioNombre -Password $Password -ErrorAction Stop
            Write-Host "Contraseña modificada correctamente para el usuario: $UsuarioNombre." -ForegroundColor Green
        }
        catch {
            Write-Host "Error: No se pudo cambiar la contraseña. Ejecuta como Administrador." -ForegroundColor Red
        }
    }
    else {
        Write-Host "Error: Ninguno de los usuarios permitidos existe en este equipo." -ForegroundColor Red
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


function Test-RemoteServiceConfiguration {
    $services = @("WinRM", "TermService", "SessionEnv", "RasMan", "RemoteRegistry", "LanmanServer")
    $finalReport = @()

    # Verificacion de Servicios de Remoteo
    Write-Host "===== VALIDACIÓN DE SERVICIOS DE REMOTO =====" -ForegroundColor Yellow
    Write-Host "===== EN EL EQUIPO: $env:COMPUTERNAME =====" -ForegroundColor Yellow
    Write-Host ""

    foreach ($ServiceName in $services) {
        try {
            $service = Get-Service -Name $ServiceName -ErrorAction Stop

            if ($service.Status -eq "Stopped") {
                Write-Host "Servicio detenido encontrado: $ServiceName" -ForegroundColor Red
                Write-Host " → Cambiando el Tipo de inicio a Manual..." -ForegroundColor White
                Set-Service -Name $ServiceName -StartupType Manual

                Write-Host " → Iniciando servicio..." -ForegroundColor White
                Start-Service -Name $ServiceName -ErrorAction SilentlyContinue

                $newState = (Get-Service -Name $ServiceName).Status
                if ($newState -eq "Running") {
                    $finalReport += "El servicio $ServiceName se inicio correctamente."
                }
                else {
                    $finalReport += "El servicio $ServiceName NO se pudo iniciar. Estado final: $newState"
                }

                Write-Host ""
            }
            else {
                $finalReport += "El servicio $ServiceName está en ejecución. No se requirió acción."
            }
        }
        catch {
            $finalReport += "El servicio $ServiceName tuvo error: $($_.Exception.Message)"
        }
    }

    Write-Host "===== ESTADO FINAL DE LOS SERVICIOS =====" -ForegroundColor Cyan
    Write-Host ""

    foreach ($line in $finalReport) {
        if ($line -like "*NO se pudo iniciar*") {
            Write-Host $line -ForegroundColor Red
        }
        else {
            Write-Host $line -ForegroundColor Green
        }
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

    $RutaLDAP = "LDAP://$DomainNetBIOS"
    $BuscadorAD = New-Object System.DirectoryServices.DirectorySearcher

    $BuscadorAD.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry(
        $RutaLDAP,
        $Credential.UserName,
        $Credential.GetNetworkCredential().Password
    )

    $BuscadorAD.Filter = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$UserId))"
    $ResultadoUsuario = $BuscadorAD.FindOne()

    if ($null -eq $ResultadoUsuario) {
        throw "El ID '$UserId' no existe en Active Directory."
    }

    [PSCustomObject]@{
        Id = $UserId
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

    $Confirmacion = Read-Host "Presione O para confirmar o cualquier otra tecla para volver a ingresar el usuario"

    if ($Confirmacion.ToUpper() -eq "O") {
        return $true
    }

    Write-Host "[INFO] Usuario no confirmado. Ingrese nuevamente el ID del usuario de red." -ForegroundColor Yellow
    return $false
}

# ======================================================
# MAIN
# ======================================================
Write-Step -Title "VALIDACION INICIAL DEL ENTORNO"
$DominioActual = Get-CurrentDomainName

if ([string]::IsNullOrWhiteSpace($DominioActual)) {
    Invoke-PreDomainMode -DomainName $DominioCorrecto -RequiredLocalUser $UsuarioAEliminar
    exit 0
}

Test-Domain -ExpectedDomain $DominioCorrecto

if (Test-CurrentLocalUser -ExpectedUser "Administrador") {
    Write-Step -Title "VALIDACION DE UBICACION EN OU"
    Confirm-ActiveDirectoryOUPlacement
    exit 0
}

if (-not (Test-CurrentLocalUser -ExpectedUser "AdmLocalSrvWindows")) {
    Exit-Error `
        -Message "[BLOQUEADO] Equipo en dominio, pero el usuario local actual no es .\Administrador ni .\AdmLocalSrvWindows." `
        -Details @(
            "Usuario actual: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)",
            "Usuarios esperados: $env:COMPUTERNAME\Administrador, $env:COMPUTERNAME\AdmLocalSrvWindows"
        )
}

Write-Host "[OK] Usuario local .\AdmLocalSrvWindows validado para continuar el proceso post-dominio." -ForegroundColor Green
$Credenciales = Get-DomainCredential -DomainNetBIOS $DominioNetBIOS
Test-AuthorizedUser -AllowedUsers $AdministradoresPermitidos

Write-Step -Title "ACTUALIZACION DE CONTRASEÑA DE ADMINISTRADOR LOCAL"
Set-AllowedLocalAdministratorPassword -AllowedAdministrators $AdministradoresPermitidos

Write-Step -Title "LIMPIEZA DE USUARIOS"
Remove-DefaultLocalUser -UserName $UsuarioAEliminar

Write-Step -Title "VALIDACION DE HOSTNAME"
Invoke-HostnameConfiguration -DomainNetBIOS $DominioNetBIOS -LocalGroup $GrupoLocal

Write-Step -Title "VALIDACION DE SERVICIOS DE REMOTO"
Test-RemoteServiceConfiguration

Write-Step -Title "AGREGAR USUARIO DE DOMINIO"
$UsuarioDominioConfirmado = $null

while ($null -eq $UsuarioDominioConfirmado) {
    $UsuarioRed = Read-Host "`nIngrese el ID del usuario de red"

    try {
        $UsuarioDominio = Get-DomainUser `
            -DomainNetBIOS $DominioNetBIOS `
            -Credential $Credenciales `
            -UserId $UsuarioRed

        if (Confirm-Operation -DomainUser $UsuarioDominio) {
            $UsuarioDominioConfirmado = $UsuarioDominio
        }
    }
    catch {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[INFO] Ingrese nuevamente el ID del usuario de red." -ForegroundColor Yellow
    }
}

try {
    Add-DomainUserToLocalGroup `
        -DomainNetBIOS $DominioNetBIOS `
        -Credential $Credenciales `
        -UserId $UsuarioDominioConfirmado.Id `
        -LocalGroup $GrupoLocal
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
}
