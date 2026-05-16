import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';

const _exportGreen = Color(0xFF0B6E4F);
const _exportGreenDeep = Color(0xFF073B2A);
const _exportCanvas = Color(0xFFF4F8F5);
const _exportLine = Color(0xFFD7E4DC);
const _exportMuted = Color(0xFF5F746A);

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
      backgroundColor: _exportCanvas,
      appBar: AppBar(
        backgroundColor: _exportCanvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: '返回',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/ledger');
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        titleSpacing: 20,
        title: const Text('导出记录'),
      ),
      body: RefreshIndicator(
        color: _exportGreen,
        onRefresh: () async => ref.refresh(exportHistoryProvider.future),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF8FBF9), Color(0xFFF2F7F3)],
            ),
          ),
          child: exports.when(
            loading: () => const _LoadingState(),
            error: (error, _) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _MessageCard(
                  icon: Icons.error_outline_rounded,
                  title: '导出记录加载失败',
                  message: '$error',
                ),
              ],
            ),
            data: (items) {
              final readyCount =
                  items.where((item) => item.isDownloadReady).length;
              final processingCount = items
                  .where((item) =>
                      item.status == 'pending' || item.status == 'processing')
                  .length;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (items.isEmpty)
                    const _MessageCard(
                      icon: Icons.inbox_outlined,
                      title: '暂无导出记录',
                      message: '当前还没有生成过导出文件。',
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '共 ${items.length} 条记录',
                        style: const TextStyle(color: _exportMuted),
                      ),
                    ),
                  if (items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          _TinySummaryChip(label: '可下载', value: '$readyCount'),
                          const SizedBox(width: 8),
                          _TinySummaryChip(
                              label: '处理中', value: '$processingCount'),
                        ],
                      ),
                    ),
                  if (items.isEmpty)
                    const SizedBox.shrink()
                  else
                    for (final item in items) ...[
                      _ExportRecordCard(item: item),
                      const SizedBox(height: 12),
                    ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TinySummaryChip extends StatelessWidget {
  const _TinySummaryChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _exportLine),
      ),
      child: Text('$label $value', style: const TextStyle(color: _exportMuted)),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72))),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _ExportHeroCard(
          totalCount: null,
          readyCount: null,
          processingCount: null,
        ),
        SizedBox(height: 18),
        _MessageCard(
          icon: Icons.cloud_sync_outlined,
          title: '正在同步导出记录',
          message: '请稍候，系统正在拉取最近的导出历史。',
        ),
      ],
    );
  }
}

class _ExportHeroCard extends StatelessWidget {
  const _ExportHeroCard({
    required this.totalCount,
    required this.readyCount,
    required this.processingCount,
  });

  final int? totalCount;
  final int? readyCount;
  final int? processingCount;

  @override
  Widget build(BuildContext context) {
    String textOf(int? value) => value == null ? '--' : '$value';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_exportGreen, _exportGreenDeep],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1C073B2A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: const Text(
              '出库看板',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '导出任务一屏追踪',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '把已完成、处理中与待下载的资料统一收束到同一条财务导出流水里。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                  child: _HeroMetric(label: '总记录', value: textOf(totalCount))),
              const SizedBox(width: 12),
              Expanded(
                  child: _HeroMetric(label: '可下载', value: textOf(readyCount))),
              const SizedBox(width: 12),
              Expanded(
                  child: _HeroMetric(
                label: '处理中',
                value: textOf(processingCount),
              )),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExportRecordCard extends ConsumerWidget {
  const _ExportRecordCard({required this.item});

  final ExportRecordModel item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foregroundColor =
        item.isDownloadReady ? _exportGreenDeep : _exportMuted;
    final statusBackground = switch (item.status) {
      'completed' => const Color(0xFFE9F5EF),
      'failed' => const Color(0xFFFDECEC),
      _ => const Color(0xFFF6F1E5),
    };
    final statusColor = switch (item.status) {
      'completed' => _exportGreenDeep,
      'failed' => const Color(0xFFB54747),
      _ => const Color(0xFF7D6126),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _exportLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10073B2A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
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
                      item.fileDisplayName,
                      style: const TextStyle(
                        color: _exportGreenDeep,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '导出编号 ${item.exportId}',
                      style: const TextStyle(color: _exportMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _TagChip(
                icon: Icons.description_outlined,
                label: item.exportTypeLabel,
              ),
              _TagChip(
                icon: item.isDownloadReady
                    ? Icons.download_done_outlined
                    : Icons.hourglass_top_rounded,
                label: item.isDownloadReady ? '可下载' : '待生成',
                foregroundColor: foregroundColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _exportCanvas,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.isDownloadReady
                      ? '文件已生成，可直接拉取到本机临时目录并交给系统打开。'
                      : item.errorMessage?.trim().isNotEmpty == true
                          ? '失败原因：${item.errorMessage}'
                          : '当前导出文件尚未可用，请稍后下拉刷新查看最新状态。',
                  style: const TextStyle(
                    color: _exportMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _TagChip(
                      icon: Icons.schedule_outlined,
                      label: item.createdAt,
                    ),
                    _TagChip(
                      icon: Icons.storage_outlined,
                      label: item.fileSizeLabel,
                    ),
                  ],
                ),
                if (item.isDownloadReady) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final savedPath = await ref
                              .read(apiClientProvider)
                              .downloadProtectedFile(
                                fileUrl: item.downloadUrl ?? item.openUrl ?? '',
                                fallbackFileName:
                                    item.fileName ?? '${item.exportId}.bin',
                              );
                          if (!context.mounted) {
                            return;
                          }
                          final opened = await launchUrl(Uri.file(savedPath));
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                opened ? '已在系统中打开导出文件' : '文件已下载到：$savedPath',
                              ),
                            ),
                          );
                        } catch (error) {
                          if (!context.mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            SnackBar(content: Text('打开导出文件失败：$error')),
                          );
                        }
                      },
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('打开导出文件'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.icon,
    required this.label,
    this.foregroundColor = _exportGreenDeep,
  });

  final IconData icon;
  final String label;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3EE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foregroundColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
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
        border: Border.all(color: _exportLine),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: _exportGreen),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: _exportGreenDeep,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _exportMuted, height: 1.45),
          ),
        ],
      ),
    );
  }
}
