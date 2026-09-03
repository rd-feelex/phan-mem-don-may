<#
 build.ps1 - Dong goi Reset-Machine.ps1 thanh Reset-Machine.exe
 Dung module ps2exe. Tu dong cai neu chua co.
 Chay: powershell -ExecutionPolicy Bypass -File build.ps1
#>

param(
    # 'gui' (mac dinh) hoac 'cli' hoac 'both'
    [ValidateSet('gui','cli','both')]
    [string]$Mode = 'gui'
)

$ErrorActionPreference = 'Stop'
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcCli  = Join-Path $here 'Reset-Machine.ps1'
$srcGui  = Join-Path $here 'Reset-Machine-GUI.ps1'
$outCli  = Join-Path $here 'Reset-Machine.exe'
$outGui  = Join-Path $here 'Reset-Machine-GUI.exe'

# Cai ps2exe neu chua co
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Dang cai module ps2exe..." -ForegroundColor Yellow
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
    } catch {
        Write-Host "Khong cai duoc tu PSGallery. Thu: Install-Module ps2exe -Scope CurrentUser" -ForegroundColor Red
        throw
    }
}
Import-Module ps2exe -ErrorAction Stop

if ($Mode -eq 'gui' -or $Mode -eq 'both') {
    if (-not (Test-Path $srcGui)) { throw "Khong tim thay $srcGui" }
    Write-Host "Dang build GUI -> $outGui" -ForegroundColor Cyan
    Invoke-ps2exe `
        -inputFile   $srcGui `
        -outputFile  $outGui `
        -requireAdmin `
        -noConsole `
        -title       'Reset Machine' `
        -description 'Xoa vinh vien du lieu ca nhan, giu lai ung dung (GUI)' `
        -company     'ozovn' `
        -version     '1.0.0'
    if (Test-Path $outGui) { Write-Host "BUILD OK: $outGui" -ForegroundColor Green }
    else { throw "Build GUI that bai." }
}

if ($Mode -eq 'cli' -or $Mode -eq 'both') {
    if (-not (Test-Path $srcCli)) { throw "Khong tim thay $srcCli" }
    Write-Host "Dang build CLI -> $outCli" -ForegroundColor Cyan
    Invoke-ps2exe `
        -inputFile   $srcCli `
        -outputFile  $outCli `
        -requireAdmin `
        -title       'Reset Machine (CLI)' `
        -description 'Xoa vinh vien du lieu ca nhan, giu lai ung dung' `
        -company     'ozovn' `
        -version     '1.0.0'
    if (Test-Path $outCli) { Write-Host "BUILD OK: $outCli" -ForegroundColor Green }
    else { throw "Build CLI that bai." }
}

Write-Host ""
Write-Host "Xong. Chay Reset-Machine-GUI.exe (bam phai -> Run as administrator neu can)." -ForegroundColor Cyan
