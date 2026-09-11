# -*- coding: utf-8 -*-
"""Sinh PDF hướng dẫn nhanh 2 trang cho nhân sự - mỗi bước một ảnh minh họa.

Ảnh lấy từ thư mục anh-hdsd/ (chụp màn hình thật của app).
Chạy: python tao-hdsd-pdf.py
"""
import os

from reportlab.lib.pagesizes import A4
from reportlab.lib.colors import HexColor, white
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

FD = "C:/Windows/Fonts/"
pdfmetrics.registerFont(TTFont("SG", FD + "segoeui.ttf"))
pdfmetrics.registerFont(TTFont("SGB", FD + "segoeuib.ttf"))
pdfmetrics.registerFont(TTFont("SGI", FD + "segoeuii.ttf"))

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.join(HERE, "anh-hdsd")

W, H = A4
M = 40                  # lề trái/phải
CW = W - 2 * M          # bề ngang vùng nội dung

DARK = HexColor("#1F2937")
BODY = HexColor("#3F4652")
RED = HexColor("#C22B2B")
REDBG = HexColor("#FDECEC")
AMBER = HexColor("#B45309")
AMBBG = HexColor("#FEF6E7")
BLUE = HexColor("#1D4ED8")
GREY = HexColor("#6B7280")
LINE = HexColor("#D6D9DE")
SOFT = HexColor("#F4F5F7")

c = canvas.Canvas(os.path.join(HERE, "HDSD-Reset-Machine.pdf"), pagesize=A4)
c.setTitle("Hướng dẫn nhanh - Reset Machine")
c.setAuthor("ozovn")


# ---------------------------------------------------------------- tiện ích vẽ
def txt(x, y, s, font="SG", size=9.5, color=BODY):
    c.setFont(font, size)
    c.setFillColor(color)
    c.drawString(x, y, s)


def wrap(s, font, size, maxw):
    lines, cur = [], ""
    for w in s.split(" "):
        t = w if not cur else cur + " " + w
        if pdfmetrics.stringWidth(t, font, size) <= maxw:
            cur = t
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def para(x, y, s, maxw, font="SG", size=9.5, color=BODY, lead=13):
    for ln in wrap(s, font, size, maxw):
        txt(x, y, ln, font, size, color)
        y -= lead
    return y


def step_head(y, num, title):
    """Vẽ số bước trong ô vuông xanh + tiêu đề. Trả về y của dòng kế tiếp."""
    s = 19
    c.setFillColor(BLUE)
    c.roundRect(M, y - s + 4, s, s, 3, stroke=0, fill=1)
    c.setFillColor(white)
    c.setFont("SGB", 11.5)
    c.drawCentredString(M + s / 2.0, y - s + 9.5, str(num))
    txt(M + s + 9, y - 9, title, "SGB", 12.5, DARK)
    return y - s - 3


def image(y, name, max_w, max_h, caption=None):
    """Chèn ảnh, giữ tỷ lệ, căn giữa theo bề ngang trang."""
    path = os.path.join(IMG, name)
    if not os.path.exists(path):
        txt(M, y - 12, "[thiếu ảnh: %s]" % name, "SGI", 8.5, GREY)
        return y - 20
    img = ImageReader(path)
    iw, ih = img.getSize()
    sc = min(max_w / float(iw), max_h / float(ih))
    w, h = iw * sc, ih * sc
    x = M + (CW - w) / 2.0
    c.drawImage(img, x, y - h, w, h, mask="auto")
    c.setStrokeColor(LINE)
    c.setLineWidth(0.7)
    c.rect(x, y - h, w, h, stroke=1, fill=0)
    y = y - h - 10
    if caption:
        c.setFont("SGI", 8)
        c.setFillColor(GREY)
        c.drawCentredString(W / 2.0, y, caption)
        y -= 10
    return y


def note(y, text, bg, bar, color, pad=7):
    """Hộp ghi chú một khối, tự tính chiều cao."""
    lines = wrap(text, "SG", 9, CW - 2 * pad - 8)
    h = len(lines) * 12 + 2 * pad
    c.setFillColor(bg)
    c.rect(M, y - h, CW, h, stroke=0, fill=1)
    c.setStrokeColor(LINE)
    c.setLineWidth(0.7)
    c.rect(M, y - h, CW, h, stroke=1, fill=0)
    c.setFillColor(bar)
    c.rect(M, y - h, 4, h, stroke=0, fill=1)
    yy = y - pad - 9
    for ln in lines:
        txt(M + pad + 6, yy, ln, "SG", 9, color)
        yy -= 12
    return y - h - 12


def footer(page):
    c.setFillColor(GREY)
    c.setFont("SG", 7.5)
    c.drawString(M, 26, "Reset Machine v1.2 — ozovn — Bộ phận IT (88-IT)")
    c.drawRightString(W - M, 26, "Trang %d/2" % page)


# ================================================================== TRANG 1
y = H - M

c.setFillColor(DARK)
c.setFont("SGB", 19)
c.drawString(M, y - 16, "Hướng dẫn dọn máy — Reset Machine")
y -= 26
y = para(M, y - 8, "App xóa vĩnh viễn mọi file cá nhân trên máy, giữ nguyên Windows và các "
                   "ứng dụng đã cài. Làm theo 5 bước dưới đây.", CW, "SG", 10, BODY, 14)
