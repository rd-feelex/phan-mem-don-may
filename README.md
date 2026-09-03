# Reset-Machine — Xóa vĩnh viễn dữ liệu, giữ lại ứng dụng

App chạy trên Windows để **reset máy bàn giao/tái sử dụng**: xóa **vĩnh viễn** (secure overwrite, không khôi phục được) dữ liệu cá nhân của người dùng, nhưng **giữ nguyên**:

- Ứng dụng đã cài (`Program Files`, `Program Files (x86)`, `ProgramData`)
- Cấu hình / data của app (`AppData`: Roaming, Local, LocalLow)
- Windows & hệ thống

**Không đụng tới**: ổ mạng (network drive) và ổ di động.

## Những gì bị xóa

Trong mỗi profile người dùng (`C:\Users\<tên>`): `Desktop, Documents, Downloads, Pictures, Music, Videos, Favorites, Contacts, Links, Searches, Saved Games, 3D Objects, OneDrive` — cộng Recycle Bin.

Sau đó: xóa **Volume Shadow Copies**, tắt **System Restore**, và (mặc định) **wipe free space** (`cipher /w`) để dữ liệu không thể khôi phục kể cả trên SSD.

## Giao diện (GUI) — khuyến nghị

`Reset-Machine-GUI.ps1` là bản có giao diện:

1. Bấm **"1. Quét (xem sẽ xóa gì)"** → hiện bảng danh sách các mục sẽ bị xóa kèm **số file + dung lượng**
2. **Bỏ tick** những mục muốn giữ lại (mặc định tick hết)
3. Bấm **"2. XÓA VĨNH VIỄN"** → gõ xác nhận `ERASE` → xóa (có thanh tiến trình + log + nút Hủy)

Tùy chọn ngay trên giao diện: *Wipe free space*, *Xóa cả ổ local khác*, *Số lần ghi đè*.

Chạy thử nhanh (không cần build): bấm phải `Reset-Machine-GUI.ps1` → *Run with PowerShell* (app tự xin quyền Admin), hoặc:
```powershell
powershell -ExecutionPolicy Bypass -File Reset-Machine-GUI.ps1
```

## Build ra file .exe

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1            # build bản GUI (mặc định)
powershell -ExecutionPolicy Bypass -File build.ps1 -Mode cli  # build bản dòng lệnh
powershell -ExecutionPolicy Bypass -File build.ps1 -Mode both # build cả hai
```

Tạo `Reset-Machine-GUI.exe` (và/hoặc `Reset-Machine.exe`). Cả hai tự yêu cầu quyền Admin khi chạy.

Bản dòng lệnh (không giao diện):

## Cách dùng

```powershell
# 1) LUÔN chạy thử trước — chỉ liệt kê, KHÔNG xóa gì:
Reset-Machine.exe -DryRun

# 2) Chạy thật (hỏi xác nhận, phải gõ "ERASE"):
Reset-Machine.exe

# 3) Chạy thật không hỏi (dùng khi tự động hóa):
Reset-Machine.exe -Force

# Tùy chọn thêm:
Reset-Machine.exe -Passes 3                 # ghi đè 3 lần (chậm hơn)
Reset-Machine.exe -WipeFreeSpace $false     # tắt wipe free space (nhanh, kém an toàn hơn trên SSD)
Reset-Machine.exe -WipeOtherLocalDrives     # xóa cả ổ local khác (D:, E:...) ngoài ổ hệ thống
```

## Mức độ không khôi phục

| Ổ | Ghi đè file (mặc định) | + Wipe free space (mặc định bật) |
|---|---|---|
| HDD | Không khôi phục được | Không khôi phục được |
| SSD/NVMe | An toàn với phần mềm recovery thường; lab forensic có thể sót | Không khôi phục được |

> ⚠️ **CẢNH BÁO:** Thao tác này **không thể hoàn tác**. Luôn chạy `-DryRun` trước và kiểm tra kỹ danh sách folder trong `Reset-Machine.ps1` (biến `$UserDataFolders`) trước khi build/chạy thật.

## Tùy chỉnh

Mở `Reset-Machine.ps1`, sửa:
- `$UserDataFolders` — thêm/bớt thư mục cần xóa (ví dụ bỏ `OneDrive` nếu muốn giữ)
- `$ProtectedRoots` — đường dẫn không bao giờ bị xóa
- `$SkipProfiles` — profile bỏ qua
