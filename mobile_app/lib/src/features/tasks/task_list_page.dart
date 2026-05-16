import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';
import '../../router.dart';

final taskListProvider =
    AutoDisposeAsyncNotifierProvider<TaskListController, TaskListState>(
  TaskListController.new,
);

class TaskListController extends AutoDisposeAsyncNotifier<TaskListState> {
  static const _defaultCompletedPageSize = 20;

  @override
  Future<TaskListState> build() async {
    final taskState = await ref.watch(apiClientProvider).getTasks(
          completedPage: 1,
          completedPageSize: _defaultCompletedPageSize,
        );
    if (taskState.runningTasks.isNotEmpty) {
      final timer = Timer(const Duration(seconds: 3), ref.invalidateSelf);
      ref.onDispose(timer.cancel);
    }
    return taskState;
  }

  Future<void> refreshTasks() async {
    final current = state.valueOrNull;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    state = AsyncData(
      current.copyWith(
        isRefreshing: true,
        isLoadingMore: false,
        errorMessage: null,
      ),
    );
    try {
      final refreshed = await ref.read(apiClientProvider).getTasks(
            completedPage: 1,
            completedPageSize: current.completedPageInfo.pageSize,
          );
      state = AsyncData(refreshed);
    } catch (error) {
      state = AsyncData(
        current.copyWith(
          isRefreshing: false,
          isLoadingMore: false,
          errorMessage: _humanizeTaskListError(error),
        ),
      );
    }
  }

  Future<void> loadMoreCompletedTasks() async {
    final current = state.valueOrNull;
    if (current == null ||
        current.isLoadingMore ||
        !current.completedPageInfo.hasNext) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        isLoadingMore: true,
        errorMessage: null,
      ),
    );
    try {
      final nextPage = current.completedPageInfo.page + 1;
      final next = await ref.read(apiClientProvider).getTasks(
            completedPage: nextPage,
            completedPageSize: current.completedPageInfo.pageSize,
          );
      state = AsyncData(
        next.copyWith(
          completedTasks: [
            ...current.completedTasks,
            ...next.completedTasks,
          ],
          isLoadingMore: false,
          errorMessage: null,
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(
          isLoadingMore: false,
          errorMessage: _humanizeTaskListError(error),
        ),
      );
    }
  }
}