y -= 4

y = note(y, "KHÔNG HOÀN TÁC ĐƯỢC. File đã xóa không có cách nào lấy lại — kể cả phần mềm "
            "cứu dữ liệu. Xem kỹ danh sách trước khi bấm nút đỏ.", REDBG, RED, RED)

# ---- Bước 1 --------------------------------------------------------------
y = step_head(y, 1, "Lấy app từ ổ NAS")
y = para(M, y - 4, "Mở File Explorer, gõ đường dẫn này vào thanh địa chỉ rồi Enter:", CW)
c.setFillColor(SOFT)
c.rect(M, y - 17, CW, 17, stroke=0, fill=1)
txt(M + 7, y - 13, r"\\192.168.1.13\ozovn-public\Du lieu hien hanh\88-IT\Phần mềm dọn máy",
    "SGB", 9.5, DARK)
y -= 26
y = para(M, y, "Copy file Reset-Machine-GUI.exe ra Màn hình nền (Desktop) của máy cần dọn.", CW)
y = image(y - 4, "01-nas.png", CW, 155,
          caption="Thư mục trên NAS — chỉ cần lấy file Reset-Machine-GUI.exe")

# ---- Bước 2 --------------------------------------------------------------
y = step_head(y - 6, 2, "Chạy app bằng quyền Administrator")
y = para(M, y - 4, "Trên Desktop, bấm chuột phải vào Reset-Machine-GUI.exe → chọn "
                   "\"Run as administrator\" → bấm Yes.", CW)
y = para(M, y, "Nếu Windows báo \"Windows protected your PC\": bấm \"More info\" → \"Run anyway\". "
               "Đây là cảnh báo mặc định cho file .exe nội bộ, không phải virus.", CW)
y = image(y - 4, "03-giao-dien.png", CW, 290,
          caption="Giao diện ngay khi mở — app tự nhận loại ổ đĩa, không cần chọn gì thêm")
y -= 2
y = note(y, "App không tự xóa chính nó — file .exe trên Desktop luôn được giữ lại.",
         SOFT, BLUE, BODY)

footer(1)
c.showPage()

# ================================================================== TRANG 2
y = H - M

# ---- Bước 3 --------------------------------------------------------------
y = step_head(y, 3, "Bấm Quét để xem sẽ xóa gì")
y = para(M, y - 4, "Bấm nút \"1. Quét (xem sẽ xóa gì)\". App liệt kê cây thư mục kèm số file và "
                   "dung lượng. Bỏ tick những gì cần giữ lại.", CW)
y = image(y - 4, "04-quet.png", CW, 235,
          caption="Bấm dấu + để bung thư mục ra và bỏ tick từng file bên trong")
y -= 2
y = para(M, y, "Ô tick có 3 trạng thái:   tick đầy = xóa cả nhánh   ·   ô trống = giữ cả nhánh   ·   "
               "ô vuông mờ = bên trong có thứ đã bỏ tick.", CW, "SG", 9)

# ---- Bước 4 --------------------------------------------------------------
y = step_head(y - 8, 4, "Bấm nút đỏ và gõ OK để xác nhận")
y = para(M, y - 4, "Bấm \"2. XÓA VĨNH VIỄN\". App hiện lại danh sách chi tiết lần cuối. "
                   "Gõ đúng chữ OK (in hoa) rồi bấm nút đỏ.", CW)
y = image(y - 4, "05-xac-nhan.png", CW, 185,
          caption="Gõ OK thì nút xóa mới sáng lên")
y -= 2
y = note(y, "Máy dùng ổ SSD chạy vài giờ. Muốn chạy qua đêm: đặt giờ ở ô \"Hẹn giờ chạy\" "
            "(mặc định 22:00), bấm \"Hẹn giờ xóa\", gõ OK ngay lúc đó, rồi để nguyên máy bật "
            "và app mở rồi ra về.", AMBBG, AMBER, BODY)

# ---- Bước 5 --------------------------------------------------------------
y = step_head(y - 2, 5, "Xong — lấy báo cáo bàn giao")
y = para(M, y - 4, "Báo cáo và log nằm ở thư mục  C:\\ProgramData\\ResetMachine\\  — file "
                   "bao-cao-ban-giao-*.txt dùng để kẹp hồ sơ bàn giao máy.", CW)
y = para(M, y, "Nếu app báo có file đang bị khóa: khởi động lại máy rồi chạy lại app "
               "một lần nữa cho dứt điểm.", CW)

y -= 6
y = note(y, "3 điều đừng quên:   (1) Đã xóa là mất hẳn, xem kỹ trước khi bấm.   "
            "(2) Dữ liệu cần giữ thì bỏ tick, hoặc báo IT thêm vào danh sách giữ lại.   "
            "(3) Đừng bật \"Xóa nhanh\" khi bàn giao máy ra ngoài công ty — mức an toàn giảm.",
         REDBG, RED, RED)

txt(M, y - 2, "Vướng mắc: liên hệ bộ phận IT (88-IT).", "SGI", 9, GREY)

footer(2)
c.save()
print("Đã tạo HDSD-Reset-Machine.pdf")
