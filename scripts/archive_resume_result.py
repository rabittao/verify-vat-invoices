"""Archive a real platform result into the original PDF folder and recheck fields."""
import json
import re
import shutil
import sys
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[2]
import workspace_archive as checker

def compare_platform_text(record, text):
    return checker.compare_platform_text(root, record, text)


def archive(number, text_path, image_path):
    with checker.archive_lock(root):
        return _archive_locked(number, text_path, image_path)


def _archive_locked(number, text_path, image_path):
    records = checker.load_records(root)
    record = next(r for r in records if r['发票号码'] == number)
    text = Path(text_path).read_text(encoding='utf-8')
    # 只在详情区域校验票号，兼容新版标题，避免表单输入被当作返回数据。
    heading = re.search(r'(?:^|\n)(发票查验明细|发票详情)(?:\n|$)', text)
    detail = text[heading.end():] if heading else ''
    returned = re.search(r'发票号码[：:]\s*(\d{20})', detail)
    modern_ready = not heading or heading.group(1) != '发票详情' or ('当日查验次数' in detail and '打印' in detail)
    if not heading or not modern_ready or not returned or returned.group(1) != number:
        raise RuntimeError('返回发票号码未明确匹配本票，不归档为该票结果。')
    checks = compare_platform_text(record, detail)
    dest = root / Path(record['PDF文件名']).stem / f"{record['页码']:03d}_{number}_查验结果.jpg"
    source = Path(image_path)
    if source.stat().st_size < 1000 or source.read_bytes()[:2] != b'\xff\xd8':
        raise RuntimeError('缺少真实JPEG结果截图，不归档。')
    with Image.open(source) as image:
        image.verify()
    dest.parent.mkdir(parents=True, exist_ok=True)
    temporary = dest.with_suffix('.tmp')
    shutil.copyfile(source, temporary)
    temporary.replace(dest)
    record['结果截图'] = str(dest.relative_to(root))
    record['查验状态'] = '平台详情已取得，核对一致' if all(checks.values()) else '平台详情已取得，存在差异待复核'
    record['票面核对'] = '；'.join(f'{k}:{"一致" if v else "待复核"}' for k, v in checks.items())
    evidence = root / '.核对工作/运行证据' / number
    evidence.mkdir(parents=True, exist_ok=True)
    checker.atomic_json(evidence / '平台结果与核对.json', {'平台原文': text, '逐项核对': checks})
    checker.save_records(root, records)
    digest = checker.verify_archived(root, record, source)
    return {'invoice_number': number, 'verification_status': 'success', 'archive_check': record['查验状态'],
            'result_screenshot': record['结果截图'], 'source_pdf': record['PDF文件名'], 'page_number': record['页码'],
            'archive_verified': True, 'archive_sha256': digest}


def main():
    if sys.argv[1:] == ['--check']:
        records = checker.load_records(root)
        for record in records:
            checker.expected_parties(root, record)
        print('本地归档依赖及清单检查通过')
    elif sys.argv[1:] == ['--recover']:
        results = []
        records = {r['发票号码']: r for r in checker.load_records(root)}
        for text in sorted((root / 'verify-vat-invoices/output/resume').glob('*-platform.txt')):
            number = text.name.removesuffix('-platform.txt')
            record = records.get(number)
            if not record or (record.get('结果截图') and (root / record['结果截图']).is_file()): continue
            image = text.with_name(number + '-result.jpg')
            if image.is_file() and re.search(r'(?:^|\n)(发票查验明细|发票详情)(?:\n|$)', text.read_text()):
                checkpoint = text.with_name(number + '-success.json')
                prior = json.loads(checkpoint.read_text()) if checkpoint.is_file() else {}
                results.append({**prior, **archive(number, text, image)})
        print(json.dumps(results, ensure_ascii=False))
    else:
        print(json.dumps(archive(*sys.argv[1:]), ensure_ascii=False))


if __name__ == '__main__':
    main()
