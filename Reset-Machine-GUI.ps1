<#
=====================================================================
 Reset-Machine-GUI.ps1
 Giao diện xóa vĩnh viễn dữ liệu cá nhân, giữ lại Windows + ứng dụng.
   1) Bấm "Quét"  -> hiện cây những gì SẼ bị xóa (kèm dung lượng, ngày sửa)
   2) Bung thư mục, bỏ tick những mục muốn giữ lại
   3) Bấm "XÓA VĨNH VIỄN" -> xác nhận -> xóa (hoặc hẹn giờ chạy ban đêm)
 Xóa chạy ở luồng nền, có thanh tiến trình + log + nút Hủy.
 !!! KHÔNG THỂ HOÀN TÁC !!!

 LƯU Ý CHO NGƯỜI SỬA FILE NÀY: file phải lưu bằng UTF-8 CÓ BOM.
 PowerShell 5.1 đọc file không BOM theo bảng mã ANSI -> chữ có dấu sẽ vỡ.
=====================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
# Bật visual styles TRƯỚC khi tạo cửa sổ: cần cho checkbox 3 trạng thái vẽ đúng.
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch {}

# ---- Yêu cầu quyền Administrator ----
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`""
        )
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Cần chạy với quyền Administrator.","Reset Machine") | Out-Null
    }
    return
}

# ---------------------------------------------------------------------
# CẤU HÌNH
# ---------------------------------------------------------------------
$SkipProfiles = @('Public','Default','Default User','All Users','defaultuser0')

# DANH SÁCH GIỮ LẠI: các đường dẫn này (và mọi thứ bên trong) KHÔNG BAO GIỜ bị xóa.
# Thêm đường dẫn kế toán / dữ liệu quan trọng vào đây để an toàn tuyệt đối.
# Ví dụ:
#   $KeepPaths = @('D:\MERGE', 'C:\Users\ketoan\Documents\MISA', 'C:\KETOAN')
$KeepPaths = @(
    # 'D:\MERGE'
)

# Các app hay GIỮ FILE trong vùng xóa -> tắt trước khi xóa để file không bị khóa.
# (Ví dụ: Outlook giữ file .pst trong Documents, OneDrive giữ file đang đồng bộ.)
# Thêm tên tiến trình (không có đuôi .exe) vào đây nếu gặp app khác giữ file.
$KillProcessNames = @(
    'OneDrive','OUTLOOK','WINWORD','EXCEL','POWERPNT','MSACCESS','MSPUB','ONENOTE',
    'chrome','msedge','firefox','opera','brave','coccoc',
    'Teams','ms-teams','Zalo','ZaloPC','Skype','Discord',
    'AcroRd32','Acrobat','FoxitPDFReader','notepad','notepad++','Code','wordpad',
    'WINRAR','7zFM','vlc','GoogleDriveFS','Dropbox'
)

# Nơi ghi log + báo cáo bàn giao. ProgramData nằm trong danh sách app LUÔN GIỮ LẠI
# nên log của chính mình không bị xóa mất.
$LogDir = Join-Path $env:ProgramData 'ResetMachine'

# ---------------------------------------------------------------------
# State chia sẻ giữa UI và luồng nền
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
    LogPath    = ''                                        # file log ghi trực tiếp xuống đĩa
    Skipped    = New-Object System.Collections.ArrayList    # file không xóa được / hoãn tới khởi động lại
    Wiping     = $false                                     # đang ở giai đoạn cipher /w
})

function Format-Size([long]$b) {
    if ($b -ge 1GB) { return ("{0:N2} GB" -f ($b/1GB)) }
    if ($b -ge 1MB) { return ("{0:N1} MB" -f ($b/1MB)) }
    if ($b -ge 1KB) { return ("{0:N0} KB" -f ($b/1KB)) }
    return "$b B"
}

function Format-Duration([double]$seconds) {
    if ($seconds -lt 90)   { return ("{0:N0} giây" -f $seconds) }
    if ($seconds -lt 5400) { return ("{0:N0} phút" -f ($seconds/60)) }
    return ("{0:N1} giờ" -f ($seconds/3600))
}

# ---------------------------------------------------------------------
# Chặn máy ngủ trong lúc chờ hẹn giờ / đang xóa.
# KHÔNG dùng ES_DISPLAY_REQUIRED để màn hình vẫn tắt được cho đỡ tốn điện.
# ---------------------------------------------------------------------
if (-not ([System.Management.Automation.PSTypeName]'NativePower').Type) {
    try {
        Add-Type -Namespace '' -Name 'NativePower' -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
public static extern uint SetThreadExecutionState(uint esFlags);
"@
    } catch {}
}
# LƯU Ý: phải ép [uint32] tường minh. PowerShell 5.1 đọc 0x80000000 thành Int32 ÂM,
# nên "0x80000000 -bor 1" ra -2147483647 và gọi hàm sẽ NÉM LỖI -> chặn ngủ hỏng âm thầm.
$ES_CONTINUOUS        = [uint32]2147483648   # 0x80000000
$ES_KEEP_SYSTEM_AWAKE = [uint32]2147483649   # 0x80000000 | ES_SYSTEM_REQUIRED(0x1)

function Set-KeepAwake([bool]$on) {
    try {
        if ($on) { [void][NativePower]::SetThreadExecutionState($ES_KEEP_SYSTEM_AWAKE) }
        else     { [void][NativePower]::SetThreadExecutionState($ES_CONTINUOUS) }
        return $true
    } catch { return $false }
}

# ---------------------------------------------------------------------
# NGUỒN SỰ THẬT DUY NHẤT về danh sách ổ đĩa được phép đụng tới.
#
# Windows báo cả ổ ẢO / ổ ĐÁM MÂY là DriveType=3 (ổ cứng cố định) - ví dụ
# Google Drive for Desktop mount thành ổ G:. Nhưng ổ ẢO KHÔNG map được sang
# đĩa vật lý (Get-Partition không tìm thấy), còn ổ THẬT thì luôn map được.
# Dùng đúng đặc điểm đó làm bộ lọc an toàn.
#
# Trả về mỗi ổ kèm chiến lược xóa theo loại ổ:
#   SSD/NVMe -> 0 lần ghi đè + wipe vùng trống
#               (wear-leveling khiến ghi đè từng file không chạm ô nhớ vật lý cũ;
#                chỉ lấp đầy vùng trống mới ép SSD ghi đè thật)
#   HDD      -> 1 lần ghi đè, KHÔNG wipe
#               (ghi đè đúng vị trí vật lý, xong trong vài phút; wipe thành thừa)
# ---------------------------------------------------------------------
function Get-RealFixedDrives {
    $result = @()
    $hasPartitionCmd = [bool](Get-Command Get-Partition -ErrorAction SilentlyContinue)
    $logical = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue)

    foreach ($ld in $logical) {
        $letter = ([string]$ld.DeviceID).TrimEnd(':')
        if ([string]::IsNullOrWhiteSpace($letter)) { continue }

        $diskNum = $null
        if ($hasPartitionCmd) {
            try { $diskNum = (Get-Partition -DriveLetter $letter -ErrorAction Stop).DiskNumber } catch { $diskNum = $null }
        } else {
            # Không có module Storage (rất hiếm): chỉ tin ổ hệ thống, bỏ qua phần còn lại
            if ($ld.DeviceID -eq $env:SystemDrive) { $diskNum = -1 }
        }
        if ($null -eq $diskNum) { continue }   # <-- ổ ẢO / ổ ĐÁM MÂY bị loại tại đây

        $media = 'SSD'; $how = 'mặc định (không nhận dạng được)'
        if ($diskNum -ge 0) {
            $phys = Get-PhysicalDisk -ErrorAction SilentlyContinue |
                        Where-Object { $_.DeviceId -eq [string]$diskNum } | Select-Object -First 1
            if ($phys) {
                if     ($phys.MediaType -eq 'SSD')  { $media = 'SSD'; $how = 'MediaType=SSD' }
                elseif ($phys.MediaType -eq 'HDD')  { $media = 'HDD'; $how = 'MediaType=HDD' }
                elseif ($phys.SpindleSpeed -eq 0)   { $media = 'SSD'; $how = 'SpindleSpeed=0' }
                elseif ($phys.BusType -eq 'NVMe')   { $media = 'SSD'; $how = 'BusType=NVMe' }
                elseif ($phys.SpindleSpeed -gt 0)   { $media = 'HDD'; $how = "SpindleSpeed=$($phys.SpindleSpeed)" }
            }
        }

        $free = [long]0; if ($ld.FreeSpace) { $free = [long]$ld.FreeSpace }
        $result += [pscustomobject]@{
            Letter    = [string]$ld.DeviceID          # 'C:'
            Root      = [string]$ld.DeviceID + '\'    # 'C:\'
            Media     = $media
            Detect    = $how
            FreeBytes = $free
            Passes    = $(if ($media -eq 'SSD') { 0 } else { 1 })
            Wipe      = ($media -eq 'SSD')
            # cipher /w ghi 3 lượt lên toàn bộ vùng trống; ước tính ~40 MB/s hiệu dụng
            WipeSecs  = [double]($free * 3 / 40MB)
        }
    }
    return $result
}

# ---------------------------------------------------------------------
# Scriptblock chung: định nghĩa hàm secure-delete (chạy trong runspace)
# ---------------------------------------------------------------------
$CoreFunctions = @'
function WLog($sync,$msg){
    [void]$sync.Log.Add($msg)
    # Ghi thẳng xuống đĩa từng dòng một: mất điện vẫn còn đến dòng cuối cùng.
    if ($sync.LogPath) {
        try {
            $line = ("[{0:HH:mm:ss}] {1}`r`n" -f (Get-Date), $msg)
            [System.IO.File]::AppendAllText($sync.LogPath, $line, [System.Text.Encoding]::UTF8)
        } catch {}
    }
}

# Số lần ghi đè áp dụng cho file này, tra theo Ổ ĐĨA chứa nó (SSD=0, HDD=1).
function Get-PassesFor($driveModes,$path){
    if ($path.Length -ge 2) {
        $k = $path.Substring(0,2).ToUpper()
        if ($driveModes.ContainsKey($k)) { return [int]$driveModes[$k] }
    }
    return 1   # không xác định được -> ghi đè 1 lần cho chắc
}

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
    # MOVEFILE_DELAY_UNTIL_REBOOT = 4 ; lpNewFileName = null => xóa khi khởi động lại
    # LƯU Ý: cơ chế này của Windows chỉ XÓA THƯỜNG lúc khởi động, KHÔNG ghi đè
    # -> file vẫn có thể khôi phục được. Phải ghi vào báo cáo bàn giao.
    try {
        $ok = [NativeDel]::MoveFileEx($path, $null, 4)
        if ($ok) {
            WLog $sync ("  KHÓA - đã lên lịch XÓA KHI KHỞI ĐỘNG LẠI (không ghi đè): " + $path)
            $sync.PendingReboot = $true
            [void]$sync.Skipped.Add("HOÃN TỚI KHỞI ĐỘNG LẠI (xóa thường, không ghi đè): $path")
        } else {
            WLog $sync ("  LỖI: không lên lịch xóa được: " + $path)
            [void]$sync.Skipped.Add("KHÔNG XÓA ĐƯỢC: $path")
        }
    } catch {
        WLog $sync ("  LỖI: " + $path + " -> " + $_.Exception.Message)
        [void]$sync.Skipped.Add("KHÔNG XÓA ĐƯỢC: $path ($($_.Exception.Message))")
    }
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
            # passes=0 (ổ SSD): bỏ qua ghi đè từng file - vô dụng vì wear-leveling.
            # Vùng dữ liệu sẽ được xử lý ở bước wipe vùng trống phía sau.
            if ($len -gt 0 -and $passes -gt 0) {
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
            # Hết lượt thử -> file vẫn bị khóa -> lên lịch xóa khi khởi động lại
            Schedule-DeleteOnReboot $sync $path
        }
    }
}

# Tắt app theo TÊN tiến trình.
# Cần thiết vì Stop-ProcsInPaths (dưới) chỉ so đường dẫn file .exe của tiến trình
# với vùng sẽ xóa - mà Outlook.exe nằm ở Program Files (không bị xóa) trong khi
# thứ nó khóa lại là Documents\Outlook Files\*.pst. Ca phổ biến nhất bị bỏ sót.
function Stop-ProcsByName($sync,$names){
    if (-not $names) { return }
    WLog $sync "-- Tắt các app hay giữ file (theo tên) --"
    foreach ($n in $names) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        $found = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
        foreach ($p in $found) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                WLog $sync ("  Đã tắt: " + $p.ProcessName)
            } catch { WLog $sync ("  Không tắt được: " + $p.ProcessName) }
        }
    }
    # Explorer giữ handle nhiều file/thumbnail -> tắt riêng, Windows tự bật lại.
    try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; WLog $sync "  Đã tắt: explorer (Windows sẽ tự bật lại)" } catch {}
    Start-Sleep -Milliseconds 1500
}

function Stop-ProcsInPaths($sync,$paths,$keeps){
    WLog $sync "-- Tắt các app đang chạy trong vùng xóa --"
    $procs = Get-Process -ErrorAction SilentlyContinue
    foreach ($pr in $procs) {
        $ppath = $null
        try { $ppath = $pr.Path } catch { $ppath = $null }
        if ([string]::IsNullOrWhiteSpace($ppath)) { continue }
        # Không tắt tiến trình hệ thống Windows
        if ($ppath -match '(?i)\\Windows\\') { continue }
        if (Test-Kept $ppath $keeps) { continue }
        $pf = [System.IO.Path]::GetFullPath($ppath).TrimEnd('\')
        foreach ($t in $paths) {
            if ([string]::IsNullOrWhiteSpace($t)) { continue }
            $tf = [System.IO.Path]::GetFullPath($t).TrimEnd('\')
            if ($pf -eq $tf -or $pf.StartsWith($tf + '\', [StringComparison]::OrdinalIgnoreCase)) {
                try { WLog $sync ("  Tắt: " + $pr.ProcessName + " (" + $ppath + ")"); Stop-Process -Id $pr.Id -Force -ErrorAction Stop }
                catch { WLog $sync ("  Không tắt được: " + $pr.ProcessName) }
                break
            }
        }
    }
    Start-Sleep -Milliseconds 1000
}

function Remove-FolderSecure($sync,$folder,$driveModes,$keeps){
    if (-not (Test-Path -LiteralPath $folder)) { return }
    if (Test-Kept $folder $keeps) { WLog $sync ("GIỮ LẠI (bỏ qua): " + $folder); return }
    WLog $sync ("-> " + $folder)
    # CHỈ xóa FILE (ghi đè vĩnh viễn). GIỮ NGUYÊN toàn bộ thư mục (không xóa folder).
    # Dùng foreach trên mảng đã liệt kê chứ KHÔNG dùng ForEach-Object: trong
    # ForEach-Object thì 'return' chỉ bỏ qua 1 item rồi chạy tiếp, không thoát
    # pipeline -> nút Hủy không dừng được ngay.
    $files = @(Get-ChildItem -LiteralPath $folder -File -Recurse -Force -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        if ($sync.Cancel) { break }
        if (Test-Kept $f.FullName $keeps) { continue }
        $sync.Status = $f.FullName
        Remove-FileSecure $sync $f.FullName (Get-PassesFor $driveModes $f.FullName)
    }
}
'@

# ---------------------------------------------------------------------
# WORKER: QUÉT
# ---------------------------------------------------------------------
$ScanScript = {
    # $realDriveLetters: danh sách ổ THẬT ('C:','D:'...) do Get-RealFixedDrives lọc sẵn
    # ở luồng UI. Ổ ảo / ổ đám mây (Google Drive...) đã bị loại trước khi tới đây.
    param($sync, $skipProfiles, $wipeOtherDrives, $keeps, $realDriveLetters)

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
        $last = $item.LastWriteTime
        if ($item.PSIsContainer) {
            # Một lượt duyệt duy nhất: vừa đếm file, vừa cộng dung lượng, vừa lấy
            # mốc sửa mới nhất. Tránh Sort-Object (tốn O(n log n) vô ích).
            $count = 0; $bytes = [long]0
            $files = @(Get-ChildItem -LiteralPath $item.FullName -File -Recurse -Force -ErrorAction SilentlyContinue)
            foreach ($f in $files) {
                $count++; $bytes += $f.Length
                if ($f.LastWriteTime -gt $last) { $last = $f.LastWriteTime }
            }
        } else { $count = 1; $bytes = [long]$item.Length }
        [void]$sync.Scan.Add([pscustomobject]@{
            Profile  = $group
            Item     = $item.Name
            Path     = $item.FullName
            Files    = $count
            Bytes    = [long]$bytes
            IsFolder = [bool]$item.PSIsContainer
            Last     = $last
        })
    }

    $sync.Busy = $true; $sync.Phase = 'scan'; $sync.Cancel = $false
    $sync.Scan.Clear()
    try {
        $sysDrive = $env:SystemDrive

        # --- (A) MỌI thứ trong từng profile, TRỪ AppData + file hệ thống ---
        $usersRoot = Join-Path $sysDrive 'Users'
        Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $p = $_
            if ($skipProfiles -contains $p.Name) { return }
            Get-ChildItem -LiteralPath $p.FullName -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $it = $_
                if ($sync.Cancel) { return }
                if (Is-Reparse $it) { return }   # bỏ các junction hệ thống (Application Data, My Documents...)
                if ($it.Name -match '(?i)^(AppData|Application Data|Local Settings|NTUSER\..*|ntuser\.dat.*)$') { return }
                if (Test-KeptScan $it.FullName $keeps) { return }
                $sync.Status = "Đang quét: $($it.FullName)"
                Add-ScanRow $sync $p.Name $it
            }
        }

        # --- (B) Thư mục/file tự tạo ở GỐC ổ hệ thống (trừ thư mục hệ thống) ---
        $sysSkip = '(?i)^(Windows|Program Files|Program Files \(x86\)|ProgramData|Users|\$Recycle\.Bin|System Volume Information|Recovery|PerfLogs|Documents and Settings|Config\.Msi|Intel|AMD|NVIDIA|OneDriveTemp|\$SysReset|\$WinREAgent|\$GetCurrent|\$Windows\.~BT|\$Windows\.~WS|EFSTMPWP|MSOCache|hiberfil\.sys|pagefile\.sys|swapfile\.sys|bootmgr|BOOTNXT|BOOTSECT\.BAK|DumpStack\.log.*|System\.sav)$'
        Get-ChildItem -LiteralPath "$sysDrive\" -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $it = $_
            if ($sync.Cancel) { return }
            if (Is-Reparse $it) { return }
            if ($it.Name -match $sysSkip) { return }
            if (Test-KeptScan $it.FullName $keeps) { return }
            $sync.Status = "Đang quét: $($it.FullName)"
            Add-ScanRow $sync "Ổ $sysDrive" $it
        }

        # --- (C) MỌI thứ trên các ổ local khác (trừ thư mục app/hệ thống) ---
        if ($wipeOtherDrives) {
            foreach ($d in $realDriveLetters) {
                if ($d -eq $sysDrive) { continue }
                Get-ChildItem -LiteralPath "$d\" -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $it = $_
                    if ($sync.Cancel) { return }
                    if (Is-Reparse $it) { return }
                    if ($it.Name -match '(?i)^(Program Files|Program Files \(x86\)|ProgramData|Windows|\$Recycle\.Bin|System Volume Information|Recovery)$') { return }
                    if (Test-KeptScan $it.FullName $keeps) { return }
                    $sync.Status = "Đang quét: $($it.FullName)"
                    Add-ScanRow $sync "Ổ $d" $it
                }
            }
        }
        $sync.Status = "Quét xong."
    } catch { $sync.Status = "Lỗi quét: $($_.Exception.Message)" }
    $sync.Phase = ''; $sync.Busy = $false
}

# ---------------------------------------------------------------------
# WORKER: XÓA
# ---------------------------------------------------------------------
$DeleteScript = {
    # $driveModes  : hashtable 'C:' -> số lần ghi đè (SSD=0, HDD=1)
    # $wipeRoots   : danh sách gốc ổ CẦN wipe vùng trống ('C:\'), chỉ gồm ổ SSD
    #                VÀ thực sự có file bị xóa
    # $restoreRoots: danh sách gốc ổ để tắt System Restore (chỉ ổ THẬT)
    param($sync, $paths, $driveModes, $wipeRoots, $restoreRoots, $core, $keeps, $killProcs, $killNames)
    $sync.Busy = $true; $sync.Phase = 'delete'; $sync.Cancel = $false
    $sync.FilesDone = 0; $sync.BytesDone = 0
    # Hạ ưu tiên để không tranh I/O với công việc của người dùng.
    try { [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'Idle' } catch {}
    try {
        . ([scriptblock]::Create($core))
        if (-not ([System.Management.Automation.PSTypeName]'NativeDel').Type) {
            try {
                Add-Type -Namespace '' -Name 'NativeDel' -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true, CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
"@
            } catch { WLog $sync "  (không nạp được MoveFileEx - file khóa sẽ không xóa-khi-reboot, phần còn lại vẫn xóa bình thường)" }
        }
        if ($killProcs) {
            Stop-ProcsByName $sync $killNames
            Stop-ProcsInPaths $sync $paths $keeps
        }
        foreach ($p in $paths) {
            if ($sync.Cancel) { WLog $sync "== ĐÃ HỦY =="; break }
            if (Test-Path -LiteralPath $p -PathType Container) {
                Remove-FolderSecure $sync $p $driveModes $keeps
            } elseif (Test-Path -LiteralPath $p) {
                if (-not (Test-Kept $p $keeps)) {
                    WLog $sync ("-> " + $p); $sync.Status = $p
                    Remove-FileSecure $sync $p (Get-PassesFor $driveModes $p)
                }
            }
        }
        if (-not $sync.Cancel) {
            WLog $sync "-- Dọn Recycle Bin --"
            try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
            WLog $sync "-- Xóa Shadow Copies + tắt System Restore --"
            try { & vssadmin delete shadows /all /quiet 2>&1 | Out-Null } catch {}
            foreach ($r in $restoreRoots) { try { Disable-ComputerRestore -Drive $r -ErrorAction SilentlyContinue } catch {} }

            if ($wipeRoots -and $wipeRoots.Count -gt 0) {
                $sync.Wiping = $true
                WLog $sync "-- Wipe vùng trống (cipher /w) - GIAI ĐOẠN LÂU NHẤT --"
                foreach ($r in $wipeRoots) {
                    if ($sync.Cancel) { break }
                    $sync.Status = "Wipe vùng trống: $r (có thể vài giờ)..."
                    WLog $sync ("  Bắt đầu wipe: " + $r)
                    $proc = $null
                    try {
                        $proc = Start-Process -FilePath 'cipher.exe' -ArgumentList "/w:$r" `
                                    -WindowStyle Hidden -PassThru -ErrorAction Stop
                        # cipher là tiến trình con -> phải hạ ưu tiên riêng cho nó
                        try { $proc.PriorityClass = 'Idle' } catch {}
                        while (-not $proc.HasExited) {
                            if ($sync.Cancel) {
                                WLog $sync ("  HỦY giữa chừng wipe: " + $r)
                                try { $proc.Kill() } catch {}
                                # cipher tạo file tạm khổng lồ lấp đầy vùng trống;
                                # bị giết giữa chừng thì phải dọn, không là đầy ổ đĩa.
                                $tmp = Join-Path $r 'EFSTMPWP'
                                if (Test-Path -LiteralPath $tmp) {
                                    try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction Stop; WLog $sync "  Đã dọn thư mục tạm EFSTMPWP" }
                                    catch { WLog $sync "  CẢNH BÁO: còn thư mục tạm $tmp - xóa tay để giải phóng ổ đĩa" }
                                }
                                break
                            }
                            Start-Sleep -Milliseconds 500
                        }
                        if ($proc.HasExited -and -not $sync.Cancel) { WLog $sync ("  Xong wipe: " + $r) }
                    } catch { WLog $sync ("  LỖI wipe " + $r + " -> " + $_.Exception.Message) }
                }
                $sync.Wiping = $false
            } else {
                WLog $sync "-- Không có ổ nào cần wipe vùng trống (không có ổ SSD trong vùng xóa) --"
            }
        }
        WLog $sync "===== HOÀN TẤT ====="
    } catch { WLog $sync "LỖI: $($_.Exception.Message)" }
    finally {
        try { [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'Normal' } catch {}
        $sync.Wiping = $false
        $sync.Status = "Xong."
        $sync.Phase = ''; $sync.Busy = $false
    }
}

