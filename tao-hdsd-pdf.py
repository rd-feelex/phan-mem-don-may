# -*- coding: utf-8 -*-
"""Sinh PDF huong dan nhanh 1 trang, 2 cot, cho nhan su."""
from reportlab.lib.pagesizes import A4
from reportlab.lib.colors import HexColor, white
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

FD = "C:/Windows/Fonts/"
pdfmetrics.registerFont(TTFont("SG", FD + "segoeui.ttf"))
pdfmetrics.registerFont(TTFont("SGB", FD + "segoeuib.ttf"))
pdfmetrics.registerFont(TTFont("SGI", FD + "segoeuii.ttf"))

W, H = A4
M = 38
GUT = 18
LW = 272                      # cot trai
RW = W - 2 * M - GUT - LW     # cot phai
LX = M
RX = M + LW + GUT

DARK  = HexColor("#1F2937")
BODY  = HexColor("#3F4652")
RED   = HexColor("#C22B2B")
REDBG = HexColor("#FDECEC")
GREEN = HexColor("#166534")
GRNBG = HexColor("#ECFAEF")
AMBER = HexColor("#B45309")
AMBBG = HexColor("#FEF6E7")
BLUE  = HexColor("#1D4ED8")
BLUBG = HexColor("#EFF4FE")
GREY  = HexColor("#6B7280")
LINE  = HexColor("#D6D9DE")
SOFT  = HexColor("#F4F5F7")

c = canvas.Canvas("HDSD-Reset-Machine.pdf", pagesize=A4)
c.setTitle("Huong dan nhanh - Reset Machine")
c.setAuthor("ozovn")


def txt(x, y, s, font="SG", size=9.5, color=BODY):
    c.setFont(font, size)
    c.setFillColor(color)
    c.drawString(x, y, s)


def wrap(s, font, size, maxw):
    words, lines, cur = s.split(" "), [], ""
    for w in words:
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


def para(x, y, s, font, size, color, maxw, lead):
    for ln in wrap(s, font, size, maxw):
        txt(x, y, ln, font, size, color)
        y -= lead
    return y


def box(x, y_top, w, h, bg, bar):
    c.setFillColor(bg)
    c.rect(x, y_top - h, w, h, stroke=0, fill=1)
    c.setStrokeColor(LINE)
    c.setLineWidth(0.8)
    c.rect(x, y_top - h, w, h, stroke=1, fill=0)
    c.setFillColor(bar)
    c.rect(x, y_top - h, 4, h, stroke=0, fill=1)


def heading(x, y, s, w):
    txt(x, y, s, "SGB", 11.5, DARK)
    c.setStrokeColor(DARK)
    c.setLineWidth(1.5)
    tw = pdfmetrics.stringWidth(s, "SGB", 11.5)
    c.line(x, y - 6, x + min(tw, w), y - 6)
    return y - 20


def checkbox(x, y, state, size=12):
    c.setStrokeColor(HexColor("#7A7A7A"))
    c.setLineWidth(1.1)
    c.setFillColor(white)
    c.rect(x, y, size, size, stroke=1, fill=1)
    if state == 1:
        c.setStrokeColor(GREEN)
        c.setLineWidth(1.9)
        c.line(x + 2.5, y + size / 2, x + size * 0.44, y + 2.8)
        c.line(x + size * 0.44, y + 2.8, x + size - 2.2, y + size - 2.4)
    elif state == 2:
        c.setFillColor(HexColor("#8A8A8A"))
        c.rect(x + 3, y + 3, size - 6, size - 6, stroke=0, fill=1)


# ---------------- Tieu de ----------------
c.setFillColor(DARK)
c.rect(0, H - 68, W, 68, stroke=0, fill=1)
txt(M, H - 34, "Xóa dữ liệu máy trước khi bàn giao", "SGB", 18, white)
txt(M, H - 54, "Hướng dẫn nhanh cho nhân sự  ·  Reset-Machine-GUI v1.2",
    "SG", 10, HexColor("#B9C0CC"))

# ---------------- Canh bao do ----------------
yb = H - 68 - 36
c.setFillColor(REDBG)
c.rect(0, yb, W, 36, stroke=0, fill=1)
c.setFillColor(RED)
c.rect(0, yb, 4.5, 36, stroke=0, fill=1)
txt(M, yb + 21, "KHÔNG THỂ HOÀN TÁC — dữ liệu đã xóa là mất hẳn, không cứu lại được.",
    "SGB", 10.5, RED)
