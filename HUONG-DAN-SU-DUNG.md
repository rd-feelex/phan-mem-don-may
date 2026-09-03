# Hướng dẫn sử dụng — Reset Machine

Công cụ xóa **vĩnh viễn mọi file** trên máy (ghi đè an toàn, không khôi phục được), **giữ nguyên**: Windows, app đã cài, cấu hình app (AppData), toàn bộ thư mục (chỉ xóa file bên trong).

---

## 1. Chuẩn bị (làm 1 lần)

Mở file `Reset-Machine-GUI.ps1` bằng Notepad, sửa danh sách **giữ lại** — thêm đường dẫn các app/dữ liệu quan trọng KHÔNG được xóa:

```powershell
$KeepPaths = @(
    'C:\eBHXH-Tokhai',
    'C:\Saodulieu-eBHXH',
    'C:\WiseEye',
    'D:\MERGE'
)
```

Rồi build lại `.exe`:
```powershell
powershell -ExecutionPolicy Bypass -File build.ps1 -Mode gui
```

> Nếu không muốn build lại, có thể bỏ tick thủ công trong bảng lúc chạy (bước 3).

---

## 2. Chạy app

Bấm phải **`Reset-Machine-GUI.exe`** → **Run as administrator** → bấm **Yes** ở cửa sổ UAC.

*(SmartScreen cảnh báo thì bấm "More info" → "Run anyway".)*

---

## 3. Các bước trên giao diện

| Bước | Thao tác |
|---|---|
| 1 | Bấm **"1. Quét (xem sẽ xóa gì)"** → hiện bảng: mỗi dòng 1 mục, kèm **số file + dung lượng** |
| 2 | **Bỏ tick** những mục muốn giữ (app portable, dữ liệu cần giữ...) |
| 3 | Bấm nút đỏ **"2. XÓA VĨNH VIỄN"** |
| 4 | Gõ đúng chữ **`ERASE`** rồi bấm OK → app bắt đầu xóa |
| 5 | Chờ chạy xong (có thanh tiến trình + log). Nếu báo cần khởi động lại → **restart máy** để xóa nốt file bị khóa |

---

## 4. Tùy chọn trên giao diện

- **Wipe free space** (mặc định bật): ghi đè vùng trống để SSD cũng không khôi phục được. Chậm hơn — tắt nếu muốn nhanh.
- **Xóa cả ổ local khác**: bật nếu muốn xóa cả file trên ổ D:, E:...
- **Tắt app đang chạy + xóa file khóa khi khởi động lại** (mặc định bật): tự tắt app để xóa được file đang chạy.
- **Số lần ghi đè**: 1 là đủ. Tăng lên nếu muốn chắc hơn (chậm hơn).

---

## 5. Kết quả

- ✅ Mọi **file** cá nhân bị xóa vĩnh viễn (không khôi phục được)
- ✅ Mọi **thư mục** vẫn còn (rỗng) — không lỗi Windows
- ✅ App đã cài + cấu hình + mục trong `$KeepPaths` được giữ nguyên

---

## Lưu ý quan trọng

- ⚠️ **Không thể hoàn tác.** Luôn bấm **Quét** và xem kỹ bảng trước khi xóa.
- ⚠️ App/dữ liệu cần giữ → cho vào `$KeepPaths` hoặc bỏ tick.
- ⚠️ **Test trên máy ảo trước**, đừng chạy thẳng trên máy có dữ liệu thật.
- 🔒 Mức không-khôi-phục: **HDD tuyệt đối**; **SSD** an toàn với phần mềm recovery thường (đủ cho bàn giao/bán máy).
