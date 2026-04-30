import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';

final taskDetailProvider = FutureProvider.autoDispose
    .family<TaskDetailModel, String>((ref, jobId) async {
  final detail = await ref.watch(apiClientProvider).getTaskDetail(jobId);
  if (!detail.isFinished) {
    final timer = Timer(const Duration(seconds: 3), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return detail;
});

class TaskDetailPage extends ConsumerWidget {
  const TaskDetailPage({
    required this.jobId,
    super.key,
  });

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(taskDetailProvider(jobId));
    return Scaffold(
      appBar: AppBar(title: Text('任务详情 $jobId')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(taskDetailProvider(jobId).future),
        child: task.when(
          loading: () => const _CenteredMessage(message: '正在加载任务详情...'),
          error: (error, _) => _CenteredMessage(message: '任务详情加载失败：$error'),
          data: (detail) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.stageLabel,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: detail.isFinished
                            ? 1
                            : detail.progressPercent <= 0
                                ? null
                                : detail.progressPercent / 100,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        detail.isFinished
                            ? '已完成'
                            : '预计进度 ${detail.progressPercent}%，页面每 3 秒自动刷新',
                      ),
                      const SizedBox(height: 8),
                      Text(
                          '总记录 ${detail.totalRecords} | 成功 ${detail.successCount} | 失败 ${detail.failedCount} | 跳过 ${detail.skippedCount}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (detail.fileGroups.isEmpty)
                const Card(child: ListTile(title: Text('暂无文件明细')))
              else
                ...detail.fileGroups
                    .map((group) => _FileGroupTile(jobId: jobId, group: group)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileGroupTile extends ConsumerWidget {
  const _FileGroupTile({
    required this.jobId,
    required this.group,
  });

  final String jobId;
  final FileGroupModel group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ExpansionTile(
        title: Text(group.fileName),
        subtitle: Text(
            '成功 ${group.successCount} / 失败 ${group.failedCount} / 跳过 ${group.skippedCount}'),
        trailing: IconButton(
          tooltip: '重试该文件',
          icon: const Icon(Icons.refresh_outlined),
          onPressed: group.retryable
              ? () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final newJobId = await ref
                        .read(apiClientProvider)
                        .retryTaskFile(jobId, group.fileId);
                    if (context.mounted) {
                      context.go('/tasks/$newJobId');
                    }
                  } catch (error) {
                    messenger
                        .showSnackBar(SnackBar(content: Text('重试失败：$error')));
                  }
                }
              : null,
        ),
        children: group.items
            .map(
              (item) => ListTile(
                title: Text(item.invoiceNumber ?? '字段缺失'),
                subtitle: Text([
                  if (item.invoiceDate != null) item.invoiceDate,
                  if (item.amount != null) item.amount,
                  if (item.failureSummary != null) item.failureSummary,
                ].join(' | ')),
                trailing: Chip(label: Text(item.statusLabel)),
              ),
            )
            .toList(),
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
