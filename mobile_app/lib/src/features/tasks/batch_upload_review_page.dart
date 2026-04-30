import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../router.dart';
import 'task_list_page.dart';

class BatchUploadReviewPage extends ConsumerWidget {
  const BatchUploadReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(selectedUploadFilesProvider);
    final totalSize = files.fold<int>(0, (sum, file) => sum + file.sizeBytes);
    return Scaffold(
      appBar: AppBar(title: const Text('批量确认')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              '已选择 ${files.length} 个 PDF，总大小 ${(totalSize / 1024 / 1024).toStringAsFixed(2)} MB'),
          const SizedBox(height: 16),
          if (files.isEmpty)
            const Card(child: ListTile(title: Text('没有待上传文件')))
          else
            ...files.map(
              (file) => Card(
                child: ListTile(
                  title: Text(file.name),
                  subtitle:
                      Text('${(file.sizeBytes / 1024).toStringAsFixed(1)} KB'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      final next = [...files]..remove(file);
                      ref.read(selectedUploadFilesProvider.notifier).state =
                          next;
                    },
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: files.isEmpty
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      messenger.showSnackBar(
                          const SnackBar(content: Text('正在上传批量任务...')));
                      final jobId =
                          await ref.read(apiClientProvider).uploadTask(files);
                      ref.read(selectedUploadFilesProvider.notifier).state =
                          const [];
                      ref.invalidate(taskListProvider);
                      if (context.mounted) {
                        context.go('/tasks/$jobId');
                      }
                    } catch (error) {
                      messenger
                          .showSnackBar(SnackBar(content: Text('上传失败：$error')));
                    }
                  },
            child: const Text('开始核验'),
          ),
        ],
      ),
    );
  }
}
