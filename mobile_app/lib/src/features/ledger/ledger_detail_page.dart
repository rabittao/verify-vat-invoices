import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_layout.dart';
import '../../core/theme/app_palette.dart';

const _detailGreenDeep = AppPalette.primaryDeep;
const _detailCanvas = AppPalette.canvas;
const _detailLine = AppPalette.lineSoft;
const _detailMuted = AppPalette.muted;

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
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: '返回台账',
          onPressed: () => context.go('/ledger'),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: const Text('台账详情'),
        actions: [
          IconButton(
            tooltip: '分享',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('当前版本可先导出详情 PDF 后分享')),
              );
            },
            icon: const Icon(Icons.share_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppPalette.pageGradient),
        child: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('台账详情加载失败：$error')),
          data: (invoice) => LayoutBuilder(
            builder: (context, constraints) {
              final pageInsets = AppLayout.pageInsets(
                constraints.maxWidth,
                top: 10,
                bottom: 126,
              );
              final horizontal = pageInsets.left;
              return Stack(
                children: [
                  ListView(
                    padding: pageInsets,
                    children: [
                      _LedgerDetailDashboard(
                        invoice: invoice,
                        baseUrl: baseUrl,
                        token: token,
                      ),
                    ],
                  ),
                  Positioned(
                    left: horizontal,
                    right: horizontal,
                    bottom: 16,
                    child: SafeArea(
                      top: false,
                      child: _BottomActionBar(
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
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LedgerDetailDashboard extends StatelessWidget {
  const _LedgerDetailDashboard({
    required this.invoice,
    required this.baseUrl,
    required this.token,
  });

  final LedgerDetailModel invoice;
  final String baseUrl;
  final String? token;

  @override
  Widget build(BuildContext context) {
    final summaryColumn = Column(
      children: [
        _DetailHeroCard(invoice: invoice),
        const SizedBox(height: 14),
        _FieldPanel(
          children: [
            _DetailFieldTile(
              label: '发票号码',
              value: invoice.invoiceNumber,
              accent: true,
            ),
            _DetailFieldTile(
              label: '开票日期',
              value: invoice.invoiceDate,
            ),
            _DetailFieldTile(
              label: '销售方',
              value: invoice.sellerDisplay,
              caption: '统一社会信用代码：-',
            ),
            _DetailFieldTile(
              label: '购买方',
              value: invoice.buyerDisplay,
              caption: '统一社会信用代码：-',
            ),
          ],
        ),
      ],
    );
    final screenshotPanel = _ScreenshotPanel(
      invoice: invoice,
      baseUrl: baseUrl,
      token: token,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              summaryColumn,
              const SizedBox(height: 14),
              screenshotPanel,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: summaryColumn),
            const SizedBox(width: 16),
            Expanded(flex: 5, child: screenshotPanel),
          ],
        );
      },
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
        borderRadius: BorderRadius.circular(26),
        color: Colors.white,
        border: Border.all(color: AppPalette.lineSoft),
        boxShadow: AppPalette.softShadow(0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '价税合计',
                        style: TextStyle(
                          color: AppPalette.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatMoney(invoice.amountDisplay),
                        style: const TextStyle(
                          color: AppPalette.text,
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _HeroStatusChip(label: invoice.hasScreenshot ? '核验成功' : '截图缺失'),
              ],
            ),
            const SizedBox(height: 18),
            _HeroInfoLine(label: '开票日期', value: invoice.invoiceDate),
            const SizedBox(height: 8),
            _HeroInfoLine(label: '发票类型', value: invoice.invoiceTypeDisplay),
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
        color: AppPalette.primarySoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.line),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppPalette.primary,
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
          color: AppPalette.muted,
          fontSize: 13,
        ),
        children: [
          TextSpan(text: '$label  '),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: AppPalette.text,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _detailLine),
        boxShadow: AppPalette.softShadow(0.28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '核验截图',
                  style: TextStyle(
                    color: _detailGreenDeep,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppPalette.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.open_in_full_rounded,
                  color: AppPalette.primary,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final previewHeight =
                  (constraints.maxWidth * 0.62).clamp(210.0, 360.0);
              return Container(
                height: previewHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppPalette.lineSoft),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ScreenshotPreview(
                      screenshotUrl: invoice.fullscreenScreenshotUrl ??
                          invoice.screenshotUrl,
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
              );
            },
          ),
        ],
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
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _detailLine),
        boxShadow: AppPalette.softShadow(0.36),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onSourcePressed,
              icon: const Icon(Icons.article_outlined),
              label: const Text('查看任务'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 54),
                foregroundColor: AppPalette.primaryDeep,
                side: const BorderSide(color: AppPalette.lineSoft),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: onExportPressed,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('导出详情 PDF'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 54),
                backgroundColor: AppPalette.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
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
        fit: BoxFit.contain,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _detailLine),
        boxShadow: const [
          BoxShadow(
            color: AppPalette.shadow,
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _DetailFieldTile extends StatelessWidget {
  const _DetailFieldTile({
    required this.label,
    required this.value,
    this.caption,
    this.accent = false,
  });

  final String label;
  final String value;
  final String? caption;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: accent ? AppPalette.primarySoft : AppPalette.cardSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(
                color: _detailMuted,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: accent ? _detailGreenDeep : AppPalette.text,
                    fontSize: accent ? 17 : 16,
                    fontWeight: accent ? FontWeight.w900 : FontWeight.w700,
                    height: 1.32,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    caption!,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      color: _detailMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMoney(String value) {
  final raw = value.trim();
  if (raw.isEmpty || raw == '-') {
    return '-';
  }
  if (raw.startsWith('¥') || raw.startsWith('￥')) {
    return raw;
  }
  return '¥$raw';
}
