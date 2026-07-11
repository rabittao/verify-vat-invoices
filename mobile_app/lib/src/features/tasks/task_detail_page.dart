import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_layout.dart';
import '../../core/theme/app_palette.dart';

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
        centerTitle: true,
        title: Text(
          '任务详情',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: _TaskWorkbenchPalette.ink,
              ),
        ),
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => context.go('/tasks'),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        actions: [
          IconButton(
            tooltip: '刷新任务详情',
            onPressed: () => ref.refresh(taskDetailProvider(jobId).future),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppPalette.pageGradient),
        child: RefreshIndicator(
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
              final resultItems = [
                for (final group in detail.fileGroups)
                  for (final item in group.items) (group.fileName, item),
              ];
              return LayoutBuilder(
                builder: (context, constraints) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: AppLayout.pageInsets(
                    constraints.maxWidth,
                    top: 8,
                    bottom: 36,
                  ),
                  children: [
                    _TaskDetailDashboard(
                      detail: detail,
                      jobId: jobId,
                      items: resultItems,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TaskDetailDashboard extends StatelessWidget {
  const _TaskDetailDashboard({
    required this.detail,
    required this.jobId,
    required this.items,
  });

  final TaskDetailModel detail;
  final String jobId;
  final List<(String, TaskItemModel)> items;

  @override
  Widget build(BuildContext context) {
    final overviewColumn = Column(
      children: [
        _TaskOverviewHero(detail: detail),
        const SizedBox(height: 12),
        _TaskSummaryPanel(detail: detail),
      ],
    );
    final resultColumn = Column(
      children: [
        if (detail.isQrInvoiceJob) ...[
          _LatestResultSection(
            jobId: jobId,
            items: items,
            screenshotOnly: true,
          ),
          const SizedBox(height: 12),
        ],
        const _TaskDetailSectionTitle(
          title: '文件明细',
          actionLabel: '按文件查看',
        ),
        const SizedBox(height: 10),
        if (detail.fileGroups.isEmpty)
          const _EmptyGroupCard()
        else
          _TaskFileGroupsGrid(
            jobId: jobId,
            groups: detail.fileGroups,
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 820) {
          return Column(
            children: [
              overviewColumn,
              const SizedBox(height: 12),
              resultColumn,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: overviewColumn),
            const SizedBox(width: 16),
            Expanded(flex: 6, child: resultColumn),
          ],
        );
      },
    );
  }
}

class _LatestResultSection extends StatelessWidget {
  const _LatestResultSection({
    required this.jobId,
    required this.items,
    this.screenshotOnly = false,
  });

  final String jobId;
  final List<(String, TaskItemModel)> items;
  final bool screenshotOnly;

  @override
  Widget build(BuildContext context) {
    final latest = items.isEmpty ? null : items.first;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: AppPalette.softCardDecoration(radius: 22, shadowAlpha: 0.26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TaskDetailSectionTitle(
            title: '最新处理结果',
            actionLabel: '最近 1 条',
            compact: true,
          ),
          const SizedBox(height: 12),
          if (latest == null)
            const _EmptyChildState(message: '暂无处理结果，完成后会展示最新发票记录。')
          else
            _LatestResultCard(
              jobId: jobId,
              fileName: latest.$1,
              item: latest.$2,
              screenshotOnly: screenshotOnly,
            ),
        ],
      ),
    );
  }
}

class _TaskDetailSectionTitle extends StatelessWidget {
  const _TaskDetailSectionTitle({
    required this.title,
    required this.actionLabel,
    this.compact = false,
  });

  final String title;
  final String actionLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: _TaskWorkbenchPalette.ink,
                  fontSize: compact ? 15 : 16,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        Text(
          actionLabel,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppPalette.primary,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _LatestResultCard extends StatelessWidget {
  const _LatestResultCard({
    required this.jobId,
    required this.fileName,
    required this.item,
    this.screenshotOnly = false,
  });

  final String jobId;
  final String fileName;
  final TaskItemModel item;
  final bool screenshotOnly;

  @override
  Widget build(BuildContext context) {
    final statusStyle = _statusStyleForItem(item.statusLabel);
    final amountText =
        item.amount == null || item.amount!.isEmpty ? '¥-' : '¥${item.amount}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.cardSoft,
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
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusStyle.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.invoiceNumber?.isNotEmpty == true
                            ? item.invoiceNumber!
                            : fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: _TaskWorkbenchPalette.ink,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _ResultMetaText('开票日期', item.invoiceDate ?? '-'),
                const SizedBox(height: 4),
                _ResultMetaText('金额', amountText),
                const SizedBox(height: 4),
                _ResultMetaText('状态', statusStyle.label),
                if (item.failureSummary?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.failureSummary!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _TaskWorkbenchPalette.dangerInk,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              _TaskItemThumb(jobId: jobId, jobItemId: item.jobItemId),
              const SizedBox(height: 10),
              if (!screenshotOnly) ...[
                _LatestResultActionButton(
                  label: '详情',
                  icon: Icons.article_outlined,
                  filled: false,
                  onPressed: () => _openEvidenceSheet(context),
                ),
                const SizedBox(height: 8),
              ],
              _LatestResultActionButton(
                label: '截图',
                icon: Icons.image_outlined,
                filled: true,
                onPressed: () => _openEvidenceSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openEvidenceSheet(BuildContext context) {
    showModalBottomSheet<void>(
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
    );
  }
}

class _LatestResultActionButton extends StatelessWidget {
  const _LatestResultActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = filled
        ? FilledButton.styleFrom(
            backgroundColor: AppPalette.primary,
            foregroundColor: Colors.white,
            side: BorderSide.none,
          )
        : OutlinedButton.styleFrom(
            foregroundColor: AppPalette.primaryDeep,
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppPalette.lineSoft),
          );
    return SizedBox(
      width: 76,
      height: 36,
      child: filled
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 14),
              label: Text(label),
              style: style.copyWith(
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 14),
              label: Text(label),
              style: style.copyWith(
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ),
    );
  }
}

class _TaskFileGroupsGrid extends StatelessWidget {
  const _TaskFileGroupsGrid({
    required this.jobId,
    required this.groups,
  });

  final String jobId;
  final List<FileGroupModel> groups;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth >= 980 ? 2 : 1;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final group in groups)
              SizedBox(
                width: width,
                child: _FileGroupCard(jobId: jobId, group: group),
              ),
          ],
        );
      },
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
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
        boxShadow: AppPalette.softShadow(0.36),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppPalette.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.description_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '任务编号',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color:
                                              _TaskWorkbenchPalette.subtleInk,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ),
                                _StatusPill(style: statusStyle),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              detail.jobId,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: _TaskWorkbenchPalette.ink,
                                    fontSize: 16,
                                    height: 1.18,
                                    letterSpacing: -0.35,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '开始时间：${detail.createdAtText}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _TaskWorkbenchPalette.subtleInk,
                        ),
                  ),
                  Text(
                    '当前阶段：${detail.stageLabel}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _TaskWorkbenchPalette.subtleInk,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppPalette.skySoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: _TaskProgressRing(
                progressPercent: detail.progressPercent,
                isFinished: detail.isFinished,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskProgressRing extends StatelessWidget {
  const _TaskProgressRing({
    required this.progressPercent,
    required this.isFinished,
  });

  final int progressPercent;
  final bool isFinished;

  @override
  Widget build(BuildContext context) {
    final progressValue = isFinished
        ? 1.0
        : progressPercent <= 0
            ? null
            : (progressPercent / 100).clamp(0.0, 1.0);
    return SizedBox.square(
      dimension: 66,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const SizedBox.square(
            dimension: 50,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppPalette.skySoft,
              ),
            ),
          ),
          SizedBox.square(
            dimension: 60,
            child: CircularProgressIndicator(
              strokeWidth: 4.5,
              value: progressValue,
              strokeCap: StrokeCap.round,
              backgroundColor: AppPalette.progressTrack,
              color: AppPalette.primary,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 42,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$progressPercent%',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppPalette.primary,
                          fontSize: 15,
                          height: 0.95,
                          letterSpacing: -0.8,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '总进度',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppPalette.muted,
                      fontSize: 8,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskSummaryPanel extends StatelessWidget {
  const _TaskSummaryPanel({required this.detail});

  final TaskDetailModel detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _TaskMetricTile(
                label: '总记录',
                value: '${detail.totalRecords}',
                icon: Icons.list_alt_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TaskMetricTile(
                label: '成功',
                value: '${detail.successCount}',
                icon: Icons.check_box_rounded,
                tone: AppPalette.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TaskMetricTile(
                label: '失败',
                value: '${detail.failedCount}',
                icon: Icons.error_rounded,
                tone: AppPalette.danger,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TaskMetricTile(
                label: '跳过',
                value: '${detail.skippedCount}',
                icon: Icons.redo_rounded,
                tone: const Color(0xFF42607A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration:
              AppPalette.softCardDecoration(radius: 22, shadowAlpha: 0.22),
          child: Column(
            children: [
              Row(
                children: [
                  _StepDot(
                    label: '上传',
                    time: '14:25',
                    done: detail.progressPercent >= 5,
                  ),
                  const Expanded(child: _StepLine(active: true)),
                  _StepDot(
                    label: '抽取',
                    time: '14:26',
                    done: detail.progressPercent >= 35,
                  ),
                  Expanded(
                    child: _StepLine(active: detail.progressPercent >= 35),
                  ),
                  _StepDot(
                    label: '核验中',
                    time: '${detail.progressPercent}%',
                    done: detail.progressPercent >= 85,
                    current: !detail.isFinished,
                  ),
                  Expanded(
                    child: _StepLine(active: detail.isFinished),
                  ),
                  _StepDot(
                    label: '入库',
                    time: detail.isFinished ? '完成' : '待开始',
                    done: detail.isFinished,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskMetricTile extends StatelessWidget {
  const _TaskMetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.tone = AppPalette.primaryDeep,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: AppPalette.softCardDecoration(radius: 16, shadowAlpha: 0.16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: tone, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.muted,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.label,
    required this.time,
    this.done = false,
    this.current = false,
  });

  final String label;
  final String time;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final color = done || current ? AppPalette.primary : AppPalette.muted;
    return SizedBox(
      width: 52,
      child: Column(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: done ? AppPalette.primary : AppPalette.skySoft,
              shape: BoxShape.circle,
              border: Border.all(color: AppPalette.primary),
            ),
            child: Icon(
              done
                  ? Icons.check_rounded
                  : current
                      ? Icons.refresh_rounded
                      : Icons.north_east_rounded,
              color: done ? Colors.white : AppPalette.primary,
              size: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
          Text(
            time,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.muted,
                  fontSize: 10,
                ),
          ),
        ],
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 32),
      color: active ? AppPalette.primary : AppPalette.progressTrack,
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
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
        boxShadow: AppPalette.softShadow(0.26),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          iconColor: _TaskWorkbenchPalette.brand,
          collapsedIconColor: _TaskWorkbenchPalette.brand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
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
                  minHeight: 7,
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
              spacing: 16,
              runSpacing: 10,
              children: [
                _CompactGroupMetric(
                    label: '成功', value: '${group.successCount}'),
                _CompactGroupMetric(
                    label: '失败',
                    value: '${group.failedCount}',
                    tone: _TaskWorkbenchPalette.dangerInk),
                _CompactGroupMetric(
                    label: '跳过', value: '${group.skippedCount}'),
                _CompactGroupMetric(
                    label: '共', value: '${group.items.length} 条'),
              ],
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppPalette.cardSoft,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppPalette.lineSoft),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      group.failedCount > 0
                          ? '建议优先核查失败记录，并结合证据截图定位问题。'
                          : '当前文件组结果稳定，可重点查看成功记录的核验截图。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _TaskWorkbenchPalette.subtleInk,
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    child: FilledButton.tonalIcon(
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
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
        boxShadow: AppPalette.softShadow(0.18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.invoiceNumber?.isNotEmpty == true
                        ? item.invoiceNumber!
                        : '发票号码缺失',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _TaskWorkbenchPalette.ink,
                          fontWeight: FontWeight.w900,
                          height: 1.18,
                          letterSpacing: -0.3,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                _StatusPill(style: statusStyle),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _TaskItemInfoRow(
                        label: '开票日期',
                        value: item.invoiceDate ?? '-',
                      ),
                      const SizedBox(height: 9),
                      _TaskItemInfoRow(
                        label: '金额',
                        value: amountText,
                      ),
                      if (item.failureSummary?.isNotEmpty == true) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _TaskWorkbenchPalette.dangerSoft,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            item.failureSummary!,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: _TaskWorkbenchPalette.dangerInk,
                                      fontWeight: FontWeight.w800,
                                      height: 1.45,
                                    ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _TaskItemThumb(jobId: jobId, jobItemId: item.jobItemId),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
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
                    icon: const Icon(Icons.article_outlined, size: 18),
                    label: const Text('详情'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _TaskWorkbenchPalette.ink,
                      minimumSize: const Size(0, 50),
                      side: const BorderSide(
                        color: _TaskWorkbenchPalette.outline,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
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
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('截图'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskItemInfoRow extends StatelessWidget {
  const _TaskItemInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppPalette.cardSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.lineSoft),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.muted,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.primaryDeep,
                    fontWeight: FontWeight.w900,
                  ),
            ),
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
      width: 116,
      height: 92,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppPalette.skySoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _TaskWorkbenchPalette.outline),
        boxShadow: AppPalette.softShadow(0.12),
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
              padding: const EdgeInsets.fromLTRB(14, 0, 8, 10),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Text(
                      '证据与处理详情',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _TaskWorkbenchPalette.ink,
                          ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
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
                    _EvidenceImageCard(
                      title: '核验截图',
                      imageUrl:
                          item.verifyScreenshotUrl ?? item.extractScreenshotUrl,
                      baseUrl: baseUrl,
                      token: token,
                    ),
                    const SizedBox(height: 16),
                    _EvidenceSummaryCard(item: item),
                    const SizedBox(height: 16),
                    _DetailTextCard(
                      title: '处理说明',
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
                    '字段摘要',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _TaskWorkbenchPalette.ink,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                if ((item.humanSummary ?? '').isNotEmpty)
                  _StatusPill(style: statusStyle),
              ],
            ),
            const SizedBox(height: 14),
            _EvidenceFieldGrid(
              rows: [
                ('发票号码', item.invoiceNumber ?? '-'),
                (
                  '金额',
                  item.totalAmount?.isNotEmpty == true
                      ? '¥${item.totalAmount}'
                      : '-'
                ),
                ('开票日期', item.invoiceDate ?? '-'),
                ('销售方', item.sellerName ?? '-'),
                (
                  '价税合计',
                  item.totalAmount?.isNotEmpty == true
                      ? '¥${item.totalAmount}'
                      : '-'
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EvidenceFieldGrid extends StatelessWidget {
  const _EvidenceFieldGrid({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 340 ? 2 : 1;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final row in rows)
              SizedBox(
                width: width,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppPalette.cardSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppPalette.lineSoft),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.$1,
                        style: const TextStyle(
                          color: AppPalette.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        row.$2,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppPalette.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EvidenceImageCard extends StatelessWidget {
  const _EvidenceImageCard({
    required this.title,
    required this.imageUrl,
    required this.baseUrl,
    required this.token,
  });

  final String title;
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: _TaskWorkbenchPalette.ink,
                        ),
                  ),
                ),
                if (imageUrl != null && imageUrl!.isNotEmpty)
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppPalette.primarySoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: '放大截图',
                      icon: const Icon(
                        Icons.open_in_full_rounded,
                        size: 16,
                        color: AppPalette.primary,
                      ),
                      onPressed: () => showDialog<void>(
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
                    ),
                  ),
              ],
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
                    height: 260,
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
                                '1/1',
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.style,
  });

  final _StatusStyle style;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
  static const Color canvas = AppPalette.canvas;
  static const Color cardSubtle = AppPalette.cardSoft;
  static const Color brand = AppPalette.primary;
  static const Color success = AppPalette.success;
  static const Color warning = AppPalette.warning;
  static const Color danger = AppPalette.danger;
  static const Color ink = AppPalette.text;
  static const Color subtleInk = AppPalette.muted;
  static const Color outline = AppPalette.lineSoft;
  static const Color track = AppPalette.skySoft;
  static const Color handle = Color(0xFFA8D7EF);
  static const Color dangerSoft = AppPalette.dangerSoft;
  static const Color dangerInk = Color(0xFFA7353D);
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
        color: _TaskWorkbenchPalette.brand,
        background: AppPalette.primarySoft,
        foreground: _TaskWorkbenchPalette.brand,
      );
  }
}

_StatusStyle _statusStyleForGroup(String status) {
  switch (status) {
    case 'succeeded':
      return const _StatusStyle(
        label: '稳定',
        color: _TaskWorkbenchPalette.success,
        background: AppPalette.successSoft,
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
        background: AppPalette.primarySoft,
        foreground: _TaskWorkbenchPalette.brand,
      );
  }
}

_StatusStyle _statusStyleForItem(String label) {
  if (label.contains('成功') || label.contains('通过')) {
    return const _StatusStyle(
      label: '成功',
      color: _TaskWorkbenchPalette.success,
      background: AppPalette.successSoft,
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
    background: AppPalette.primarySoft,
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
