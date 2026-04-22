#!/usr/bin/env python3
"""Scan PDFs, render pages, extract VAT invoice fields via vision models, and emit normalized JSON records."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import fitz  # type: ignore
except Exception as exc:  # pragma: no cover
    fitz = None
    PYMUPDF_IMPORT_ERROR = exc
else:
    PYMUPDF_IMPORT_ERROR = None

DEFAULT_RENDER_BACKEND = "pymupdf"

VISION_SYSTEM_PROMPT = """You are an expert at extracting structured data from Chinese VAT invoice images.
Return only valid JSON.
Analyze the invoice image carefully and extract all VAT invoice fields.
If no VAT invoice is found, return invoices as an empty array.
Use null for unknown fields.
Do not invent or guess values.
"""

VISION_USER_PROMPT_TEMPLATE = """Extract all VAT invoice fields from this invoice image.

Return a JSON object with keys: page_status, page_message, invoices.
invoices must be an array of invoice objects.

For each invoice, extract these exact fields:
- invoice_type: The invoice type text (e.g., \"增值税专用发票\", \"增值税普通发票\", \"电子发票（普通发票）\", \"增值税电子普通发票\")
- invoice_code: The invoice code (10-12 digits, usually labeled 发票代码). For fully digitized e-invoices (全电发票/电子发票), there is NO invoice code — set this to null.
- invoice_number: The invoice number (usually 8 or 20 digits, labeled 发票号码). Fully digitized e-invoices (全电发票) use a 20-digit number.
- invoice_date: The issue date in YYYY-MM-DD format (e.g., 2024-01-15)
- pretax_amount: The pretax amount/金额 (before tax, usually labeled 金额 or 不含税金额)
- tax_amount: The tax amount/税额
- total_amount: The total amount including tax/价税合计
- seller_name: The seller/销售方 name
- buyer_name: The buyer/购买方 name
- check_code: The check code/校验码 (usually labeled 校验码, a 20-digit string). For fully digitized e-invoices (全电发票/电子发票) there is no check code — set this to null.

Be precise with Chinese VAT invoice formats.
Normalize dates to YYYY-MM-DD.
Normalize amounts to plain decimal strings like 123.45.
Leave unknown fields as null.

Source: {source_pdf}, Page: {page_number}
"""

FLOAT_TOLERANCE = 0.01


@dataclass
class PageRecord:
    source_pdf: str
    page_number: int
    invoice_index: int
    invoice_type: str | None
    invoice_code: str | None
    invoice_number: str | None
    invoice_date: str | None
    pretax_amount: str | None
    tax_amount: str | None
    total_amount: str | None
    seller_name: str | None
    buyer_name: str | None
    check_code: str | None
    extraction_status: str
    extraction_message: str
    extraction_method: str
    result_screenshot: str | None = None
    raw_text_excerpt: str | None = None
    validation_status: str = "pass"
    validation_errors: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        data = self.__dict__.copy()
        data["record_id"] = build_record_id(self.source_pdf, self.page_number, self.invoice_index)
        data["invoice_key"] = build_invoice_key(
            self.invoice_code,
            self.invoice_number,
            self.invoice_date,
            self.pretax_amount,
        )
        data["needs_verification"] = has_minimum_verification_fields(data)
        return data


@dataclass
class RenderSupport:
    backend: str | None
    available_backends: list[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", default=".", help="Directory containing PDFs.")
    parser.add_argument("--output-json", required=True, help="Where to write extracted JSON.")
    parser.add_argument("--render-dir", help="Directory for rendered page PNGs.")
    parser.add_argument("--recursive", action="store_true", help="Recursively search subdirectories for PDFs.")
    parser.add_argument(
        "--render-backend",
        default=DEFAULT_RENDER_BACKEND,
        choices=("pymupdf",),
        help="PDF render backend. Only PyMuPDF is supported.",
    )
    return parser.parse_args()




def load_env_file() -> None:
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if not env_path.exists():
        return
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip())


def get_qwen_vl_key() -> str | None:
    api_key = os.environ.get("QWEN_API_KEY", "").strip()
    return api_key or None


def resolve_render_support(preferred_backend: str) -> RenderSupport:
    available = ["pymupdf"] if fitz is not None else []
    backend = preferred_backend if preferred_backend in available else None
    return RenderSupport(backend=backend, available_backends=available)


def discover_pdfs(input_dir: Path, recursive: bool) -> list[Path]:
    if recursive:
        return sorted(path for path in input_dir.rglob("*.pdf") if path.is_file())
    return sorted(path for path in input_dir.glob("*.pdf") if path.is_file())


def pdf_page_count(pdf_path: Path) -> int:
    if fitz is None:
        raise RuntimeError(f"PyMuPDF is required: {PYMUPDF_IMPORT_ERROR}")
    document = fitz.open(str(pdf_path))
    try:
        return int(document.page_count)
    finally:
        document.close()


def render_pdf_page_pymupdf(pdf_path: Path, page_index: int, output_path: Path, scale: float = 2.0) -> None:
    if fitz is None:
        raise RuntimeError("PyMuPDF is not installed")
    document = fitz.open(str(pdf_path))
    try:
        page = document.load_page(page_index)
        matrix = fitz.Matrix(scale, scale)
        pixmap = page.get_pixmap(matrix=matrix, alpha=False)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        pixmap.save(str(output_path))
    finally:
        document.close()


def render_pdf_page(pdf_path: Path, page_index: int, output_path: Path, render_support: RenderSupport) -> None:
    if render_support.backend != "pymupdf":
        raise RuntimeError("PyMuPDF render backend is unavailable. Install it with `python3 -m pip install PyMuPDF`.")
    render_pdf_page_pymupdf(pdf_path, page_index, output_path)


def encode_image_data_url(image_path: Path) -> str:
    encoded = base64.b64encode(image_path.read_bytes()).decode("ascii")
    return f"data:image/png;base64,{encoded}"


def parse_json_object(raw_text: str) -> dict[str, Any]:
    cleaned = raw_text.strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned)
        cleaned = re.sub(r"\s*```$", "", cleaned)
    parsed = json.loads(cleaned)
    if isinstance(parsed, list):
        return {"page_status": "ok", "page_message": None, "invoices": parsed}
    return parsed


def call_qwen_vision_invoice(api_key: str, image_path: Path, pdf_path: str, page_number: int) -> dict[str, Any]:
    prompt = VISION_USER_PROMPT_TEMPLATE.format(source_pdf=pdf_path, page_number=page_number)
    image_data = encode_image_data_url(image_path)
    payload = {
        "model": "qwen-vl-max",
        "messages": [
            {"role": "system", "content": VISION_SYSTEM_PROMPT},
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": image_data}},
                    {"type": "text", "text": prompt},
                ],
            },
        ],
        "response_format": {"type": "json_object"},
    }
    request = urllib.request.Request(
        "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"Qwen vision API HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Qwen vision API request failed: {exc}") from exc
    try:
        text = body["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as exc:
        raise RuntimeError(f"Unexpected Qwen vision response shape: {body}") from exc
    return parse_json_object(text)


def call_vision_for_invoice_extraction(image_path: Path, pdf_path: str, page_number: int) -> tuple[dict[str, Any], str]:
    qwen_key = get_qwen_vl_key()
    if not qwen_key:
        raise RuntimeError("QWEN_API_KEY is required for invoice vision extraction")
    return call_qwen_vision_invoice(qwen_key, image_path, pdf_path, page_number), "qwen-vl-max"


def clean_text(text: str) -> str:
    text = text.replace("\x00", " ")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def normalize_digits(value: Any) -> str | None:
    if value in (None, ""):
        return None
    text = re.sub(r"\D+", "", str(value))
    return text or None


def normalize_amount(value: Any) -> str | None:
    if value in (None, ""):
        return None
    text = str(value).strip().replace("￥", "").replace("¥", "").replace(",", "").replace("，", "")
    text = text.replace("元", "").replace(" ", "")
    match = re.search(r"-?\d+(?:\.\d+)?", text)
    if not match:
        return None
    return f"{float(match.group(0)):.2f}"


def normalize_date(value: Any) -> str | None:
    if value in (None, ""):
        return None
    text = str(value).strip().replace("年", "-").replace("月", "-").replace("日", "")
    text = text.replace("/", "-").replace(".", "-")
    match = re.search(r"(\d{4})-(\d{1,2})-(\d{1,2})", text)
    if match:
        year, month, day = match.groups()
        return f"{year}-{int(month):02d}-{int(day):02d}"
    digits = re.sub(r"\D+", "", text)
    if len(digits) == 8:
        return f"{digits[:4]}-{digits[4:6]}-{digits[6:]}"
    return None


def normalize_text_field(value: Any) -> str | None:
    if value in (None, ""):
        return None
    text = clean_text(str(value))
    return text or None


def normalize_check_code(value: Any) -> str | None:
    """Extract digits from check code and return the last 6 digits."""
    if value in (None, ""):
        return None
    digits = re.sub(r"\D+", "", str(value))
    if len(digits) < 6:
        return digits or None
    return digits[-6:]


def build_record_id(source_pdf: str, page_number: int, invoice_index: int) -> str:
    raw = f"{source_pdf}|{page_number}|{invoice_index}".encode("utf-8")
    return hashlib.sha1(raw).hexdigest()[:16]


def build_invoice_key(invoice_code: str | None, invoice_number: str | None, invoice_date: str | None, pretax_amount: str | None) -> str | None:
    required = [invoice_number, invoice_date, pretax_amount]
    if not all(required):
        return None
    return "|".join([invoice_code or "", invoice_number, invoice_date, pretax_amount])


def has_minimum_verification_fields(record: dict[str, Any]) -> bool:
    required = (record.get("invoice_number"), record.get("invoice_date"), record.get("pretax_amount"))
    return all(required)


def extract_labeled_invoice_fields(page_text: str) -> dict[str, str | None]:
    """Extract a few high-value labeled fields from the PDF text layer as a fallback."""
    text = clean_text(page_text or "")

    def extract(pattern: str) -> str | None:
        match = re.search(pattern, text, re.MULTILINE)
        return match.group(1) if match else None

    invoice_number = extract(r"发票号码[:：]?\s*(\d{8,20})")
    if not invoice_number:
        # Some PDF text layers separate labels and values into different blocks.
        # For e-invoices, the first 20-digit sequence on the page is typically the invoice number.
        invoice_number = extract(r"\b(\d{20})\b")

    invoice_date = extract(r"开票日期[:：]?\s*([0-9]{4}年[0-9]{2}月[0-9]{2}日)")
    if not invoice_date:
        invoice_date = extract(r"\b([0-9]{4}年[0-9]{2}月[0-9]{2}日)\b")

    return {
        "invoice_number": invoice_number,
        "invoice_date": invoice_date,
    }


def apply_text_layer_fallbacks(invoice: dict[str, Any], page_text: str) -> dict[str, Any]:
    labeled = extract_labeled_invoice_fields(page_text)
    invoice_number = invoice.get("invoice_number")
    fallback_number = normalize_digits(labeled.get("invoice_number"))
    is_e_invoice = "电子发票" in str(invoice.get("invoice_type") or "")

    # Vision extraction occasionally drops a digit in 20-digit e-invoice numbers.
    # Prefer the labeled text-layer number when it is more complete.
    if fallback_number and (
        not invoice_number
        or (is_e_invoice and len(invoice_number) < len(fallback_number))
    ):
        invoice["invoice_number"] = fallback_number

    if not invoice.get("invoice_date") and labeled.get("invoice_date"):
        invoice["invoice_date"] = normalize_date(labeled["invoice_date"])

    return invoice


def extract_pdf_page_text(pdf_path: Path, page_number: int) -> str:
    if fitz is None:
        return ""
    document = fitz.open(str(pdf_path))
    try:
        return document.load_page(page_number - 1).get_text("text")
    finally:
        document.close()


def normalize_invoice(raw_invoice: dict[str, Any], page_text: str | None = None) -> dict[str, Any]:
    invoice_code = normalize_digits(raw_invoice.get("invoice_code"))
    invoice_number = normalize_digits(raw_invoice.get("invoice_number"))
    if not invoice_number and invoice_code:
        invoice_number = invoice_code
    # 全电发票没有发票代码，模型可能将同一个号码填入两个字段
    # 如果发票代码与发票号码完全相同，说明是误填，将发票代码置空
    if invoice_code and invoice_number and invoice_code == invoice_number:
        invoice_code = None
    invoice = {
        "invoice_type": normalize_text_field(raw_invoice.get("invoice_type")),
        "invoice_code": invoice_code,
        "invoice_number": invoice_number,
        "invoice_date": normalize_date(raw_invoice.get("invoice_date")),
        "pretax_amount": normalize_amount(raw_invoice.get("pretax_amount")),
        "tax_amount": normalize_amount(raw_invoice.get("tax_amount")),
        "total_amount": normalize_amount(raw_invoice.get("total_amount")),
        "seller_name": normalize_text_field(raw_invoice.get("seller_name")),
        "buyer_name": normalize_text_field(raw_invoice.get("buyer_name")),
        "check_code": normalize_check_code(raw_invoice.get("check_code")),
    }
    if page_text:
        invoice = apply_text_layer_fallbacks(invoice, page_text)
    return invoice


def validate_invoice_fields(record: dict[str, Any]) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []

    for field_name in ("invoice_number", "invoice_date", "pretax_amount"):
        if not record.get(field_name):
            errors.append(f"Missing required field: {field_name}")

    invoice_number = record.get("invoice_number")
    if invoice_number and not re.fullmatch(r"\d{8,20}", invoice_number):
        errors.append(f"Invoice number format invalid: {invoice_number!r} (expected 8-20 digits)")

    invoice_code = record.get("invoice_code")
    if invoice_code and not re.fullmatch(r"\d+", invoice_code):
        warnings.append(f"Invoice code contains non-digits: {invoice_code!r}")

    invoice_date = record.get("invoice_date")
    if invoice_date and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", invoice_date):
        errors.append(f"Invoice date format invalid: {invoice_date!r} (expected YYYY-MM-DD)")

    for field_name in ("pretax_amount", "tax_amount", "total_amount"):
        value_str = record.get(field_name)
        if value_str is None:
            continue
        try:
            value = float(value_str)
            if value < 0:
                errors.append(f"{field_name} must not be negative: {value}")
        except (TypeError, ValueError):
            errors.append(f"{field_name} is not a valid number: {value_str!r}")

    pretax_str = record.get("pretax_amount")
    tax_str = record.get("tax_amount")
    total_str = record.get("total_amount")
    if pretax_str is not None and total_str is not None:
        try:
            if float(pretax_str) > float(total_str):
                errors.append(f"pretax_amount ({pretax_str}) exceeds total_amount ({total_str})")
        except (TypeError, ValueError):
            pass
    if pretax_str is not None and tax_str is not None and total_str is not None:
        try:
            pretax = float(pretax_str)
            tax = float(tax_str)
            total = float(total_str)
            expected_tax = total - pretax
            if abs(tax - expected_tax) > FLOAT_TOLERANCE:
                errors.append(
                    f"Tax amount mismatch: tax_amount={tax}, expected={expected_tax:.2f} "
                    f"(total={total} - pretax={pretax}, tolerance={FLOAT_TOLERANCE})"
                )
        except (TypeError, ValueError):
            pass

    status = "fail" if errors else "warning" if warnings else "pass"
    return {
        "validation_status": status,
        "validation_errors": errors,
        "validation_warnings": warnings,
    }


def extract_page_records(pdf_path: Path, relative_pdf: str, page_number: int, image_path: Path) -> list[PageRecord]:
    payload, method = call_vision_for_invoice_extraction(image_path, relative_pdf, page_number)
    document_text = extract_pdf_page_text(pdf_path, page_number)
    invoices = payload.get("invoices") or []
    page_message = normalize_text_field(payload.get("page_message")) or ""

    records: list[PageRecord] = []
    for index, raw_invoice in enumerate(invoices, start=1):
        if not isinstance(raw_invoice, dict):
            continue
        invoice = normalize_invoice(raw_invoice, document_text)
        status = "success" if has_minimum_verification_fields(invoice) else "missing_fields"
        message = page_message or "invoice extracted via vision model"
        if status != "success":
            missing = [field_name for field_name in ("invoice_number", "invoice_date", "pretax_amount") if not invoice.get(field_name)]
            message = f"missing required fields: {', '.join(missing)}"
        record = PageRecord(
            source_pdf=relative_pdf,
            page_number=page_number,
            invoice_index=index,
            invoice_type=invoice["invoice_type"],
            invoice_code=invoice["invoice_code"],
            invoice_number=invoice["invoice_number"],
            invoice_date=invoice["invoice_date"],
            pretax_amount=invoice["pretax_amount"],
            tax_amount=invoice["tax_amount"],
            total_amount=invoice["total_amount"],
            seller_name=invoice["seller_name"],
            buyer_name=invoice["buyer_name"],
            check_code=invoice["check_code"],
            extraction_status=status,
            extraction_message=message,
            extraction_method=method,
            result_screenshot=str(image_path),
        )
        validation = validate_invoice_fields(invoice)
        record.validation_status = validation["validation_status"]
        record.validation_errors = validation["validation_errors"]
        records.append(record)

    if records:
        return records

    record = PageRecord(
        source_pdf=relative_pdf,
        page_number=page_number,
        invoice_index=0,
        invoice_type=None,
        invoice_code=None,
        invoice_number=None,
        invoice_date=None,
        pretax_amount=None,
        tax_amount=None,
        total_amount=None,
        seller_name=None,
        buyer_name=None,
        check_code=None,
        extraction_status="no_invoice_detected",
        extraction_message=page_message or "page does not contain a VAT invoice",
        extraction_method=method,
        result_screenshot=str(image_path),
    )
    record.validation_status = "not_applicable"
    record.validation_errors = []
    return [record]


def build_failed_record(relative_pdf: str, page_number: int, message: str, method: str, image_path: Path | None = None) -> dict[str, Any]:
    record = PageRecord(
        source_pdf=relative_pdf,
        page_number=page_number,
        invoice_index=1,
        invoice_type=None,
        invoice_code=None,
        invoice_number=None,
        invoice_date=None,
        pretax_amount=None,
        tax_amount=None,
        total_amount=None,
        seller_name=None,
        buyer_name=None,
        check_code=None,
        extraction_status="failed",
        extraction_message=message,
        extraction_method=method,
        result_screenshot=str(image_path) if image_path else None,
    )
    validation = validate_invoice_fields({"invoice_number": None, "invoice_date": None, "pretax_amount": None})
    record.validation_status = validation["validation_status"]
    record.validation_errors = validation["validation_errors"]
    return record.to_dict()


def main() -> int:
    load_env_file()
    args = parse_args()
    render_support = resolve_render_support(args.render_backend)
    input_dir = Path(args.input_dir).resolve()
    output_json = Path(args.output_json).resolve()
    render_dir = Path(args.render_dir).resolve() if args.render_dir else output_json.parent.parent / "rendered"
    output_json.parent.mkdir(parents=True, exist_ok=True)
    render_dir.mkdir(parents=True, exist_ok=True)

    if not get_qwen_vl_key():
        raise RuntimeError("QWEN_API_KEY is required for invoice vision extraction")

    pdf_paths = discover_pdfs(input_dir, args.recursive)
    records: list[dict[str, Any]] = []

    for pdf_path in pdf_paths:
        relative_pdf = str(pdf_path.relative_to(input_dir))
        pdf_records: list[dict[str, Any]] = []
        try:
            page_count = pdf_page_count(pdf_path)
            pdf_slug = hashlib.sha1(relative_pdf.encode("utf-8")).hexdigest()[:10]
            for page_index in range(page_count):
                page_number = page_index + 1
                image_path = render_dir / f"{pdf_slug}-{pdf_path.stem}-page-{page_number:03d}.png"
                try:
                    render_pdf_page(pdf_path, page_index, image_path, render_support)
                except Exception as exc:
                    pdf_records.append(build_failed_record(relative_pdf, page_number, f"page render failed: {exc}", "render-error"))
                    continue
                try:
                    page_records = extract_page_records(pdf_path, relative_pdf, page_number, image_path)
                    pdf_records.extend(record.to_dict() for record in page_records)
                except Exception as exc:
                    pdf_records.append(
                        build_failed_record(relative_pdf, page_number, f"vision extraction failed: {exc}", "vision-error", image_path)
                    )
        except Exception as exc:
            pdf_records.append(build_failed_record(relative_pdf, 0, f"pdf extraction failed: {exc}", "pdf-error"))

        if not pdf_records:
            pdf_records.append(build_failed_record(relative_pdf, 0, "no VAT invoice detected in PDF", "scan-summary"))
        records.extend(pdf_records)

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "input_dir": str(input_dir),
        "render_backend": render_support.backend,
        "available_render_backends": render_support.available_backends,
        "record_count": len(records),
        "records": records,
    }
    output_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {len(records)} extracted records to {output_json}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[extract_invoices] {exc}", file=sys.stderr)
        raise
