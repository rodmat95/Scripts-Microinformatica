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

    $Confirmacion = Read-Host "Presione O para continuar"

    if ($Confirmacion.ToUpper() -ne "O") {
        Write-Host "[CANCELADO] Operacion cancelada." -ForegroundColor Yellow
        exit 0
    }
}

# ======================================================
# MAIN
# ======================================================
Write-Step -Title "VALIDACION INICIAL DEL ENTORNO"
Test-Domain -ExpectedDomain $DominioCorrecto
$Credenciales = Get-DomainCredential -DomainNetBIOS $DominioNetBIOS
Test-AuthorizedUser -AllowedUsers $AdministradoresPermitidos

Write-Step -Title "LIMPIEZA DE USUARIOS"
Remove-DefaultLocalUser -UserName $UsuarioAEliminar

Write-Step -Title "VALIDACION DE HOSTNAME"
Invoke-HostnameConfiguration -DomainNetBIOS $DominioNetBIOS -LocalGroup $GrupoLocal

Write-Step -Title "AGREGAR USUARIO DE DOMINIO"
$UsuarioRed = Read-Host "`nIngrese el ID del usuario de red"

try {
    $UsuarioDominio = Get-DomainUser `
        -DomainNetBIOS $DominioNetBIOS `
        -Credential $Credenciales `
        -UserId $UsuarioRed

    Confirm-Operation -DomainUser $UsuarioDominio

    Add-DomainUserToLocalGroup `
        -DomainNetBIOS $DominioNetBIOS `
        -Credential $Credenciales `
        -UserId $UsuarioDominio.Id `
        -LocalGroup $GrupoLocal
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
}