String _humanizeTaskListError(Object error) {
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return '后端服务暂时无法连接，请确认本地服务已经启动。';
    }
    if (error.response?.statusCode == 401) {
      return '登录状态已失效，请重新登录后再查看任务列表。';
    }
    final detail = error.response?.data;
    if (detail is Map<String, dynamic>) {
      final message = detail['detail'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    }
  }
  return '请检查网络或后端服务状态。';
}

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
        UploadDraft(name: file.name, bytes: bytes, sizeBytes: file.size),
      );
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
    BuildContext context,
    WidgetRef ref,
    List<UploadDraft> drafts,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        const SnackBar(content: Text('正在上传并创建核验任务...')),
      );
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

  Future<void> _refresh(WidgetRef ref) async {
    await ref.read(taskListProvider.notifier).refreshTasks();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final taskList = ref.watch(taskListProvider);
    const background = Color(0xFFF6F5F1);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: Text(
          '任务',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF21332B),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '通知',
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            edgeOffset: 12,
            onRefresh: () => _refresh(ref),
            child: taskList.when(
              loading: () => const _LoadingState(),
              error: (error, _) => _FeedbackState(
                icon: Icons.cloud_off_outlined,
                title: '任务列表暂时不可用',
                message: _humanizeTaskListError(error),
                actionLabel: '重新加载',
                onPressed: () => ref.invalidate(taskListProvider),
              ),
              data: (state) => ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 128),
                children: [
                  _SyncNoticeCard(
                      hasRunningTasks: state.runningTasks.isNotEmpty),
                  if (state.isRefreshing) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(minHeight: 3),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: '进行中',
                          value: '${state.runningTasks.length}',
                          subtitle: '${state.totalSourceFileCount} 个任务',
                          highlighted: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          title: '今日完成',
                          value: '${state.completedTasks.length}',
                          subtitle: '${state.completedTasks.length} 个任务',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          title: '成功入台账',
                          value: '${state.totalSuccessCount}',
                          subtitle: '${state.totalProcessedRecords} 张发票',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SectionHeader(
                    title: '进行中任务',
                    subtitle: state.runningTasks.isEmpty ? '' : '',
                    countLabel: '',
                  ),
                  const SizedBox(height: 8),
                  if (state.runningTasks.isEmpty)
                    const _EmptyCard(
                      title: '当前没有进行中的任务',
                      message: '上传新的 PDF 后，这里会展示抽取、核验与入账过程。',
                      icon: Icons.inbox_outlined,
                    )
                  else
                    ...state.runningTasks.map((task) => _TaskCard(task: task)),
                  const SizedBox(height: 20),
                  _SectionHeader(
                    title: '已完成任务',
                    subtitle:
                        '共 ${state.completedPageInfo.total} 个历史任务，按时间倒序展示。',
                    countLabel: '',
                  ),
                  const SizedBox(height: 8),
                  if (state.completedTasks.isEmpty)
                    const _EmptyCard(
                      title: '暂无完成记录',
                      message: '完成后的核验任务会自动归档在这里，便于后续追踪和删除。',
                      icon: Icons.history_toggle_off_outlined,
                    )
                  else
                    ...state.completedTasks.map(
                      (task) => _TaskCard(
                        task: task,
                        isCompleted: true,
                      ),
                    ),
                  _CompletedTasksFooter(
                    state: state,
                    onLoadMore: () => ref
                        .read(taskListProvider.notifier)
                        .loadMoreCompletedTasks(),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 22,
            bottom: 18,
            child: _UploadTaskButton(
              onPressed: () => _pickPdfFiles(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadTaskButton extends StatelessWidget {
  const _UploadTaskButton({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 8,
      shadowColor: const Color(0x26165246),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF166246),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.upload_rounded, color: Colors.white, size: 20),
              SizedBox(height: 4),
              Text(
                '上传发票',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    this.highlighted = false,
  });

  final String title;
  final String value;
  final String subtitle;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFE8F2EB) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E1DA)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: const Color(0xFF566C61),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: const Color(0xFF166246),
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF718279),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncNoticeCard extends StatelessWidget {
  const _SyncNoticeCard({
    required this.hasRunningTasks,
  });

  final bool hasRunningTasks;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4EF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9E5DD)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              hasRunningTasks
                  ? Icons.autorenew_rounded
                  : Icons.task_alt_rounded,
              size: 16,
              color: const Color(0xFF166246),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasRunningTasks ? '专注发票核验，让财务工作更高效' : '当前没有进行中的任务，可直接上传新批次',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF50655C),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.countLabel,
  });

  final String title;
  final String subtitle;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF203229),
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (countLabel.isNotEmpty) Text(countLabel),
      ],
    );
  }
}

class _CompletedTasksFooter extends StatelessWidget {
  const _CompletedTasksFooter({
    required this.state,
    required this.onLoadMore,
  });

