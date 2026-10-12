"""Local workspace reconciliation; no network or external script dependency."""
import csv
import hashlib
import json
import os
import re
import tempfile
import fcntl
from contextlib import contextmanager
from decimal import Decimal
from pathlib import Path


@contextmanager
def archive_lock(root):
    """Serialize ledger read/modify/write with the running archiver."""
    with (root / '.核对工作/归档写入.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=path.name + '.')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as out:
            json.dump(value, out, ensure_ascii=False, indent=2)
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def normalize(text):
    return re.sub(r'\s+', '', str(text))


def load_records(root):
    records = json.loads((root / '.核对工作/manifest.json').read_text(encoding='utf-8'))
    numbers = set()
    for row in records:
        number = row['发票号码']
        if not re.fullmatch(r'\d{20}', number) or number in numbers:
            raise ValueError('清单发票号码缺失或重复')
        numbers.add(number)
        if Path(row['PDF文件名']).name != row['PDF文件名'] or int(row['页码']) < 1:
            raise ValueError('无效PDF文件名或页码')
        if Decimal(row['金额']) + Decimal(row['税额']) != Decimal(row['价税合计']):
            raise ValueError('清单金额勾稽不一致')
    return records


def expected_parties(root, record):
    stem = Path(record['PDF文件名']).stem
    rows = json.loads((root / '.核对工作/OCR' / f"{stem}__{record['页码']:03d}.json").read_text())
    result = {}
    for side, left in [('购买方', True), ('销售方', False)]:
        texts = [r['text'] for r in rows if (r['x'] < .5) == left and .55 < r['y'] < .65]
        names = [m.group(1).strip() for text in texts if (m := re.search(r'名称[：:]\s*(.+)', text))]
        ids = [m.group(1) for text in texts if (m := re.search(r'(?:纳税人识别号|统一社会信用代码)[^：:]*[：:]\s*([A-Z0-9]{18})', text))]
        # 不从多候选或缺失OCR臆测；缺项在核对结果中保持待复核。
        if len(names) == 1:
            result[side + '名称'] = names[0]
        if len(ids) == 1:
            result[side + '识别号'] = ids[0]
    return result


def compare_platform_text(root, record, text):
    number = re.search(r'发票号码[：:]\s*(\d{20})', text)
    date = re.search(r'开票日期[：:]\s*(\d{4})年(\d{2})月(\d{2})日', text)
    total = re.search(r'[（(]小写[）)]\s*[￥¥]\s*(\d+\.\d{2})', text)
    # Bound the multiline summary so the grand total cannot become a tax amount.
    summary = re.search(r'(?:^|\n)合计(?P<values>.*?)价税合计', text, re.S)
    amounts = re.findall(r'[￥¥]\s*(\d+\.\d{2})', summary['values'] if summary else '')
    checks = {
        '发票号码': bool(number and number.group(1) == record['发票号码']),
        '开票日期': bool(date and ''.join(date.groups()) == record['开票日期']),
        '价税合计': bool(total and Decimal(total.group(1)) == Decimal(record['价税合计'])),
        '金额与税额': bool(len(amounts) == 2 and Decimal(amounts[0]) == Decimal(record['金额']) and Decimal(amounts[1]) == Decimal(record['税额'])),
    }
    if len(amounts) == 1 and re.search(r'免税|不征税', text) and Decimal(record['税额']) == 0:
        checks['金额与税额'] = Decimal(amounts[0]) == Decimal(record['金额'])
    names = re.findall(r'名称[：:]\s*([^\t\n]+)', text)
    ids = re.findall(r'统一社会信用代码/纳税人识别号[：:]\s*([0-9A-Z]{18})', text)
    expected = expected_parties(root, record)
    for index, side in enumerate(['购买方', '销售方']):
        checks[side + '名称'] = bool(len(names) == 2 and expected.get(side + '名称') and normalize(names[index]) == normalize(expected[side + '名称']))
        checks[side + '识别号'] = bool(len(ids) == 2 and expected.get(side + '识别号') and ids[index] == expected[side + '识别号'])
    return checks


def save_records(root, records):
    keys = list(dict.fromkeys(k for r in records for k in r))
    def write_csv(path, rows):
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=path.name + '.')
        try:
            with os.fdopen(fd, 'w', encoding='utf-8-sig', newline='') as out:
                writer = csv.DictWriter(out, fieldnames=keys)
                writer.writeheader()
                writer.writerows(rows)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary): os.unlink(temporary)
    write_csv(root / '发票查验核对总表.csv', records)
    for stem in {Path(r['PDF文件名']).stem for r in records}:
        write_csv(root / stem / '核对清单.csv', [r for r in records if Path(r['PDF文件名']).stem == stem])
    atomic_json(root / '.核对工作/manifest.json', records)


def verify_archived(root, record, source):
    """Read the final screenshot and all ledgers before reporting archival success."""
    relative = record['结果截图']
    expected = f"{Path(record['PDF文件名']).stem}/{record['页码']:03d}_{record['发票号码']}_查验结果.jpg"
    if relative != expected:
        raise RuntimeError('归档目录或文件名与原PDF、页码不一致')
    destination = root / relative
    digest = lambda file: hashlib.sha256(Path(file).read_bytes()).hexdigest()
    if not destination.is_file() or digest(destination) != digest(source):
        raise RuntimeError('归档截图回读失败或与原结果截图不一致')
    saved = next(r for r in load_records(root) if r['发票号码'] == record['发票号码'])
    keys = ['PDF文件名', '页码', '结果截图', '查验状态', '票面核对']
    if any(saved.get(k) != record.get(k) for k in keys):
        raise RuntimeError('manifest归档信息回读不一致')
    for ledger in [root / '发票查验核对总表.csv', destination.parent / '核对清单.csv']:
        with ledger.open(encoding='utf-8-sig', newline='') as stream:
            matching = [r for r in csv.DictReader(stream) if r['发票号码'] == record['发票号码']]
        if len(matching) != 1 or any(matching[0].get(k) != str(record.get(k)) for k in keys):
            raise RuntimeError(f'{ledger.name}归档信息回读不一致')
    return digest(destination)
