import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_layout.dart';
import '../../core/theme/app_palette.dart';
import '../../router.dart';
import 'task_list_page.dart';

class BatchUploadReviewPage extends ConsumerStatefulWidget {
  const BatchUploadReviewPage({super.key});

  @override
  ConsumerState<BatchUploadReviewPage> createState() =>
      _BatchUploadReviewPageState();
}

class _BatchUploadReviewPageState extends ConsumerState<BatchUploadReviewPage> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final files = ref.watch(selectedUploadFilesProvider);
    final totalSize = files.fold<int>(0, (sum, file) => sum + file.sizeBytes);
    return Scaffold(
      backgroundColor: _UploadPalette.canvas,
      appBar: AppBar(
        backgroundColor: _UploadPalette.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: Text(
          '批量确认上传',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _UploadPalette.ink,
                fontWeight: FontWeight.w900,
              ),
        ),
        actions: [
          IconButton(
            tooltip: '上传说明',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('确认后会自动抽取发票字段、税站核验并写入台账。'),
                ),
              );
            },
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppPalette.pageGradient),
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: AppLayout.pageInsets(
              constraints.maxWidth,
              top: 18,
              bottom: 36,
            ),
            children: [
              _UploadHeroCard(
                files: files,
                totalSizeText: _formatSize(totalSize),
                onContinueSelect: () => context.pop(),
                onRemoveFile: _removeFileAt,
              ),
              const SizedBox(height: 16),
              _UploadSummaryCard(
                invoiceCount: files.length,
                isSubmitting: _isSubmitting,
                onSubmit: files.isEmpty ? null : () => _submit(files),
              ),
              if (files.isEmpty) const SizedBox(height: 16),
              if (files.isEmpty)
                _EmptySelectionCard(
                  onBack: () => context.pop(),
                )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(List<UploadDraft> files) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSubmitting = true);
    try {
      messenger.showSnackBar(
        const SnackBar(content: Text('正在创建批量核验任务...')),
      );
      final jobId = await ref.read(apiClientProvider).uploadTask(files);
      ref.read(selectedUploadFilesProvider.notifier).state = const [];
      ref.invalidate(taskListProvider);
      if (!mounted) {
        return;
      }
      context.go('/tasks/$jobId');
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('上传失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _removeFileAt(int index) {
    final files = ref.read(selectedUploadFilesProvider);
    if (index < 0 || index >= files.length) {
      return;
    }
    final nextFiles = [...files]..removeAt(index);
    ref.read(selectedUploadFilesProvider.notifier).state = nextFiles;
  }
}

class _UploadHeroCard extends StatelessWidget {
  const _UploadHeroCard({
    required this.files,
    required this.totalSizeText,
    required this.onContinueSelect,
    required this.onRemoveFile,
  });

  final List<UploadDraft> files;
  final String totalSizeText;
  final VoidCallback onContinueSelect;
  final ValueChanged<int> onRemoveFile;

  @override
  Widget build(BuildContext context) {
    final fileCount = files.length;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white,
        border: Border.all(color: AppPalette.lineSoft),
        boxShadow: AppPalette.softShadow(0.45),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fileCount == 0 ? '尚未选择文件' : '已选择 $fileCount 个文件',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppPalette.primaryDeep,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onContinueSelect,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('继续选择'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.primary,
                    side: const BorderSide(color: AppPalette.lineSoft),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '共 $totalSizeText',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.muted,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (files.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...files.indexed.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _UploadSelectedFileRow(
                    file: entry.$2,
                    onRemove: () => onRemoveFile(entry.$1),
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

class _UploadSelectedFileRow extends StatelessWidget {
  const _UploadSelectedFileRow({
    required this.file,
    required this.onRemove,
  });

  final UploadDraft file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppPalette.lineSoft.withValues(alpha: 0.72)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppPalette.danger,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.picture_as_pdf_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppPalette.primaryDeep,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatSize(file.sizeBytes),
                  style: const TextStyle(
                    color: AppPalette.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: AppPalette.warning,
                    ),
                    SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '确认后自动抽取字段并进入税站核验',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppPalette.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '移除文件',
            onPressed: onRemove,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFEAF3FA),
              foregroundColor: AppPalette.muted,
              fixedSize: const Size(34, 34),
              minimumSize: const Size(34, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _UploadSummaryCard extends StatelessWidget {
  const _UploadSummaryCard({
    required this.invoiceCount,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final int invoiceCount;
  final bool isSubmitting;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _UploadPalette.outline),
        boxShadow: AppPalette.softShadow(0.35),
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
                    '预计汇总',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _UploadPalette.ink,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Text(
                  '$invoiceCount 张',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppPalette.primaryDeep,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '预计发票数量',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _UploadPalette.subtleInk,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: isSubmitting ? null : onSubmit,
                icon: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(isSubmitting ? '上传中...' : '确认上传'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppPalette.primarySoft,
                  disabledForegroundColor: AppPalette.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
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

class _EmptySelectionCard extends StatelessWidget {
  const _EmptySelectionCard({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _UploadPalette.outline),
      ),
      child: Column(
        children: [
          Icon(
            Icons.upload_file_outlined,
            size: 40,
            color: _UploadPalette.subtleInk.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 12),
          Text(
            '没有待上传文件',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _UploadPalette.ink,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '请先从任务列表选择 PDF，再回到这里完成确认上传。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _UploadPalette.subtleInk,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('返回上一页'),
          ),
        ],
      ),
    );
  }
}

String _formatSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

class _UploadPalette {
  static const Color canvas = AppPalette.canvas;
  static const Color ink = AppPalette.text;
  static const Color subtleInk = AppPalette.muted;
  static const Color outline = AppPalette.lineSoft;
}
