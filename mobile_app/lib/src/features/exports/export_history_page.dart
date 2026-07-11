import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_layout.dart';
import '../../core/theme/app_palette.dart';

const _exportGreen = AppPalette.primary;
const _exportGreenDeep = AppPalette.primaryDeep;
const _exportCanvas = AppPalette.canvas;
const _exportLine = AppPalette.lineSoft;
const _exportMuted = AppPalette.muted;

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
          decoration: const BoxDecoration(gradient: AppPalette.pageGradient),
          child: exports.when(
            loading: () => const _LoadingState(),
            error: (error, _) => LayoutBuilder(
              builder: (context, constraints) => ListView(
                padding: AppLayout.pageInsets(
                  constraints.maxWidth,
                  top: 12,
                  bottom: 32,
                ),
                children: [
                  _MessageCard(
                    icon: Icons.error_outline_rounded,
                    title: '导出记录加载失败',
                    message: '$error',
                  ),
                ],
              ),
            ),
            data: (items) {
              final readyCount =
                  items.where((item) => item.isDownloadReady).length;
              final processingCount = items
                  .where((item) =>
                      item.status == 'pending' || item.status == 'processing')
                  .length;
              return LayoutBuilder(
                builder: (context, constraints) => ListView(
                  padding: AppLayout.pageInsets(
                    constraints.maxWidth,
                    top: 12,
                    bottom: 32,
                  ),
                  children: [
                    _ExportHeroCard(
                      totalCount: items.length,
                      readyCount: readyCount,
                      processingCount: processingCount,
                    ),
                    const SizedBox(height: 14),
                    if (items.isEmpty)
                      const _MessageCard(
                        icon: Icons.inbox_outlined,
                        title: '暂无导出记录',
                        message: '当前还没有生成过导出文件。',
                      )
                    else
                      _ExportRecordsGrid(items: items),
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

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: AppLayout.pageInsets(
          constraints.maxWidth,
          top: 12,
          bottom: 32,
        ),
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
      ),
    );
  }
}

class _ExportRecordsGrid extends StatelessWidget {
  const _ExportRecordsGrid({required this.items});

  final List<ExportRecordModel> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppPalette.softCardDecoration(radius: 26, shadowAlpha: 0.75),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppPalette.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.file_download_outlined,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '导出记录',
                    style: TextStyle(
                      color: AppPalette.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppPalette.primarySoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '全部记录 ${items.length}',
                    style: const TextStyle(
                      color: AppPalette.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (var index = 0; index < items.length; index++) ...[
              _ExportRecordCard(item: items[index]),
              if (index != items.length - 1)
                const Divider(height: 1, color: AppPalette.lineSoft),
            ],
          ],
        ),
      ),
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
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: AppPalette.heroGradient,
        border: Border.all(color: AppPalette.lineSoft),
        boxShadow: const [
          BoxShadow(
            color: AppPalette.shadow,
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -34,
            right: -4,
            child: Container(
              width: 128,
              height: 78,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.36),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '导出记录',
                          style: TextStyle(
                            color: AppPalette.text,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '查看 PDF 与 Excel 导出历史，跟踪完成状态。',
                          style: TextStyle(
                            color: AppPalette.muted,
                            height: 1.45,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppPalette.primarySoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '全部记录',
                      style: TextStyle(
                        color: AppPalette.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppPalette.lineSoft),
                ),
                child: Text(
                  '共 ${textOf(totalCount)} 条记录 · ${textOf(readyCount)} 个可下载 · ${textOf(processingCount)} 个处理中',
                  style: const TextStyle(
                    color: AppPalette.primaryDeep,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
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

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: item.isDownloadReady
          ? () => _openExportFile(context, ref, item)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppPalette.skySoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppPalette.lineSoft),
              ),
              child: Icon(
                item.exportType == 'invoice_list_excel'
                    ? Icons.grid_on_rounded
                    : Icons.picture_as_pdf_outlined,
                color: foregroundColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.fileDisplayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppPalette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _recordSubtitle(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppPalette.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.status == 'failed' &&
                      item.errorMessage?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 5),
                    Text(
                      item.errorMessage!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppPalette.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: statusBackground,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.status == 'completed') ...[
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: AppPalette.success,
                        ),
                        const SizedBox(width: 5),
                      ] else if (item.status == 'processing' ||
                          item.status == 'pending') ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppPalette.primary,
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        item.statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.fileSizeLabel,
                  style: const TextStyle(
                    color: AppPalette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _recordSubtitle(ExportRecordModel item) {
    final createdAt = item.createdAt.trim();
    if (createdAt.isEmpty) {
      return item.exportTypeLabel;
    }
    return '${item.exportTypeLabel}  $createdAt';
  }

  Future<void> _openExportFile(
    BuildContext context,
    WidgetRef ref,
    ExportRecordModel item,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final savedPath = await ref.read(apiClientProvider).downloadProtectedFile(
            fileUrl: item.downloadUrl ?? item.openUrl ?? '',
            fallbackFileName: item.fileName ?? '${item.exportId}.bin',
          );
      if (!context.mounted) {
        return;
      }
      final opened = await launchUrl(Uri.file(savedPath));
      messenger.showSnackBar(
        SnackBar(
          content: Text(opened ? '已在系统中打开导出文件' : '文件已下载到：$savedPath'),
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
