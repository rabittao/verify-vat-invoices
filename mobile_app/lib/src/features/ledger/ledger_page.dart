import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';

const _ledgerGreen = Color(0xFF0B6E4F);
const _ledgerGreenDeep = Color(0xFF073B2A);
const _ledgerGreenSoft = Color(0xFFE8F3EE);
const _ledgerCanvas = Color(0xFFF4F8F5);
const _ledgerLine = Color(0xFFD7E4DC);
const _ledgerTextMuted = Color(0xFF5F746A);

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

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(ledgerProvider);
    final activeFilter = ref.watch(ledgerInvoiceNumberProvider);
    return Scaffold(
      backgroundColor: _ledgerCanvas,
      appBar: AppBar(
        backgroundColor: _ledgerCanvas,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: const Text('台账'),
        actions: [
          IconButton(
            tooltip: '导出记录',
            onPressed: () => context.push('/exports'),
            icon: const Icon(Icons.history_toggle_off_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'exports') {
                context.push('/exports');
                return;
              }
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(apiClientProvider).createExport(
                      exportType: value == 'export_excel'
                          ? 'invoice_list_excel'
                          : 'invoice_list_summary_pdf',
                      invoiceNumber: activeFilter,
                    );
                if (!context.mounted) {
                  return;
                }
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      value == 'export_excel'
                          ? '已创建 Excel 导出任务'
                          : '已创建汇总 PDF 导出任务',
                    ),
                  ),
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
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export_excel', child: Text('导出 Excel')),
              PopupMenuItem(value: 'export_pdf', child: Text('导出汇总 PDF')),
              PopupMenuItem(value: 'exports', child: Text('查看导出记录')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF7FBF8),
              Color(0xFFF1F6F2),
            ],
          ),
        ),
        child: RefreshIndicator(
          color: _ledgerGreen,
          onRefresh: () async => ref.refresh(ledgerProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _LedgerFilterPanel(
                controller: _invoiceNumberController,
                activeFilter: activeFilter,
                onApply: _applyFilter,
                onClear: _clearFilter,
              ),
              const SizedBox(height: 12),
              invoices.when(
                loading: () => const Text(
                  '共 -- 条台账记录',
                  style: TextStyle(color: _ledgerTextMuted),
                ),
                error: (_, __) => const Text(
                  '共 0 条台账记录',
                  style: TextStyle(color: _ledgerTextMuted),
                ),
                data: (items) => Text(
                  '共 ${items.length} 条台账记录',
                  style: const TextStyle(color: _ledgerTextMuted),
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
                  return Column(
                    children: [
                      for (final invoice in items) ...[
                        _InvoiceCard(invoice: invoice),
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ledgerLine),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF7F8F5),
                hintText: '输入发票号码搜索',
                prefixIcon:
                    const Icon(Icons.confirmation_number_outlined, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onApply(),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onApply,
            style: OutlinedButton.styleFrom(
              foregroundColor: _ledgerGreenDeep,
              side: const BorderSide(color: _ledgerLine),
              minimumSize: const Size(42, 42),
              padding: EdgeInsets.zero,
            ),
            child: const Icon(Icons.search_rounded, size: 18),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
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
            style: OutlinedButton.styleFrom(
              foregroundColor: _ledgerGreenDeep,
              side: const BorderSide(color: _ledgerLine),
              minimumSize: const Size(42, 42),
              padding: EdgeInsets.zero,
            ),
            child: Icon(hasFilter ? Icons.close_rounded : Icons.tune_rounded,
                size: 18),
          ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice});

  final LedgerItemModel invoice;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/ledger/${invoice.invoiceId}'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _ledgerLine),
          ),
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
                        Text(
                          invoice.invoiceNumber,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _ledgerGreenDeep,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '开票日期 ${invoice.invoiceDate}',
                          style: const TextStyle(color: _ledgerTextMuted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _ledgerGreenSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          '价税合计',
                          style: TextStyle(
                            fontSize: 12,
                            color: _ledgerTextMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          invoice.amountDisplay,
                          style: const TextStyle(
                            color: _ledgerGreen,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _ledgerCanvas,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    _LedgerFieldRow(label: '销售方', value: invoice.sellerDisplay),
                    const SizedBox(height: 10),
                    _LedgerFieldRow(label: '购买方', value: invoice.buyerDisplay),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoChip(
                    icon: invoice.hasScreenshot
                        ? Icons.photo_library_outlined
                        : Icons.image_not_supported_outlined,
                    label: invoice.hasScreenshot ? '已留存截图' : '暂无截图',
                    foregroundColor: invoice.hasScreenshot
                        ? _ledgerGreenDeep
                        : _ledgerTextMuted,
                    backgroundColor: invoice.hasScreenshot
                        ? _ledgerGreenSoft
                        : const Color(0xFFF2F4F3),
                  ),
                  _InfoChip(
                    icon: Icons.schedule_outlined,
                    label: invoice.verificationDisplay,
                    foregroundColor: _ledgerTextMuted,
                    backgroundColor: const Color(0xFFF6F3E8),
                  ),
                  _InfoChip(
                    icon: Icons.work_history_outlined,
                    label: invoice.sourceDisplay,
                    foregroundColor: const Color(0xFF6A5531),
                    backgroundColor: const Color(0xFFF7F0E1),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Text(
                    '查看截图与字段详情',
                    style: TextStyle(
                      color: _ledgerGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final IconData icon;
  final String label;
  final Color foregroundColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foregroundColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
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
