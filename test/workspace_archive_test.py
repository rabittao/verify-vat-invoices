import json
import sys
import tempfile
import unittest
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import archive_resume_result as archiver
import workspace_archive as checker


class ArchiveTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.original_root = archiver.root
        archiver.root = self.root
        folder = self.root / '.核对工作/OCR'
        folder.mkdir(parents=True)
        self.record = {'PDF文件名': 'sample.pdf', '页码': 21, '发票号码': '12345678901234567890',
                       '开票日期': '20260917', '金额': '1.48', '税额': '0.04', '价税合计': '1.52',
                       '结果截图': '', '查验状态': '待查验'}
        checker.atomic_json(self.root / '.核对工作/manifest.json', [self.record])
        checker.atomic_json(folder / 'sample__021.json', [
            {'x': .1, 'y': .6, 'text': '名称：购买方'},
            {'x': .1, 'y': .58, 'text': '统一社会信用代码/纳税人识别号：12345678901234567AB'},
            {'x': .6, 'y': .6, 'text': '名称：销售方'},
            {'x': .6, 'y': .58, 'text': '统一社会信用代码/纳税人识别号：12345678901234567CD'},
        ])
        self.text = self.root / 'platform.txt'
        self.text.write_text('发票查验明细\n发票号码：12345678901234567890\t开票日期：2026年09月17日\n'
                             '名称：\t购买方\t名称：\t销售方\n'
                             '统一社会信用代码/纳税人识别号：\t12345678901234567AB\t统一社会信用代码/纳税人识别号：\t12345678901234567CD\n'
                             '合计\t￥1.48\t￥0.04\n价税合计（大写）\t壹圆伍角贰分\t（小写）￥1.52')
        self.image = self.root / 'result.jpg'
        Image.new('RGB', (800, 600), 'white').save(self.image)

    def tearDown(self):
        archiver.root = self.original_root
        self.temporary.cleanup()

    def test_success_archives_without_external_checker_and_updates_all_ledgers(self):
        result = archiver.archive(self.record['发票号码'], self.text, self.image)
        self.assertEqual(result['archive_check'], '平台详情已取得，核对一致')
        self.assertTrue(result['archive_verified'])
        self.assertEqual(len(result['archive_sha256']), 64)
        self.assertTrue((self.root / result['result_screenshot']).is_file())
        self.assertEqual(checker.load_records(self.root)[0]['结果截图'], result['result_screenshot'])
        self.assertIn(result['result_screenshot'], (self.root / 'sample/核对清单.csv').read_text(encoding='utf-8-sig'))
        self.assertIn(result['result_screenshot'], (self.root / '发票查验核对总表.csv').read_text(encoding='utf-8-sig'))

    def test_modern_details_and_multiline_totals_archive(self):
        text = self.text.read_text().replace('发票查验明细', '发票详情\n当日查验次数：第1次\n打印')
        self.text.write_text(text.replace('合计\t￥1.48\t￥0.04', '合计\n¥1.48\n¥0.04'))
        result = archiver.archive(self.record['发票号码'], self.text, self.image)
        self.assertEqual(result['archive_check'], '平台详情已取得，核对一致')
        self.assertTrue(result['archive_verified'])

    def test_form_number_cannot_mask_different_returned_number(self):
        text = self.text.read_text().replace(self.record['发票号码'], '99999999999999999999')
        self.text.write_text('发票号码：' + self.record['发票号码'] + '\n' + text)
        with self.assertRaisesRegex(RuntimeError, '未明确匹配'):
            archiver.archive(self.record['发票号码'], self.text, self.image)

    def test_non_taxable_multiline_single_amount(self):
        record = {**self.record, '金额': '1.52', '税额': '0.00'}
        text = self.text.read_text().replace('合计\t￥1.48\t￥0.04', '不征税\n合计\n¥1.52\n*')
        self.assertTrue(checker.compare_platform_text(self.root, record, text)['金额与税额'])
        self.assertFalse(checker.compare_platform_text(self.root, record, text.replace('不征税', '3%'))['金额与税额'])
        self.assertFalse(checker.compare_platform_text(self.root, record, text.replace('¥1.52\n*', '¥1.51\n*'))['金额与税额'])
        self.assertFalse(checker.compare_platform_text(self.root, record, text.replace('¥1.52\n*', '¥1.52\n¥0.01'))['金额与税额'])

    def test_wrong_invoice_refuses_archive(self):
        self.text.write_text(self.text.read_text().replace(self.record['发票号码'], '99999999999999999999'))
        with self.assertRaisesRegex(RuntimeError, '未明确匹配'):
            archiver.archive(self.record['发票号码'], self.text, self.image)
        self.assertEqual(checker.load_records(self.root)[0]['结果截图'], '')

    def test_mismatch_is_preserved_as_review_required(self):
        self.text.write_text(self.text.read_text().replace('销售方', '另一公司'))
        result = archiver.archive(self.record['发票号码'], self.text, self.image)
        self.assertEqual(result['archive_check'], '平台详情已取得，存在差异待复核')

    def test_corrupt_screenshot_never_archived(self):
        self.image.write_bytes(b'\xff\xd8' + b'x' * 1500)
        with self.assertRaises(Exception):
            archiver.archive(self.record['发票号码'], self.text, self.image)
        self.assertEqual(checker.load_records(self.root)[0]['结果截图'], '')

    def test_ledger_readback_rejects_missing_archive_path(self):
        archiver.archive(self.record['发票号码'], self.text, self.image)
        record = checker.load_records(self.root)[0]
        ledger = self.root / 'sample/核对清单.csv'
        ledger.write_text(ledger.read_text(encoding='utf-8-sig').replace(record['结果截图'], 'missing.jpg'), encoding='utf-8-sig')
        with self.assertRaisesRegex(RuntimeError, '核对清单.csv归档信息回读不一致'):
            checker.verify_archived(self.root, record, self.image)


if __name__ == '__main__':
    unittest.main()
