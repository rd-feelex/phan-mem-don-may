<#
=====================================================================
 Reset-Machine-GUI.ps1
 Giao dien (WinForms) cho cong cu xoa vinh vien du lieu ca nhan,
 giu lai ung dung + cau hinh app.
   1) Bam "Quet"  -> hien bang nhung gi SE bi xoa (kem dung luong)
   2) Tick chon / bo tung muc
   3) Bam "XOA VINH VIEN" -> xac nhan -> xoa (ghi de an toan)
 Xoa chay o luong nen, co thanh tien trinh + log + nut Huy.
 !!! KHONG THE HOAN TAC !!!
=====================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# ---- Yeu cau quyen Administrator ----
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`""
        )
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Can chay voi quyen Administrator.","Reset Machine") | Out-Null
    }
    return
}

# ---------------------------------------------------------------------
# CAU HINH (giong ban CLI)
# ---------------------------------------------------------------------
$UserDataFolders = @(
    'Desktop','Documents','Downloads','Pictures','Music','Videos',
    'Favorites','Contacts','Links','Searches','Saved Games','3D Objects','OneDrive'
)
$SkipProfiles = @('Public','Default','Default User','All Users','defaultuser0')

# DANH SACH GIU LAI: cac duong dan nay (va moi thu ben trong) KHONG BAO GIO bi xoa.
# Them duong dan ke toan / du lieu quan trong vao day de an toan tuyet doi.
# Vi du:
#   $KeepPaths = @('D:\MERGE', 'C:\Users\ketoan\Documents\MISA', 'C:\KETOAN')
$KeepPaths = @(
    # 'D:\MERGE'
)

# ---------------------------------------------------------------------
# State chia se giua UI va luong nen
# ---------------------------------------------------------------------
$sync = [hashtable]::Synchronized(@{
    Log        = New-Object System.Collections.ArrayList
    Scan       = New-Object System.Collections.ArrayList
    FilesTotal = 0
    FilesDone  = 0
    BytesDone  = 0
    Status     = ''
    Cancel     = $false
    Busy       = $false
    Phase      = ''   # 'scan' | 'delete' | ''
    PendingReboot = $false
})

function Format-Size([long]$b) {
    if ($b -ge 1GB) { return ("{0:N2} GB" -f ($b/1GB)) }
    if ($b -ge 1MB) { return ("{0:N1} MB" -f ($b/1MB)) }
    if ($b -ge 1KB) { return ("{0:N0} KB" -f ($b/1KB)) }
    return "$b B"
}

# ---------------------------------------------------------------------
# Scriptblock chung: dinh nghia ham secure-delete (chay trong runspace)
# ---------------------------------------------------------------------
$CoreFunctions = @'
function WLog($sync,$msg){ [void]$sync.Log.Add($msg) }

function Test-Kept($path,$keeps){
    if (-not $keeps) { return $false }
    $full = [System.IO.Path]::GetFullPath($path).TrimEnd('\')
    foreach ($keep in $keeps) {
        if ([string]::IsNullOrWhiteSpace($keep)) { continue }
        $k = [System.IO.Path]::GetFullPath($keep).TrimEnd('\')
        if ($full -eq $k -or $full.StartsWith($k + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Schedule-DeleteOnReboot($sync,$path){
    # MOVEFILE_DELAY_UNTIL_REBOOT = 4 ; lpNewFileName = null => xoa khi khoi dong lai
    try {
        $ok = [NativeDel]::MoveFileEx($path, $null, 4)
        if ($ok) { WLog $sync ("  KHOA - da len lich XOA KHI KHOI DONG LAI: " + $path); $sync.PendingReboot = $true }
        else     { WLog $sync ("  LOI: khong len lich xoa duoc: " + $path) }
    } catch { WLog $sync ("  LOI: " + $path + " -> " + $_.Exception.Message) }
}

function Remove-FileSecure($sync,$path,$passes){
    $maxTry = 3
    for ($attempt=1; $attempt -le $maxTry; $attempt++) {
        try {
            $fi = New-Object System.IO.FileInfo($path)
            if ($fi.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                $fi.Attributes = [System.IO.FileAttributes]::Normal
            }
            $len = $fi.Length
            if ($len -gt 0) {
                $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
                $bufSize = [Math]::Min($len, 4MB)
                $buf = New-Object byte[] $bufSize
                for ($p=0; $p -lt $passes; $p++) {
                    $fs = [System.IO.File]::Open($path,'Open','Write','None')
                    try {
                        $fs.Position = 0; $rem = $len
                        while ($rem -gt 0) {
                            $chunk = [Math]::Min($rem, $buf.Length)
                            $rng.GetBytes($buf); $fs.Write($buf,0,$chunk); $rem -= $chunk
                        }
                        $fs.Flush($true)
                    } finally { $fs.Close() }
                }
                $rng.Dispose()
            }
            $rand = [System.IO.Path]::GetRandomFileName()
            Rename-Item -LiteralPath $path -NewName $rand -ErrorAction SilentlyContinue
            $newPath = Join-Path $fi.DirectoryName $rand
            if (Test-Path -LiteralPath $newPath) { Remove-Item -LiteralPath $newPath -Force -ErrorAction Stop }
            else { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
            $sync.FilesDone++; $sync.BytesDone += $len
            return
        } catch {
            if ($attempt -lt $maxTry) { Start-Sleep -Milliseconds 300; continue }
            # Het luot thu -> file van bi khoa -> len lich xoa khi khoi dong lai
            Schedule-DeleteOnReboot $sync $path
        }
    }
}

function Stop-ProcsInPaths($sync,$paths,$keeps){
    WLog $sync "-- Tat cac app dang chay trong vung xoa --"
    $procs = Get-Process -ErrorAction SilentlyContinue
    foreach ($pr in $procs) {
        $ppath = $null
        try { $ppath = $pr.Path } catch { $ppath = $null }
        if ([string]::IsNullOrWhiteSpace($ppath)) { continue }
        # Khong tat tien trinh he thong Windows
        if ($ppath -match '(?i)\\Windows\\') { continue }
        if (Test-Kept $ppath $keeps) { continue }
        $pf = [System.IO.Path]::GetFullPath($ppath).TrimEnd('\')
        foreach ($t in $paths) {
            if ([string]::IsNullOrWhiteSpace($t)) { continue }
            $tf = [System.IO.Path]::GetFullPath($t).TrimEnd('\')
            if ($pf -eq $tf -or $pf.StartsWith($tf + '\', [StringComparison]::OrdinalIgnoreCase)) {
                try { WLog $sync ("  Tat: " + $pr.ProcessName + " (" + $ppath + ")"); Stop-Process -Id $pr.Id -Force -ErrorAction Stop }
                catch { WLog $sync ("  Khong tat duoc: " + $pr.ProcessName) }
                break
            }
        }
    }
    Start-Sleep -Milliseconds 1000
}

function Remove-FolderSecure($sync,$folder,$passes,$keeps){
    if (-not (Test-Path -LiteralPath $folder)) { return }
    if (Test-Kept $folder $keeps) { WLog $sync ("GIU LAI (bo qua): " + $folder); return }
    WLog $sync ("-> " + $folder)
    # CHI xoa FILE (ghi de vinh vien). GIU NGUYEN toan bo thu muc (khong xoa folder).
    Get-ChildItem -LiteralPath $folder -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($sync.Cancel) { return }
        if (Test-Kept $_.FullName $keeps) { return }
        $sync.Status = $_.FullName
        Remove-FileSecure $sync $_.FullName $passes
    }
}
'@

# ---------------------------------------------------------------------
# WORKER: QUET
# ---------------------------------------------------------------------
$ScanScript = {
    param($sync, $skipProfiles, $wipeOtherDrives, $keeps)

    function Test-KeptScan($path,$keeps){
        if (-not $keeps) { return $false }
        $full = [System.IO.Path]::GetFullPath($path).TrimEnd('\')
        foreach ($keep in $keeps) {
            if ([string]::IsNullOrWhiteSpace($keep)) { continue }
            $k = [System.IO.Path]::GetFullPath($keep).TrimEnd('\')
            if ($full -eq $k -or $full.StartsWith($k + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }
    function Is-Reparse($item){ return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) }
    function Add-ScanRow($sync,$group,$item){
        if ($item.PSIsContainer) {
            $files = Get-ChildItem -LiteralPath $item.FullName -File -Recurse -Force -ErrorAction SilentlyContinue
            $count = ($files | Measure-Object).Count
            $bytes = ($files | Measure-Object -Property Length -Sum).Sum
        } else { $count = 1; $bytes = $item.Length }
        if (-not $bytes) { $bytes = 0 }
        [void]$sync.Scan.Add([pscustomobject]@{
            Profile=$group; Item=$item.Name; Path=$item.FullName; Files=$count; Bytes=[long]$bytes
        })
    }

    $sync.Busy = $true; $sync.Phase = 'scan'; $sync.Cancel = $false
    $sync.Scan.Clear()
    try {
        $sysDrive = $env:SystemDrive

        # --- (A) MOI thu trong tung profile, TRU AppData + file he thong ---
        $usersRoot = Join-Path $sysDrive 'Users'
        Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $p = $_
            if ($skipProfiles -contains $p.Name) { return }
            Get-ChildItem -LiteralPath $p.FullName -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $it = $_
                if ($sync.Cancel) { return }
                if (Is-Reparse $it) { return }   # bo cac junction he thong (Application Data, My Documents...)
                if ($it.Name -match '(?i)^(AppData|Application Data|Local Settings|NTUSER\..*|ntuser\.dat.*)$') { return }
                if (Test-KeptScan $it.FullName $keeps) { return }
                $sync.Status = "Dang quet: $($it.FullName)"
                Add-ScanRow $sync $p.Name $it
            }
        }

        # --- (B) Thu muc/file tu tao o GOC o he thong (tru thu muc he thong) ---
        $sysSkip = '(?i)^(Windows|Program Files|Program Files \(x86\)|ProgramData|Users|\$Recycle\.Bin|System Volume Information|Recovery|PerfLogs|Documents and Settings|Config\.Msi|Intel|AMD|NVIDIA|OneDriveTemp|\$SysReset|\$WinREAgent|\$GetCurrent|\$Windows\.~BT|\$Windows\.~WS|EFSTMPWP|MSOCache|hiberfil\.sys|pagefile\.sys|swapfile\.sys|bootmgr|BOOTNXT|BOOTSECT\.BAK|DumpStack\.log.*|System\.sav)$'
        Get-ChildItem -LiteralPath "$sysDrive\" -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $it = $_
            if ($sync.Cancel) { return }
            if (Is-Reparse $it) { return }
            if ($it.Name -match $sysSkip) { return }
            if (Test-KeptScan $it.FullName $keeps) { return }
            $sync.Status = "Dang quet: $($it.FullName)"
            Add-ScanRow $sync "[O $sysDrive]" $it
        }

        # --- (C) MOI thu tren cac o local khac (tru thu muc app/he thong) ---
        if ($wipeOtherDrives) {
            $fixed = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object -ExpandProperty DeviceID
            foreach ($d in $fixed) {
                if ($d -eq $sysDrive) { continue }
                Get-ChildItem -LiteralPath "$d\" -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $it = $_
                    if ($sync.Cancel) { return }
                    if (Is-Reparse $it) { return }
                    if ($it.Name -match '(?i)^(Program Files|Program Files \(x86\)|ProgramData|Windows|\$Recycle\.Bin|System Volume Information|Recovery)$') { return }
                    if (Test-KeptScan $it.FullName $keeps) { return }
                    $sync.Status = "Dang quet: $($it.FullName)"
                    Add-ScanRow $sync "[O $d]" $it
                }
            }
        }
        $sync.Status = "Quet xong."
    } catch { $sync.Status = "Loi quet: $($_.Exception.Message)" }
    $sync.Phase = ''; $sync.Busy = $false
}

# ---------------------------------------------------------------------
# WORKER: XOA
# ---------------------------------------------------------------------
$DeleteScript = {
    param($sync, $paths, $passes, $wipeFree, $core, $keeps, $killProcs)
    if (-not ([System.Management.Automation.PSTypeName]'NativeDel').Type) {
        Add-Type -Namespace '' -Name 'NativeDel' -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true, CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
"@
    }
    . ([scriptblock]::Create($core))
    $sync.Busy = $true; $sync.Phase = 'delete'; $sync.Cancel = $false
    $sync.FilesDone = 0; $sync.BytesDone = 0
    try {
        if ($killProcs) { Stop-ProcsInPaths $sync $paths $keeps }
        foreach ($p in $paths) {
            if ($sync.Cancel) { WLog $sync "== DA HUY =="; break }
            if (Test-Path -LiteralPath $p -PathType Container) {
                Remove-FolderSecure $sync $p $passes $keeps
            } elseif (Test-Path -LiteralPath $p) {
                if (-not (Test-Kept $p $keeps)) { WLog $sync ("-> " + $p); $sync.Status = $p; Remove-FileSecure $sync $p $passes }
            }
        }
        if (-not $sync.Cancel) {
            WLog $sync "-- Don Recycle Bin --"
            try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
            WLog $sync "-- Xoa Shadow Copies + tat System Restore --"
            try { & vssadmin delete shadows /all /quiet 2>&1 | Out-Null } catch {}
            $fixed = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object -ExpandProperty DeviceID
            foreach ($d in $fixed) { try { Disable-ComputerRestore -Drive "$d\" -ErrorAction SilentlyContinue } catch {} }
            if ($wipeFree) {
                WLog $sync "-- Wipe free space (cipher /w) - CO THE LAU --"
                foreach ($d in $fixed) {
                    if ($sync.Cancel) { break }
                    $sync.Status = "Wipe free space: $d ..."
                    try { & cipher /w:"$d\" 2>&1 | Out-Null } catch {}
                }
            }
        }
        WLog $sync "===== HOAN TAT ====="
    } catch { WLog $sync "LOI: $($_.Exception.Message)" }
    $sync.Status = "Xong."
    $sync.Phase = ''; $sync.Busy = $false
}

# ---------------------------------------------------------------------
# Ham chay 1 scriptblock trong runspace nen
# ---------------------------------------------------------------------
$script:CurrentPS = $null
function Start-BgWork {
    param([scriptblock]$Script, [object[]]$Arguments)
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($Script.ToString())
    foreach ($a in $Arguments) { [void]$ps.AddArgument($a) }
    $script:CurrentPS = $ps
    [void]$ps.BeginInvoke()
}

# =====================================================================
# GIAO DIEN
# =====================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Reset Machine - Xoa vinh vien du lieu (giu app)"
$form.Size = New-Object System.Drawing.Size(880, 660)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(760, 560)

# Banner canh bao
$lblWarn = New-Object System.Windows.Forms.Label
$lblWarn.Text = "CANH BAO: Xoa VINH VIEN moi FILE (ghi de an toan) - KHONG HOAN TAC. GIU nguyen thu muc + Windows + app + AppData + danh sach giu lai. Bo qua o mang."
$lblWarn.Dock = 'Top'; $lblWarn.Height = 40; $lblWarn.TextAlign = 'MiddleLeft'
$lblWarn.BackColor = [System.Drawing.Color]::FromArgb(255, 244, 199, 199)
$lblWarn.ForeColor = [System.Drawing.Color]::DarkRed
$lblWarn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblWarn.Padding = New-Object System.Windows.Forms.Padding(8,0,8,0)

# Panel tuy chon
$pnlOpt = New-Object System.Windows.Forms.Panel
$pnlOpt.Dock = 'Top'; $pnlOpt.Height = 76

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "1. Quet (xem se xoa gi)"; $btnScan.Location = New-Object System.Drawing.Point(10,10)
$btnScan.Size = New-Object System.Drawing.Size(180,30)

$chkFree = New-Object System.Windows.Forms.CheckBox
$chkFree.Text = "Wipe free space (chong khoi phuc tren SSD, cham)"; $chkFree.Checked = $true
$chkFree.Location = New-Object System.Drawing.Point(210,8); $chkFree.AutoSize = $true

$chkOther = New-Object System.Windows.Forms.CheckBox
$chkOther.Text = "Xoa ca o local khac (D:, E:...) ngoai o he thong"
$chkOther.Location = New-Object System.Drawing.Point(210,30); $chkOther.AutoSize = $true

$chkKill = New-Object System.Windows.Forms.CheckBox
$chkKill.Text = "Tat app dang chay + xoa file khoa khi khoi dong lai"; $chkKill.Checked = $true
$chkKill.Location = New-Object System.Drawing.Point(210,52); $chkKill.AutoSize = $true

$lblPass = New-Object System.Windows.Forms.Label
$lblPass.Text = "So lan ghi de:"; $lblPass.Location = New-Object System.Drawing.Point(600,10); $lblPass.AutoSize = $true
$numPass = New-Object System.Windows.Forms.NumericUpDown
$numPass.Location = New-Object System.Drawing.Point(690,8); $numPass.Size = New-Object System.Drawing.Size(50,24)
$numPass.Minimum = 1; $numPass.Maximum = 7; $numPass.Value = 1

$pnlOpt.Controls.AddRange(@($btnScan,$chkFree,$chkOther,$chkKill,$lblPass,$numPass))

# ListView danh sach
$lv = New-Object System.Windows.Forms.ListView
$lv.Dock = 'Fill'; $lv.View = 'Details'; $lv.CheckBoxes = $true
$lv.FullRowSelect = $true; $lv.GridLines = $true
[void]$lv.Columns.Add("Profile", 130)
[void]$lv.Columns.Add("Muc", 130)
[void]$lv.Columns.Add("Duong dan", 360)
[void]$lv.Columns.Add("So file", 80)
[void]$lv.Columns.Add("Dung luong", 110)

# Panel duoi: tong + nut xoa
$pnlBottom = New-Object System.Windows.Forms.Panel
$pnlBottom.Dock = 'Bottom'; $pnlBottom.Height = 190

$lblTotal = New-Object System.Windows.Forms.Label
$lblTotal.Text = "Tong: 0 muc, 0 file, 0 B"; $lblTotal.Location = New-Object System.Drawing.Point(10,6)
$lblTotal.AutoSize = $true; $lblTotal.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = "2. XOA VINH VIEN"; $btnDelete.Location = New-Object System.Drawing.Point(10,30)
$btnDelete.Size = New-Object System.Drawing.Size(180,34); $btnDelete.Enabled = $false
$btnDelete.BackColor = [System.Drawing.Color]::FromArgb(255,200,40,40)
$btnDelete.ForeColor = [System.Drawing.Color]::White
$btnDelete.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Huy"; $btnCancel.Location = New-Object System.Drawing.Point(200,30)
$btnCancel.Size = New-Object System.Drawing.Size(90,34); $btnCancel.Enabled = $false

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(10,72); $progress.Size = New-Object System.Drawing.Size(840,18)
$progress.Anchor = 'Top,Left,Right'

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "San sang."; $lblStatus.Location = New-Object System.Drawing.Point(10,94)
$lblStatus.Size = New-Object System.Drawing.Size(840,16); $lblStatus.Anchor = 'Top,Left,Right'; $lblStatus.AutoEllipsis = $true

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(10,114); $txtLog.Size = New-Object System.Drawing.Size(840,66)
$txtLog.Multiline = $true; $txtLog.ScrollBars = 'Vertical'; $txtLog.ReadOnly = $true
$txtLog.Anchor = 'Top,Bottom,Left,Right'; $txtLog.Font = New-Object System.Drawing.Font("Consolas", 8)

$pnlBottom.Controls.AddRange(@($lblTotal,$btnDelete,$btnCancel,$progress,$lblStatus,$txtLog))

$form.Controls.Add($lv)
$form.Controls.Add($pnlBottom)
$form.Controls.Add($pnlOpt)
$form.Controls.Add($lblWarn)

# ---- Timer cap nhat UI tu state nen ----
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 200
$timer.Add_Tick({
    # Do log ra textbox
    while ($sync.Log.Count -gt 0) {
        $msg = $sync.Log[0]; $sync.Log.RemoveAt(0)
        $txtLog.AppendText($msg + "`r`n")
    }
    if ($sync.Status) { $lblStatus.Text = $sync.Status }

    if ($sync.Phase -eq 'scan') {
        $progress.Style = 'Marquee'
    }
    elseif ($sync.Phase -eq 'delete') {
        $progress.Style = 'Continuous'
        if ($sync.FilesTotal -gt 0) {
            $pct = [int](($sync.FilesDone / $sync.FilesTotal) * 100)
            if ($pct -gt 100) { $pct = 100 }
            $progress.Value = $pct
            $lblStatus.Text = "Da xoa $($sync.FilesDone)/$($sync.FilesTotal) file ($(Format-Size $sync.BytesDone))  -  $($sync.Status)"
        }
    }

    # Khi scan xong -> do vao ListView
    if ($sync.Phase -eq '' -and -not $sync.Busy -and $script:AwaitScan) {
        $script:AwaitScan = $false
        $progress.Style = 'Continuous'; $progress.Value = 0
        $lv.Items.Clear()
        $totalFiles = 0; [long]$totalBytes = 0
        foreach ($r in $sync.Scan) {
            $it = New-Object System.Windows.Forms.ListViewItem($r.Profile)
            $it.Checked = $true
            [void]$it.SubItems.Add([string]$r.Item)
            [void]$it.SubItems.Add([string]$r.Path)
            [void]$it.SubItems.Add([string]$r.Files)
            [void]$it.SubItems.Add((Format-Size $r.Bytes))
            $it.Tag = $r
            [void]$lv.Items.Add($it)
            $totalFiles += $r.Files; $totalBytes += $r.Bytes
        }
        $lblTotal.Text = "Tong: $($sync.Scan.Count) muc, $totalFiles file, $(Format-Size $totalBytes)"
        $btnScan.Enabled = $true
        $btnDelete.Enabled = ($lv.Items.Count -gt 0)
        $lblStatus.Text = "Quet xong. Bo tick nhung muc muon giu, roi bam XOA VINH VIEN."
    }

    # Khi xoa xong
    if ($sync.Phase -eq '' -and -not $sync.Busy -and $script:AwaitDelete) {
        $script:AwaitDelete = $false
        $timer.Stop() | Out-Null
        $progress.Value = 100
        $btnScan.Enabled = $true; $btnDelete.Enabled = $false; $btnCancel.Enabled = $false
        $chkFree.Enabled = $true; $chkOther.Enabled = $true; $numPass.Enabled = $true; $chkKill.Enabled = $true
        if ($sync.PendingReboot) {
            [System.Windows.Forms.MessageBox]::Show("Da hoan tat xoa.`n`nCo mot so file dang bi khoa -> da len lich XOA KHI KHOI DONG LAI. Hay khoi dong lai may de xoa nhung file do.","Reset Machine",
                [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("Da hoan tat xoa.","Reset Machine",
                [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
    }
})

# ---- Su kien nut ----
$btnScan.Add_Click({
    $btnScan.Enabled = $false; $btnDelete.Enabled = $false
    $lv.Items.Clear(); $txtLog.Clear()
    $lblStatus.Text = "Dang quet..."; $progress.Style = 'Marquee'
    $script:AwaitScan = $true
    $timer.Start()
    Start-BgWork -Script $ScanScript -Arguments @($sync, $SkipProfiles, [bool]$chkOther.Checked, $KeepPaths)
})

$btnDelete.Add_Click({
    $paths = @(); $files = 0
    foreach ($it in $lv.Items) { if ($it.Checked) { $paths += $it.Tag.Path; $files += [int]$it.Tag.Files } }
    if ($paths.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Chua chon muc nao.","Reset Machine") | Out-Null; return
    }
    $msg = "Se XOA VINH VIEN $($paths.Count) muc (~$files file).`n`nKHONG THE HOAN TAC.`n`nGo dung chu:  ERASE  de xac nhan:"
    $ans = [Microsoft.VisualBasic.Interaction]::InputBox($msg, "Xac nhan xoa", "")
    if ($ans -ne 'ERASE') { $lblStatus.Text = "Da huy (khong go dung ERASE)."; return }

    $sync.FilesTotal = $files; $sync.FilesDone = 0; $sync.BytesDone = 0; $sync.PendingReboot = $false
    $btnScan.Enabled = $false; $btnDelete.Enabled = $false; $btnCancel.Enabled = $true
    $chkFree.Enabled = $false; $chkOther.Enabled = $false; $numPass.Enabled = $false; $chkKill.Enabled = $false
    $progress.Style = 'Continuous'; $progress.Value = 0
    $txtLog.AppendText("===== BAT DAU XOA =====`r`n")
    $script:AwaitDelete = $true
    $timer.Start()
    Start-BgWork -Script $DeleteScript -Arguments @($sync, $paths, [int]$numPass.Value, [bool]$chkFree.Checked, $CoreFunctions, $KeepPaths, [bool]$chkKill.Checked)
})

$btnCancel.Add_Click({
    $sync.Cancel = $true
    $lblStatus.Text = "Dang huy... (cho thao tac hien tai ket thuc)"
    $btnCancel.Enabled = $false
})

$form.Add_FormClosing({
    if ($sync.Busy) {
        $r = [System.Windows.Forms.MessageBox]::Show("Dang chay. Huy va thoat?","Reset Machine",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -eq [System.Windows.Forms.DialogResult]::No) { $_.Cancel = $true }
        else { $sync.Cancel = $true }
    }
})

[void]$form.ShowDialog()
