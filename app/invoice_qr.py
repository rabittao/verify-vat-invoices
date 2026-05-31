from __future__ import annotations

import re
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from urllib.parse import parse_qs, unquote, urlparse


DATE_RE = re.compile(r"^(20\d{2})(\d{2})(\d{2})$")
ISO_DATE_RE = re.compile(r"^20\d{2}-\d{2}-\d{2}$")
AMOUNT_RE = re.compile(r"^-?\d+(?:\.\d{1,2})?$")


@dataclass(frozen=True)
class ParsedInvoiceQr:
    raw_text: str
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
    confidence: str
    parse_message: str
    tokens: list[str]


def normalize_digits(value: str | None) -> str | None:
    if value is None:
        return None
    digits = re.sub(r"\D+", "", value)
    return digits or None


def normalize_amount(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip().replace("￥", "").replace("¥", "").replace(",", "")
    if not AMOUNT_RE.fullmatch(normalized):
        return None
    try:
        return f"{Decimal(normalized):.2f}"
    except InvalidOperation:
        return None


def normalize_date(value: str | None) -> str | None:
    if value is None:
        return None
    raw = value.strip()
    if ISO_DATE_RE.fullmatch(raw):
        return raw
    digits = normalize_digits(raw)
    if not digits:
        return None
    match = DATE_RE.fullmatch(digits)
    if not match:
        return None
    year, month, day = match.groups()
    return f"{year}-{month}-{day}"


def normalize_check_code(value: str | None) -> str | None:
    digits = normalize_digits(value)
    if not digits:
        return None
    return digits[-6:] if len(digits) >= 6 else digits


def build_invoice_key(
    invoice_code: str | None,
    invoice_number: str | None,
    invoice_date: str | None,
    pretax_amount: str | None,
) -> str | None:
    if not invoice_number or not invoice_date or not pretax_amount:
        return None
    return "|".join([invoice_code or "", invoice_number, invoice_date, pretax_amount])


def validate_parsed_invoice(parsed: ParsedInvoiceQr) -> tuple[str, list[str]]:
    errors: list[str] = []
    if not parsed.invoice_number:
        errors.append("Missing required field: invoice_number")
    if not parsed.invoice_date:
        errors.append("Missing required field: invoice_date")
    if not parsed.pretax_amount:
        errors.append("Missing required field: pretax_amount")
    return ("pass" if not errors else "fail", errors)


def split_qr_tokens(raw_text: str) -> list[str]:
    decoded = unquote(raw_text.strip())
    return [
        token.strip()
        for token in re.split(r"[,，\n\r\t|;； ]+", decoded)
        if token.strip()
    ]


def _extract_query_fields(raw_text: str) -> dict[str, str]:
    parsed = urlparse(raw_text.strip())
    if not parsed.query:
        return {}
    query = parse_qs(parsed.query)
    aliases = {
        "invoice_code": ("fpdm", "invoice_code", "code"),
        "invoice_number": ("fphm", "invoice_number", "number", "fpno"),
        "invoice_date": ("kprq", "invoice_date", "date"),
        "pretax_amount": ("je", "amount", "pretax_amount", "hjje"),
        "total_amount": ("jshj", "total_amount"),
        "check_code": ("jym", "check_code", "checkcode"),
    }
    fields: dict[str, str] = {}
    for target, names in aliases.items():
        for name in names:
            values = query.get(name) or query.get(name.upper())
            if values and values[0].strip():
                fields[target] = values[0].strip()
                break
    return fields


def parse_invoice_qr(raw_text: str) -> ParsedInvoiceQr:
    cleaned = raw_text.strip()
    if not cleaned:
        return ParsedInvoiceQr(
            raw_text=raw_text,
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
            confidence="low",
            parse_message="二维码内容为空",
            tokens=[],
        )

    query_fields = _extract_query_fields(cleaned)
    tokens = split_qr_tokens(cleaned)
    digit_tokens = [normalize_digits(token) for token in tokens]
    digit_tokens = [token for token in digit_tokens if token]

    invoice_code = normalize_digits(query_fields.get("invoice_code"))
    invoice_number = normalize_digits(query_fields.get("invoice_number"))
    invoice_date = normalize_date(query_fields.get("invoice_date"))
    pretax_amount = normalize_amount(query_fields.get("pretax_amount"))
    total_amount = normalize_amount(query_fields.get("total_amount"))
    check_code = normalize_check_code(query_fields.get("check_code"))

    token_dates = [(index, normalize_date(token)) for index, token in enumerate(tokens)]
    token_dates = [(index, value) for index, value in token_dates if value]
    if not invoice_date and token_dates:
        invoice_date = token_dates[0][1]

    if not pretax_amount:
        amount_candidates = [
            normalize_amount(token)
            for token in tokens
            if any(marker in token for marker in (".", "￥", "¥"))
            and normalize_amount(token)
        ]
        pretax_amount = amount_candidates[0] if amount_candidates else None

    ordinary_number = next((token for token in digit_tokens if len(token) == 8), None)
    ordinary_code = next(
        (
            token
            for token in digit_tokens
            if token != ordinary_number and len(token) in {10, 12}
        ),
        None,
    )

    if not invoice_number and ordinary_number and ordinary_code:
        # Ordinary VAT invoice QR strings commonly contain invoice code then 8-digit number.
        invoice_number = ordinary_number
        invoice_code = invoice_code or ordinary_code

    if not invoice_number:
        # Fully digitized e-invoices usually carry a 20-digit invoice number.
        invoice_number = next((token for token in digit_tokens if len(token) == 20), None)

    if not invoice_code and invoice_number and len(invoice_number) == 8:
        candidates = [
            token
            for token in digit_tokens
            if token != invoice_number and len(token) in {10, 12}
        ]
        invoice_code = candidates[0] if candidates else None

    if not check_code:
        long_digit_tokens = [
            token
            for token in digit_tokens
            if token not in {invoice_code, invoice_number}
            and token != normalize_digits(invoice_date)
            and len(token) >= 12
        ]
        if long_digit_tokens:
            check_code = normalize_check_code(long_digit_tokens[-1])

    invoice_type = None
    if invoice_number and len(invoice_number) == 20 and not invoice_code:
        invoice_type = "数电票/全电发票"
    elif invoice_number:
        invoice_type = "增值税普通发票"

    required = [invoice_number, invoice_date, pretax_amount]
    confidence = "high" if all(required) else "medium" if invoice_number else "low"
    parse_message = "二维码解析成功" if confidence == "high" else "二维码内容已读取，但关键字段不完整"

    return ParsedInvoiceQr(
        raw_text=cleaned,
        invoice_type=invoice_type,
        invoice_code=invoice_code,
        invoice_number=invoice_number,
        invoice_date=invoice_date,
        pretax_amount=pretax_amount,
        tax_amount=None,
        total_amount=total_amount,
        seller_name=None,
        buyer_name=None,
        check_code=check_code,
        confidence=confidence,
        parse_message=parse_message,
        tokens=tokens,
    )
