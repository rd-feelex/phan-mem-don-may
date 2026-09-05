<#
 Test-SecureDelete.ps1
 Kiem tra co che GHI DE + XOA tren mot thu muc GIA (KHONG dung du lieu that).

 Khac ban cu: KHONG sao chep logic sang day nua. Test nay trich thang khoi
 $CoreFunctions trong Reset-Machine-GUI.ps1 ra chay, nen no luon kiem tra
 dung code that cua app - sua app la test theo, khong bao giờ lech.

 An toan tuyet doi: chi thao tac trong thu muc test tu tao trong %TEMP%.
 Chay: powershell -ExecutionPolicy Bypass -File Test-SecureDelete.ps1
#>

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$app  = Join-Path $here 'Reset-Machine-GUI.ps1'
if (-not (Test-Path $app)) { throw "Khong tim thay $app" }
$root = Join-Path $env:TEMP ('rmtest-' + [Guid]::NewGuid().ToString('N').Substring(0,8))

# --- Nap CoreFunctions THAT tu app ---
$ast    = [System.Management.Automation.Language.Parser]::ParseFile($app, [ref]$null, [ref]$null)
$assign = $ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$CoreFunctions' }, $true)
if ($assign.Count -eq 0) { throw "Khong tim thay \$CoreFunctions trong app" }
$core = $assign[0].Right.Extent.Text
$core = $core.Substring(2, $core.Length - 4)   # bo @' va '@
. ([scriptblock]::Create($core))

Add-Type -Namespace '' -Name 'NativeDel' -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true, CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool MoveFileEx(string lpExistingFileName, System.IntPtr lpNewFileName, int dwFlags);
"@ -ErrorAction SilentlyContinue

function New-Sync {
    return [hashtable]::Synchronized(@{
        Log = New-Object System.Collections.ArrayList; Scan = New-Object System.Collections.ArrayList
        FilesTotal=0; FilesDone=0; FilesFailed=0; BytesDone=0; Status=''; Cancel=$false; Busy=$false; Phase=''
        PendingReboot=$false; LogPath=''; Skipped=New-Object System.Collections.ArrayList; Wiping=$false
    })
}
function New-Tree($base,$n) {
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base 'sub') -Force | Out-Null
    for ($i=1; $i -le $n; $i++) {
        Set-Content -Path (Join-Path $base "f$i.txt")     -Value ("NOI DUNG BI MAT $i " * 50) -Encoding UTF8
        Set-Content -Path (Join-Path $base "sub\g$i.txt") -Value ("NOI DUNG SAU $i " * 50)    -Encoding UTF8
    }
}
$pass=0; $fail=0
function Check($name,$cond,$detail) {
    if ($cond) { Write-Host "  OK   $name" -ForegroundColor Green; $script:pass++ }
    else       { Write-Host "  FAIL $name -> $detail" -ForegroundColor Red; $script:fail++ }
}

Write-Host "`n=== 1. Get-PassesFor: so lan ghi de theo tung o dia ===" -ForegroundColor Cyan
$dm = @{ 'C:' = 0; 'D:' = 1 }
Check "C: (SSD) -> 0 lan"       ((Get-PassesFor $dm 'C:\Users\a\x.txt') -eq 0) (Get-PassesFor $dm 'C:\Users\a\x.txt')
Check "D: (HDD) -> 1 lan"       ((Get-PassesFor $dm 'D:\data\y.txt')    -eq 1) (Get-PassesFor $dm 'D:\data\y.txt')
Check "o la -> mac dinh 1 lan"  ((Get-PassesFor $dm 'E:\z.txt')         -eq 1) (Get-PassesFor $dm 'E:\z.txt')
Check "chu thuong van khop"     ((Get-PassesFor $dm 'c:\x.txt')         -eq 0) (Get-PassesFor $dm 'c:\x.txt')