txt(M, yb + 8, "Luôn bấm Quét và xem kỹ danh sách trước khi xóa.", "SG", 9.5, RED)

TOP = yb - 22

# =====================================================================
# COT TRAI - 5 buoc
# =====================================================================
y = heading(LX, TOP, "LÀM THEO 5 BƯỚC", LW)

steps = [
    ("Mở app bằng quyền Admin",
     "Chuột phải vào Reset-Machine-GUI.exe → Run as administrator → bấm Yes.",
     "Windows cảnh báo thì: More info → Run anyway."),
    ("Bấm “1. Quét (xem sẽ xóa gì)”",
     "App liệt kê cây thư mục sẽ bị xóa, kèm số file, dung lượng, ngày sửa gần nhất.",
     None),
    ("Bỏ tick những thứ cần GIỮ LẠI",
     "Mặc định mọi thứ đều tick = sẽ bị xóa. Bấm dấu + để bung thư mục, bỏ tick từng file.",
     "Cần giữ nhiều: bấm “Bỏ chọn tất cả” rồi tick lại đúng thứ cần xóa."),
    ("Bấm nút đỏ “2. XÓA VĨNH VIỄN”",
     "App hiện danh sách chi tiết để xem lại lần cuối. Gõ đúng chữ ERASE rồi bấm nút đỏ.",
     None),
    ("Chờ chạy xong",
     "Có thanh tiến trình, máy vẫn dùng được bình thường trong lúc chạy.",
     "App báo còn file bị khóa → khởi động lại máy rồi chạy lại app một lần nữa."),
]

for i, (title, d1, d2) in enumerate(steps, 1):
    c.setFillColor(DARK)
    c.circle(LX + 11, y - 4, 11, stroke=0, fill=1)
    c.setFont("SGB", 11)
    c.setFillColor(white)
    c.drawCentredString(LX + 11, y - 8, str(i))

    tx = LX + 30
    tw = LW - 30
    txt(tx, y - 2, title, "SGB", 10.8, DARK)
    yy = para(tx, y - 16, d1, "SG", 9.3, BODY, tw, 11.5)
    if d2:
        yy = para(tx, yy - 1, d2, "SGI", 8.8, GREY, tw, 10.5)
    y = yy - 15

# --- Khoi GIU LAI vs BI XOA (cuoi cot trai) ---
y = heading(LX, y - 20, "APP GIỮ LẠI GÌ, XÓA GÌ", LW)

bh = 158
box(LX, y + 6, LW, bh, SOFT, GREY)

cy = y - 8
txt(LX + 13, cy, "GIỮ NGUYÊN", "SGB", 9.6, GREEN)
cy -= 15
for s in ["Windows và toàn bộ app đã cài",
          "Cấu hình, dữ liệu của app (AppData)",
          "Khung thư mục — vẫn còn, chỉ rỗng đi",
          "Ổ đám mây (Google Drive) và ổ mạng"]:
    c.setFillColor(GREEN)
    c.circle(LX + 18, cy + 3, 2.4, stroke=0, fill=1)
    txt(LX + 26, cy, s, "SG", 9, BODY)
    cy -= 13

cy -= 6
txt(LX + 13, cy, "BỊ XÓA VĨNH VIỄN", "SGB", 9.6, RED)
cy -= 15
for s in ["File cá nhân của mọi người dùng: Desktop,",
          "Documents, Downloads, Pictures, Videos...",
          "Thùng rác và các bản sao ngầm của Windows"]:
    c.setFillColor(RED)
    c.circle(LX + 18, cy + 3, 2.4, stroke=0, fill=1)
    txt(LX + 26, cy, s, "SG", 9, BODY)
    cy -= 13

# =====================================================================
# COT PHAI
# =====================================================================
ry = heading(RX, TOP, "Ô TICK CÓ 3 TRẠNG THÁI", RW)

bh = 104
box(RX, ry + 6, RW, bh, BLUBG, BLUE)
iy = ry - 8
for state, name, desc, col in [
    (1, "Tick đầy", "Xóa cả nhánh này", GREEN),
    (0, "Ô trống", "Giữ lại cả nhánh này", GREY),
    (2, "Ô vuông mờ", "Trong nhánh CÓ THỨ ĐÃ BỎ TICK", AMBER),
]:
    checkbox(RX + 14, iy - 3, state)
    txt(RX + 33, iy, name, "SGB", 9.4, col)
    txt(RX + 96, iy, desc, "SG", 9.2, BODY)
    iy -= 18
