# Fecha y ruta de salida
$fecha = Get-Date -Format "yyyyMMdd_HHmm"
$rutaSalida = "C:\Reportes\AD_Usuarios_$fecha.csv"

# Crea la carpeta si no existe
$carpeta = Split-Path $rutaSalida
if (!(Test-Path $carpeta)) { New-Item -ItemType Directory -Path $carpeta | Out-Null }

# Asegura el módulo de Active Directory
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

# Obtiene todos los usuarios y selecciona los campos requeridos
Get-ADUser -Filter * -Properties sAMAccountName, displayName, title, mobile, mail, physicalDeliveryOfficeName `
| Select-Object `
    @{Name="Matricula"; Expression = { $_.sAMAccountName }},
    @{Name="Nombre";    Expression = { $_.displayName }},
    @{Name="Puesto";    Expression = { $_.title }},
    @{Name="Movil";     Expression = { $_.mobile }},
    @{Name="Correo";    Expression = { $_.mail }},
    @{Name="Oficina";   Expression = { $_.physicalDeliveryOfficeName }} |
Export-Csv -Path $rutaSalida -NoTypeInformation -Encoding UTF8 -Delimiter ';'

Write-Host "Exportación completada: $rutaSalida"