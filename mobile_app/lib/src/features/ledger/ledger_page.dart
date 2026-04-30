import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';

final ledgerInvoiceNumberProvider = StateProvider.autoDispose<String>((ref) => '');

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('台账'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'exports') {
                context.go('/exports');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('导出创建接口已就绪，下一步接确认弹层')),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export_excel', child: Text('导出 Excel')),
              PopupMenuItem(value: 'export_pdf', child: Text('导出汇总 PDF')),
              PopupMenuItem(value: 'exports', child: Text('导出记录')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(ledgerProvider.future),
        child: invoices.when(
          loading: () => const _CenteredMessage(message: '正在加载台账...'),
          error: (error, _) => _CenteredMessage(message: '台账加载失败：$error'),
          data: (items) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _invoiceNumberController,
                        decoration: InputDecoration(
                          prefixIcon:
                              const Icon(Icons.confirmation_number_outlined),
                          labelText: '发票号码',
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '清空',
                                onPressed: _clearFilter,
                                icon: const Icon(Icons.close),
                              ),
                              IconButton(
                                tooltip: '搜索',
                                onPressed: _applyFilter,
                                icon: const Icon(Icons.search),
                              ),
                            ],
                          ),
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _applyFilter(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Card(child: ListTile(title: Text('暂无成功入库发票')))
              else
                ...items.map((invoice) => _InvoiceCard(invoice: invoice)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice});

  final LedgerItemModel invoice;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => context.go('/ledger/${invoice.invoiceId}'),
        title: Text(invoice.invoiceNumber),
        subtitle: Text(
          '${invoice.sellerName ?? '-'} -> ${invoice.buyerName ?? '-'}\n'
          '${invoice.invoiceDate} | ${invoice.totalAmount} | ${invoice.lastVerifiedAt}',
        ),
        trailing: invoice.hasScreenshot
            ? const Icon(Icons.image_outlined)
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.35),
        Center(child: Text(message)),
      ],
    );
  }
}
