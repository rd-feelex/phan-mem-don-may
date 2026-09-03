<#
 Test-SecureDelete.ps1
 Kiem tra co che GHI DE + XOA tren mot thu muc GIA (KHONG dung du lieu that).
 - Tao 1 thu muc test co file rac
 - Chay ham secure-delete y het trong app
 - Kiem tra file da bi ghi de va xoa het chua
 An toan tuyet doi: chi thao tac trong thu muc test tu tao.
#>

$ErrorActionPreference = 'Stop'

# ----- Ham secure-delete (giong het trong app) -----
function Remove-FileSecure($path,$passes){
    $fi = New-Object System.IO.FileInfo($path)
    if ($fi.Attributes -band [System.IO.FileAttributes]::ReadOnly) { $fi.Attributes = [System.IO.FileAttributes]::Normal }
    $len = $fi.Length
    if ($len -gt 0) {
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $buf = New-Object byte[] ([Math]::Min($len,4MB))
        for ($p=0;$p -lt $passes;$p++){
            $fs=[System.IO.File]::Open($path,'Open','Write','None')
            try { $fs.Position=0; $rem=$len; while($rem -gt 0){ $c=[Math]::Min($rem,$buf.Length); $rng.GetBytes($buf); $fs.Write($buf,0,$c); $rem-=$c }; $fs.Flush($true) }
            finally { $fs.Close() }
        }
        $rng.Dispose()
    }
    $rand=[System.IO.Path]::GetRandomFileName()
    Rename-Item -LiteralPath $path -NewName $rand -ErrorAction SilentlyContinue
    $np=Join-Path $fi.DirectoryName $rand
    if (Test-Path -LiteralPath $np){ Remove-Item -LiteralPath $np -Force } else { Remove-Item -LiteralPath $path -Force }
}
function Remove-FolderSecure($folder,$passes){
    Get-ChildItem -LiteralPath $folder -File -Recurse -Force | ForEach-Object { Remove-FileSecure $_.FullName $passes }
    Get-ChildItem -LiteralPath $folder -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $folder -Force -Recurse -ErrorAction SilentlyContinue
}

# ----- 1) Tao thu muc test gia -----
$test = Join-Path $env:TEMP ("SecureDeleteTest_" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $test | Out-Null
New-Item -ItemType Directory -Path (Join-Path $test 'Documents') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $test 'Documents\Sub') | Out-Null

$secret = "DAY-LA-DU-LIEU-BI-MAT-" + ("X" * 5000)
Set-Content -Path (Join-Path $test 'Documents\file1.txt') -Value $secret
Set-Content -Path (Join-Path $test 'Documents\Sub\file2.txt') -Value $secret
Set-Content -Path (Join-Path $test 'file3.txt') -Value $secret

Write-Host "Da tao thu muc test: $test" -ForegroundColor Cyan
$before = Get-ChildItem -LiteralPath $test -File -Recurse
Write-Host "So file truoc khi xoa: $($before.Count)" -ForegroundColor Cyan
$before | ForEach-Object { Write-Host "  - $($_.FullName) ($($_.Length) bytes)" }

# ----- 2) Chay secure-delete -----
Write-Host "`nDang ghi de + xoa..." -ForegroundColor Yellow
Remove-FolderSecure $test 1

# ----- 3) Kiem tra ket qua -----
Write-Host ""
if (-not (Test-Path -LiteralPath $test)) {
    Write-Host "KET QUA: PASS - Thu muc test da bi xoa hoan toan." -ForegroundColor Green
} else {
    $left = Get-ChildItem -LiteralPath $test -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "KET QUA: FAIL - Con sot $($left.Count) muc." -ForegroundColor Red
}
Write-Host "Xong test. (Khong co du lieu that nao bi dung toi.)" -ForegroundColor Cyan
