Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Windows.Forms;

public class DataGridViewProgressCell : DataGridViewTextBoxCell
{
    public DataGridViewProgressCell()
    {
        this.ValueType = typeof(int);
    }

    protected override void Paint(Graphics graphics, Rectangle clipBounds, Rectangle cellBounds, int rowIndex,
        DataGridViewElementStates cellState, object value, object formattedValue, string errorText,
        DataGridViewCellStyle cellStyle, DataGridViewAdvancedBorderStyle advancedBorderStyle,
        DataGridViewPaintParts paintParts)
    {
        base.Paint(graphics, clipBounds, cellBounds, rowIndex, cellState, value, formattedValue, errorText,
            cellStyle, advancedBorderStyle, paintParts & ~DataGridViewPaintParts.ContentForeground);

        int progress = 0;
        if (value != null)
        {
            Int32.TryParse(value.ToString(), out progress);
        }
        progress = Math.Max(0, Math.Min(100, progress));

        Rectangle barBounds = new Rectangle(cellBounds.X + 4, cellBounds.Y + 6, cellBounds.Width - 8, cellBounds.Height - 12);
        if (barBounds.Width <= 0 || barBounds.Height <= 0)
        {
            return;
        }

        graphics.FillRectangle(Brushes.White, barBounds);
        graphics.DrawRectangle(Pens.Gray, barBounds);

        int barWidth = (int)Math.Round((barBounds.Width - 1) * (progress / 100.0));
        if (barWidth > 0)
        {
            Rectangle progressBounds = new Rectangle(barBounds.X + 1, barBounds.Y + 1, barWidth, barBounds.Height - 1);
            graphics.FillRectangle(Brushes.LightGreen, progressBounds);
        }

        string text = progress.ToString() + "%";
        TextRenderer.DrawText(graphics, text, cellStyle.Font, barBounds, Color.Black,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
    }
}

public class DataGridViewProgressColumn : DataGridViewColumn
{
    public DataGridViewProgressColumn() : base(new DataGridViewProgressCell())
    {
        this.ValueType = typeof(int);
    }
}
"@ -ReferencedAssemblies System.Windows.Forms,System.Drawing

# Lista de equipos
$computers    = 129..148 | ForEach-Object { "A12AVD01-$_" }
<#
# Lista de equipos de forma unitaria
$computers     = @(
	'L12AUD75','L12AUD48','L12AUD90','L12AUD34'
)
#>

# Origen LOCAL
$sourcePath = 'D:\python-3.12.8-amd64.exe'   # archivo o carpeta

# Ruta destino
$shareRoot    = 'C$'
$relativePath = ''   # '' = raíz | 'Tools' = subcarpeta

function New-CopyWindow {
    param([string[]]$ComputerList)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Multi-CopyFiles - Estado de copiado'
    $form.Size = New-Object System.Drawing.Size(1000, 650)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = New-Object System.Drawing.Size(850, 500)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Top'
    $grid.Height = 360
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.ReadOnly = $true
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.SelectionMode = 'FullRowSelect'

    [void]$grid.Columns.Add('Equipo', 'VM')
    [void]$grid.Columns.Add('Estado', 'Estado')
    $progressColumn = New-Object DataGridViewProgressColumn
    $progressColumn.Name = 'Progreso'
    $progressColumn.HeaderText = 'Progreso VM'
    [void]$grid.Columns.Add($progressColumn)
    [void]$grid.Columns.Add('Destino', 'Destino')
    [void]$grid.Columns.Add('Detalle', 'Detalle')

    $grid.Columns['Equipo'].FillWeight = 18
    $grid.Columns['Estado'].FillWeight = 14
    $grid.Columns['Progreso'].FillWeight = 18
    $grid.Columns['Destino'].FillWeight = 30
    $grid.Columns['Detalle'].FillWeight = 35

    foreach ($pc in $ComputerList) {
        [void]$grid.Rows.Add($pc, 'Pendiente', 0, '', '')
    }

    $lblGeneral = New-Object System.Windows.Forms.Label
    $lblGeneral.Text = 'Progreso general: 0%'
    $lblGeneral.Dock = 'Top'
    $lblGeneral.Height = 24
    $lblGeneral.Padding = New-Object System.Windows.Forms.Padding(8, 4, 0, 0)

    $progressGeneral = New-Object System.Windows.Forms.ProgressBar
    $progressGeneral.Dock = 'Top'
    $progressGeneral.Height = 25
    $progressGeneral.Minimum = 0
    $progressGeneral.Maximum = [Math]::Max(1, $ComputerList.Count)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Dock = 'Fill'
    $txtLog.Multiline = $true
    $txtLog.ScrollBars = 'Both'
    $txtLog.ReadOnly = $true
    $txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)