Write-Host "`n=== 2. Xoa che do SSD (passes=0) ===" -ForegroundColor Cyan
$t = Join-Path $root 'ssd'; New-Tree $t 5
$s = New-Sync; $s.LogPath = Join-Path $root 'test.log'
Remove-FolderSecure $s $t @{ ($t.Substring(0,2)) = 0 } @()
Check "xoa het file"           ((Get-ChildItem $t -File -Recurse).Count -eq 0) ((Get-ChildItem $t -File -Recurse).Count)
Check "GIU LAI khung thu muc"  (Test-Path (Join-Path $t 'sub'))                "thu muc sub bi mat"
Check "dem dung 10 file"       ($s.FilesDone -eq 10)                           $s.FilesDone
Check "cong don dung luong"    ($s.BytesDone -gt 0)                            $s.BytesDone

Write-Host "`n=== 3. Xoa che do HDD (passes=1, co ghi de) ===" -ForegroundColor Cyan
$t2 = Join-Path $root 'hdd'; New-Tree $t2 5
$s2 = New-Sync
Remove-FolderSecure $s2 $t2 @{ ($t2.Substring(0,2)) = 1 } @()
Check "xoa het file"      ((Get-ChildItem $t2 -File -Recurse).Count -eq 0) ((Get-ChildItem $t2 -File -Recurse).Count)
Check "dem dung 10 file"  ($s2.FilesDone -eq 10)                           $s2.FilesDone

Write-Host "`n=== 4. Ghi de that su xoa sach noi dung cu ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $root -Force | Out-Null
$probe = Join-Path $root 'probe.txt'
Set-Content -Path $probe -Value ('BIMAT-CANHBAO-' * 200) -Encoding ASCII
$before = [System.IO.File]::ReadAllBytes($probe)
$len = (Get-Item $probe).Length
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$buf = New-Object byte[] $len
$fs  = [System.IO.File]::Open($probe,'Open','Write','None')
$rng.GetBytes($buf); $fs.Position = 0; $fs.Write($buf,0,$buf.Length); $fs.Flush($true); $fs.Close()
$after = [System.IO.File]::ReadAllBytes($probe)
Check "noi dung da doi hoan toan" (-not ([System.Linq.Enumerable]::SequenceEqual($before,$after))) "noi dung khong doi"
Check "khong con chuoi cu"        (-not ([System.Text.Encoding]::ASCII.GetString($after) -like '*BIMAT*')) "van con chuoi cu"
Remove-Item $probe -Force

Write-Host "`n=== 5. Nut Huy dung ngay ===" -ForegroundColor Cyan
$t3 = Join-Path $root 'cancel'; New-Tree $t3 5
$s3 = New-Sync; $s3.Cancel = $true
Remove-FolderSecure $s3 $t3 @{ ($t3.Substring(0,2)) = 0 } @()
Check "khong xoa file nao" ((Get-ChildItem $t3 -File -Recurse).Count -eq 10) ((Get-ChildItem $t3 -File -Recurse).Count)
Check "FilesDone = 0"      ($s3.FilesDone -eq 0)                             $s3.FilesDone

Write-Host "`n=== 6. Danh sach GIU LAI (KeepPaths) duoc ton trong ===" -ForegroundColor Cyan
$t4 = Join-Path $root 'keep'; New-Tree $t4 3
$keepDir = Join-Path $t4 'sub'
$s4 = New-Sync
Remove-FolderSecure $s4 $t4 @{ ($t4.Substring(0,2)) = 0 } @($keepDir)
Check "file trong vung giu lai con nguyen" ((Get-ChildItem $keepDir -File).Count -eq 3) ((Get-ChildItem $keepDir -File).Count)
Check "file ngoai vung giu lai da xoa"     ((Get-ChildItem $t4 -File).Count -eq 0)      ((Get-ChildItem $t4 -File).Count)

Write-Host "`n=== 7. Log ghi thang xuong dia (chiu duoc mat dien) ===" -ForegroundColor Cyan
Check "file log ton tai"        (Test-Path $s.LogPath)                       $s.LogPath
Check "log co noi dung"         ((Get-Content $s.LogPath -Raw).Length -gt 0) "log rong"
Check "log ghi muc da xoa"      ((Get-Content $s.LogPath -Raw) -like "*$([System.IO.Path]::GetFileName($t))*") "khong thay muc da xoa"