para(RX + 14, iy - 2,
     "Thu cây lại vẫn nhìn ra ngay nhánh nào có ngoại lệ.",
     "SGI", 8.7, GREY, RW - 26, 10)

ry = ry + 6 - bh - 30
ry = heading(RX, ry, "CHẠY BAN ĐÊM NẾU MẤT NHIỀU GIỜ", RW)

bh = 124
box(RX, ry + 6, RW, bh, GRNBG, GREEN)
iy = ry - 8
for i, s in enumerate([
    "Quét và bỏ tick như bước 2 – 3.",
    "Đặt giờ ở ô cạnh nút xóa (mặc định 22:00).",
    "Bấm “Hẹn giờ xóa”, gõ ERASE ngay lúc này.",
    "Để nguyên máy bật và app mở rồi ra về.",
], 1):
    c.setFillColor(GREEN)
    c.circle(RX + 18, iy + 3.2, 6.5, stroke=0, fill=1)
    c.setFont("SGB", 8)
    c.setFillColor(white)
    c.drawCentredString(RX + 18, iy + 0.9, str(i))
    txt(RX + 31, iy, s, "SG", 9.2, HexColor("#33413A"))
    iy -= 15
txt(RX + 31, iy + 2, "Màn hình tắt vẫn được.", "SGI", 8.7, GREY)
iy -= 14
txt(RX + 14, iy, "Không chờ được?", "SGB", 9, AMBER)
para(RX + 14, iy - 12,
     "Tick “Xóa nhanh” — xong trong vài phút, nhưng giảm an toàn trên SSD. "
     "Chỉ dùng cho máy nội bộ.",
     "SG", 8.8, HexColor("#4A3A22"), RW - 26, 10.5)

ry = ry + 6 - bh - 30
ry = heading(RX, ry, "GẶP SỰ CỐ", RW)

for q, a in [
    ("Lỡ bỏ tick nhầm", "Bấm “1. Quét” lại từ đầu, mọi lựa chọn đặt lại."),
    ("Cần dừng giữa chừng", "Bấm “Hủy”. Giai đoạn wipe cần thêm chút thời gian mới dừng."),
    ("Máy có ổ Google Drive", "Yên tâm, app tự bỏ qua ổ đám mây và ổ mạng."),
    ("Không thấy cửa sổ app", "Phải chạy Run as administrator, đừng bấm đúp thường."),
]:
    txt(RX + 2, ry, "• " + q, "SGB", 9.3, DARK)
    ry = para(RX + 10, ry - 12, a, "SG", 9, BODY, RW - 14, 11)
    ry -= 12

ry = heading(RX, ry - 12, "SAU KHI XONG", RW)

bh = 68
box(RX, ry + 6, RW, bh, AMBBG, AMBER)
txt(RX + 14, ry - 8, "Lấy báo cáo bàn giao kẹp hồ sơ:", "SGB", 9.4, AMBER)
txt(RX + 14, ry - 22, "C:\\ProgramData\\ResetMachine", "SGB", 9.6, DARK)
para(RX + 14, ry - 36, "File bao-cao-ban-giao-*.txt ghi rõ máy nào, ai chạy, xóa bao nhiêu.",
     "SG", 8.9, HexColor("#4A3A22"), RW - 26, 10.5)

# =====================================================================
# Canh bao cuoi + chan trang
# =====================================================================
yf = 62
c.setFillColor(REDBG)
c.rect(M, yf, W - 2 * M, 32, stroke=0, fill=1)
c.setFillColor(RED)
c.rect(M, yf, 4, 32, stroke=0, fill=1)
txt(M + 14, yf + 19, "Trước khi chạy trên máy thật: hỏi lại chủ máy đã sao lưu thứ cần giữ chưa.",
    "SGB", 9.8, RED)
txt(M + 14, yf + 7, "Dữ liệu xóa rồi thì không có cách nào lấy lại.", "SG", 9.2, RED)

c.setStrokeColor(LINE)
c.setLineWidth(0.8)
c.line(M, 48, W - M, 48)
txt(M, 36, "Reset Machine v1.2  ·  ozovn", "SG", 8, GREY)
c.setFont("SG", 8)
c.setFillColor(GREY)
c.drawRightString(W - M, 36, "Hướng dẫn chi tiết: HUONG-DAN-SU-DUNG.md")

c.save()
print("Da tao HDSD-Reset-Machine.pdf (1 trang)")
