<#
=====================================================================
 Reset-Machine.ps1
 ---------------------------------------------------------------------
 Xoa VINH VIEN (secure overwrite) du lieu ca nhan cua nguoi dung tren
 may Windows, nhung GIU LAI:
   - Ung dung da cai (Program Files, Program Files (x86), ProgramData)
   - Cau hinh / data cua app (AppData: Roaming, Local, LocalLow)
   - Windows va he thong
 BO QUA (khong dung toi):
   - O mang (network drive) va o anh xa
   - O di dong (removable) - tuy config

 Sau khi xoa se: xoa Volume Shadow Copies, tat System Restore, va
 (tuy chon) wipe free space de du lieu KHONG the khoi phuc.

 !!! CANH BAO: THAO TAC NAY KHONG THE HOAN TAC !!!
 Luon chay -DryRun truoc de xem se xoa nhung gi.
=====================================================================
#>

[CmdletBinding()]
param(
    # Chi liet ke, KHONG xoa gi. LUON chay cai nay truoc.
    [switch]$DryRun,

    # Bo qua buoc go xac nhan (dung khi chay tu dong / .exe). Neu khong co,
    # script se yeu cau go dung chu "ERASE" de xac nhan.
    [switch]$Force,

    # So lan ghi de moi file (NIST 800-88: 1 pass la du cho o hien dai).
    [int]$Passes = 1,

    # Co wipe free space (cipher /w) sau khi xoa khong.
    # Mac dinh: bat (an toan nhat, chong lab forensic tren SSD).
    [bool]$WipeFreeSpace = $true,

    # Co wipe TOAN BO cac o local khac (D:, E:...) ngoai o he thong khong.
    # Mac dinh: TAT (chi xoa thu muc ca nhan trong profile de an toan).
    [switch]$WipeOtherLocalDrives,

    # DANH SACH GIU LAI: cac duong dan nay (va moi thu ben trong) KHONG BAO GIO bi xoa,
    # ke ca khi nam trong vung xoa (vd thu muc ke toan trong Documents).
    # Vi du: -KeepPaths 'D:\MERGE','C:\Users\ketoan\Documents\MISA'
    [string[]]$KeepPaths = @()
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------
# CAU HINH
# ---------------------------------------------------------------------

# Ten cac thu muc ca nhan trong moi profile se bi XOA.
# (KHONG bao gom AppData => cau hinh app duoc giu lai)
$UserDataFolders = @(
    'Desktop',
    'Documents',
    'Downloads',
    'Pictures',
    'Music',
    'Videos',
    'Favorites',
    'Contacts',
    'Links',
    'Searches',
    'Saved Games',
    '3D Objects',
    'OneDrive'          # cache OneDrive local - bo dong nay neu muon giu
)

# Profile he thong khong dung toi.
$SkipProfiles = @('Public', 'Default', 'Default User', 'All Users', 'defaultuser0')

# Duong dan KHONG BAO GIO duoc xoa (an toan tuyet doi).
$ProtectedRoots = @(
    "$env:SystemRoot",                       # C:\Windows
    "${env:ProgramFiles}",                   # C:\Program Files
    "${env:ProgramFiles(x86)}",              # C:\Program Files (x86)
    "$env:ProgramData",                      # C:\ProgramData
    "$env:SystemDrive\PerfLogs"
)

$LogFile = Join-Path $env:SystemDrive "Reset-Machine_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# ---------------------------------------------------------------------
# HAM TIEN ICH
# ---------------------------------------------------------------------

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'OK'    { Write-Host $line -ForegroundColor Green }
        'DRY'   { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line }
    }
    try { Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue } catch {}
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Protected {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    foreach ($root in $ProtectedRoots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $r = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
        if ($full -eq $r -or $full.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    # Bao ve AppData trong bat ky profile nao
    if ($full -match '(?i)\\AppData(\\|$)') { return $true }
    # Danh sach giu lai do nguoi dung khai bao
    foreach ($keep in $KeepPaths) {
        if ([string]::IsNullOrWhiteSpace($keep)) { continue }
        $k = [System.IO.Path]::GetFullPath($keep).TrimEnd('\')
        if ($full -eq $k -or $full.StartsWith($k + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

# Ghi de an toan noi dung 1 file roi xoa.
function Remove-FileSecure {
    param([string]$Path, [int]$Passes = 1)

    if ($DryRun) { Write-Log "WOULD ERASE FILE: $Path" 'DRY'; return }
    if (Test-Protected $Path) { Write-Log "SKIP (protected): $Path" 'WARN'; return }

    try {
        $fi = New-Object System.IO.FileInfo($Path)
        if ($fi.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
            $fi.Attributes = [System.IO.FileAttributes]::Normal
        }
        $len = $fi.Length
        if ($len -gt 0) {
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $bufSize = [Math]::Min($len, 4MB)
            $buf = New-Object byte[] $bufSize
            for ($p = 0; $p -lt $Passes; $p++) {
                $fs = [System.IO.File]::Open($Path, 'Open', 'Write', 'None')
                try {
                    $fs.Position = 0
                    $remaining = $len
                    while ($remaining -gt 0) {
                        $chunk = [Math]::Min($remaining, $buf.Length)
                        $rng.GetBytes($buf)
                        $fs.Write($buf, 0, $chunk)
                        $remaining -= $chunk
                    }
                    $fs.Flush($true)
                } finally { $fs.Close() }
            }
            $rng.Dispose()
        }
        # Doi ten ngau nhien de xoa dau vet ten file trong MFT (best-effort)
        $rand = [System.IO.Path]::GetRandomFileName()
        $newPath = Join-Path $fi.DirectoryName $rand
        Rename-Item -LiteralPath $Path -NewName $rand -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $newPath) {
            Remove-Item -LiteralPath $newPath -Force -ErrorAction Stop
        } else {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
        $script:FilesErased++
        $script:BytesErased += $len
    } catch {
        Write-Log "FAIL erase '$Path': $($_.Exception.Message)" 'ERROR'
    }
}

# Xoa toan bo 1 thu muc bang secure overwrite.
function Remove-FolderSecure {
    param([string]$Folder, [int]$Passes = 1)

    if (-not (Test-Path -LiteralPath $Folder)) { return }
    if (Test-Protected $Folder) { Write-Log "SKIP (protected): $Folder" 'WARN'; return }

    Write-Log "-> $Folder"
    # Xoa tung file
    Get-ChildItem -LiteralPath $Folder -File -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-FileSecure -Path $_.FullName -Passes $Passes }

    # Xoa cac thu muc rong con lai
    if (-not $DryRun) {
        Get-ChildItem -LiteralPath $Folder -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object {
                if (-not (Test-Protected $_.FullName)) {
                    Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue
                }
            }
        # Tao lai thu muc rong (giu cau truc profile) - bo dong duoi neu muon xoa han
        # New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        Remove-Item -LiteralPath $Folder -Force -Recurse -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------
# BAT DAU
# ---------------------------------------------------------------------

$script:FilesErased = 0
$script:BytesErased = 0

if (-not (Test-Admin)) {
    Write-Host "Script phai chay voi quyen Administrator. Dang thu nang quyen..." -ForegroundColor Yellow
    $psi = @{
        FilePath     = 'powershell.exe'
        ArgumentList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") + $MyInvocation.UnboundArguments
        Verb         = 'RunAs'
    }
    try { Start-Process @psi } catch { Write-Host "Khong the nang quyen." -ForegroundColor Red }
    return
}

Write-Log "================ RESET MACHINE ================"
$modeText = if ($DryRun) { 'DRY-RUN (khong xoa)' } else { 'THUC THI (xoa that)' }
Write-Log "Che do: $modeText"
Write-Log "Passes: $Passes | WipeFreeSpace: $WipeFreeSpace | WipeOtherLocalDrives: $([bool]$WipeOtherLocalDrives)"
Write-Log "Log: $LogFile"

# Xac nhan an toan
if (-not $DryRun -and -not $Force) {
    Write-Host ""
    Write-Host "!!! CANH BAO: Se XOA VINH VIEN du lieu ca nhan. KHONG the hoan tac. !!!" -ForegroundColor Red
    $ans = Read-Host "Go dung chu  ERASE  de tiep tuc"
    if ($ans -ne 'ERASE') { Write-Log "Nguoi dung huy." 'WARN'; return }
}

# --- Xac dinh o LOCAL co dinh (bo qua o mang & removable) ---
# DriveType: 2=Removable, 3=LocalDisk(Fixed), 4=Network, 5=CD
$fixedDrives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
    Select-Object -ExpandProperty DeviceID
Write-Log "O local co dinh se xu ly: $($fixedDrives -join ', ')"
Write-Log "(O mang / o di dong duoc bo qua)"

# ---------------------------------------------------------------------
# 1) XOA DU LIEU CA NHAN TRONG TUNG PROFILE
# ---------------------------------------------------------------------
Write-Log "--- Buoc 1: Xoa du lieu ca nhan trong profiles ---"
$usersRoot = Join-Path $env:SystemDrive 'Users'
Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $profile = $_
    if ($SkipProfiles -contains $profile.Name) {
        Write-Log "Bo qua profile he thong: $($profile.Name)"
        return
    }
    Write-Log "Profile: $($profile.Name)"
    foreach ($sub in $UserDataFolders) {
        $target = Join-Path $profile.FullName $sub
        Remove-FolderSecure -Folder $target -Passes $Passes
    }
}

# ---------------------------------------------------------------------
# 2) DON RECYCLE BIN
# ---------------------------------------------------------------------
Write-Log "--- Buoc 2: Don Recycle Bin ---"
if (-not $DryRun) {
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Write-Log "Da don Recycle Bin." 'OK' }
    catch { Write-Log "Clear-RecycleBin: $($_.Exception.Message)" 'WARN' }
} else { Write-Log "WOULD clear Recycle Bin" 'DRY' }

# ---------------------------------------------------------------------
# 3) (TUY CHON) WIPE TOAN BO O LOCAL KHAC
# ---------------------------------------------------------------------
if ($WipeOtherLocalDrives) {
    Write-Log "--- Buoc 3: Wipe cac o local khac ngoai o he thong ---"
    foreach ($d in $fixedDrives) {
        if ($d -eq $env:SystemDrive) { continue }
        $root = "$d\"
        Write-Log "Xu ly o: $root"
        Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | ForEach-Object {
            # Bo qua thu muc he thong tren o do
            if ($_.Name -match '(?i)^(Program Files|Program Files \(x86\)|ProgramData|Windows|\$Recycle\.Bin|System Volume Information)$') {
                Write-Log "  giu: $($_.Name)"
                return
            }
            if ($_.PSIsContainer) { Remove-FolderSecure -Folder $_.FullName -Passes $Passes }
            else { Remove-FileSecure -Path $_.FullName -Passes $Passes }
        }
    }
} else {
    Write-Log "Bo qua wipe o local khac (WipeOtherLocalDrives = false)."
}

# ---------------------------------------------------------------------
# 4) XOA VOLUME SHADOW COPIES + TAT SYSTEM RESTORE
# ---------------------------------------------------------------------
Write-Log "--- Buoc 4: Xoa Shadow Copies & System Restore ---"
if (-not $DryRun) {
    try { & vssadmin delete shadows /all /quiet 2>&1 | Out-Null; Write-Log "Da xoa Volume Shadow Copies." 'OK' }
    catch { Write-Log "vssadmin: $($_.Exception.Message)" 'WARN' }
    foreach ($d in $fixedDrives) {
        try { Disable-ComputerRestore -Drive "$d\" -ErrorAction SilentlyContinue } catch {}
    }
    Write-Log "Da tat System Restore." 'OK'
} else { Write-Log "WOULD delete shadow copies + disable restore" 'DRY' }

# ---------------------------------------------------------------------
# 5) (TUY CHON) WIPE FREE SPACE
# ---------------------------------------------------------------------
if ($WipeFreeSpace) {
    Write-Log "--- Buoc 5: Wipe free space (cipher /w) - CO THE LAU ---"
    foreach ($d in $fixedDrives) {
        if ($DryRun) { Write-Log "WOULD wipe free space on $d" 'DRY'; continue }
        Write-Log "Wiping free space: $d ... (dang chay)"
        try { & cipher /w:"$d\" 2>&1 | Out-Null; Write-Log "Xong free space: $d" 'OK' }
        catch { Write-Log "cipher $d : $($_.Exception.Message)" 'WARN' }
    }
} else {
    Write-Log "Bo qua wipe free space (WipeFreeSpace = false)."
}

# ---------------------------------------------------------------------
# KET THUC
# ---------------------------------------------------------------------
$mb = [math]::Round($script:BytesErased / 1MB, 1)
Write-Log "================ HOAN TAT ================" 'OK'
Write-Log "Da xoa an toan: $($script:FilesErased) file, ~$mb MB" 'OK'
if ($DryRun) { Write-Log "Day la DRY-RUN: khong co gi bi xoa that." 'DRY' }
Write-Log "Log luu tai: $LogFile"
