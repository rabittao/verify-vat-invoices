import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';
import '../../router.dart';

final taskListProvider = FutureProvider.autoDispose<TaskListState>((ref) async {
  final state = await ref.watch(apiClientProvider).getTasks();
  if (state.runningTasks.isNotEmpty) {
    final timer = Timer(const Duration(seconds: 3), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return state;
});

class TaskListPage extends ConsumerWidget {
  const TaskListPage({super.key});

  static const maxUploadFiles = 10;
  static const maxTotalBytes = 50 * 1024 * 1024;
  static const maxSingleBytes = 15 * 1024 * 1024;

  Future<void> _pickPdfFiles(BuildContext context, WidgetRef ref) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, '打开文件选择器失败：$error');
      }
      return;
    }
    if (result == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final files = result.files;
    final drafts = <UploadDraft>[];
    final totalBytes = files.fold<int>(0, (sum, file) => sum + file.size);
    if (files.length > maxUploadFiles) {
      _showMessage(context, '最多上传 10 个 PDF');
      return;
    }
    if (totalBytes > maxTotalBytes ||
        files.any((file) => file.size > maxSingleBytes)) {
      _showMessage(context, '文件数量或大小超过限制');
      return;
    }
    for (final file in files) {
      final bytes = file.bytes;
      if (bytes == null) {
        _showMessage(context, '无法读取文件：${file.name}');
        return;
      }
      drafts.add(
          UploadDraft(name: file.name, bytes: bytes, sizeBytes: file.size));
    }
    if (drafts.length == 1) {
      await _uploadAndOpenTask(context, ref, drafts);
      return;
    }
    if (!context.mounted) {
      return;
    }
    ref.read(selectedUploadFilesProvider.notifier).state = drafts;
    context.go('/tasks/upload-review');
  }

  Future<void> _uploadAndOpenTask(
      BuildContext context, WidgetRef ref, List<UploadDraft> drafts) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(const SnackBar(content: Text('正在上传并创建核验任务...')));
      final jobId = await ref.read(apiClientProvider).uploadTask(drafts);
      ref.invalidate(taskListProvider);
      if (context.mounted) {
        context.go('/tasks/$jobId');
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('上传失败：$error')));
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskList = ref.watch(taskListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('任务')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pickPdfFiles(context, ref),
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('上传发票'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(taskListProvider.future),
        child: taskList.when(
          loading: () => const _CenteredMessage(message: '正在加载任务...'),
          error: (error, _) => _CenteredMessage(message: '任务加载失败：$error'),
          data: (state) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _SectionHeader(title: '进行中', subtitle: '后台任务完成后会刷新到已完成区块。'),
              if (state.runningTasks.isEmpty)
                const _EmptyCard(message: '当前没有进行中的任务')
              else
                ...state.runningTasks.map((task) => _TaskCard(task: task)),
              const SizedBox(height: 24),
              _SectionHeader(
                title: '已完成',
                subtitle: '共 ${state.completedPageInfo.total} 个历史任务，按时间倒序展示。',
              ),
              if (state.completedTasks.isEmpty)
                const _EmptyCard(message: '还没有已完成任务')
              else
                ...state.completedTasks
                    .map((task) => _TaskCard(task: task, isCompleted: true)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    this.isCompleted = false,
  });

  final TaskCardModel task;
  final bool isCompleted;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => context.go('/tasks/${task.jobId}'),
        title: Text(task.title),
        subtitle: Text(
            '成功 ${task.successCount} / 失败 ${task.failedCount} / 跳过 ${task.skippedCount}\n${task.sourceFileNames.join('、')}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${task.progressPercent}%'),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    task.stage,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            if (isCompleted) ...[
              const SizedBox(width: 8),
              Consumer(
                builder: (context, ref, _) => IconButton(
                  tooltip: '删除任务',
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    if (!task.deletable) {
                      messenger.showSnackBar(
                        SnackBar(
                          content:
                              Text(task.deleteBlockReason ?? '该任务当前不可删除'),
                        ),
                      );
                      return;
                    }
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('删除已完成任务'),
                        content: Text('确认删除任务 ${task.jobId} 吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !context.mounted) {
                      return;
                    }
                    try {
                      await ref.read(apiClientProvider).deleteTask(task.jobId);
                      ref.invalidate(taskListProvider);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('任务已删除')),
                      );
                    } on DioException catch (error) {
                      final responseData = error.response?.data;
                      final detail = responseData is Map<String, dynamic>
                          ? responseData['detail'] as String?
                          : null;
                      messenger.showSnackBar(
                        SnackBar(
                          content:
                              Text('删除失败：${detail ?? error.message ?? error}'),
                        ),
                      );
                    } catch (error) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('删除失败：$error')),
                      );
                    }
                  },
                  icon: Icon(
                    Icons.delete_outline,
                    color: task.deletable
                        ? null
                        : Theme.of(context).disabledColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(message),
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