# ---------------------------------------------------------------------
# Hàm chạy 1 scriptblock trong runspace nền
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
# GIAO DIỆN
# =====================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Reset Machine - Xóa vĩnh viễn dữ liệu (giữ lại ứng dụng)"
$form.Size = New-Object System.Drawing.Size(980, 720)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(880, 600)

# ---- Banner cảnh báo ----
$lblWarn = New-Object System.Windows.Forms.Label
$lblWarn.Text = "CẢNH BÁO: Xóa VĨNH VIỄN mọi FILE - KHÔNG HOÀN TÁC. Giữ nguyên khung thư mục + Windows + ứng dụng + AppData + danh sách giữ lại." +
                [Environment]::NewLine + "BỎ QUA ổ mạng và ổ đám mây (Google Drive, Dropbox...) - chỉ đụng tới ổ cứng thật."
$lblWarn.Dock = 'Top'; $lblWarn.Height = 40; $lblWarn.TextAlign = 'MiddleLeft'
$lblWarn.BackColor = [System.Drawing.Color]::FromArgb(255, 244, 199, 199)
$lblWarn.ForeColor = [System.Drawing.Color]::DarkRed
$lblWarn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblWarn.Padding = New-Object System.Windows.Forms.Padding(8,0,8,0)

# ---- Panel tùy chọn ----
$pnlOpt = New-Object System.Windows.Forms.Panel
$pnlOpt.Dock = 'Top'; $pnlOpt.Height = 116

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "1. Quét (xem sẽ xóa gì)"; $btnScan.Location = New-Object System.Drawing.Point(10,10)
$btnScan.Size = New-Object System.Drawing.Size(180,30)

