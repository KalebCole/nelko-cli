import json
import subprocess
import sys
from pathlib import Path

import pytest

from nelko import cli


def run_cli(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "nelko", *arguments],
        text=True,
        capture_output=True,
        check=False,
    )


def test_preview_json_writes_controlled_inspectable_artifacts(tmp_path: Path):
    output_dir = tmp_path / "preview"

    result = run_cli(
        "preview",
        "--text",
        "AGENT SAFE",
        "--output-dir",
        str(output_dir),
        "--no-input",
        "--json",
    )

    assert result.returncode == 0
    assert result.stderr == ""
    metadata = json.loads(result.stdout)
    assert metadata == {
        "job_bytes": 3515,
        "job_path": str(output_dir / "label.p21"),
        "landscape_preview_path": str(output_dir / "label-landscape.png"),
        "operation": "preview",
        "raster_bytes": 3408,
        "raster_preview_path": str(output_dir / "label-raster.png"),
        "raster_size": [96, 284],
        "schema_version": 1,
    }
    assert (output_dir / "label.p21").stat().st_size == 3515
    assert (output_dir / "label-landscape.png").is_file()
    assert (output_dir / "label-raster.png").is_file()


def test_encode_json_writes_only_the_p21_job(tmp_path: Path):
    output_dir = tmp_path / "encoded"

    result = run_cli(
        "encode",
        "--text",
        "ENCODE ONLY",
        "--output-dir",
        str(output_dir),
        "--no-input",
        "--json",
    )

    assert result.returncode == 0
    metadata = json.loads(result.stdout)
    assert metadata["operation"] == "encode"
    assert metadata["job_path"] == str(output_dir / "label.p21")
    assert metadata["job_bytes"] == 3515
    assert "landscape_preview_path" not in metadata
    assert "raster_preview_path" not in metadata
    assert (output_dir / "label.p21").is_file()
    assert not (output_dir / "label-landscape.png").exists()
    assert not (output_dir / "label-raster.png").exists()


def test_cli_invalid_input_returns_generic_error_without_label_content(tmp_path: Path):
    secret = "TOP SECRET CUSTOMER NAME " * 20

    result = run_cli(
        "encode",
        "--text",
        secret,
        "--output-dir",
        str(tmp_path),
        "--no-input",
    )

    assert result.returncode == 2
    assert result.stdout == ""
    assert result.stderr == "error: invalid label input\n"
    assert secret not in result.stderr


def test_cli_hides_unexpected_rendering_errors_that_include_label_content(monkeypatch, capsys, tmp_path):
    secret = "PRIVATE LABEL CONTENT"

    def fail(_operation):
        raise RuntimeError(secret)

    monkeypatch.setattr(cli, "execute", fail)

    assert cli.main(["encode", "--text", secret, "--output-dir", str(tmp_path), "--no-input"]) == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err == "error: artifact generation failed\n"
    assert secret not in captured.err
