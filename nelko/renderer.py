"""Offline P21 label composition and deterministic artifact generation."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from textwrap import wrap

from PIL import Image, ImageDraw, ImageFont

LANDSCAPE_SIZE = (284, 96)
RASTER_SIZE = (96, 284)
ROW_BYTES = 12
RASTER_BYTES = ROW_BYTES * RASTER_SIZE[1]
JOB_BYTES = 3515
MAX_TEXT_LENGTH = 160
MAX_TEXT_LINES = 4

_FRAME_PREFIX = (
    b"\x1b!o\r\n"
    b"SIZE 14.0 mm,40.0 mm\r\n"
    b"GAP 5.0 mm,0 mm\r\n"
    b"DIRECTION 1,1\r\n"
    b"DENSITY 15\r\n"
    b"CLS\r\n"
    b"BITMAP 0,0,12,284,1,"
)
_FRAME_SUFFIX = b"\r\nPRINT 1\r\n"


class InputValidationError(ValueError):
    """Raised for invalid label content without including that content."""

    def __init__(self) -> None:
        super().__init__("invalid label input")


@dataclass(frozen=True)
class LabelRequest:
    text: str


@dataclass(frozen=True)
class RenderedLabel:
    landscape: Image.Image
    raster_image: Image.Image
    raster: bytes
    job: bytes


@dataclass(frozen=True)
class ArtifactOperation:
    """Typed, terminal-independent request for controlled offline artifacts."""

    request: LabelRequest
    output_dir: Path
    include_previews: bool


@dataclass(frozen=True)
class ArtifactResult:
    operation: str
    job_path: Path
    job_bytes: int
    raster_bytes: int
    raster_size: tuple[int, int]
    landscape_preview_path: Path | None = None
    raster_preview_path: Path | None = None

    def metadata(self) -> dict[str, object]:
        data: dict[str, object] = {
            "schema_version": 1,
            "operation": self.operation,
            "job_path": str(self.job_path),
            "job_bytes": self.job_bytes,
            "raster_bytes": self.raster_bytes,
            "raster_size": list(self.raster_size),
        }
        if self.landscape_preview_path is not None:
            data["landscape_preview_path"] = str(self.landscape_preview_path)
        if self.raster_preview_path is not None:
            data["raster_preview_path"] = str(self.raster_preview_path)
        return data


def _validate_text(text: str) -> list[str]:
    if not isinstance(text, str) or not text.strip() or len(text) > MAX_TEXT_LENGTH:
        raise InputValidationError()
    if any(ord(character) < 32 and character != "\n" for character in text):
        raise InputValidationError()

    lines: list[str] = []
    for source_line in text.splitlines() or [text]:
        lines.extend(wrap(source_line, width=38, break_long_words=True) or [""])
    if len(lines) > MAX_TEXT_LINES:
        raise InputValidationError()
    return lines


def compose_landscape(request: LabelRequest) -> Image.Image:
    """Compose request text into the readable 284x96 landscape layout."""
    lines = _validate_text(request.text)
    image = Image.new("1", LANDSCAPE_SIZE, 1)
    draw = ImageDraw.Draw(image)
    draw.rectangle((2, 2, LANDSCAPE_SIZE[0] - 3, LANDSCAPE_SIZE[1] - 3), outline=0, width=2)
    draw.rectangle((8, 8, 19, 19), fill=0)
    draw.line((8, 27, LANDSCAPE_SIZE[0] - 9, 27), fill=0)
    font = ImageFont.load_default()
    y = 38
    for line in lines:
        draw.text((12, y), line, fill=0, font=font)
        y += 13
    return image


def rotate_clockwise(landscape: Image.Image) -> Image.Image:
    if landscape.mode != "1" or landscape.size != LANDSCAPE_SIZE:
        raise ValueError("landscape must be a 284x96 monochrome image")
    return landscape.transpose(Image.Transpose.ROTATE_270)


def pack_raster(image: Image.Image) -> bytes:
    if image.mode != "1" or image.size != RASTER_SIZE:
        raise ValueError("raster image must be a 96x284 monochrome image")
    raster = image.tobytes()
    if len(raster) != RASTER_BYTES:
        raise ValueError("raster must be exactly 3408 bytes")
    return raster


def build_job(raster: bytes) -> bytes:
    if len(raster) != RASTER_BYTES:
        raise ValueError("raster must be exactly 3408 bytes")
    job = _FRAME_PREFIX + raster + _FRAME_SUFFIX
    if len(job) != JOB_BYTES:
        raise RuntimeError("P21 job frame contract violation")
    return job


def render_label(request: LabelRequest) -> RenderedLabel:
    landscape = compose_landscape(request)
    raster_image = rotate_clockwise(landscape)
    raster = pack_raster(raster_image)
    return RenderedLabel(landscape, raster_image, raster, build_job(raster))


def execute(operation: ArtifactOperation) -> ArtifactResult:
    """Generate artifacts locally; this operation performs no printer or network I/O."""
    rendered = render_label(operation.request)
    output_dir = operation.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    job_path = output_dir / "label.p21"
    job_path.write_bytes(rendered.job)

    if not operation.include_previews:
        for preview_name in ("label-landscape.png", "label-raster.png"):
            (output_dir / preview_name).unlink(missing_ok=True)
        return ArtifactResult(
            operation="encode",
            job_path=job_path,
            job_bytes=len(rendered.job),
            raster_bytes=len(rendered.raster),
            raster_size=RASTER_SIZE,
        )

    landscape_path = output_dir / "label-landscape.png"
    raster_path = output_dir / "label-raster.png"
    rendered.landscape.save(landscape_path)
    rendered.raster_image.save(raster_path)
    return ArtifactResult(
        operation="preview",
        job_path=job_path,
        job_bytes=len(rendered.job),
        raster_bytes=len(rendered.raster),
        raster_size=RASTER_SIZE,
        landscape_preview_path=landscape_path,
        raster_preview_path=raster_path,
    )