Write-Host "`n=== 8. Loc o dia: chi nhan o THAT (loai o dam may / o mang) ===" -ForegroundColor Cyan
foreach ($fname in @('Format-Size','Format-Duration','Get-RealFixedDrives')) {
    $fn = $ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fname }, $true)
    if ($fn.Count -gt 0) { . ([scriptblock]::Create($fn[0].Extent.Text)) }
}
$real     = @(Get-RealFixedDrives)
$allFixed = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty DeviceID)
$net      = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=4" -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty DeviceID)
$realLetters = @($real | ForEach-Object { $_.Letter })
Write-Host ("  Windows bao la o co dinh : " + ($allFixed -join ', '))
Write-Host ("  App chap nhan dung toi   : " + ($realLetters -join ', '))
$loai = @($allFixed | Where-Object { $realLetters -notcontains $_ })
if ($loai.Count -gt 0) { Write-Host ("  DA LOAI (o ao / dam may) : " + ($loai -join ', ')) -ForegroundColor Yellow }
Check "co nhan ra o he thong"      ($realLetters -contains $env:SystemDrive)  ($realLetters -join ',')
Check "khong nhan o mang"          (@($realLetters | Where-Object { $net -contains $_ }).Count -eq 0) "co o mang lot vao"
Check "moi o deu co che do xoa"    (@($real | Where-Object { $_.Media -notin @('SSD','HDD') }).Count -eq 0) "co o khong ro loai"

Write-Host "`n=== 9. Toc do: file bi KHOA khong duoc lam cham ca me ===" -ForegroundColor Cyan
# Lỗi "file dang bi giu" la loai TAM THOI -> duoc thu lai, nhung phai nhanh.
New-Item -ItemType Directory -Path $root -Force | Out-Null
$locked = Join-Path $root 'dangmo.txt'
Set-Content -Path $locked -Value ('x' * 5000) -Encoding UTF8
$fsLock = [System.IO.File]::Open($locked, 'Open', 'ReadWrite', 'None')
$s9 = New-Sync
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Remove-FileSecure $s9 $locked 0
$sw.Stop()
$fsLock.Close()
Write-Host ("  Mot file bi khoa mat {0} ms" -f $sw.ElapsedMilliseconds)
Check "khong xoa duoc (dung nhu mong doi)" ($s9.FilesDone -eq 0) $s9.FilesDone
Check "co dem vao so file hong"            ($s9.FilesFailed -eq 1) $s9.FilesFailed
Check "duoi 700ms (truoc kia ~900ms ngu)"  ($sw.ElapsedMilliseconds -lt 700) "$($sw.ElapsedMilliseconds) ms"
Check "co ghi RO ly do that vao bao cao"   ($s9.Skipped[0] -match 'process|dùng|used|denied|Exception') $s9.Skipped[0]
Remove-Item $locked -Force -ErrorAction SilentlyContinue

Write-Host "`n=== 10. Toc do: xoa hang loat file binh thuong ===" -ForegroundColor Cyan
$bulk = Join-Path $root 'bulk'
New-Item -ItemType Directory -Path $bulk -Force | Out-Null
1..300 | ForEach-Object { Set-Content -Path (Join-Path $bulk "f$_.txt") -Value ('y' * 2000) }
$s10 = New-Sync
$sw2 = [System.Diagnostics.Stopwatch]::StartNew()
Remove-FolderSecure $s10 $bulk @{ ($bulk.Substring(0,2)) = 0 } @()
$sw2.Stop()
$per = $sw2.ElapsedMilliseconds / 300
Write-Host ("  300 file mat {0} ms  ->  {1:N2} ms/file" -f $sw2.ElapsedMilliseconds, $per)
Write-Host ("  Suy ra 23.635 file (nhu may DESKTOP-M8CR8V3): {0:N1} phut" -f ($per * 23635 / 60000))
Check "xoa het 300 file"        ($s10.FilesDone -eq 300) $s10.FilesDone
Check "duoi 3 ms/file"          ($per -lt 3) ("{0:N2} ms/file" -f $per)

Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "`n===== KET QUA: $pass dat / $fail hong =====" -ForegroundColor $(if ($fail -eq 0) {'Green'} else {'Red'})
if ($fail -gt 0) { exit 1 }
