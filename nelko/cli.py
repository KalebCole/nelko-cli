"""Terminal adapter for offline P21 artifact operations."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Sequence

from .renderer import ArtifactOperation, InputValidationError, LabelRequest, execute


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="nelko")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("preview", "encode"):
        operation = subparsers.add_parser(command)
        operation.add_argument("--text", required=True, help="label text")
        operation.add_argument("--output-dir", required=True, type=Path)
        operation.add_argument(
            "--no-input",
            action="store_true",
            help="confirm non-interactive operation (no prompts are used)",
        )
        operation.add_argument("--json", action="store_true", help="write stable artifact metadata")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    operation = ArtifactOperation(
        request=LabelRequest(text=args.text),
        output_dir=args.output_dir,
        include_previews=args.command == "preview",
    )
    try:
        result = execute(operation)
    except InputValidationError:
        print("error: invalid label input", file=sys.stderr)
        return 2
    except Exception:
        print("error: artifact generation failed", file=sys.stderr)
        return 1

    metadata = result.metadata()
    if args.json:
        print(json.dumps(metadata, sort_keys=True))
    else:
        print(metadata["job_path"])
        if result.landscape_preview_path is not None:
            print(metadata["landscape_preview_path"])
            print(metadata["raster_preview_path"])
    return 0