$chkOther = New-Object System.Windows.Forms.CheckBox
$chkOther.Text = "Xóa cả ổ local khác (D:, E:...) ngoài ổ hệ thống"
$chkOther.Location = New-Object System.Drawing.Point(210,8); $chkOther.AutoSize = $true

$chkKill = New-Object System.Windows.Forms.CheckBox
$chkKill.Text = "Tắt app đang chạy (để xóa được file đang bị khóa)"; $chkKill.Checked = $true
$chkKill.Location = New-Object System.Drawing.Point(210,30); $chkKill.AutoSize = $true

# Chế độ xóa KHÔNG cho chọn tay nữa - máy tự quyết theo loại ổ đĩa.
$lblDrives = New-Object System.Windows.Forms.Label
$lblDrives.Location = New-Object System.Drawing.Point(10,50)
$lblDrives.Size = New-Object System.Drawing.Size(945,62)
$lblDrives.Anchor = 'Top,Left,Right'
$lblDrives.Font = New-Object System.Drawing.Font("Consolas", 8)

$pnlOpt.Controls.AddRange(@($btnScan,$chkOther,$chkKill,$lblDrives))

# ---- Do ổ đĩa 1 lần lúc khởi động, dùng chung cho cả app ----
$script:Drives = @(Get-RealFixedDrives)

