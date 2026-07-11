# ===========================
# Información OperatingSystem
# ===========================
Write-Host "===== Información del Sistema Operativo =====" -ForegroundColor Cyan
Get-WmiObject Win32_OperatingSystem | Select-Object `
    Caption, Version, BuildNumber, OSArchitecture,
    @{Name="InstallDate";Expression={($_.ConvertToDateTime($_.InstallDate)).ToString("yyyy-MM-dd")}},
    @{Name="LastBootUpTime";Expression={($_.ConvertToDateTime($_.LastBootUpTime)).ToString("yyyy-MM-dd")}},
    Manufacturer, SerialNumber, Status
Write-Host ""

# ===========================
# Información ComputerSystem
# ===========================
Write-Host "===== Información del Sistema =====" -ForegroundColor Cyan
Get-WmiObject Win32_ComputerSystem | Select-Object `
    Manufacturer, Model, SystemType, NumberOfProcessors, NumberOfLogicalProcessors,
    @{Name="TotalPhysicalMemory (MB)";Expression={[math]::Round($_.TotalPhysicalMemory / 1MB, 2)}},
    BootupState, DNSHostName, Domain, Status
Write-Host ""

# ===========================
# Información ComputerSystemProduct
# ===========================
Write-Host "===== Información del Producto del Sistema (OEM) =====" -ForegroundColor Cyan
Get-WmiObject Win32_ComputerSystemProduct | Select-Object `
    Description, Vendor, Name, IdentifyingNumber, UUID
Write-Host ""

# ===========================
# Información Processor
# ===========================
Write-Host "===== Información del Procesador =====" -ForegroundColor Cyan
# Tipos de arquitectura
$archMap = @{
    0 = "x86"; 1 = "MIPS"; 2 = "Alpha"; 3 = "PowerPC";
    5 = "ARM"; 6 = "Itanium-based"; 9 = "x64"; 12 = "ARM64"
}
# Tipos de procesador
$processorTypeMap = @{
    1="Otro"; 2="Desconocido"; 3="CPU central";
    4="Procesador matemático"; 5="Canal multiprocesador (MPC)";
    6="DSP (Digital Signal Processor)"; 7="Video Processor"
}
# Tipos de estatus del CPU
$cpuStatusMap = @{
    0="Desconocido"; 1="CPU habilitada";
    2="CPU deshabilitada"; 3="Fuera de servicio";
    4="En prueba"; 7="No aplicable"
}
Get-WmiObject Win32_Processor | Select-Object `
    Role, Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, CurrentClockSpeed,
    @{Name="Architecture";Expression={ $key = [int]$_.Architecture
        $( if ($archMap.ContainsKey($key)) { $archMap[$key] } else { $_.Architecture } )
    }},
    @{Name="ProcessorType";Expression={ $key = [int]$_.ProcessorType
        $( if ($processorTypeMap.ContainsKey($key)) { $processorTypeMap[$key] } else { $_.ProcessorType } )
    }},
    ProcessorId,
    @{Name="CpuStatus";Expression={
        $key = [int]$_.CpuStatus
        $( if ($cpuStatusMap.ContainsKey($key)) { $cpuStatusMap[$key] } else { $_.CpuStatus } )
    }},
    Status
Write-Host ""

# ===========================
# Información BaseBoard
# ===========================
Write-Host "===== Información de la Placa Base =====" -ForegroundColor Cyan
Get-WmiObject Win32_BaseBoard | Select-Object `
    Description, Manufacturer, Product, Version, SerialNumber, Status
Write-Host ""

# ===========================
# Información MotherboardDevice
# ===========================
Write-Host "===== Información del Dispositivo de la Placa Madre =====" -ForegroundColor Cyan
# Tipos de disponibilidad
$availabilityMap = @{
    0="Desconocido"; 1="Otro"; 2="No disponible"; 3="Ejecutándose/Full Power";
    4="Advertencia"; 5="En prueba"; 6="No aplicable"; 7="Apagado";
    8="Apagado pero listo"; 9="Reiniciando"; 10="En espera";
    11="En ciclo de energía"; 12="En reserva"; 13="Pausado";
    14="Bajo consumo"; 15="En espera"; 16="Suspendido"; 17="Lista"
}
Get-WmiObject Win32_MotherboardDevice | Select-Object `
    Description, PrimaryBusType, SecondaryBusType,
    @{Name="Availability";Expression={ $key = [int]$_.Availability
        $( if ($availabilityMap.ContainsKey($key)) { $availabilityMap[$key] } else { $_.Availability } )
    }},
    Status
Write-Host ""

# ===========================
# Información PhysicalMemory
# ===========================
Write-Host "===== Información de la Memoria Física =====" -ForegroundColor Cyan
# Tipos de memoria
$memTypeMap = @{
    0="Desconocido"; 1="Otro"; 2="DRAM"; 3="Synchronous DRAM"; 4="Cache DRAM";
    5="EDO"; 6="EDRAM"; 7="VRAM"; 8="SRAM"; 9="RAM"; 10="ROM"; 11="Flash";
    12="EEPROM"; 13="FEPROM"; 14="EPROM"; 15="CDRAM"; 16="3DRAM"; 17="SDRAM";
    18="SGRAM"; 19="RDRAM"; 20="DDR"; 21="DDR2"; 22="DDR2 FB-DIMM"; 24="DDR3";
    26="DDR4"; 27="LPDDR"; 28="LPDDR2"; 29="LPDDR3"; 30="LPDDR4"; 31="LPDDR4X";
    32="DDR5"; 33="LPDDR5"
}
Get-WmiObject Win32_PhysicalMemory | Select-Object `
    Description, Manufacturer, PartNumber,
    @{Name="MemoryType";Expression={ $key = [int]$_.MemoryType
        $( if ($memTypeMap.ContainsKey($key)) { $memTypeMap[$key] } else { $_.MemoryType } )
    }},
    @{Name="Capacity (MB)";Expression={[math]::Round($_.Capacity / 1MB, 2)}},
    Speed, ConfiguredClockSpeed, SerialNumber
Write-Host ""

# ===========================
# Información DiskDrive
# ===========================
Write-Host "===== Información de la Unidad de Disco =====" -ForegroundColor Cyan
Get-WmiObject Win32_DiskDrive | Select-Object `
    Description, Model, MediaType, InterfaceType,
    @{Name="Size (MB)";Expression={[math]::round($_.Size / 1MB, 2)}}, 
    Partitions, FirmwareRevision, SerialNumber, Status
Write-Host ""


# ===========================
# Información de los productos instalados
# ===========================
<#
Write-Host "===== Información de los productos instalados =====" -ForegroundColor Cyan
Get-WmiObject Win32_Product | Select-Object `
    Name, Version, Vendor, InstallDate
Write-Host ""
#>