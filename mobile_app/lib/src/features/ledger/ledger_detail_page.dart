import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';

const _detailGreen = Color(0xFF0B6E4F);
const _detailGreenDeep = Color(0xFF073B2A);
const _detailCanvas = Color(0xFFF4F8F5);
const _detailPanel = Color(0xFFE8F3EE);
const _detailLine = Color(0xFFD7E4DC);
const _detailMuted = Color(0xFF5F746A);

final ledgerDetailProvider =
    FutureProvider.autoDispose.family<LedgerDetailModel, int>((ref, invoiceId) {
  return ref.watch(apiClientProvider).getInvoiceDetail(invoiceId);
});

class LedgerDetailPage extends ConsumerWidget {
  const LedgerDetailPage({
    required this.invoiceId,
    super.key,
  });

  final int invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(ledgerDetailProvider(invoiceId));
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final token = ref.watch(authTokenProvider);
    return Scaffold(
      backgroundColor: _detailCanvas,
      appBar: AppBar(
        backgroundColor: _detailCanvas,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: const Text('台账详情'),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FBF9), Color(0xFFF2F7F3)],
          ),
        ),
        child: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('台账详情加载失败：$error')),
          data: (invoice) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _DetailHeroCard(
                invoice: invoice,
              ),
              const SizedBox(height: 14),
              _ScreenshotPanel(
                invoice: invoice,
                baseUrl: baseUrl,
                token: token,
              ),
              const SizedBox(height: 14),
              _SourceTaskPanel(
                invoice: invoice,
                onSourcePressed: () {
                  final sourceJobId = invoice.sourceJobId;
                  if (sourceJobId == null || sourceJobId.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('当前台账未关联来源任务')),
                    );
                    return;
                  }
                  context.go('/tasks/$sourceJobId');
                },
              ),
              const SizedBox(height: 14),
              _BottomActionBar(
                onExportPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(apiClientProvider).createExport(
                          exportType: 'invoice_detail_pdf',
                          invoiceId: invoice.invoiceId,
                        );
                    if (!context.mounted) {
                      return;
                    }
                    messenger.showSnackBar(
                      const SnackBar(content: Text('已创建详情 PDF 导出任务')),
                    );
                    context.push('/exports');
                  } catch (error) {
                    if (!context.mounted) {
                      return;
                    }
                    messenger.showSnackBar(
                      SnackBar(content: Text('创建导出失败：$error')),
                    );
                  }
                },
                onSourcePressed: () {
                  final sourceJobId = invoice.sourceJobId;
                  if (sourceJobId == null || sourceJobId.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('当前台账未关联来源任务')),
                    );
                    return;
                  }
                  context.go('/tasks/$sourceJobId');
                },
              ),
              const SizedBox(height: 14),
              _FieldPanel(
                children: [
                  _DetailFieldTile(
                    label: '发票号码',
                    value: invoice.invoiceNumber,
                    accent: true,
                  ),
                  _DetailFieldTile(label: '开票日期', value: invoice.invoiceDate),
                  _DetailFieldTile(label: '价税合计', value: invoice.amountDisplay),
                  _DetailFieldTile(label: '销售方', value: invoice.sellerDisplay),
                  _DetailFieldTile(label: '购买方', value: invoice.buyerDisplay),
                  _DetailFieldTile(label: '来源任务', value: invoice.sourceDisplay),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailHeroCard extends StatelessWidget {
  const _DetailHeroCard({
    required this.invoice,
  });

  final LedgerDetailModel invoice;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_detailGreen, _detailGreenDeep],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    invoice.invoiceNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _HeroStatusChip(label: invoice.hasScreenshot ? '核验成功' : '截图缺失'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HeroInfoLine(label: '开票日期', value: invoice.invoiceDate),
                      const SizedBox(height: 8),
                      _HeroInfoLine(label: '销售方', value: invoice.sellerDisplay),
                      const SizedBox(height: 8),
                      _HeroInfoLine(label: '购买方', value: invoice.buyerDisplay),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '价税合计',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.76),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      invoice.amountDisplay,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStatusChip extends StatelessWidget {
  const _HeroStatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeroInfoLine extends StatelessWidget {
  const _HeroInfoLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.74),
          fontSize: 13,
        ),
        children: [
          TextSpan(text: '$label  '),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenshotPanel extends StatelessWidget {
  const _ScreenshotPanel({
    required this.invoice,
    required this.baseUrl,
    required this.token,
  });

  final LedgerDetailModel invoice;
  final String baseUrl;
  final String? token;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _detailLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '核验截图（脱敏）',
            style: TextStyle(
              color: _detailGreenDeep,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 240,
            decoration: BoxDecoration(
              color: _detailPanel,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _ScreenshotPreview(
                  screenshotUrl: invoice.screenshotUrl,
                  baseUrl: baseUrl,
                  token: token,
                ),
                const Positioned(
                  right: 12,
                  bottom: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xAA1A1A1A),
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Text(
                        '1/1',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceTaskPanel extends StatelessWidget {
  const _SourceTaskPanel({
    required this.invoice,
    required this.onSourcePressed,
  });

  final LedgerDetailModel invoice;
  final VoidCallback onSourcePressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _detailLine),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _detailPanel,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.description_outlined, color: _detailGreen),
        ),
        title: const Text(
          '来源任务',
          style: TextStyle(color: _detailMuted, fontSize: 13),
        ),
        subtitle: Text(
          invoice.sourceDisplay,
          style: const TextStyle(
            color: Color(0xFF20332B),
            fontWeight: FontWeight.w700,
          ),
        ),
        trailing: OutlinedButton(
          onPressed: onSourcePressed,
          child: const Text('查看任务'),
        ),
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.onExportPressed,
    required this.onSourcePressed,
  });

  final VoidCallback onExportPressed;
  final VoidCallback onSourcePressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _detailLine),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onExportPressed,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('导出详情 PDF'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  builder: (context) => SafeArea(
                    child: ListTile(
                      leading: const Icon(Icons.share_outlined),
                      title: const Text('分享'),
                      subtitle: const Text('当前版本可先通过导出详情 PDF 进行分享。'),
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('分享'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  builder: (context) => SafeArea(
                    child: ListTile(
                      leading: const Icon(Icons.work_history_outlined),
                      title: const Text('更多'),
                      subtitle: const Text('查看来源任务'),
                      onTap: () {
                        Navigator.of(context).pop();
                        onSourcePressed();
                      },
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.more_horiz_rounded),
              label: const Text('更多'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenshotPreview extends StatelessWidget {
  const _ScreenshotPreview({
    required this.screenshotUrl,
    required this.baseUrl,
    required this.token,
  });

  final String? screenshotUrl;
  final String baseUrl;
  final String? token;

  @override
  Widget build(BuildContext context) {
    if (screenshotUrl == null || screenshotUrl!.isEmpty) {
      return Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: 40, color: Colors.white70),
            SizedBox(height: 10),
            Text(
              '暂无核验截图',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    final resolvedUrl = _resolveUrl(baseUrl, screenshotUrl!);
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text('核验截图'),
            ),
            body: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(
                child: _NetworkScreenshotImage(
                  resolvedUrl: resolvedUrl,
                  token: token,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
      child: _NetworkScreenshotImage(
        resolvedUrl: resolvedUrl,
        token: token,
        fit: BoxFit.cover,
      ),
    );
  }

  String _resolveUrl(String baseUrl, String path) {
    final uri = Uri.tryParse(path);
    if (uri != null && uri.hasScheme) {
      return path;
    }
    return Uri.parse(baseUrl).resolve(path).toString();
  }
}

class _NetworkScreenshotImage extends StatelessWidget {
  const _NetworkScreenshotImage({
    required this.resolvedUrl,
    required this.token,
    required this.fit,
  });

  final String resolvedUrl;
  final String? token;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      resolvedUrl,
      fit: fit,
      width: double.infinity,
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
      errorBuilder: (context, error, stackTrace) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              '核验截图加载失败：$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      },
    );
  }
}

class _FieldPanel extends StatelessWidget {
  const _FieldPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _detailLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10073B2A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _DetailFieldTile extends StatelessWidget {
  const _DetailFieldTile({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: accent ? _detailPanel : _detailCanvas,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(
                color: _detailMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: accent ? _detailGreenDeep : const Color(0xFF20332B),
                fontSize: accent ? 16 : 15,
                fontWeight: accent ? FontWeight.w700 : FontWeight.w500,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