  final TaskListState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final pageInfo = state.completedPageInfo;
    if (state.completedTasks.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final loaded = state.completedTasks.length;
    final total = pageInfo.total;
    final message =
        total <= loaded ? '已加载全部历史任务' : '已加载 $loaded / $total 个历史任务';

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Column(
        children: [
          if (state.errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF2D2B6)),
              ),
              child: Text(
                '加载更多失败：${state.errorMessage}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8A4A22),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6D7D74),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (pageInfo.hasNext)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: state.isLoadingMore ? null : onLoadMore,
                icon: state.isLoadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(state.isLoadingMore ? '正在加载历史任务...' : '加载更多历史任务'),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD9E3DC)),
              ),
              child: Text(
                '没有更多历史任务了',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF50655C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final palette = _TaskPalette.resolve(
      colorScheme,
      task: task,
      isCompleted: isCompleted,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.go('/tasks/${task.jobId}'),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD9E3DC)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  task.sourceSummary,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: const Color(0xFF203229),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                _StatusChip(
                                  label: isCompleted ? '已完成' : '进行中',
                                  foreground: palette.foreground,
                                  background: palette.container,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '任务编号 ${task.jobId}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF6D7D74),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 18,
                              runSpacing: 8,
                              children: [
                                _TaskInlineMetric(
                                    label: '文件数',
                                    value: '${task.safeSourceFileCount}'),
                                _TaskInlineMetric(
                                    label: '记录数',
                                    value: '${task.totalRecords}'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 18,
                              runSpacing: 8,
                              children: [
                                _TaskInlineMetric(
                                    label: '成功',
                                    value: '${task.successCount}',
                                    success: true),
                                _TaskInlineMetric(
                                    label: '失败',
                                    value: '${task.failedCount}',
                                    error: true),
                                _TaskInlineMetric(
                                    label: '跳过', value: '${task.skippedCount}'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              task.timelineSummary
                                  .replaceFirst('更新于 ', '开始时间 ')
                                  .replaceFirst('创建于 ', '开始时间 '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF6D7D74),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: palette.container,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${task.progressPercent}%',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: palette.foreground,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  task.stageLabel,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: palette.foreground.withValues(
                                      alpha: 0.82,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isCompleted) ...[
                            const SizedBox(height: 10),
                            _DeleteTaskButton(task: task),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: task.isFinished
                          ? 1
                          : task.progressPercent <= 0
                              ? null
                              : task.progressValue,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        palette.foreground,
                      ),
                    ),
                  ),
                  if (task.sourceFileNames.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: task.sourceFileNames
                          .take(3)
                          .map(
                            (fileName) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                fileName,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskInlineMetric extends StatelessWidget {
  const _TaskInlineMetric({
    required this.label,
    required this.value,
    this.success = false,
    this.error = false,
  });

  final String label;
  final String value;
  final bool success;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error
        ? const Color(0xFFCC5B46)
        : success
            ? const Color(0xFF166246)
            : const Color(0xFF203229);
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF66786E),
            ),
        children: [
          TextSpan(text: '$label  '),
          TextSpan(
            text: value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteTaskButton extends ConsumerWidget {
  const _DeleteTaskButton({
    required this.task,
  });

  final TaskCardModel task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton.filledTonal(
      tooltip: '删除任务',
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        if (!task.deletable) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(task.deleteBlockReason ?? '该任务当前不可删除'),
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
              content: Text('删除失败：${detail ?? error.message ?? error}'),
            ),
          );
        } catch (error) {
          messenger.showSnackBar(
            SnackBar(content: Text('删除失败：$error')),
          );
        }
      },
      icon: const Icon(Icons.delete_outline_rounded),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: foreground),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(height: 14),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _FeedbackState extends StatelessWidget {
  const _FeedbackState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 120),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 28, color: colorScheme.primary),
              ),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onPressed,
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 118),
      children: [
        Container(
          height: 220,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary,
                const Color(0xFF175E4A),
              ],
            ),
            borderRadius: BorderRadius.circular(32),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '正在载入任务工作台',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '正在同步最新任务、核验结果与历史记录。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(minHeight: 8),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Card(
              child: SizedBox(
                height: 148,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 18,
                        width: 160,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 12,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 220,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const Spacer(),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 7,
                          value: 0.5,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TaskPalette {
  const _TaskPalette({
    required this.surface,
    required this.container,
    required this.foreground,
    required this.border,
  });

  final Color surface;
  final Color container;
  final Color foreground;
  final Color border;

  factory _TaskPalette.resolve(
    ColorScheme scheme, {
    required TaskCardModel task,
    required bool isCompleted,
  }) {
    if (!isCompleted) {
      return _TaskPalette(
        surface: scheme.primaryContainer.withValues(alpha: 0.34),
        container: scheme.primaryContainer,
        foreground: scheme.primary,
        border: scheme.primaryContainer.withValues(alpha: 0.8),
      );
    }
    if (task.hasFailures) {
      return _TaskPalette(
        surface: scheme.tertiaryContainer.withValues(alpha: 0.42),
        container: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
        border: scheme.tertiaryContainer.withValues(alpha: 0.92),
      );
    }
    return _TaskPalette(
      surface: scheme.secondaryContainer.withValues(alpha: 0.34),
      container: scheme.secondaryContainer,
      foreground: scheme.secondary,
      border: scheme.secondaryContainer.withValues(alpha: 0.9),
    );
  }
}