function Update-DriveLabel {
    if ($script:Drives.Count -eq 0) {
        $lblDrives.ForeColor = [System.Drawing.Color]::DarkRed
        $lblDrives.Text = "KHÔNG tìm thấy ổ đĩa thật nào. Không thể chạy."
        return
    }
    $lines = @("Chế độ xóa (máy tự quyết theo loại ổ đĩa):")
    foreach ($d in $script:Drives) {
        if ($d.Wipe) {
            $lines += ("  {0} {1,-3} -> wipe vùng trống {2} (~{3}), không ghi đè từng file  [{4}]" -f `
                        $d.Letter, $d.Media, (Format-Size $d.FreeBytes), (Format-Duration $d.WipeSecs), $d.Detect)
        } else {
            $lines += ("  {0} {1,-3} -> ghi đè từng file 1 lần, không wipe (nhanh)  [{2}]" -f `
                        $d.Letter, $d.Media, $d.Detect)
        }
    }
    $lblDrives.ForeColor = [System.Drawing.Color]::FromArgb(255,20,80,20)
    $lblDrives.Text = ($lines -join "`r`n")
}
Update-DriveLabel

# ---------------------------------------------------------------------
# CÂY CHỌN - checkbox 3 trạng thái
#
# WinForms TreeView không có checkbox 3 trạng thái sẵn. Cách làm: tắt
# CheckBoxes mặc định, dùng StateImageList 3 ảnh và tự quản StateImageIndex:
#   0 = không chọn   1 = chọn hết   2 = chọn một phần (ô vuông mờ)
# Nhờ trạng thái 2 mà thu cây lại vẫn nhìn ra nhánh nào có thứ bị loại trừ.
# ---------------------------------------------------------------------
$ST_NONE = 0; $ST_ALL = 1; $ST_PART = 2

function New-CheckImage($cbState) {
    $bmp = New-Object System.Drawing.Bitmap(16,16)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Transparent)
    $drawn = $false
    try {
        if ([System.Windows.Forms.CheckBoxRenderer]::IsSupported) {
            [System.Windows.Forms.CheckBoxRenderer]::DrawCheckBox($g, (New-Object System.Drawing.Point(1,1)), $cbState)
            $drawn = $true
        }
    } catch { $drawn = $false }
    if (-not $drawn) {
        # Dự phòng khi visual styles không dùng được: tự vẽ ô vuông.
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,90,90,90))
        $g.DrawRectangle($pen, 1, 1, 12, 12)
        if ($cbState -eq [System.Windows.Forms.VisualStyles.CheckBoxState]::CheckedNormal) {
            $p2 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,20,110,20), 2)
            $g.DrawLine($p2, 3, 7, 6, 10); $g.DrawLine($p2, 6, 10, 11, 4); $p2.Dispose()
        } elseif ($cbState -eq [System.Windows.Forms.VisualStyles.CheckBoxState]::MixedNormal) {
            $br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,110,110,110))
            $g.FillRectangle($br, 4, 4, 7, 7); $br.Dispose()
        }
        $pen.Dispose()
    }
    $g.Dispose()
    return $bmp
}

$imgStates = New-Object System.Windows.Forms.ImageList
$imgStates.ImageSize = New-Object System.Drawing.Size(16,16)
$imgStates.ColorDepth = 'Depth32Bit'
[void]$imgStates.Images.Add((New-CheckImage ([System.Windows.Forms.VisualStyles.CheckBoxState]::UncheckedNormal)))
[void]$imgStates.Images.Add((New-CheckImage ([System.Windows.Forms.VisualStyles.CheckBoxState]::CheckedNormal)))
[void]$imgStates.Images.Add((New-CheckImage ([System.Windows.Forms.VisualStyles.CheckBoxState]::MixedNormal)))

# ---- Thanh công cụ trên cây ----
$pnlTools = New-Object System.Windows.Forms.Panel
$pnlTools.Dock = 'Top'; $pnlTools.Height = 32

$btnAll = New-Object System.Windows.Forms.Button
$btnAll.Text = "Chọn tất cả"; $btnAll.Location = New-Object System.Drawing.Point(10,3)
$btnAll.Size = New-Object System.Drawing.Size(100,25); $btnAll.Enabled = $false

$btnNone = New-Object System.Windows.Forms.Button
$btnNone.Text = "Bỏ chọn tất cả"; $btnNone.Location = New-Object System.Drawing.Point(116,3)
$btnNone.Size = New-Object System.Drawing.Size(110,25); $btnNone.Enabled = $false

$lblFilter = New-Object System.Windows.Forms.Label
$lblFilter.Text = "Lọc (trong các mục đã mở):"; $lblFilter.Location = New-Object System.Drawing.Point(240,8)
$lblFilter.AutoSize = $true

$txtFilter = New-Object System.Windows.Forms.TextBox
$txtFilter.Location = New-Object System.Drawing.Point(400,4)
$txtFilter.Size = New-Object System.Drawing.Size(230,24)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = "Bấm dấu + để bung thư mục và chọn từng file"
$lblHint.Location = New-Object System.Drawing.Point(645,8); $lblHint.AutoSize = $true
$lblHint.ForeColor = [System.Drawing.Color]::Gray

$pnlTools.Controls.AddRange(@($btnAll,$btnNone,$lblFilter,$txtFilter,$lblHint))

# ---- Cây ----
$tv = New-Object System.Windows.Forms.TreeView
$tv.Dock = 'Fill'
$tv.CheckBoxes = $false            # dùng StateImageList tự quản thay cho checkbox 2 trạng thái
$tv.StateImageList = $imgStates
$tv.HideSelection = $false
$tv.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# ---- Danh sách kết quả lọc (chỉ hiện khi đang lọc) ----
$lstFilter = New-Object System.Windows.Forms.ListBox
$lstFilter.Dock = 'Bottom'; $lstFilter.Height = 120; $lstFilter.Visible = $false
$lstFilter.Font = New-Object System.Drawing.Font("Consolas", 8)

# ---- Thanh đường dẫn ----
$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Dock = 'Bottom'; $lblPath.Height = 20; $lblPath.TextAlign = 'MiddleLeft'
$lblPath.BackColor = [System.Drawing.Color]::FromArgb(255,245,245,245)
$lblPath.Font = New-Object System.Drawing.Font("Consolas", 8)
$lblPath.AutoEllipsis = $true
$lblPath.Padding = New-Object System.Windows.Forms.Padding(6,0,0,0)
$lblPath.Text = "Đường dẫn: (chưa chọn dòng nào)"

$pnlTree = New-Object System.Windows.Forms.Panel
$pnlTree.Dock = 'Fill'
$pnlTree.Controls.AddRange(@($tv,$lblPath,$lstFilter,$pnlTools))

# ---- Menu chuột phải ----
$ctx = New-Object System.Windows.Forms.ContextMenuStrip
$miCheckBranch   = $ctx.Items.Add("Chọn cả nhánh này")
$miUncheckBranch = $ctx.Items.Add("Bỏ chọn cả nhánh này")
[void]$ctx.Items.Add("-")
$miExpandBranch  = $ctx.Items.Add("Bung hết nhánh này")
$tv.ContextMenuStrip = $ctx

# ---------------------------------------------------------------------
# Panel dưới: tổng + nút xóa + hẹn giờ + tiến trình + log
# ---------------------------------------------------------------------
$pnlBottom = New-Object System.Windows.Forms.Panel
$pnlBottom.Dock = 'Bottom'; $pnlBottom.Height = 190

