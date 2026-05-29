import 'dart:async';

import 'package:dio/dio.dart';
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

final taskItemEvidenceProvider = FutureProvider.autoDispose
    .family<_TaskItemEvidenceDetail, _TaskItemEvidenceRequest>(
        (ref, request) async {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  final token = ref.watch(authTokenProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    ),
  );
  final response = await dio.get(
    '/api/tasks/${request.jobId}/items/${request.jobItemId}',
  );
  return _TaskItemEvidenceDetail.fromJson(
    response.data as Map<String, dynamic>,
  );
});

final taskDetailTabProvider =
    StateProvider.autoDispose.family<int, String>((ref, jobId) => 0);

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
      backgroundColor: _TaskWorkbenchPalette.canvas,
      appBar: AppBar(
        backgroundColor: _TaskWorkbenchPalette.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: Text(
          '任务详情',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: _TaskWorkbenchPalette.ink,
              ),
        ),
        actions: [
          IconButton(
            tooltip: '刷新任务详情',
            onPressed: () => ref.refresh(taskDetailProvider(jobId).future),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: _TaskWorkbenchPalette.brand,
        backgroundColor: Colors.white,
        onRefresh: () async => ref.refresh(taskDetailProvider(jobId).future),
        child: task.when(
          loading: () => const _TaskMessageView(
            title: '正在拉取任务进度',
            message: '系统正在同步最新的核验状态与文件结果。',
            showSpinner: true,
          ),
          error: (error, _) => _TaskMessageView(
            title: '任务详情加载失败',
            message: '$error',
            action: FilledButton.tonalIcon(
              onPressed: () => ref.refresh(taskDetailProvider(jobId).future),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新加载'),
            ),
          ),
          data: (detail) {
            final currentTab = ref.watch(taskDetailTabProvider(jobId));
            final resultItems = [
              for (final group in detail.fileGroups)
                for (final item in group.items) (group.fileName, item),
            ];
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _TaskOverviewHero(detail: detail),
                const SizedBox(height: 12),
                _TaskSummaryPanel(detail: detail),
                const SizedBox(height: 12),
                _TaskSegmentTabs(
                  index: currentTab,
                  onChanged: (value) =>
                      ref.read(taskDetailTabProvider(jobId).notifier).state =
                          value,
                ),
                const SizedBox(height: 12),
                if (currentTab == 0) ...[
                  if (detail.fileGroups.isEmpty)
                    const _EmptyGroupCard()
                  else
                    ...detail.fileGroups.map(
                      (group) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _FileGroupCard(jobId: jobId, group: group),
                      ),
                    ),
                ] else ...[
                  if (resultItems.isEmpty)
                    const _EmptyGroupCard()
                  else
                    ...resultItems.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ResultItemCard(
                          jobId: jobId,
                          fileName: entry.$1,
                          item: entry.$2,
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TaskOverviewHero extends StatelessWidget {
  const _TaskOverviewHero({required this.detail});

  final TaskDetailModel detail;

  @override
  Widget build(BuildContext context) {
    final statusStyle = _statusStyleForTask(detail.status, detail.isFinished);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.fileGroups.isNotEmpty
                            ? detail.fileGroups.first.fileName
                            : '批量发票任务',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: _TaskWorkbenchPalette.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '任务编号   ${detail.jobId}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _TaskWorkbenchPalette.subtleInk,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '开始时间   ${detail.createdAtText}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _TaskWorkbenchPalette.subtleInk,
                            ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(style: statusStyle, compact: false),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskSummaryPanel extends StatelessWidget {
  const _TaskSummaryPanel({required this.detail});

  final TaskDetailModel detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '当前阶段   ${detail.stageLabel}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: _TaskWorkbenchPalette.ink,
                        ),
                  ),
                ),
                Text(
                  '${detail.progressPercent}%',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: _TaskWorkbenchPalette.brand,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: detail.isFinished
                    ? 1
                    : detail.progressPercent <= 0
                        ? null
                        : detail.progressPercent / 100,
                backgroundColor: _TaskWorkbenchPalette.track,
                color: _TaskWorkbenchPalette.brand,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _SummaryInlineMetric(label: '总记录', value: '${detail.totalRecords} 条')),
                Expanded(child: _SummaryInlineMetric(label: '成功', value: '${detail.successCount}', success: true)),
                Expanded(child: _SummaryInlineMetric(label: '失败', value: '${detail.failedCount}', error: true)),
                Expanded(child: _SummaryInlineMetric(label: '跳过', value: '${detail.skippedCount}')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskSegmentTabs extends StatelessWidget {
  const _TaskSegmentTabs({
    required this.index,
    required this.onChanged,
  });

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(int value, String label) {
      final selected = index == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected
                    ? _TaskWorkbenchPalette.brand
                    : _TaskWorkbenchPalette.subtleInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4EF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
      ),
      child: Row(
        children: [
          tab(0, '按文件查看'),
          tab(1, '按结果查看'),
        ],
      ),
    );
  }
}

class _SummaryInlineMetric extends StatelessWidget {
  const _SummaryInlineMetric({
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
        ? _TaskWorkbenchPalette.dangerInk
        : success
            ? _TaskWorkbenchPalette.success
            : _TaskWorkbenchPalette.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _TaskWorkbenchPalette.subtleInk,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
        ),
      ],
    );
  }
}

class _CompactGroupMetric extends StatelessWidget {
  const _CompactGroupMetric({
    required this.label,
    required this.value,
    this.tone,
  });

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _TaskWorkbenchPalette.subtleInk,
            ),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
            style: TextStyle(
              color: tone ?? _TaskWorkbenchPalette.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactMetaLine extends StatelessWidget {
  const _CompactMetaLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _TaskWorkbenchPalette.subtleInk,
            ),
        children: [
          TextSpan(text: '$label  '),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: _TaskWorkbenchPalette.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FileGroupCard extends ConsumerWidget {
  const _FileGroupCard({
    required this.jobId,
    required this.group,
  });

  final String jobId;
  final FileGroupModel group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = group.successCount + group.failedCount + group.skippedCount;
    final ratio = total == 0 ? 0.0 : group.successCount / total;
    final statusStyle = _statusStyleForGroup(group.status);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: _TaskWorkbenchPalette.brand,
          collapsedIconColor: _TaskWorkbenchPalette.brand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: _TaskWorkbenchPalette.ink,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _StatusPill(style: statusStyle),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: ratio.clamp(0.0, 1.0),
                  backgroundColor: _TaskWorkbenchPalette.track,
                  color: statusStyle.color,
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _CompactGroupMetric(label: '成功', value: '${group.successCount}'),
                _CompactGroupMetric(
                    label: '失败',
                    value: '${group.failedCount}',
                    tone: _TaskWorkbenchPalette.dangerInk),
                _CompactGroupMetric(label: '跳过', value: '${group.skippedCount}'),
                _CompactGroupMetric(label: '共', value: '${group.items.length} 条'),
              ],
            ),
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.failedCount > 0
                        ? '建议优先核查失败记录，并结合证据截图定位问题。'
                        : '当前文件组结果稳定，可重点查看成功记录的核验截图。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _TaskWorkbenchPalette.subtleInk,
                          height: 1.5,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: group.retryable
                      ? () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final newJobId = await ref
                                .read(apiClientProvider)
                                .retryTaskFile(jobId, group.fileId);
                            if (!context.mounted) {
                              return;
                            }
                            context.go('/tasks/$newJobId');
                          } catch (error) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('重试失败：$error')),
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试文件'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (group.items.isEmpty)
              const _EmptyChildState(
                message: '该文件组暂无可展示的发票记录。',
              )
            else
              ...group.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TaskItemCard(jobId: jobId, item: item),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskItemCard extends StatelessWidget {
  const _TaskItemCard({
    required this.jobId,
    required this.item,
  });

  final String jobId;
  final TaskItemModel item;

  @override
  Widget build(BuildContext context) {
    final statusStyle = _statusStyleForItem(item.statusLabel);
    final amountText = item.amount == null || item.amount!.isEmpty
        ? '金额待补充'
        : '¥${item.amount}';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.invoiceNumber?.isNotEmpty == true
                        ? item.invoiceNumber!
                        : '发票号码缺失',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: _TaskWorkbenchPalette.ink,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _CompactMetaLine(label: '开票日期', value: item.invoiceDate ?? '-'),
                  const SizedBox(height: 4),
                  _CompactMetaLine(label: '金额', value: amountText),
                  if (item.failureSummary?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      item.failureSummary!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _TaskWorkbenchPalette.dangerInk,
                          ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => FractionallySizedBox(
                            heightFactor: 0.92,
                            child: _TaskItemEvidenceSheet(
                              jobId: jobId,
                              jobItemId: item.jobItemId,
                            ),
                          ),
                        ),
                        child: const Text('详情'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => FractionallySizedBox(
                            heightFactor: 0.92,
                            child: _TaskItemEvidenceSheet(
                              jobId: jobId,
                              jobItemId: item.jobItemId,
                            ),
                          ),
                        ),
                        child: const Text('截图'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _StatusPill(style: statusStyle),
                const SizedBox(height: 8),
                _TaskItemThumb(jobId: jobId, jobItemId: item.jobItemId),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultItemCard extends StatelessWidget {
  const _ResultItemCard({
    required this.jobId,
    required this.fileName,
    required this.item,
  });

  final String jobId;
  final String fileName;
  final TaskItemModel item;

  @override
  Widget build(BuildContext context) {
    final statusStyle = _statusStyleForItem(item.statusLabel);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: _TaskWorkbenchPalette.subtleInk,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.invoiceNumber?.isNotEmpty == true
                      ? item.invoiceNumber!
                      : '发票号码缺失',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _TaskWorkbenchPalette.ink,
                      ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _ResultMetaText('开票日期', item.invoiceDate ?? '-'),
                    _ResultMetaText('金额', '¥${item.amount ?? '-'}'),
                  ],
                ),
                if (item.failureSummary?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.failureSummary!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _TaskWorkbenchPalette.dangerInk,
                        ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => FractionallySizedBox(
                          heightFactor: 0.92,
                          child: _TaskItemEvidenceSheet(
                            jobId: jobId,
                            jobItemId: item.jobItemId,
                          ),
                        ),
                      ),
                      child: const Text('处理说明'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => FractionallySizedBox(
                          heightFactor: 0.92,
                          child: _TaskItemEvidenceSheet(
                            jobId: jobId,
                            jobItemId: item.jobItemId,
                          ),
                        ),
                      ),
                      child: const Text('证据截图'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusPill(style: statusStyle),
              const SizedBox(height: 8),
              _TaskItemThumb(jobId: jobId, jobItemId: item.jobItemId),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultMetaText extends StatelessWidget {
  const _ResultMetaText(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _TaskWorkbenchPalette.subtleInk,
            ),
        children: [
          TextSpan(text: '$label  '),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: _TaskWorkbenchPalette.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskItemThumb extends ConsumerWidget {
  const _TaskItemThumb({
    required this.jobId,
    required this.jobItemId,
  });

  final String jobId;
  final int jobItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evidence = ref.watch(
      taskItemEvidenceProvider(
        _TaskItemEvidenceRequest(jobId: jobId, jobItemId: jobItemId),
      ),
    );
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final token = ref.watch(authTokenProvider);
    return Container(
      width: 108,
      height: 82,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
      ),
      child: evidence.when(
        loading: () => const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (_, __) => const Center(
          child: Icon(Icons.image_not_supported_outlined, size: 18),
        ),
        data: (item) {
          final url = item.verifyScreenshotUrl ?? item.extractScreenshotUrl;
          if (url == null || url.isEmpty) {
            return const Center(
              child: Icon(Icons.image_not_supported_outlined, size: 18),
            );
          }
          return _NetworkEvidenceImage(
            resolvedUrl: _resolveUrl(baseUrl, url),
            token: token,
            fit: BoxFit.cover,
          );
        },
      ),
    );
  }
}

class _TaskItemEvidenceSheet extends ConsumerWidget {
  const _TaskItemEvidenceSheet({
    required this.jobId,
    required this.jobItemId,
  });

  final String jobId;
  final int jobItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(
      taskItemEvidenceProvider(
        _TaskItemEvidenceRequest(jobId: jobId, jobItemId: jobItemId),
      ),
    );
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final token = ref.watch(authTokenProvider);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _TaskWorkbenchPalette.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: _TaskWorkbenchPalette.handle,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '证据与处理详情',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: _TaskWorkbenchPalette.ink,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '明细 #$jobItemId · 用于核查抽取结果与税站截图',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _TaskWorkbenchPalette.subtleInk,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: detail.when(
                loading: () => const _TaskMessageView(
                  title: '正在拉取证据截图',
                  message: '请稍候，系统正在读取该明细的截图与处理详情。',
                  showSpinner: true,
                  topPadding: 80,
                ),
                error: (error, _) => _TaskMessageView(
                  title: '证据详情加载失败',
                  message: '$error',
                  topPadding: 80,
                ),
                data: (item) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    _EvidenceSummaryCard(item: item),
                    const SizedBox(height: 16),
                    _SectionHeading(
                      title: '证据截图',
                      subtitle: '优先查看核验截图，其次核对抽取截图',
                    ),
                    const SizedBox(height: 12),
                    _EvidenceImageCard(
                      title: '抽取截图',
                      subtitle: 'OCR 抽取阶段生成的页面证据',
                      imageUrl: item.extractScreenshotUrl,
                      baseUrl: baseUrl,
                      token: token,
                    ),
                    const SizedBox(height: 12),
                    _EvidenceImageCard(
                      title: '核验截图',
                      subtitle: '税站核验结果页截图',
                      imageUrl: item.verifyScreenshotUrl,
                      baseUrl: baseUrl,
                      token: token,
                    ),
                    const SizedBox(height: 16),
                    _SectionHeading(
                      title: '处理备注',
                      subtitle: '帮助财务人员判断是否需要重试或人工复核',
                    ),
                    const SizedBox(height: 12),
                    _DetailTextCard(
                      title: '人工摘要',
                      content: item.humanSummary ?? '暂无人工摘要',
                    ),
                    if (item.validationErrors.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _DetailTextCard(
                        title: '校验异常',
                        content: item.validationErrors.join('\n'),
                        tone: _TaskWorkbenchPalette.dangerSoft,
                        foreground: _TaskWorkbenchPalette.dangerInk,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EvidenceSummaryCard extends StatelessWidget {
  const _EvidenceSummaryCard({required this.item});

  final _TaskItemEvidenceDetail item;

  @override
  Widget build(BuildContext context) {
    final statusStyle = _statusStyleForItem(item.humanSummary ?? '');
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.invoiceNumber?.isNotEmpty == true
                        ? item.invoiceNumber!
                        : '发票号码缺失',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _TaskWorkbenchPalette.ink,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                if ((item.humanSummary ?? '').isNotEmpty)
                  _StatusPill(style: statusStyle),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MicroMetricChip(
                  label: '日期',
                  value: item.invoiceDate ?? '-',
                  tone: _TaskWorkbenchPalette.brand,
                ),
                _MicroMetricChip(
                  label: '金额',
                  value: item.totalAmount?.isNotEmpty == true
                      ? '¥${item.totalAmount}'
                      : '-',
                  tone: _TaskWorkbenchPalette.success,
                ),
                _MicroMetricChip(
                  label: '销售方',
                  value: item.sellerName ?? '-',
                  tone: _TaskWorkbenchPalette.warning,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EvidenceImageCard extends StatelessWidget {
  const _EvidenceImageCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.baseUrl,
    required this.token,
  });

  final String title;
  final String subtitle;
  final String? imageUrl;
  final String baseUrl;
  final String? token;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _TaskWorkbenchPalette.ink,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _TaskWorkbenchPalette.subtleInk,
                  ),
            ),
            const SizedBox(height: 12),
            if (imageUrl == null || imageUrl!.isEmpty)
              const _EmptyChildState(message: '暂无截图证据')
            else
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => Dialog.fullscreen(
                    child: Scaffold(
                      appBar: AppBar(title: Text(title)),
                      body: Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        child: InteractiveViewer(
                          minScale: 0.8,
                          maxScale: 5,
                          child: _NetworkEvidenceImage(
                            resolvedUrl: _resolveUrl(baseUrl, imageUrl!),
                            token: token,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 210,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Color(0xFFEEF4F1),
                          ),
                          child: _NetworkEvidenceImage(
                            resolvedUrl: _resolveUrl(baseUrl, imageUrl!),
                            token: token,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                '点击放大',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailTextCard extends StatelessWidget {
  const _DetailTextCard({
    required this.title,
    required this.content,
    this.tone = Colors.white,
    this.foreground = _TaskWorkbenchPalette.ink,
  });

  final String title;
  final String content;
  final Color tone;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              content,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: 0.9),
                    height: 1.55,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskMessageView extends StatelessWidget {
  const _TaskMessageView({
    required this.title,
    required this.message,
    this.action,
    this.showSpinner = false,
    this.topPadding = 150,
  });

  final String title;
  final String message;
  final Widget? action;
  final bool showSpinner;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(24, topPadding, 24, 24),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _TaskWorkbenchPalette.outline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (showSpinner) ...[
                  const CircularProgressIndicator(
                    color: _TaskWorkbenchPalette.brand,
                  ),
                  const SizedBox(height: 18),
                ],
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _TaskWorkbenchPalette.ink,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _TaskWorkbenchPalette.subtleInk,
                        height: 1.5,
                      ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 18),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MicroMetricChip extends StatelessWidget {
  const _MicroMetricChip({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _TaskWorkbenchPalette.ink,
                ),
            children: [
              TextSpan(
                text: '$label ',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              TextSpan(
                text: value,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: tone,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.style,
    this.compact = true,
  });

  final _StatusStyle style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 7 : 8,
        ),
        child: Text(
          style.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: style.foreground,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _TaskWorkbenchPalette.ink,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _TaskWorkbenchPalette.subtleInk,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyGroupCard extends StatelessWidget {
  const _EmptyGroupCard();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: _EmptyChildState(message: '当前任务还没有生成文件分组结果。'),
      ),
    );
  }
}

class _EmptyChildState extends StatelessWidget {
  const _EmptyChildState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _TaskWorkbenchPalette.cardSubtle,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _TaskWorkbenchPalette.subtleInk,
            ),
      ),
    );
  }
}

class _NetworkEvidenceImage extends StatelessWidget {
  const _NetworkEvidenceImage({
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
          child: Text('截图加载失败：$error'),
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

class _TaskItemEvidenceRequest {
  const _TaskItemEvidenceRequest({
    required this.jobId,
    required this.jobItemId,
  });

  final String jobId;
  final int jobItemId;

  @override
  bool operator ==(Object other) {
    return other is _TaskItemEvidenceRequest &&
        other.jobId == jobId &&
        other.jobItemId == jobItemId;
  }

  @override
  int get hashCode => Object.hash(jobId, jobItemId);
}

class _TaskItemEvidenceDetail {
  const _TaskItemEvidenceDetail({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.totalAmount,
    required this.sellerName,
    required this.humanSummary,
    required this.extractScreenshotUrl,
    required this.verifyScreenshotUrl,
    required this.validationErrors,
  });

  final String? invoiceNumber;
  final String? invoiceDate;
  final String? totalAmount;
  final String? sellerName;
  final String? humanSummary;
  final String? extractScreenshotUrl;
  final String? verifyScreenshotUrl;
  final List<String> validationErrors;

  factory _TaskItemEvidenceDetail.fromJson(Map<String, dynamic> json) {
    final basicInfo = json['basic_info'] as Map<String, dynamic>? ?? const {};
    final processingInfo =
        json['processing_info'] as Map<String, dynamic>? ?? const {};
    final evidence = json['evidence'] as Map<String, dynamic>? ?? const {};
    final technical =
        json['technical_details'] as Map<String, dynamic>? ?? const {};
    final validationErrors =
        technical['validation_errors'] as List<dynamic>? ?? const <dynamic>[];
    return _TaskItemEvidenceDetail(
      invoiceNumber: basicInfo['invoice_number'] as String?,
      invoiceDate: basicInfo['invoice_date'] as String?,
      totalAmount: (basicInfo['total_amount'] as String?) ??
          (basicInfo['pretax_amount'] as String?),
      sellerName: basicInfo['seller_name'] as String?,
      humanSummary: processingInfo['human_summary'] as String?,
      extractScreenshotUrl: evidence['extract_screenshot_url'] as String?,
      verifyScreenshotUrl: evidence['verify_screenshot_url'] as String?,
      validationErrors:
          validationErrors.map((entry) => entry.toString()).toList(),
    );
  }
}

class _TaskWorkbenchPalette {
  static const Color canvas = Color(0xFFF4F7F2);
  static const Color cardSubtle = Color(0xFFF7FAF8);
  static const Color brand = Color(0xFF0B6E4F);
  static const Color success = Color(0xFF11795B);
  static const Color warning = Color(0xFFB9821B);
  static const Color danger = Color(0xFFB04A39);
  static const Color ink = Color(0xFF173229);
  static const Color subtleInk = Color(0xFF60756D);
  static const Color outline = Color(0xFFDCE8E1);
  static const Color track = Color(0xFFE8F1EC);
  static const Color handle = Color(0xFFB6C7BF);
  static const Color dangerSoft = Color(0xFFF9EEEA);
  static const Color dangerInk = Color(0xFF8D4334);
}

class _StatusStyle {
  const _StatusStyle({
    required this.label,
    required this.color,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color color;
  final Color background;
  final Color foreground;
}

_StatusStyle _statusStyleForTask(String status, bool isFinished) {
  switch (status) {
    case 'succeeded':
      return const _StatusStyle(
        label: '已完成',
        color: _TaskWorkbenchPalette.success,
        background: Color(0xFFE6F4EE),
        foreground: _TaskWorkbenchPalette.success,
      );
    case 'partially_failed':
      return const _StatusStyle(
        label: '部分异常',
        color: _TaskWorkbenchPalette.warning,
        background: Color(0xFFFBF2E1),
        foreground: Color(0xFF8A6314),
      );
    case 'failed':
      return const _StatusStyle(
        label: '处理失败',
        color: _TaskWorkbenchPalette.danger,
        background: Color(0xFFF9EDEA),
        foreground: _TaskWorkbenchPalette.dangerInk,
      );
    default:
      return _StatusStyle(
        label: isFinished ? '结果已生成' : '处理中',
        color: Colors.white,
        background: Colors.white.withValues(alpha: 0.18),
        foreground: Colors.white,
      );
  }
}

_StatusStyle _statusStyleForGroup(String status) {
  switch (status) {
    case 'succeeded':
      return const _StatusStyle(
        label: '稳定',
        color: _TaskWorkbenchPalette.success,
        background: Color(0xFFE8F5EE),
        foreground: _TaskWorkbenchPalette.success,
      );
    case 'failed':
      return const _StatusStyle(
        label: '异常',
        color: _TaskWorkbenchPalette.danger,
        background: Color(0xFFF9EEEA),
        foreground: _TaskWorkbenchPalette.dangerInk,
      );
    case 'partially_failed':
      return const _StatusStyle(
        label: '需复核',
        color: _TaskWorkbenchPalette.warning,
        background: Color(0xFFFCF3E5),
        foreground: Color(0xFF8A6314),
      );
    default:
      return const _StatusStyle(
        label: '处理中',
        color: _TaskWorkbenchPalette.brand,
        background: Color(0xFFE8F3EF),
        foreground: _TaskWorkbenchPalette.brand,
      );
  }
}

_StatusStyle _statusStyleForItem(String label) {
  if (label.contains('成功') || label.contains('通过')) {
    return const _StatusStyle(
      label: '成功',
      color: _TaskWorkbenchPalette.success,
      background: Color(0xFFE8F5EE),
      foreground: _TaskWorkbenchPalette.success,
    );
  }
  if (label.contains('跳过')) {
    return const _StatusStyle(
      label: '跳过',
      color: _TaskWorkbenchPalette.warning,
      background: Color(0xFFFCF3E5),
      foreground: Color(0xFF8A6314),
    );
  }
  if (label.contains('失败') || label.contains('异常') || label.contains('错误')) {
    return const _StatusStyle(
      label: '失败',
      color: _TaskWorkbenchPalette.danger,
      background: Color(0xFFF9EEEA),
      foreground: _TaskWorkbenchPalette.dangerInk,
    );
  }
  return _StatusStyle(
    label: label.isEmpty ? '处理中' : label,
    color: _TaskWorkbenchPalette.brand,
    background: const Color(0xFFE8F3EF),
    foreground: _TaskWorkbenchPalette.brand,
  );
}

String _resolveUrl(String baseUrl, String path) {
  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme) {
    return path;
  }
  return Uri.parse(baseUrl).resolve(path).toString();
}