    $form.Controls.Add($txtLog)
    $form.Controls.Add($progressGeneral)
    $form.Controls.Add($lblGeneral)
    $form.Controls.Add($grid)

    [pscustomobject]@{
        Form = $form
        Grid = $grid
        ProgressGeneral = $progressGeneral
        LabelGeneral = $lblGeneral
        Log = $txtLog
    }
}

function Write-UiLog {
    param($Ui, [string]$Message)

    $line = '{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message
    $Ui.Log.AppendText($line + [Environment]::NewLine)
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-RowState {
    param($Ui, [int]$RowIndex, [string]$Estado, [int]$Progress, [string]$Destino, [string]$Detalle)

    $row = $Ui.Grid.Rows[$RowIndex]
    $row.Cells['Estado'].Value = $Estado
    $row.Cells['Progreso'].Value = [Math]::Max(0, [Math]::Min(100, $Progress))
    if ($PSBoundParameters.ContainsKey('Destino')) { $row.Cells['Destino'].Value = $Destino }
    if ($PSBoundParameters.ContainsKey('Detalle')) { $row.Cells['Detalle'].Value = $Detalle }

    switch ($Estado) {
        'OK'        { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::Honeydew }
        'ERROR'     { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::MistyRose }
        'Copiando'  { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightCyan }
        default     { $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::White }
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Copy-FileWithProgress {
    param([string]$Source, [string]$Destination, $Ui, [int]$RowIndex)

    $bufferSize = 4MB
    $sourceInfo = Get-Item -Path $Source -ErrorAction Stop
    $totalBytes = [Math]::Max(1, $sourceInfo.Length)
    $copiedBytes = 0L

    $inputStream = [System.IO.File]::Open($Source, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $outputStream = [System.IO.File]::Open($Destination, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $buffer = New-Object byte[] $bufferSize
            while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $outputStream.Write($buffer, 0, $read)
                $copiedBytes += $read
                $percent = [int](($copiedBytes * 100) / $totalBytes)
                Set-RowState -Ui $Ui -RowIndex $RowIndex -Estado 'Copiando' -Progress $percent -Destino $Destination -Detalle ('{0:N1} MB / {1:N1} MB' -f ($copiedBytes / 1MB), ($totalBytes / 1MB))
            }
        } finally {
            $outputStream.Close()
        }
    } finally {
        $inputStream.Close()
    }
}

function Invoke-CopyToComputer {
    param([string]$Pc, [int]$RowIndex, $Ui)

    $itemName = Split-Path $sourcePath -Leaf

    if (-not $relativePath) {
        $destRoot = "\\$Pc\$shareRoot"
    } else {
        $destRoot = "\\$Pc\$shareRoot\$relativePath"
    }

    $destPath = Join-Path $destRoot $itemName
    $now      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    try {
        Set-RowState -Ui $Ui -RowIndex $RowIndex -Estado 'Copiando' -Progress 5 -Destino $destPath -Detalle 'Validando origen y destino'
        Write-UiLog -Ui $Ui -Message "[$Pc] Validando origen local: $sourcePath"

        if (-not (Test-Path $sourcePath)) {
            throw "No existe origen LOCAL: $sourcePath"
        }

        Write-UiLog -Ui $Ui -Message "[$Pc] Validando acceso remoto: \\$Pc\$shareRoot"
        if (-not (Test-Path "\\$Pc\$shareRoot")) {
            throw "No acceso a \\$Pc\$shareRoot"
        }

        if (-not (Test-Path $destRoot)) {
            Write-UiLog -Ui $Ui -Message "[$Pc] Creando carpeta destino: $destRoot"
            New-Item -Path $destRoot -ItemType Directory -Force | Out-Null
        }

        $isDirectory = (Get-Item $sourcePath).PSIsContainer

        if ($isDirectory) {
            Set-RowState -Ui $Ui -RowIndex $RowIndex -Estado 'Copiando' -Progress 25 -Destino $destPath -Detalle 'Copiando carpeta con robocopy'
            Write-UiLog -Ui $Ui -Message "[$Pc] Iniciando robocopy hacia $destPath"
            $cmd = "robocopy `"$sourcePath`" `"$destPath`" /E /Z /R:2 /W:2 /NFL /NDL"
            $proc = Start-Process cmd.exe -ArgumentList "/c $cmd" -Wait -PassThru
            $exit = $proc.ExitCode
            $ok = ($exit -le 7)
            Set-RowState -Ui $Ui -RowIndex $RowIndex -Estado 'Copiando' -Progress 90 -Destino $destPath -Detalle "Robocopy ExitCode: $exit"
        } else {
            Write-UiLog -Ui $Ui -Message "[$Pc] Copiando archivo hacia $destPath"
            Copy-FileWithProgress -Source $sourcePath -Destination $destPath -Ui $Ui -RowIndex $RowIndex
            $exit = 0
            $ok   = $true
        }

        $exists = Test-Path $destPath
        $result = if ($ok -and $exists) { 'OK' } else { 'ERROR' }
        Set-RowState -Ui $Ui -RowIndex $RowIndex -Estado $result -Progress $(if ($result -eq 'OK') { 100 } else { 0 }) -Destino $destPath -Detalle "Verificado: $exists; ExitCode: $exit"
        Write-UiLog -Ui $Ui -Message "[$Pc] Resultado: $result (Verificado: $exists; ExitCode: $exit)"

        [pscustomobject]@{
            Equipo     = $Pc
            Origen     = $sourcePath
            Destino    = $destPath
            Tipo       = if ($isDirectory) { 'Carpeta' } else { 'Archivo' }
            ExitCode   = $exit
            Verificado = $exists
            Resultado  = $result
            Fecha      = $now
        }
    } catch {
        Set-RowState -Ui $Ui -RowIndex $RowIndex -Estado 'ERROR' -Progress 0 -Destino $destRoot -Detalle $_.Exception.Message
        Write-UiLog -Ui $Ui -Message "[$Pc] ERROR: $($_.Exception.Message)"

        [pscustomobject]@{
            Equipo     = $Pc
            Origen     = $sourcePath
            Destino    = $destRoot
            Tipo       = 'N/A'
            ExitCode   = $null
            Verificado = $false
            Resultado  = 'ERROR'
            Mensaje    = $_.Exception.Message
            Fecha      = $now
        }
    }
}

# Encabezado
$nombre = Split-Path $sourcePath -Leaf
$ui = New-CopyWindow -ComputerList $computers
$ui.Form.Show()
Write-UiLog -Ui $ui -Message "===== Copiado de $nombre a $($computers.Count) equipos ====="

$resultados = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $computers.Count; $i++) {
    if ($ui.Form.IsDisposed) { break }

    $pc = $computers[$i]
    $resultado = Invoke-CopyToComputer -Pc $pc -RowIndex $i -Ui $ui
    [void]$resultados.Add($resultado)

    $ui.ProgressGeneral.Value = [Math]::Min($ui.ProgressGeneral.Maximum, $i + 1)
    $percentGeneral = [int]((($i + 1) * 100) / [Math]::Max(1, $computers.Count))
    $ui.LabelGeneral.Text = "Progreso general: $percentGeneral% ($($i + 1)/$($computers.Count))"
    [System.Windows.Forms.Application]::DoEvents()
}

Write-UiLog -Ui $ui -Message '===== Proceso finalizado ====='
$resultados | Format-Table -AutoSize
[void][System.Windows.Forms.MessageBox]::Show('Proceso finalizado. Revise la tabla y el log para ver el detalle.', 'Multi-CopyFiles', 'OK', 'Information')
