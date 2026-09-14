"""Generate one non-destructive 14x40mm P21 live-test job; performs no I/O to hardware."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT, ROW_BYTES = 96, 284, 12
out = Path("artifacts/live-p21-test-label.p21")
out.parent.mkdir(exist_ok=True)
image = Image.new("1", (WIDTH, HEIGHT), 1)
draw = ImageDraw.Draw(image)
font = ImageFont.load_default()
draw.rectangle((2, 2, 93, 281), outline=0, width=1)
draw.text((6, 14), "P21 LIVE TEST", fill=0, font=font)
draw.text((6, 42), "RFCOMM OK", fill=0, font=font)
draw.text((6, 70), "2026-09-14", fill=0, font=font)
draw.line((6, 94, 89, 94), fill=0, width=1)
draw.text((6, 110), "ONE LABEL", fill=0, font=font)
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
out.write_bytes(payload)
print(f"JOB={out} bytes={len(payload)} raster_bytes={len(raster)} prefix={payload[:89]!r} suffix={payload[-11:]!r}")
