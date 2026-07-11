import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_layout.dart';
import '../../core/theme/app_palette.dart';

const _ledgerGreen = AppPalette.primary;
const _ledgerGreenDeep = AppPalette.primaryDeep;
const _ledgerCanvas = AppPalette.canvas;
const _ledgerLine = AppPalette.lineSoft;
const _ledgerTextMuted = AppPalette.muted;

final ledgerInvoiceNumberProvider =
    StateProvider.autoDispose<String>((ref) => '');

final ledgerProvider = FutureProvider.autoDispose<List<LedgerItemModel>>((ref) {
  final invoiceNumber = ref.watch(ledgerInvoiceNumberProvider);
  return ref.watch(apiClientProvider).getInvoices(
        invoiceNumber: invoiceNumber,
      );
});

class LedgerPage extends ConsumerStatefulWidget {
  const LedgerPage({super.key});

  @override
  ConsumerState<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends ConsumerState<LedgerPage> {
  late final TextEditingController _invoiceNumberController;

  @override
  void initState() {
    super.initState();
    _invoiceNumberController = TextEditingController(
      text: ref.read(ledgerInvoiceNumberProvider),
    );
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    ref.read(ledgerInvoiceNumberProvider.notifier).state =
        _invoiceNumberController.text.trim();
    ref.invalidate(ledgerProvider);
  }

  void _clearFilter() {
    _invoiceNumberController.clear();
    ref.read(ledgerInvoiceNumberProvider.notifier).state = '';
    ref.invalidate(ledgerProvider);
  }

  Future<void> _createExport(
    BuildContext context, {
    required String exportType,
    required String successMessage,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final activeFilter = ref.read(ledgerInvoiceNumberProvider);
    try {
      await ref.read(apiClientProvider).createExport(
            exportType: exportType,
            invoiceNumber: activeFilter,
          );
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(successMessage)));
        context.push('/exports');
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('创建导出失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(ledgerProvider);
    final activeFilter = ref.watch(ledgerInvoiceNumberProvider);
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final token = ref.watch(authTokenProvider);
    return Scaffold(
      backgroundColor: _ledgerCanvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppPalette.pageGradient),
        child: RefreshIndicator(
          color: _ledgerGreen,
          onRefresh: () async => ref.refresh(ledgerProvider.future),
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              padding: AppLayout.pageInsets(
                constraints.maxWidth,
                top: 12,
                bottom: AppLayout.bottomNavHeight,
              ),
              children: [
                _LedgerHeaderBar(
                  onExportExcel: () => _createExport(
                    context,
                    exportType: 'invoice_list_excel',
                    successMessage: '已创建 Excel 导出任务',
                  ),
                  onExportPdf: () => _createExport(
                    context,
                    exportType: 'invoice_list_summary_pdf',
                    successMessage: '已创建汇总 PDF 导出任务',
                  ),
                ),
                const SizedBox(height: 14),
                _LedgerFilterPanel(
                  controller: _invoiceNumberController,
                  activeFilter: activeFilter,
                  onApply: _applyFilter,
                  onClear: _clearFilter,
                ),
                invoices.when(
                  loading: () => const _LedgerSummaryStrip(
                    totalText: '共 -- 条台账记录',
                    filterText: '正在同步',
                  ),
                  error: (_, __) => const _LedgerSummaryStrip(
                    totalText: '共 0 条台账记录',
                    filterText: '加载失败',
                  ),
                  data: (items) => _LedgerSummaryStrip(
                    totalText: '共 ${items.length} 条台账记录',
                    filterText: activeFilter.trim().isEmpty ? '全部记录' : '筛选中',
                  ),
                ),
                const SizedBox(height: 12),
                invoices.when(
                  loading: () => const _StateCard(
                    icon: Icons.inventory_2_outlined,
                    title: '正在加载台账',
                    message: '正在拉取最新入库发票，请稍候。',
                  ),
                  error: (error, _) => _StateCard(
                    icon: Icons.error_outline_rounded,
                    title: '台账加载失败',
                    message: '$error',
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return const _StateCard(
                        icon: Icons.receipt_long_outlined,
                        title: '暂无成功入库发票',
                        message: '当前筛选条件下没有可展示的台账记录。',
                      );
                    }
                    return _LedgerInvoicesGrid(
                      items: items,
                      baseUrl: baseUrl,
                      token: token,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LedgerHeaderBar extends StatelessWidget {
  const _LedgerHeaderBar({
    required this.onExportExcel,
    required this.onExportPdf,
  });

  final VoidCallback onExportExcel;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: AppPalette.heroGradient,
            border: Border.all(color: AppPalette.lineSoft),
            boxShadow: AppPalette.softShadow(0.45),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _LedgerTitleBlock(),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _LedgerExportButton(
                      label: '导出 Excel',
                      icon: Icons.grid_on_rounded,
                      onTap: onExportExcel,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LedgerExportButton(
                      label: '导出汇总 PDF',
                      icon: Icons.picture_as_pdf_rounded,
                      onTap: onExportPdf,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LedgerTitleBlock extends StatelessWidget {
  const _LedgerTitleBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '台账列表',
          style: TextStyle(
            color: AppPalette.primaryDeep,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        SizedBox(height: 6),
        Text(
          '查询、筛选与导出核验后的发票台账。',
          style: TextStyle(
            color: AppPalette.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _LedgerSummaryStrip extends StatelessWidget {
  const _LedgerSummaryStrip({
    required this.totalText,
    required this.filterText,
  });

  final String totalText;
  final String filterText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              totalText,
              style: const TextStyle(
                color: AppPalette.primaryDeep,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppPalette.primarySoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              filterText,
              style: const TextStyle(
                color: AppPalette.primary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerInvoicesGrid extends StatelessWidget {
  const _LedgerInvoicesGrid({
    required this.items,
    required this.baseUrl,
    required this.token,
  });

  final List<LedgerItemModel> items;
  final String baseUrl;
  final String? token;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = switch (constraints.maxWidth) {
          >= 1180 => 3,
          >= 760 => 2,
          _ => 1,
        };
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final invoice in items)
              SizedBox(
                width: cardWidth,
                child: _InvoiceCard(
                  invoice: invoice,
                  baseUrl: baseUrl,
                  token: token,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LedgerFilterPanel extends StatelessWidget {
  const _LedgerFilterPanel({
    required this.controller,
    required this.activeFilter,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController controller;
  final String activeFilter;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasFilter = activeFilter.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _ledgerLine),
        boxShadow: AppPalette.softShadow(0.35),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                isDense: false,
                filled: true,
                fillColor: const Color(0xFFF5FBFF),
                hintText: '输入发票号码搜索',
                hintStyle: const TextStyle(
                  color: Color(0xFF9AAAB8),
                  fontWeight: FontWeight.w800,
                ),
                prefixIcon: const Icon(
                  Icons.confirmation_number_outlined,
                  size: 22,
                  color: AppPalette.muted,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: AppPalette.lineSoft),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: AppPalette.lineSoft),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide:
                      const BorderSide(color: AppPalette.primary, width: 1.4),
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onApply(),
            ),
          ),
          const SizedBox(width: 10),
          _RoundFilterButton(
            onPressed: onApply,
            icon: Icons.search_rounded,
          ),
          const SizedBox(width: 8),
          _RoundFilterButton(
            onPressed: hasFilter
                ? onClear
                : () {
                    showModalBottomSheet<void>(
                      context: context,
                      builder: (context) => const SafeArea(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            '当前版本仅保留“发票号码”查询，其他筛选功能已按产品要求移除。',
                          ),
                        ),
                      ),
                    );
                  },
            icon: hasFilter ? Icons.close_rounded : Icons.tune_rounded,
          ),
        ],
      ),
    );
  }
}

class _RoundFilterButton extends StatelessWidget {
  const _RoundFilterButton({
    required this.onPressed,
    required this.icon,
  });

  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: _ledgerGreenDeep,
          backgroundColor: Colors.white,
          side: const BorderSide(color: _ledgerLine),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
        child: Icon(icon, size: 23),
      ),
    );
  }
}

class _LedgerExportButton extends StatelessWidget {
  const _LedgerExportButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 19),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppPalette.primary,
        side: const BorderSide(color: AppPalette.lineSoft),
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.baseUrl,
    required this.token,
  });

  final LedgerItemModel invoice;
  final String baseUrl;
  final String? token;

  @override
  Widget build(BuildContext context) {
    final amountText = _formatMoney(invoice.amountDisplay);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => context.go('/ledger/${invoice.invoiceId}'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _ledgerLine),
            boxShadow: AppPalette.softShadow(0.42),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      invoice.invoiceNumber,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.16,
                        fontWeight: FontWeight.w900,
                        color: _ledgerGreenDeep,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppPalette.successSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '核验成功',
                      style: TextStyle(
                        color: AppPalette.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _LedgerInfoCell(
                          label: '开票日期',
                          value: invoice.invoiceDate,
                        ),
                        const SizedBox(height: 10),
                        _LedgerInfoCell(
                          label: '金额',
                          value: amountText,
                        ),
                        const SizedBox(height: 10),
                        _LedgerInfoCell(
                          label: '来源任务',
                          value: invoice.sourceDisplay,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _LedgerScreenshotBadge(
                    hasScreenshot: invoice.hasScreenshot,
                    screenshotUrl: invoice.screenshotUrl,
                    baseUrl: baseUrl,
                    token: token,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5FBFF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppPalette.lineSoft),
                ),
                child: Column(
                  children: [
                    _LedgerFieldRow(
                      label: '销售方',
                      value: invoice.sellerDisplay,
                    ),
                    const SizedBox(height: 8),
                    _LedgerFieldRow(
                      label: '购买方',
                      value: invoice.buyerDisplay,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: AppPalette.muted,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      invoice.verificationDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ledgerTextMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Text(
                    '查看详情',
                    style: TextStyle(
                      color: _ledgerGreen,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.chevron_right_rounded, color: _ledgerGreen),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LedgerScreenshotBadge extends StatelessWidget {
  const _LedgerScreenshotBadge({
    required this.hasScreenshot,
    required this.screenshotUrl,
    required this.baseUrl,
    required this.token,
  });

  final bool hasScreenshot;
  final String? screenshotUrl;
  final String baseUrl;
  final String? token;

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = _resolveUrl(screenshotUrl);
    return Container(
      width: 84,
      height: 82,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: hasScreenshot ? const Color(0xFFEAF6FF) : AppPalette.cardSoft,
        border: Border.all(color: AppPalette.lineSoft),
        boxShadow: AppPalette.softShadow(0.16),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: _buildPreview(resolvedUrl)),
          Positioned(
            right: 7,
            bottom: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                hasScreenshot ? '1张' : '无',
                style: const TextStyle(
                  color: AppPalette.primaryDeep,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(String? resolvedUrl) {
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return Center(
        child: Icon(
          hasScreenshot
              ? Icons.image_rounded
              : Icons.image_not_supported_rounded,
          color: hasScreenshot ? AppPalette.primary : AppPalette.muted,
          size: 24,
        ),
      );
    }
    return Image.network(
      resolvedUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
      errorBuilder: (context, error, stackTrace) => Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: hasScreenshot ? AppPalette.primary : AppPalette.muted,
          size: 24,
        ),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }

  String? _resolveUrl(String? path) {
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    final raw = path.trim();
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) {
      return raw;
    }
    return Uri.parse(baseUrl).resolve(raw).toString();
  }
}

class _LedgerInfoCell extends StatelessWidget {
  const _LedgerInfoCell({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              color: _ledgerTextMuted,
              fontWeight: FontWeight.w900,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ledgerGreenDeep,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _LedgerFieldRow extends StatelessWidget {
  const _LedgerFieldRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 54,
          child: Text(
            label,
            style: const TextStyle(
              color: _ledgerTextMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: _ledgerGreenDeep,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _ledgerLine),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: _ledgerGreen),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: _ledgerGreenDeep,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ledgerTextMuted, height: 1.5),
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
