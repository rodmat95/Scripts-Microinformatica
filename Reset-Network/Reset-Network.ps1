Start-Sleep -Seconds 20

Start-Transcript -Path "C:\Windows\Temp\Reset-Network.log" -Append

try {
    ipconfig /release
    Start-Sleep -Seconds 3

    ipconfig /renew
    Clear-DnsClientCache
    Register-DnsClient

    netsh winsock reset
    netsh int ip reset

    Get-NetAdapter |
        Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface } |
        Restart-NetAdapter -Confirm:$false

}
catch {
    $_ | Out-File "C:\Windows\Temp\Reset-Network-error.log" -Append
}

Stop-Transcript