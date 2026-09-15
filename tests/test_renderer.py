import hashlib

import pytest
from PIL import Image

from nelko.renderer import (
    JOB_BYTES,
    LANDSCAPE_SIZE,
    RASTER_SIZE,
    RASTER_BYTES,
    LabelRequest,
    InputValidationError,
    build_job,
    pack_raster,
    render_label,
    rotate_clockwise,
    ArtifactOperation,
    execute,
)


def test_render_label_produces_known_p21_dimensions_and_job_contract():
    rendered = render_label(LabelRequest(text="OFFLINE LABEL"))

    assert rendered.landscape.size == LANDSCAPE_SIZE == (284, 96)
    assert rendered.raster_image.size == RASTER_SIZE == (96, 284)
    assert len(rendered.raster) == RASTER_BYTES == 3408
    assert len(rendered.job) == JOB_BYTES == 3515


def test_rotate_clockwise_moves_top_left_black_pixel_to_top_right():
    landscape = Image.new("1", LANDSCAPE_SIZE, 1)
    landscape.putpixel((0, 0), 0)

    raster_image = rotate_clockwise(landscape)

    assert raster_image.getpixel((95, 0)) == 0
    assert raster_image.getpixel((0, 0)) == 1


def test_pack_raster_is_msb_first_with_black_zero_and_white_one():
    image = Image.new("1", RASTER_SIZE, 1)
    image.putpixel((0, 0), 0)
    image.putpixel((7, 0), 0)
    image.putpixel((8, 0), 0)

    raster = pack_raster(image)

    assert raster[:2] == bytes((0b01111110, 0b01111111))
    assert len(raster) == RASTER_BYTES


def test_build_job_has_exact_proven_frame_and_one_copy_trailer():
    raster = bytes([0xFF]) * RASTER_BYTES

    job = build_job(raster)

    assert len(job) == JOB_BYTES
    assert job.startswith(
        b"\x1b!o\r\n"
        b"SIZE 14.0 mm,40.0 mm\r\n"
        b"GAP 5.0 mm,0 mm\r\n"
        b"DIRECTION 1,1\r\n"
        b"DENSITY 15\r\n"
        b"CLS\r\n"
        b"BITMAP 0,0,12,284,1,"
    )
    assert job.endswith(b"\r\nPRINT 1\r\n")
    assert job[-(len(raster) + 11):-11] == raster


def test_build_job_rejects_any_non_contract_raster_length():
    with pytest.raises(ValueError, match="raster must be exactly 3408 bytes"):
        build_job(b"\xff")


@pytest.mark.parametrize(
    "text",
    ["", "x" * 161, "ok\x00bad", "one\ntwo\nthree\nfour\nfive"],
)
def test_render_label_rejects_invalid_input_without_echoing_content(text):
    with pytest.raises(InputValidationError) as error:
        render_label(LabelRequest(text=text))

    assert str(error.value) == "invalid label input"
    if text:
        assert text not in str(error.value)


def test_rendered_job_is_deterministic_for_a_request():
    first = render_label(LabelRequest(text="stable"))
    second = render_label(LabelRequest(text="stable"))

    assert first.job == second.job
    assert hashlib.sha256(first.job).hexdigest() == hashlib.sha256(second.job).hexdigest()


def test_typed_encode_operation_removes_stale_preview_artifacts(tmp_path):
    request = LabelRequest(text="typed operation")
    preview = execute(ArtifactOperation(request, tmp_path, include_previews=True))

    encoded = execute(ArtifactOperation(request, tmp_path, include_previews=False))

    assert preview.landscape_preview_path is not None
    assert encoded.operation == "encode"
    assert encoded.landscape_preview_path is None
    assert encoded.raster_preview_path is None
    assert encoded.job_path.read_bytes() == render_label(request).job
    assert not (tmp_path / "label-landscape.png").exists()
    assert not (tmp_path / "label-raster.png").exists()
