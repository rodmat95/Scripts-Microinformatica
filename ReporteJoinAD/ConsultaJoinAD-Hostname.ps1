# Solicita el hostname a consultar
$hostname = Read-Host "Ingrese el hostname a consultar"

# Busca el equipo en el AD
$computer = Get-ADComputer -Identity $hostname -Property Name, WhenCreated, DistinguishedName -ErrorAction SilentlyContinue

if (-not $computer) {
    Write-Host "No se encontró el equipo '$hostname' en el Active Directory." -ForegroundColor Red
    exit
}

# Función para obtener el usuario que unió el equipo al dominio
function Get-UserWhoJoinedComputer {
    param (
        [string]$computerDN
    )

    try {
        $ownerDN = (Get-Acl "ad:\$computerDN").Owner
        $ownerSam = $ownerDN.Split('\')[1]

        $user = Get-ADUser -Identity $ownerSam -ErrorAction Stop

        return $user.Name
    }
    catch {
        return "No se pudo determinar el usuario (posible cuenta eliminada)."
    }
}

# Obtiene el usuario que creó el objeto en AD
$usuarioUnion = Get-UserWhoJoinedComputer -computerDN $computer.DistinguishedName

# Muestra resultados
Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "  INFORMACIÓN DEL EQUIPO: $($computer.Name)" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Cyan

Write-Host "Hostname:              $($computer.Name)"
Write-Host "Fecha de creación AD:  $($computer.WhenCreated.ToString('yyyy-MM-dd HH:mm'))"
Write-Host "Usuario que lo creó:   $usuarioUnion"

Write-Host "====================================================" -ForegroundColor Cyan