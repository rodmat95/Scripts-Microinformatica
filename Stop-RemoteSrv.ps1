# Desactivar Servicios de Escritorio Remoto
Set-Service -Name WinRM -StartupType Disabled -PassThru | Stop-Service -Force
Set-Service -Name TermService -StartupType Disabled -PassThru | Stop-Service -Force
Set-Service -Name SessionEnv -StartupType Disabled -PassThru | Stop-Service -Force
Set-Service -Name RasMan -StartupType Disabled -PassThru | Stop-Service -Force
Set-Service -Name RemoteRegistry -StartupType Disabled -PassThru | Stop-Service -Force

# Desabilitar Reglas del Grupo de Escritorio Remoto
if (Get-NetFirewallRule -DisplayGroup "Escritorio remoto" -Enabled True -ErrorAction SilentlyContinue) {
    Disable-NetFirewallRule -DisplayGroup "Escritorio remoto"
}

# Desactivar conexiones de Escritorio Remoto
if ((Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server').fDenyTSConnections -ne 1) {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1
}

# Desactivar Autenticación a Nivel de Red (NLA)
if ((Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp').UserAuthentication -ne 0) {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0
}

# Desactivar la Capacidad de Escritorio Remoto
if ((Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Remote Assistance').fAllowToGetHelp -ne 0) {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Remote Assistance' -Name "fAllowToGetHelp" -Value 0
}