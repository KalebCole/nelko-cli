"""Generate one rotated 14x40 mm P21 calibration label; performs no hardware I/O."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

LANDSCAPE_WIDTH, LANDSCAPE_HEIGHT = 284, 96
WIDTH, HEIGHT, ROW_BYTES = 96, 284, 12
OUT = Path("artifacts/p21-rotation-calibration.p21")

font_path = "/System/Library/Fonts/Supplemental/Arial.ttf"
font_bold_path = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
font = ImageFont.truetype(font_path, 16)
small = ImageFont.truetype(font_path, 11)
bold = ImageFont.truetype(font_bold_path, 21)

landscape = Image.new("1", (LANDSCAPE_WIDTH, LANDSCAPE_HEIGHT), 1)
draw = ImageDraw.Draw(landscape)
draw.rectangle((2, 2, LANDSCAPE_WIDTH - 3, LANDSCAPE_HEIGHT - 3), outline=0, width=2)
draw.rectangle((8, 8, 25, 25), fill=0)
draw.text((35, 6), "BLACK MARK = TOP LEFT", fill=0, font=small)
draw.line((8, 33, LANDSCAPE_WIDTH - 9, 33), fill=0, width=1)
draw.text((48, 39), "P21 CALIBRATION", fill=0, font=bold)
draw.text((47, 67), "ROTATED / ONE LABEL", fill=0, font=font)
image = landscape.transpose(Image.Transpose.ROTATE_270)
assert image.size == (WIDTH, HEIGHT)
raster = image.tobytes()
assert len(raster) == ROW_BYTES * HEIGHT
payload = (
    b"\x1b!o\r\n"
    b"SIZE 14.0 mm,40.0 mm\r\n"
    b"GAP 5.0 mm,0 mm\r\n"
    b"DIRECTION 1,1\r\n"
    b"DENSITY 15\r\n"
    b"CLS\r\n"
    b"BITMAP 0,0,12,284,1," + raster + b"\r\n"
    b"PRINT 1\r\n"
)
OUT.parent.mkdir(exist_ok=True)
OUT.write_bytes(payload)
landscape.save("artifacts/p21-rotation-calibration-landscape-preview.png")
image.save("artifacts/p21-rotation-calibration-raster-preview.png")
print(f"JOB={OUT} bytes={len(payload)} raster_bytes={len(raster)} orientation=clockwise sha256=", end="")
import hashlib
print(hashlib.sha256(payload).hexdigest())