$lblTotal = New-Object System.Windows.Forms.Label
$lblTotal.Text = "Tổng: 0 mục, 0 file, 0 B"; $lblTotal.Location = New-Object System.Drawing.Point(10,6)
$lblTotal.AutoSize = $true; $lblTotal.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = "2. XÓA VĨNH VIỄN"; $btnDelete.Location = New-Object System.Drawing.Point(10,30)
$btnDelete.Size = New-Object System.Drawing.Size(180,34); $btnDelete.Enabled = $false
$btnDelete.BackColor = [System.Drawing.Color]::FromArgb(255,200,40,40)
$btnDelete.ForeColor = [System.Drawing.Color]::White
$btnDelete.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Hủy"; $btnCancel.Location = New-Object System.Drawing.Point(200,30)
$btnCancel.Size = New-Object System.Drawing.Size(90,34); $btnCancel.Enabled = $false

# ---- Hẹn giờ: chạy ngoài giờ làm việc (máy để bật, app để mở) ----
$lblAt = New-Object System.Windows.Forms.Label
$lblAt.Text = "Hẹn giờ chạy:"; $lblAt.Location = New-Object System.Drawing.Point(302,39); $lblAt.AutoSize = $true

$dtpTime = New-Object System.Windows.Forms.DateTimePicker
$dtpTime.Format = 'Custom'; $dtpTime.CustomFormat = 'HH:mm'; $dtpTime.ShowUpDown = $true
$dtpTime.Location = New-Object System.Drawing.Point(390,35)
$dtpTime.Size = New-Object System.Drawing.Size(60,24)
$dtpTime.Value = (Get-Date).Date.AddHours(22)   # mặc định 22:00

$btnSchedule = New-Object System.Windows.Forms.Button
$btnSchedule.Text = "Hẹn giờ xóa"; $btnSchedule.Location = New-Object System.Drawing.Point(458,30)
$btnSchedule.Size = New-Object System.Drawing.Size(110,34); $btnSchedule.Enabled = $false

$lblCountdown = New-Object System.Windows.Forms.Label
$lblCountdown.Location = New-Object System.Drawing.Point(578,39); $lblCountdown.AutoSize = $true
$lblCountdown.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblCountdown.ForeColor = [System.Drawing.Color]::FromArgb(255,180,90,0)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(10,72); $progress.Size = New-Object System.Drawing.Size(940,18)
$progress.Anchor = 'Top,Left,Right'

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Sẵn sàng."; $lblStatus.Location = New-Object System.Drawing.Point(10,94)
$lblStatus.Size = New-Object System.Drawing.Size(940,16); $lblStatus.Anchor = 'Top,Left,Right'; $lblStatus.AutoEllipsis = $true

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(10,114); $txtLog.Size = New-Object System.Drawing.Size(940,66)
$txtLog.Multiline = $true; $txtLog.ScrollBars = 'Vertical'; $txtLog.ReadOnly = $true
$txtLog.Anchor = 'Top,Bottom,Left,Right'; $txtLog.Font = New-Object System.Drawing.Font("Consolas", 8)

$pnlBottom.Controls.AddRange(@($lblTotal,$btnDelete,$btnCancel,$lblAt,$dtpTime,$btnSchedule,$lblCountdown,$progress,$lblStatus,$txtLog))

$form.Controls.Add($pnlTree)
$form.Controls.Add($pnlBottom)
$form.Controls.Add($pnlOpt)
$form.Controls.Add($lblWarn)

# =====================================================================
# LOGIC CÂY
# =====================================================================

