param (
    [string[]]$ComputerName
)

# Si no se pasó por parámetro, pedir uno o varios (separados por coma)
if (-not $ComputerName -or $ComputerName.Count -eq 0) {
    $inputStr = Read-Host "Ingrese uno o varios equipos (hostname o IP), separados por coma"
    # Usar -split + pipeline (compatible con Windows PowerShell 5.x)
    $ComputerName = ($inputStr -split '\s*,\s*') | Where-Object { $_ -ne '' }
}

# Configurar TrustedHosts en '*'
Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force

# ---

# Credenciales fijas
$user = "EM72647765"
$password = ConvertTo-SecureString "M1c01\\M1b@nC0" -AsPlainText -Force

# Obtener credenciales
# $cred = Get-Credential
# $password = Get-Credential -UserName $user -Message "Proporcione su contraseña" | Select-Object -ExpandProperty Password

# Crear el objeto de credenciales
$cred = New-Object System.Management.Automation.PSCredential ($user, $password)

# ---

# Crear las sesiones remotas (misma autenticación: Negotiate)
$sessions = @()
foreach ($c in $ComputerName) {
    try {
        $s = New-PSSession -ComputerName $c -Credential $cred -Authentication Negotiate -ErrorAction Stop
        $sessions += $s
        Write-Host "Sesión creada: Id=$($s.Id) Equipo=$c"
    } catch {
        Write-Warning "No se pudo crear sesión con '$c': $($_.Exception.Message)"
    }
}

if (-not $sessions -or $sessions.Count -eq 0) {
    Write-Error "No hay sesiones disponibles."
    return
}

# Función auxiliar para saltar entre sesiones por índice o nombre
function Switch-Session {
    param(
        [Parameter(Mandatory=$false)]
        [int]$Index,

        [Parameter(Mandatory=$false)]
        [string]$Name
    )

    $target = $null
    if ($PSBoundParameters.ContainsKey('Index')) {
        if ($Index -lt 0 -or $Index -ge $sessions.Count) {
            Write-Warning "Indice fuera de rango. Use 0..$($sessions.Count - 1)."
            return
        }
        $target = $sessions[$Index]
    } elseif ($PSBoundParameters.ContainsKey('Name')) {
        $target = $sessions | Where-Object { $_.ComputerName -ieq $Name } | Select-Object -First 1
        if (-not $target) {
            Write-Warning "No se encontro una sesion para '$Name'."
            return
        }
    } else {
        Write-Host ""
        Write-Host "Sesiones disponibles:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $sessions.Count; $i++) {
            $s = $sessions[$i]
            Write-Host ("[{0}] Id={1} Equipo={2} Estado={3}" -f $i, $s.Id, $s.ComputerName, $s.State)
        }
        $sel = Read-Host "Ingrese el indice de la sesión a abrir"
        if (-not [int]::TryParse($sel, [ref]$Index)) {
            Write-Warning "Entrada no valida."
            return
        }
        if ($Index -lt 0 -or $Index -ge $sessions.Count) {
            Write-Warning "Indice fuera de rango."
            return
        }
        $target = $sessions[$Index]
    }

    Write-Host "Entrando a sesion: Id=$($target.Id) Equipo=$($target.ComputerName)"
    Enter-PSSession -Session $target
    # Al salir con 'Exit-PSSession', regresas aquí.
}

# Entrar a la primera sesion por defecto (igual que tu script)
Write-Host "Entrando a la primera sesion por defecto..."
Enter-PSSession -Session $sessions[0]

# Menú para saltar entre sesiones
while ($true) {
    Write-Host ""
    Write-Host "Opciones: (I)ndice, (N)ombre, (L)istar, (S)alir" -ForegroundColor Cyan
    $opt = Read-Host "Seleccione opcion"

    switch ($opt.ToUpper()) {
        'I' { Switch-Session }             # mostrará menú e índice
        'N' {
            $name = Read-Host "Nombre/IP del equipo"
            Switch-Session -Name $name
        }
        'L' {
            for ($i = 0; $i -lt $sessions.Count; $i++) {
                $s = $sessions[$i]
                Write-Host ("[{0}] Id={1} Equipo={2} Estado={3}" -f $i, $s.Id, $s.ComputerName, $s.State)
            }
        }
        'S' { break }
        default { Write-Warning "Opcion no valida." }
    }
}

# Cerrar sesiones al terminar
Remove-PSSession -Session $sessions -ErrorAction SilentlyContinue
Write-Host "Sesiones cerradas."