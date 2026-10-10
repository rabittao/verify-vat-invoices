"""Archive a real platform result into the original PDF folder and recheck fields."""
import json
import re
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / '查验程序'))
import invoice_check as checker

def compare_platform_text(record, text):
    checks = checker.compare_result(record, text)
    # 旧版查验弹窗按表格行读取：先列购销标题，再交错列出名称和税号。
    names = re.search(r'名称[：:]\s*\t([^\t\n]+)\t名称[：:]\s*\t([^\t\n]+)', text)
    ids = re.search(r'统一社会信用代码/纳税人识别号[：:]\s*\t([0-9A-Z]{18})\t统一社会信用代码/纳税人识别号[：:]\s*\t([0-9A-Z]{18})', text)
    expected = checker.expected_parties(record)
    if names and ids:
        for side, name, taxid in zip(['购买方', '销售方'], names.groups(), ids.groups()):
            checks[side + '名称'] = checker.normalize(name) == checker.normalize(expected.get(side + '名称', ''))
            checks[side + '识别号'] = taxid == expected.get(side + '识别号')
    return checks


def main():
    number, text_path, image_path = sys.argv[1:]
    records = checker.load_records()
    record = next(r for r in records if r['发票号码'] == number)
    text = Path(text_path).read_text(encoding='utf-8')
    returned = re.search(r'发票号码[：:]\s*(\d{20})', text)
    if not returned or returned.group(1) != number:
        raise RuntimeError('返回发票号码未明确匹配本票，不归档为该票结果。')
    checks = compare_platform_text(record, text)
    dest = root / Path(record['PDF文件名']).stem / f"{record['页码']:03d}_{number}_查验结果.jpg"
    shutil.copyfile(image_path, dest)
    record['结果截图'] = str(dest.relative_to(root))
    record['查验状态'] = '平台详情已取得，核对一致' if all(checks.values()) else '平台详情已取得，存在差异待复核'
    record['票面核对'] = '；'.join(f'{k}:{"一致" if v else "待复核"}' for k, v in checks.items())
    evidence = root / '.核对工作/运行证据' / number
    evidence.mkdir(parents=True, exist_ok=True)
    checker.atomic_json(evidence / '平台结果与核对.json', {'平台原文': text, '逐项核对': checks})
    checker.save_records(records)
    print(record['查验状态'])


if __name__ == '__main__':
    main()
