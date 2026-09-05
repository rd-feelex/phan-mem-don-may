# Reset-Machine — Xóa vĩnh viễn dữ liệu, giữ lại ứng dụng

App chạy trên Windows để **reset máy bàn giao/tái sử dụng**: xóa **vĩnh viễn** (không khôi phục được) dữ liệu cá nhân của người dùng, nhưng **giữ nguyên**:

- Ứng dụng đã cài (`Program Files`, `Program Files (x86)`, `ProgramData`)
- Cấu hình / data của app (`AppData`: Roaming, Local, LocalLow)
- Windows & hệ thống
- **Khung thư mục** — app chỉ xóa **file** bên trong, thư mục vẫn còn (rỗng) nên Windows không lỗi

**Không đụng tới**: ổ mạng, ổ di động, và **ổ đám mây** (Google Drive, Dropbox... — những ổ này Windows báo là ổ cứng cố định nên phải lọc riêng, xem mục *An toàn ổ đĩa*).

## Những gì bị xóa

Toàn bộ nội dung trong mỗi profile người dùng (`C:\Users\<tên>`) **trừ** `AppData` và file hệ thống, cộng các thư mục tự tạo ở gốc ổ hệ thống, cộng Recycle Bin. Tùy chọn thêm ổ local khác (D:, E:...).

Sau đó: xóa **Volume Shadow Copies** và tắt **System Restore**.

## Chế độ xóa — máy tự quyết theo loại ổ

App tự dò từng ổ là SSD hay HDD rồi áp chiến lược riêng. **Không còn ô "số lần ghi đè"** để chọn tay.

| Loại ổ | Ghi đè từng file | Wipe vùng trống | Vì sao |
|---|---|---|---|
| **SSD / NVMe** | 0 lần | **Có** (`cipher /w`) | Wear-leveling khiến ghi đè từng file không chạm ô nhớ vật lý cũ — bản gốc vẫn nằm đó. Chỉ lấp đầy vùng trống mới ép SSD ghi đè thật |
| **HDD** | 1 lần | Không | Ghi đè đè đúng vị trí vật lý, xong trong vài phút; wipe vùng trống trở thành thừa |

Máy có cả hai loại ổ thì mỗi ổ dùng chế độ của nó. Giao diện hiện rõ ổ nào dùng cách nào kèm ước tính thời gian.

> Cấu hình cũ (ghi đè 1 lần **rồi** wipe vùng trống) ghi đè cùng một vùng dữ liệu tới 4 lượt — chậm gấp đôi mà không an toàn hơn.

**Wipe vùng trống chỉ chạy trên ổ thực sự có file bị xóa** — không đụng tới ổ không liên quan.

## An toàn ổ đĩa

App chỉ đụng tới ổ **map được sang đĩa vật lý**. Đây là bộ lọc quan trọng: Google Drive for Desktop mount thành ổ `G:` mà Windows báo `DriveType=3` — **giống hệt ổ cứng thật**. Nếu không lọc, app sẽ xóa sạch dữ liệu đám mây rồi đồng bộ ngược lên cloud.

Ổ ảo/đám mây không có `MSFT_Partition` nên bị loại ngay, và giao diện ghi rõ ổ nào bị bỏ qua.

## Cách dùng

1. Bấm phải `Reset-Machine-GUI.exe` → **Run as administrator**
2. Bấm **"1. Quét (xem sẽ xóa gì)"** → hiện **cây thư mục** kèm số file, dung lượng và ngày sửa gần nhất
3. **Bỏ tick** những mục muốn giữ lại (mặc định tick hết). Bấm dấu **+** để bung thư mục và chọn tới **từng file**
4. Bấm **"2. XÓA VĨNH VIỄN"** → xem lại danh sách chi tiết → gõ xác nhận `ERASE` → xóa

### Cây chọn

Ô tick có 3 trạng thái: **tick đầy** = xóa cả nhánh, **trống** = giữ cả nhánh, **ô vuông mờ** = trong nhánh có thứ đã bỏ tick. Nhờ trạng thái mờ mà thu cây lại vẫn nhìn ra ngay nhánh nào có ngoại lệ.

Kèm theo: nút **Chọn / Bỏ chọn tất cả**, menu chuột phải để thao tác cả nhánh, **ô lọc** tìm nhanh, **thanh đường dẫn** đầy đủ, và các mục **tự sắp theo dung lượng giảm dần**.

Cây **nạp lười** — bung tới đâu quét tới đó — nên lần quét đầu vẫn nhanh dù máy nhiều dữ liệu.

Chạy thử nhanh không cần build: bấm phải `Reset-Machine-GUI.ps1` → *Run with PowerShell* (app tự xin quyền Admin), hoặc:
```powershell
powershell -ExecutionPolicy Bypass -File Reset-Machine-GUI.ps1
```

### Hẹn giờ chạy ngoài giờ làm việc

Wipe vùng trống trên SSD có thể mất vài giờ. Chọn xong các mục, đặt giờ rồi bấm **"Hẹn giờ xóa"** và gõ `ERASE` ngay lúc đó. **Để nguyên máy bật và app mở** rồi ra về — app tự chặn máy ngủ và chạy đúng giờ đã hẹn (màn hình vẫn tắt bình thường).

Trong lúc chạy, app hạ ưu tiên I/O xuống mức thấp nhất để không tranh ổ đĩa với công việc khác.

## Log và báo cáo bàn giao

Mỗi lần chạy ghi 2 file vào `C:\ProgramData\ResetMachine\`:

- `reset-<máy>-<thời gian>.log` — log chi tiết, ghi thẳng xuống đĩa từng dòng nên **mất điện vẫn còn**
- `bao-cao-ban-giao-<máy>-<thời gian>.txt` — tóm tắt để kẹp hồ sơ: máy nào, ai chạy, mỗi ổ dùng chế độ gì, tổng dung lượng đã xóa, và **danh sách file chưa xóa an toàn**

> File đang bị app khác khóa sẽ được hoãn tới lần khởi động lại. Cơ chế này của Windows chỉ **xóa thường, không ghi đè** — file đó **vẫn khôi phục được**. Báo cáo liệt kê rõ để xử lý dứt điểm: khởi động lại máy rồi chạy lại app.

## Build ra file .exe

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
```

Tạo `Reset-Machine-GUI.exe`, tự yêu cầu quyền Admin khi chạy.

## Tùy chỉnh

Mở `Reset-Machine-GUI.ps1`, sửa:
- `$KeepPaths` — đường dẫn **không bao giờ** bị xóa (dữ liệu kế toán, app portable...)
- `$SkipProfiles` — profile bỏ qua
- `$KillProcessNames` — app cần tắt trước khi xóa để không khóa file (Outlook, OneDrive, Chrome...)
- `$LogDir` — nơi ghi log và báo cáo

> ⚠️ **Khi sửa file `.ps1` phải lưu lại bằng UTF-8 CÓ BOM.** PowerShell 5.1 đọc file không BOM theo bảng mã ANSI nên toàn bộ chữ tiếng Việt có dấu sẽ vỡ. Trong Notepad: *Save As* → Encoding chọn **UTF-8 with BOM**. Trong VS Code: góc dưới phải chọn **UTF-8 with BOM**.

> ⚠️ **CẢNH BÁO:** Thao tác này **không thể hoàn tác**. Luôn bấm **Quét** và xem kỹ bảng trước khi xóa, và test trên máy ảo trước.
