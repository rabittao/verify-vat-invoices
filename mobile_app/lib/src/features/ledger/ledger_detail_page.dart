import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';

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
      appBar: AppBar(title: Text('台账详情 #$invoiceId')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('台账详情加载失败：$error')),
        data: (invoice) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    height: 220,
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: _ScreenshotPreview(
                      screenshotUrl: invoice.screenshotUrl,
                      baseUrl: baseUrl,
                      token: token,
                    ),
                  ),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.tonal(
                        onPressed: () {},
                        child: const Text('导出详情 PDF'),
                      ),
                      FilledButton.tonal(
                        onPressed: () {},
                        child: Text(invoice.sourceJobLabel ?? '来源任务'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _InfoTile(title: '发票号码', value: invoice.invoiceNumber),
            _InfoTile(title: '开票日期', value: invoice.invoiceDate),
            _InfoTile(title: '价税合计', value: invoice.totalAmount ?? '-'),
            _InfoTile(title: '销售方', value: invoice.sellerName ?? '-'),
            _InfoTile(title: '购买方', value: invoice.buyerName ?? '-'),
          ],
        ),
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
      return const Text('暂无核验截图');
    }

    final resolvedUrl = _resolveUrl(baseUrl, screenshotUrl!);
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(title: const Text('核验截图')),
            body: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: _NetworkScreenshotImage(
              resolvedUrl: resolvedUrl,
              token: token,
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  '点击查看大图',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
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
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Text('核验截图加载失败：$error'),
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(title: Text(title), subtitle: Text(value));
  }
}