function Test-KeptUI($path) {
    foreach ($keep in $KeepPaths) {
        if ([string]::IsNullOrWhiteSpace($keep)) { continue }
        try {
            $k = [System.IO.Path]::GetFullPath($keep).TrimEnd('\')
            $f = [System.IO.Path]::GetFullPath($path).TrimEnd('\')
            if ($f -eq $k -or $f.StartsWith($k + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
        } catch {}
    }
    return $false
}

function Format-NodeText($name, $isFolder, $files, $bytes, $last) {
    $t = $name
    if ($isFolder) { $t += ("  —  {0:N0} file · {1}" -f $files, (Format-Size $bytes)) }
    else           { $t += ("  —  {0}" -f (Format-Size $bytes)) }
    if ($last) { $t += ("  ·  sửa {0:dd/MM/yyyy}" -f $last) }
    return $t
}

# Liệt kê con cấp 1 của một thư mục, kèm số file / dung lượng / ngày sửa mới nhất.
# Mỗi cây con được duyệt đúng một lần nên tổng chi phí bằng một lượt duyệt thư mục cha.
function Get-ChildEntries($path) {
    $out = @()
    $items = @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue)
    foreach ($it in $items) {
        if (($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        if (Test-KeptUI $it.FullName) { continue }
        if ($it.PSIsContainer) {
            $cnt = 0; $bytes = [long]0; $last = $it.LastWriteTime
            $files = @(Get-ChildItem -LiteralPath $it.FullName -File -Recurse -Force -ErrorAction SilentlyContinue)
            foreach ($f in $files) {
                $cnt++; $bytes += $f.Length
                if ($f.LastWriteTime -gt $last) { $last = $f.LastWriteTime }
            }
            $out += @{ Path=$it.FullName; Name=$it.Name; IsFolder=$true; IsGroup=$false; Files=$cnt; Bytes=$bytes; Last=$last; Loaded=$false }
        } else {
            $out += @{ Path=$it.FullName; Name=$it.Name; IsFolder=$false; IsGroup=$false; Files=1; Bytes=[long]$it.Length; Last=$it.LastWriteTime; Loaded=$true }
        }
    }
    # Tự sắp theo dung lượng giảm dần (thay cho việc bấm sắp xếp cột).
    return @($out | Sort-Object -Property @{Expression={[long]$_.Bytes}} -Descending)
}

function New-TreeNode($entry, $state) {
    $n = New-Object System.Windows.Forms.TreeNode
    $n.Text = Format-NodeText $entry.Name $entry.IsFolder $entry.Files $entry.Bytes $entry.Last
    $n.Tag = $entry
    $n.StateImageIndex = $state
    if ($entry.IsFolder -and -not $entry.Loaded) {
        # Node giả để hiện dấu + ; nội dung thật nạp khi bung (nạp lười).
        $dummy = New-Object System.Windows.Forms.TreeNode("Đang đọc...")
        $dummy.Tag = $null
        [void]$n.Nodes.Add($dummy)
    }
    return $n
}

# Đặt trạng thái cho node và lan xuống toàn bộ con ĐÃ NẠP.
function Set-NodeState($node, $state) {
    $node.StateImageIndex = $state
    if ($state -eq $ST_PART) { return }
    foreach ($c in $node.Nodes) {
        if ($null -eq $c.Tag) { continue }   # node giả
        Set-NodeState $c $state
    }
}

# Tính lại trạng thái cha từ các con đã nạp: hết tick -> 1, hết trống -> 0, còn lại -> 2 (mờ).
function Update-Ancestors($node) {
    $p = $node.Parent
    while ($p) {
        $all = $true; $none = $true
        foreach ($c in $p.Nodes) {
            if ($null -eq $c.Tag) { continue }
            if ($c.StateImageIndex -ne $ST_ALL)  { $all  = $false }
            if ($c.StateImageIndex -ne $ST_NONE) { $none = $false }
        }
        if     ($all)  { $p.StateImageIndex = $ST_ALL }
        elseif ($none) { $p.StateImageIndex = $ST_NONE }
        else           { $p.StateImageIndex = $ST_PART }
        $p = $p.Parent
    }
}

function Toggle-Node($node) {
    if ($null -eq $node -or $null -eq $node.Tag) { return }
    # Mờ hoặc trống -> bấm thành chọn hết; đang chọn hết -> bấm thành trống.
    $new = if ($node.StateImageIndex -eq $ST_ALL) { $ST_NONE } else { $ST_ALL }
    Set-NodeState $node $new
    Update-Ancestors $node
    Update-SelectionTotals
}

# Nạp lười: bung tới đâu quét tới đó. Con mới sinh thừa hưởng trạng thái của cha.
function Expand-Node($node) {
    $t = $node.Tag
    if ($null -eq $t -or $t.Loaded) { return }
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $tv.BeginUpdate()
    try {
        $node.Nodes.Clear()
        $inherit = $node.StateImageIndex
        if ($inherit -eq $ST_PART) { $inherit = $ST_ALL }   # không xảy ra, nhưng phòng xa
        foreach ($e in (Get-ChildEntries $t.Path)) {
            [void]$node.Nodes.Add((New-TreeNode $e $inherit))
        }
        $t.Loaded = $true
        if ($node.Nodes.Count -eq 0) { $node.Text += "  (rỗng)" }
    } catch {
        $node.Nodes.Clear()
        [void]$node.Nodes.Add((New-Object System.Windows.Forms.TreeNode("(không đọc được: $($_.Exception.Message))")))
        $t.Loaded = $true
    } finally {
        $tv.EndUpdate()
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

# Gom lựa chọn thành TẬP PHỦ NHỎ NHẤT: node nào tick hết thì lấy cả nhánh và
# không đi sâu nữa; node mờ thì đi tiếp vào con. Nhờ vậy danh sách gửi sang
# worker gọn, mà worker vẫn giữ nguyên hợp đồng cũ (nhận thư mục hoặc file).
function Get-CheckedSelection {
    $paths = New-Object System.Collections.ArrayList
    $stats = @{ Files = 0; Bytes = [long]0 }

    function Walk($nodes) {
        foreach ($n in $nodes) {
            $t = $n.Tag
            if ($null -eq $t) { continue }
            $st = $n.StateImageIndex
            if ($st -eq $ST_NONE) { continue }
            if ($t.IsGroup) { Walk $n.Nodes; continue }
            if ($st -eq $ST_ALL) {
                [void]$paths.Add($t.Path)
                $stats.Files += [int]$t.Files
                $stats.Bytes += [long]$t.Bytes
            } else {
                Walk $n.Nodes
            }
        }
    }
    Walk $tv.Nodes
    return [pscustomobject]@{ Paths = @($paths); Files = $stats.Files; Bytes = $stats.Bytes }
}

function Update-SelectionTotals {
    $sel = Get-CheckedSelection
    $lblTotal.Text = "Đã chọn: {0:N0} mục, {1:N0} file, {2}" -f $sel.Paths.Count, $sel.Files, (Format-Size $sel.Bytes)
    $can = ($sel.Paths.Count -gt 0) -and (-not $sync.Busy) -and (-not $script:ScheduledAt)
    $btnDelete.Enabled   = $can
    $btnSchedule.Enabled = $can
}

# =====================================================================
# HỘP XÁC NHẬN - liệt kê chi tiết đúng những gì đang được tick
# =====================================================================
function Confirm-Erase($sel, $whenText) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Xác nhận xóa vĩnh viễn"
    $dlg.Size = New-Object System.Drawing.Size(760, 520)
    $dlg.StartPosition = 'CenterParent'
    $dlg.MinimizeBox = $false; $dlg.MaximizeBox = $false

    $head = New-Object System.Windows.Forms.Label
    $head.Dock = 'Top'; $head.Height = 62; $head.TextAlign = 'MiddleLeft'
    $head.Padding = New-Object System.Windows.Forms.Padding(10,0,10,0)
    $head.BackColor = [System.Drawing.Color]::FromArgb(255,244,199,199)
    $head.ForeColor = [System.Drawing.Color]::DarkRed
    $head.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $htxt = "SẼ XÓA VĨNH VIỄN {0:N0} mục — {1:N0} file — {2}." -f $sel.Paths.Count, $sel.Files, (Format-Size $sel.Bytes)
    if ($whenText) { $htxt += [Environment]::NewLine + "Sẽ chạy lúc: $whenText" }
    $htxt += [Environment]::NewLine + "KHÔNG THỂ HOÀN TÁC."
    $head.Text = $htxt

    $lblList = New-Object System.Windows.Forms.Label
    $lblList.Dock = 'Top'; $lblList.Height = 20; $lblList.Padding = New-Object System.Windows.Forms.Padding(10,2,0,0)
    $lblList.Text = "Danh sách chi tiết những mục sẽ bị xóa:"

    $lst = New-Object System.Windows.Forms.ListBox
    $lst.Dock = 'Fill'; $lst.Font = New-Object System.Drawing.Font("Consolas", 8)
    $lst.HorizontalScrollbar = $true
    foreach ($p in $sel.Paths) { [void]$lst.Items.Add($p) }

    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Dock = 'Bottom'; $pnl.Height = 80

    $lblAsk = New-Object System.Windows.Forms.Label
    $lblAsk.Text = "Gõ đúng chữ  ERASE  để xác nhận:"
    $lblAsk.Location = New-Object System.Drawing.Point(10,12); $lblAsk.AutoSize = $true

    $txtAsk = New-Object System.Windows.Forms.TextBox
    $txtAsk.Location = New-Object System.Drawing.Point(10,34)
    $txtAsk.Size = New-Object System.Drawing.Size(200,26)
    $txtAsk.Font = New-Object System.Drawing.Font("Consolas", 11)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "XÓA VĨNH VIỄN"; $btnOk.Location = New-Object System.Drawing.Point(430,30)
    $btnOk.Size = New-Object System.Drawing.Size(150,32); $btnOk.Enabled = $false
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(255,200,40,40)
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = "Hủy bỏ"; $btnNo.Location = New-Object System.Drawing.Point(590,30)
    $btnNo.Size = New-Object System.Drawing.Size(120,32)
    $btnNo.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    # Nút xóa chỉ bật khi gõ đúng ERASE.
    $txtAsk.Add_TextChanged({ $btnOk.Enabled = ($txtAsk.Text -ceq 'ERASE') }.GetNewClosure())

    $pnl.Controls.AddRange(@($lblAsk,$txtAsk,$btnOk,$btnNo))
    $dlg.Controls.AddRange(@($lst,$lblList,$head,$pnl))
    $dlg.AcceptButton = $btnOk; $dlg.CancelButton = $btnNo

    $r = $dlg.ShowDialog($form)
    $ok = ($r -eq [System.Windows.Forms.DialogResult]::OK -and $txtAsk.Text -ceq 'ERASE')
    $dlg.Dispose()
    return $ok
}

# =====================================================================
# CHẠY XÓA
# =====================================================================
$script:ScheduledAt = $null
$script:PendingSel  = $null
$script:RunStart    = $null
$script:RunWipeRoots = @()

function Start-DeleteRun($sel) {
    $paths = $sel.Paths
    # Bảng tra ổ -> số lần ghi đè (SSD=0, HDD=1)
    $driveModes = @{}
    foreach ($d in $script:Drives) { $driveModes[$d.Letter.ToUpper()] = $d.Passes }

    # CHỈ wipe những ổ vừa là SSD, vừa THỰC SỰ có file bị xóa.
    $used = @{}
    foreach ($p in $paths) { if ($p.Length -ge 2) { $used[$p.Substring(0,2).ToUpper()] = $true } }
    $wipeRoots = @()
    foreach ($d in $script:Drives) {
        if ($d.Wipe -and $used.ContainsKey($d.Letter.ToUpper())) { $wipeRoots += $d.Root }
    }
    $restoreRoots = @($script:Drives | ForEach-Object { $_.Root })

    # Mở file log trước khi chạy: mất điện vẫn còn đến dòng cuối cùng.
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
        $sync.LogPath = Join-Path $LogDir ("reset-{0}-{1:yyyyMMdd-HHmmss}.log" -f $env:COMPUTERNAME, (Get-Date))
    } catch { $sync.LogPath = '' }
    $script:RunStart = Get-Date
    $script:RunWipeRoots = $wipeRoots
    $sync.Skipped.Clear()

    $sync.FilesTotal = $sel.Files; $sync.FilesDone = 0; $sync.BytesDone = 0; $sync.PendingReboot = $false
    $btnScan.Enabled = $false; $btnDelete.Enabled = $false; $btnSchedule.Enabled = $false; $btnCancel.Enabled = $true
    $chkOther.Enabled = $false; $chkKill.Enabled = $false; $dtpTime.Enabled = $false
    $btnAll.Enabled = $false; $btnNone.Enabled = $false; $tv.Enabled = $false
    $progress.Style = 'Continuous'; $progress.Value = 0
    $txtLog.AppendText("===== BẮT ĐẦU XÓA =====`r`n")
    if ($wipeRoots.Count -gt 0) {
        $secs = 0.0
        foreach ($d in $script:Drives) { if ($wipeRoots -contains $d.Root) { $secs += $d.WipeSecs } }
        $txtLog.AppendText("LƯU Ý: giai đoạn wipe vùng trống ước tính ~$(Format-Duration $secs). Bấm Hủy sẽ dừng nhưng phải dọn thư mục tạm.`r`n")
    }
    $null = Set-KeepAwake $true

    $script:AwaitDelete = $true
    $sync.Busy = $true; $sync.Phase = 'delete'   # đặt trước để tránh race với timer (Add-Type mất ~1-2s)
    $timer.Start()
    Start-BgWork -Script $DeleteScript -Arguments @(
        $sync, $paths, $driveModes, $wipeRoots, $restoreRoots,
        $CoreFunctions, $KeepPaths, [bool]$chkKill.Checked, $KillProcessNames
    )
}

function Write-HandoverReport {
    if (-not $sync.LogPath) { return $null }
    try {
        $path = Join-Path $LogDir ("bao-cao-ban-giao-{0}-{1:yyyyMMdd-HHmmss}.txt" -f $env:COMPUTERNAME, $script:RunStart)
        $L = @()
        $L += "BÁO CÁO XÓA DỮ LIỆU BÀN GIAO MÁY"
        $L += "================================="
        $L += "Máy            : $env:COMPUTERNAME"
        $L += "Người chạy     : $env:USERDOMAIN\$env:USERNAME"
        $L += "Bắt đầu        : {0:dd/MM/yyyy HH:mm:ss}" -f $script:RunStart
        $L += "Kết thúc       : {0:dd/MM/yyyy HH:mm:ss}" -f (Get-Date)
        $L += ""
        $L += "CHẾ ĐỘ XÓA THEO TỪNG Ổ ĐĨA"
        foreach ($d in $script:Drives) {
            if ($d.Wipe) { $L += ("  {0} ({1}) : wipe vùng trống, không ghi đè từng file  [{2}]" -f $d.Letter,$d.Media,$d.Detect) }
            else         { $L += ("  {0} ({1}) : ghi đè từng file 1 lần, không wipe        [{2}]" -f $d.Letter,$d.Media,$d.Detect) }
        }
        if ($script:RunWipeRoots -and $script:RunWipeRoots.Count -gt 0) {
            $L += ("  Đã wipe vùng trống trên: " + ($script:RunWipeRoots -join ', '))
        } else {
            $L += "  Không wipe vùng trống ổ nào."
        }
        $L += ""
        $L += "KẾT QUẢ"
        $L += "  Số file đã xóa   : $($sync.FilesDone) / $($sync.FilesTotal)"
        $L += "  Dung lượng       : $(Format-Size $sync.BytesDone)"
        $L += "  Bị hủy giữa chừng: $(if ($sync.Cancel) { 'CÓ' } else { 'Không' })"
        $L += ""
        if ($sync.Skipped.Count -gt 0) {
            $L += "CẢNH BÁO - $($sync.Skipped.Count) FILE CHƯA XÓA AN TOÀN"
            $L += "File hoãn tới lần khởi động lại chỉ bị XÓA THƯỜNG, KHÔNG được ghi đè,"
            $L += "nghĩa là vẫn có thể khôi phục được. Khởi động lại máy rồi chạy lại app"
            $L += "để xử lý dứt điểm những file này."
            foreach ($s in $sync.Skipped) { $L += "  - $s" }
        } else {
            $L += "Không có file nào bị bỏ sót."
        }
        $L += ""
        $L += "Log chi tiết: $($sync.LogPath)"
        [System.IO.File]::WriteAllLines($path, $L, (New-Object System.Text.UTF8Encoding($true)))
        return $path
    } catch { return $null }
}

# =====================================================================
# TIMER cập nhật UI từ state nền
# =====================================================================
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 200
$timer.Add_Tick({
    # ---- Đếm ngược hẹn giờ ----
    if ($script:ScheduledAt) {
        $left = $script:ScheduledAt - (Get-Date)
        if ($left.TotalSeconds -le 0) {
            if (-not $sync.Busy) {          # không chạy chồng lên việc đang chạy
                $sel = $script:PendingSel
                $script:ScheduledAt = $null; $script:PendingSel = $null
                $btnSchedule.Text = "Hẹn giờ xóa"; $lblCountdown.Text = ""
                $txtLog.AppendText("Đã tới giờ hẹn - bắt đầu xóa.`r`n")
                Start-DeleteRun $sel
            }
        } else {
            $lblCountdown.Text = ("Chạy sau {0:hh\:mm\:ss}" -f $left)
        }
    }

    # Đổ log ra textbox
    while ($sync.Log.Count -gt 0) {
        $msg = $sync.Log[0]; $sync.Log.RemoveAt(0)
        $txtLog.AppendText($msg + "`r`n")
    }
    if ($sync.Status) { $lblStatus.Text = $sync.Status }

    if ($sync.Phase -eq 'scan') {
        $progress.Style = 'Marquee'
    }
    elseif ($sync.Phase -eq 'delete') {
        if ($sync.Wiping) {
            # Giai đoạn wipe: số file đã cố định nên thanh % sẽ đứng im hàng giờ
            # -> chuyển sang chạy băng để biết app vẫn đang làm việc.
            $progress.Style = 'Marquee'
            $lblStatus.Text = $sync.Status
        } else {
            $progress.Style = 'Continuous'
            if ($sync.FilesTotal -gt 0) {
                $pct = [int](($sync.FilesDone / $sync.FilesTotal) * 100)
                if ($pct -gt 100) { $pct = 100 }
                $progress.Value = $pct
                $lblStatus.Text = "Đã xóa $($sync.FilesDone)/$($sync.FilesTotal) file ($(Format-Size $sync.BytesDone))  -  $($sync.Status)"
            }
        }
    }

    # ---- Khi quét xong -> dựng cây ----
    if ($sync.Phase -eq '' -and -not $sync.Busy -and $script:AwaitScan) {
        $script:AwaitScan = $false
        $progress.Style = 'Continuous'; $progress.Value = 0
        $tv.BeginUpdate()
        $tv.Nodes.Clear()
        $groups = [ordered]@{}
        $totalFiles = 0; [long]$totalBytes = 0
        foreach ($r in $sync.Scan) {
            # Sao giá trị sang hashtable tạo ở luồng UI ngay tại đây: object sinh
            # trong runspace khác không dùng lại được về sau.
            $e = @{
                Path = [string]$r.Path; Name = [string]$r.Item; IsFolder = [bool]$r.IsFolder
                IsGroup = $false; Files = [int]$r.Files; Bytes = [long]$r.Bytes
                Last = $r.Last; Loaded = (-not [bool]$r.IsFolder)
            }
            $g = [string]$r.Profile
            if (-not $groups.Contains($g)) { $groups[$g] = New-Object System.Collections.ArrayList }
            [void]$groups[$g].Add($e)
            $totalFiles += $e.Files; $totalBytes += $e.Bytes
        }
        foreach ($g in $groups.Keys) {
            $gn = New-Object System.Windows.Forms.TreeNode
            $gFiles = 0; [long]$gBytes = 0
            foreach ($e in $groups[$g]) { $gFiles += $e.Files; $gBytes += $e.Bytes }
            $gn.Text = "{0}  —  {1:N0} file · {2}" -f $g, $gFiles, (Format-Size $gBytes)
            $gn.Tag = @{ Path=$null; Name=$g; IsFolder=$true; IsGroup=$true; Files=$gFiles; Bytes=$gBytes; Last=$null; Loaded=$true }
            $gn.StateImageIndex = $ST_ALL
            $gn.NodeFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
            foreach ($e in ($groups[$g] | Sort-Object -Property @{Expression={[long]$_.Bytes}} -Descending)) {
                [void]$gn.Nodes.Add((New-TreeNode $e $ST_ALL))
            }
            [void]$tv.Nodes.Add($gn)
        }
        $tv.EndUpdate()
        foreach ($n in $tv.Nodes) { $n.Expand() }   # bung sẵn cấp nhóm cho dễ nhìn

        $btnScan.Enabled = $true
        $btnAll.Enabled = ($tv.Nodes.Count -gt 0); $btnNone.Enabled = ($tv.Nodes.Count -gt 0)
        Update-SelectionTotals
        # Xoá Status: timer ghi $lblStatus tu $sync.Status moi 200ms, khong xoa thi
        # dong tom tat duoi day bi ghi de lai bang "Quét xong." ngay tick ke tiep.
        $sync.Status = ''
        $lblStatus.Text = "Quét xong: {0:N0} file, {1}. Bung thư mục để chọn từng file, bỏ tick mục muốn giữ." -f $totalFiles, (Format-Size $totalBytes)
    }

    # ---- Khi xóa xong ----
    if ($sync.Phase -eq '' -and -not $sync.Busy -and $script:AwaitDelete) {
        $script:AwaitDelete = $false
        $timer.Stop() | Out-Null
        $progress.Value = 100
        $null = Set-KeepAwake $false
        $btnScan.Enabled = $true; $btnDelete.Enabled = $false; $btnCancel.Enabled = $false
        $btnSchedule.Enabled = $false; $dtpTime.Enabled = $true
        $chkOther.Enabled = $true; $chkKill.Enabled = $true
        $btnAll.Enabled = $true; $btnNone.Enabled = $true; $tv.Enabled = $true

        $report = Write-HandoverReport
        $tail = ""
        if ($report) { $tail = "`n`nBáo cáo bàn giao:`n$report" }

        if ($sync.PendingReboot) {
            [System.Windows.Forms.MessageBox]::Show(
                "Đã hoàn tất xóa.`n`nCó $($sync.Skipped.Count) file đang bị khóa -> đã lên lịch xóa khi khởi động lại." +
                "`nLƯU Ý: những file đó chỉ bị XÓA THƯỜNG, KHÔNG được ghi đè - vẫn có thể khôi phục." +
                "`nHãy khởi động lại máy rồi chạy lại app để xử lý dứt điểm." + $tail,
                "Reset Machine",
                [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("Đã hoàn tất xóa." + $tail,"Reset Machine",
                [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
    }
})

# =====================================================================
# SỰ KIỆN
# =====================================================================
$btnScan.Add_Click({
    $btnScan.Enabled = $false; $btnDelete.Enabled = $false; $btnSchedule.Enabled = $false
    $btnAll.Enabled = $false; $btnNone.Enabled = $false
    $tv.Nodes.Clear(); $txtLog.Clear(); $txtFilter.Clear(); $lstFilter.Visible = $false
    $lblTotal.Text = "Tổng: 0 mục, 0 file, 0 B"
    $lblStatus.Text = "Đang quét..."; $progress.Style = 'Marquee'

    $letters = @($script:Drives | ForEach-Object { $_.Letter })
    # Ghi rõ ổ nào bị loại khỏi vùng xóa. Google Drive for Desktop mount thành ổ
    # local ảo (DriveType=3) - phải thấy nó bị bỏ qua ở đây.
    $allFixed = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty DeviceID)
    foreach ($f in $allFixed) {
        if ($letters -notcontains $f) {
            $txtLog.AppendText("BỎ QUA $f - không map được sang đĩa vật lý (ổ ảo / ổ đám mây)`r`n")
        }
    }

    $script:AwaitScan = $true
    $sync.Busy = $true; $sync.Phase = 'scan'   # đặt trước để tránh race với timer
    $timer.Start()
    Start-BgWork -Script $ScanScript -Arguments @($sync, $SkipProfiles, [bool]$chkOther.Checked, $KeepPaths, $letters)
})

# ---- Tương tác cây ----
$tv.Add_BeforeExpand({ param($s,$e) Expand-Node $e.Node })

$tv.Add_NodeMouseClick({
    param($s,$e)
    $hit = $tv.HitTest($e.X, $e.Y)
    if ($hit.Location -eq [System.Windows.Forms.TreeViewHitTestLocations]::StateImage) {
        Toggle-Node $e.Node
    }
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) { $tv.SelectedNode = $e.Node }
})

$tv.Add_KeyDown({
    param($s,$e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Space) {
        Toggle-Node $tv.SelectedNode
        $e.Handled = $true; $e.SuppressKeyPress = $true
    }
})

$tv.Add_AfterSelect({
    param($s,$e)
    $t = $e.Node.Tag
    if ($null -ne $t -and $t.Path) { $lblPath.Text = "Đường dẫn: " + $t.Path }
    elseif ($null -ne $t -and $t.IsGroup) { $lblPath.Text = "Nhóm: " + $t.Name }
    else { $lblPath.Text = "Đường dẫn: (chưa chọn dòng nào)" }
})

$btnAll.Add_Click({
    $tv.BeginUpdate()
    foreach ($n in $tv.Nodes) { Set-NodeState $n $ST_ALL }
    $tv.EndUpdate(); Update-SelectionTotals
})
$btnNone.Add_Click({
    $tv.BeginUpdate()
    foreach ($n in $tv.Nodes) { Set-NodeState $n $ST_NONE }
    $tv.EndUpdate(); Update-SelectionTotals
})

$miCheckBranch.Add_Click({
    $n = $tv.SelectedNode
    if ($n) { Set-NodeState $n $ST_ALL; Update-Ancestors $n; Update-SelectionTotals }
})
$miUncheckBranch.Add_Click({
    $n = $tv.SelectedNode
    if ($n) { Set-NodeState $n $ST_NONE; Update-Ancestors $n; Update-SelectionTotals }
})
$miExpandBranch.Add_Click({
    $n = $tv.SelectedNode
    if ($n) { $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor; try { $n.ExpandAll() } finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default } }
})

# ---- Bộ lọc: tìm trong các node đã nạp, kết quả ra danh sách phẳng ----
$script:FilterHits = @()

$txtFilter.Add_TextChanged({
    $q = $txtFilter.Text.Trim()
    $lstFilter.Items.Clear()
    $script:FilterHits = @()
    if ($q.Length -eq 0) { $lstFilter.Visible = $false; return }

    $hits = New-Object System.Collections.ArrayList
    function Scan-Nodes($nodes) {
        foreach ($n in $nodes) {
            $t = $n.Tag
            if ($null -ne $t -and -not $t.IsGroup -and $t.Name -and
                $t.Name.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                [void]$hits.Add($n)
            }
            Scan-Nodes $n.Nodes
        }
    }
    Scan-Nodes $tv.Nodes

    $script:FilterHits = @($hits)
    foreach ($n in $script:FilterHits) { [void]$lstFilter.Items.Add($n.Tag.Path) }
    if ($script:FilterHits.Count -eq 0) { [void]$lstFilter.Items.Add("(không thấy mục nào khớp trong các mục đã mở)") }
    $lstFilter.Visible = $true
})

$lstFilter.Add_SelectedIndexChanged({
    $i = $lstFilter.SelectedIndex
    if ($i -ge 0 -and $i -lt $script:FilterHits.Count) {
        $n = $script:FilterHits[$i]
        $n.EnsureVisible(); $tv.SelectedNode = $n; $tv.Focus() | Out-Null
    }
})

# ---- Xóa ngay ----
$btnDelete.Add_Click({
    $sel = Get-CheckedSelection
    if ($sel.Paths.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Chưa chọn mục nào.","Reset Machine") | Out-Null; return
    }
    if (-not (Confirm-Erase $sel $null)) { $lblStatus.Text = "Đã hủy (không xác nhận)."; return }
    Start-DeleteRun $sel
})

# ---- Hẹn giờ ----
# Xác nhận ERASE lấy NGAY LÚC BẤM HẸN, không phải lúc tới giờ (lúc đó không có ai ở máy).
$btnSchedule.Add_Click({
    if ($script:ScheduledAt) {   # đang hẹn -> nút này thành "Hủy hẹn"
        $script:ScheduledAt = $null; $script:PendingSel = $null
        $null = Set-KeepAwake $false
        $btnSchedule.Text = "Hẹn giờ xóa"
        $lblCountdown.Text = ""
        $btnScan.Enabled = $true; $tv.Enabled = $true
        $btnAll.Enabled = $true; $btnNone.Enabled = $true
        $chkOther.Enabled = $true; $chkKill.Enabled = $true; $dtpTime.Enabled = $true
        Update-SelectionTotals
        $lblStatus.Text = "Đã hủy hẹn giờ."
        return
    }

    $sel = Get-CheckedSelection
    if ($sel.Paths.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Chưa chọn mục nào.","Reset Machine") | Out-Null; return
    }
    # Giờ đã qua trong hôm nay -> hiểu là ngày mai
    $when = (Get-Date).Date.AddHours($dtpTime.Value.Hour).AddMinutes($dtpTime.Value.Minute)
    if ($when -le (Get-Date)) { $when = $when.AddDays(1) }

    if (-not (Confirm-Erase $sel ("{0:dd/MM/yyyy HH:mm}" -f $when))) {
        $lblStatus.Text = "Đã hủy (không xác nhận)."; return
    }

    $script:ScheduledAt = $when
    $script:PendingSel  = $sel
    # Không cho máy ngủ trong lúc chờ. Nếu chặn ngủ HỎNG thì phải báo ngay,
    # vì máy ngủ là lịch hẹn không bao giờ chạy.
    if (-not (Set-KeepAwake $true)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Không chặn được chế độ ngủ của máy.`n`nHãy vào Settings > System > Power & sleep, đặt Sleep = Never trước khi ra về, nếu không lịch hẹn sẽ không chạy.",
            "Reset Machine",
            [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        $txtLog.AppendText("CẢNH BÁO: không chặn được chế độ ngủ - phải tắt Sleep bằng tay.`r`n")
    }
    $btnSchedule.Text = "Hủy hẹn giờ"
    $btnSchedule.Enabled = $true
    $btnScan.Enabled = $false; $btnDelete.Enabled = $false; $tv.Enabled = $false
    $btnAll.Enabled = $false; $btnNone.Enabled = $false
    $chkOther.Enabled = $false; $chkKill.Enabled = $false; $dtpTime.Enabled = $false
    $txtLog.AppendText(("Đã hẹn chạy lúc {0:dd/MM/yyyy HH:mm}. Để nguyên máy bật và app mở.`r`n" -f $when))
    $timer.Start()
})

$btnCancel.Add_Click({
    $sync.Cancel = $true
    $lblStatus.Text = "Đang hủy... (chờ thao tác hiện tại kết thúc)"
    $btnCancel.Enabled = $false
})

$form.Add_FormClosing({
    if ($script:ScheduledAt -and -not $sync.Busy) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            ("Đang hẹn chạy lúc {0:dd/MM/yyyy HH:mm}.`n`nĐóng app sẽ HỦY lịch hẹn. Thoát?" -f $script:ScheduledAt),
            "Reset Machine",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -eq [System.Windows.Forms.DialogResult]::No) { $_.Cancel = $true; return }
    }
    if ($sync.Busy) {
        $r = [System.Windows.Forms.MessageBox]::Show("Đang chạy. Hủy và thoát?","Reset Machine",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -eq [System.Windows.Forms.DialogResult]::No) { $_.Cancel = $true; return }
        $sync.Cancel = $true
    }
    $null = Set-KeepAwake $false
})

[void]$form.ShowDialog()
