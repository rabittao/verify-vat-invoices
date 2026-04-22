#!/usr/bin/env python3
"""Run extraction and verification for VAT invoice PDFs."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def load_env() -> dict[str, str]:
    env_path = Path(__file__).resolve().parent.parent / ".env"
    env = {}
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, value = line.partition("=")
                env[key.strip()] = value.strip()
    return env


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", default=".", help="Directory containing PDF invoices.")
    parser.add_argument(
        "--output-root",
        help="Output root path. Defaults to <input-dir>/output",
    )
    parser.add_argument("--recursive", action="store_true", help="Recursively scan subdirectories.")
    return parser.parse_args()


def run_command(command: list[str], cwd: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged_env = {**os.environ, **(env or {})}
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        capture_output=True,
        check=False,
        env=merged_env,
    )


def build_default_output_root(input_dir: Path) -> Path:
    return input_dir / "output"


def build_fallback_verification(extracted_json: Path, verified_json: Path, message: str) -> None:
    extracted_payload = json.loads(extracted_json.read_text(encoding="utf-8"))
    results_by_key = {}
    for record in extracted_payload.get("records", []):
        invoice_key = record.get("invoice_key") or record.get("record_id")
        if invoice_key in results_by_key:
            continue
        results_by_key[invoice_key] = {
            "invoice_key": record.get("invoice_key"),
            "verification_status": "verification_script_error",
            "verification_message": message,
            "captcha_attempts": 0,
            "verified_at": datetime.now(timezone.utc).isoformat(),
            "result_screenshot": None,
            "result_text": None,
        }
    verified_json.write_text(
        json.dumps(
            {
                "generated_at": datetime.now(timezone.utc).isoformat(),
                "source_file": str(extracted_json),
                "results_by_key": results_by_key,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()

    script_dir = Path(__file__).resolve().parent
    skill_root = script_dir.parent
    input_dir = Path(args.input_dir).resolve()
    env = load_env()

    output_root = Path(args.output_root).resolve() if args.output_root else build_default_output_root(input_dir)
    artifacts_root = output_root / "artifacts"
    intermediate_dir = artifacts_root / "intermediate"
    rendered_dir = artifacts_root / "rendered"
    playwright_dir = artifacts_root / "playwright"
    for directory in (intermediate_dir, rendered_dir, playwright_dir):
        directory.mkdir(parents=True, exist_ok=True)

    # 清空 playwright 目录中的旧截图
    if playwright_dir.exists():
        for item in playwright_dir.iterdir():
            if item.is_file():
                item.unlink()
            elif item.is_dir():
                import shutil
                shutil.rmtree(item)

    extracted_json = intermediate_dir / "extracted.json"
    verified_json = intermediate_dir / "verified.json"

    extract_cmd = [
        sys.executable,
        str(script_dir / "extract_invoices.py"),
        "--input-dir",
        str(input_dir),
        "--output-json",
        str(extracted_json),
        "--render-dir",
        str(rendered_dir),
    ]
    if args.recursive:
        extract_cmd.append("--recursive")
    extraction = run_command(extract_cmd, cwd=skill_root, env=env)
    if extraction.returncode != 0:
        sys.stderr.write(extraction.stderr or extraction.stdout)
        return extraction.returncode
    if extraction.stdout:
        print(extraction.stdout.strip())

    verify_cmd = [
        "node",
        str(script_dir / "verify_invoices.js"),
        "--input-json",
        str(extracted_json),
        "--output-json",
        str(verified_json),
        "--artifacts-dir",
        str(playwright_dir),
    ]
    verification = run_command(verify_cmd, cwd=skill_root, env=env)
    if verification.returncode != 0:
        message = (verification.stderr or verification.stdout).strip() or "verification script failed"
        build_fallback_verification(extracted_json, verified_json, message)
        print(f"Verification step failed; wrote fallback results to {verified_json}")
    elif verification.stdout:
        print(verification.stdout.strip())

    print(f"Pipeline completed. Extracted JSON: {extracted_json}")
    print(f"Pipeline completed. Verified JSON: {verified_json}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[run_pipeline] {exc}", file=sys.stderr)
        raise
