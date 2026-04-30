import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';

final exportHistoryProvider =
    FutureProvider.autoDispose<List<ExportRecordModel>>((ref) {
  return ref.watch(apiClientProvider).getExports();
});

class ExportHistoryPage extends ConsumerWidget {
  const ExportHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exports = ref.watch(exportHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('导出记录')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(exportHistoryProvider.future),
        child: exports.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              ListView(children: [ListTile(title: Text('导出记录加载失败：$error'))]),
          data: (items) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (items.isEmpty)
                const Card(child: ListTile(title: Text('暂无导出记录')))
              else
                ...items.map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(item.fileName ?? item.exportType),
                      subtitle: Text('${item.status} | ${item.exportId}'),
                      trailing: Icon(item.downloadUrl == null
                          ? Icons.hourglass_empty_outlined
                          : Icons.download_done_outlined),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
