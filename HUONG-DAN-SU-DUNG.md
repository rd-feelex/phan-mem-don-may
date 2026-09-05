# Hướng dẫn sử dụng — Reset Machine

Công cụ xóa **vĩnh viễn mọi file** trên máy (không khôi phục được), **giữ nguyên**: Windows, app đã cài, cấu hình app (AppData), và toàn bộ khung thư mục (chỉ xóa file bên trong).

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
powershell -ExecutionPolicy Bypass -File build.ps1
```

> Nếu không muốn build lại, có thể bỏ tick thủ công trong bảng lúc chạy (bước 3).

---

## 2. Chạy app

Bấm phải **`Reset-Machine-GUI.exe`** → **Run as administrator** → bấm **Yes** ở cửa sổ UAC.

*(SmartScreen cảnh báo thì bấm "More info" → "Run anyway".)*

Ngay khi mở, app tự dò ổ đĩa và hiện chế độ xóa sẽ dùng cho từng ổ, kèm ước tính thời gian. Không cần chọn gì thêm.

---

## 3. Các bước trên giao diện

| Bước | Thao tác |
|---|---|
| 1 | Bấm **"1. Quét (xem sẽ xóa gì)"** → hiện **cây thư mục**, mỗi dòng kèm **số file + dung lượng + ngày sửa gần nhất** |
| 2 | **Bỏ tick** những mục muốn giữ (app portable, dữ liệu cần giữ...) |
| 3 | Bấm nút đỏ **"2. XÓA VĨNH VIỄN"** (hoặc đặt giờ rồi bấm **"Hẹn giờ xóa"** — xem mục 5) |
| 4 | Xem lại **danh sách chi tiết** hiện ra, gõ đúng chữ **`ERASE`** rồi bấm nút đỏ |
| 5 | Chờ chạy xong. Nếu báo có file bị khóa → **khởi động lại máy rồi chạy lại app** (xem cảnh báo ở mục 6) |

### Chọn tới từng file

Mặc định mọi thứ đều được tick. Bấm **dấu +** để bung thư mục ra và bỏ tick riêng từng file bên trong — không phải giữ/xóa cả thư mục như trước.

Ô tick có **3 trạng thái**:

| Ô tick | Nghĩa |
|---|---|
| ☑ tick đầy | Xóa toàn bộ nhánh này |
| ☐ trống | Giữ lại toàn bộ nhánh này |
| ▪ **ô vuông mờ** | Trong nhánh này **có thứ đã bỏ tick** |

Ô vuông mờ là thứ quan trọng nhất: kể cả khi bạn đã thu cây lại, nhìn một cái là biết ngay nhánh nào có ngoại lệ, không phải bung ra kiểm tra lại từng cấp.

### Các nút hỗ trợ

- **Chọn tất cả / Bỏ chọn tất cả** — thao tác nhanh khi chỉ cần giữ lại vài mục (bấm *Bỏ chọn tất cả* rồi tick lại đúng thứ cần xóa).
- **Chuột phải vào một dòng** → *Chọn cả nhánh này* / *Bỏ chọn cả nhánh này* / *Bung hết nhánh này*.
- **Ô Lọc** — gõ để tìm nhanh trong các mục đang mở; bấm vào kết quả thì cây tự nhảy tới đúng chỗ.
- **Thanh đường dẫn** dưới cây luôn hiện đường dẫn đầy đủ của dòng đang đứng.
- Các mục **tự sắp theo dung lượng giảm dần**, mục to nhất nằm trên cùng.

---

## 4. Tùy chọn trên giao diện

- **Xóa cả ổ local khác**: bật nếu muốn xóa cả file trên ổ D:, E:...
- **Tắt app đang chạy** (mặc định bật): tự tắt Outlook, OneDrive, Chrome... để xóa được file chúng đang giữ.
- **Xóa nhanh** (mặc định tắt): bỏ qua bước wipe vùng trống — thứ chạy hàng giờ. Xong trong vài phút, nhưng trên ổ SSD thì **mức an toàn giảm**: chặn được phần mềm recovery thông thường chứ không tuyệt đối. Chỉ dùng khi dọn máy nội bộ, **đừng dùng khi bàn giao máy ra ngoài**.

Chế độ ghi đè **không còn chọn tay** — app tự quyết theo loại ổ:

| Ổ | App làm gì | Mất bao lâu |
|---|---|---|
| **SSD / NVMe** | Xóa file rồi wipe toàn bộ vùng trống | Vài giờ (tùy dung lượng trống) |
| **HDD** | Ghi đè từng file 1 lần | Vài phút |

---

## 5. Hẹn giờ chạy ngoài giờ làm việc

Với máy SSD, phần wipe vùng trống chạy khá lâu và chiếm ổ đĩa. Cách chạy qua đêm:

1. Quét và bỏ tick như bình thường
2. Đặt giờ ở ô bên cạnh (mặc định **22:00**)
3. Bấm **"Hẹn giờ xóa"** → gõ `ERASE` xác nhận **ngay lúc này**
4. **Để nguyên máy bật và app mở** rồi ra về

App tự chặn máy ngủ và chạy đúng giờ đã hẹn. Màn hình vẫn tắt bình thường. Muốn hủy thì bấm **"Hủy hẹn giờ"**.

> Đóng app sẽ hủy lịch hẹn — app sẽ hỏi lại trước khi đóng.

Trong lúc chạy, app hạ ưu tiên xuống mức thấp nhất nên máy vẫn dùng được, chỉ hơi chậm khi thao tác nhiều với ổ đĩa.

---

## 6. Kết quả

- ✅ Mọi **file** cá nhân bị xóa vĩnh viễn
- ✅ Mọi **thư mục** vẫn còn (rỗng) — không lỗi Windows
- ✅ App đã cài + cấu hình + mục trong `$KeepPaths` được giữ nguyên
- ✅ Ổ đám mây (Google Drive...) và ổ mạng **không bị đụng tới**

Log và báo cáo bàn giao nằm ở **`C:\ProgramData\ResetMachine\`**. File `bao-cao-ban-giao-*.txt` dùng để kẹp hồ sơ bàn giao máy.

> ⚠️ **Về file bị khóa:** nếu có app nào vẫn giữ file khi xóa, file đó được hoãn tới lần khởi động lại. Cơ chế này của Windows chỉ **xóa thường, không ghi đè** — file đó **vẫn khôi phục được**. Báo cáo bàn giao liệt kê rõ từng file. Khởi động lại máy rồi **chạy lại app** để xử lý dứt điểm.

---

## Lưu ý quan trọng

- ⚠️ **Không thể hoàn tác.** Luôn bấm **Quét** và xem kỹ bảng trước khi xóa.
- ⚠️ App/dữ liệu cần giữ → cho vào `$KeepPaths` hoặc bỏ tick.
- ⚠️ **Test trên máy ảo trước**, đừng chạy thẳng trên máy có dữ liệu thật.
- 🔒 Mức không-khôi-phục: **HDD tuyệt đối**. **SSD** cũng tuyệt đối khi wipe vùng trống chạy xong — đừng hủy giữa chừng ở giai đoạn này.
