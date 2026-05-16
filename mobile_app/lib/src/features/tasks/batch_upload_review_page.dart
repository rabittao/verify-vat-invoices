import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';
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
    final groupedFiles = _buildUploadGroups(files);
    return Scaffold(
      backgroundColor: _UploadPalette.canvas,
      appBar: AppBar(
        backgroundColor: _UploadPalette.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '批量确认上传',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _UploadPalette.ink,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(
              '确认文件清单后开始自动抽取与税站核验',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _UploadPalette.subtleInk,
                  ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _UploadPalette.outline),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140B3D2B),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '已确认 ${files.length} 份 PDF',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: _UploadPalette.ink,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '总大小 ${_formatSize(totalSize)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _UploadPalette.subtleInk,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: files.isEmpty || _isSubmitting
                      ? null
                      : () => _submit(files),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_rounded),
                  label: Text(_isSubmitting ? '上传中...' : '确认上传'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: _UploadPalette.brand,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _UploadHeroCard(
            fileCount: files.length,
            totalSizeText: _formatSize(totalSize),
          ),
          const SizedBox(height: 16),
          const _UploadChecklistCard(),
          const SizedBox(height: 20),
          _SectionHeading(
            title: '文件分组',
            subtitle: '按文件体积分层查看，避免上传前遗漏大文件或异常件',
            trailing: Text(
              '${groupedFiles.length} 组',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _UploadPalette.brand,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(height: 12),
          if (files.isEmpty)
            _EmptySelectionCard(
              onBack: () => context.pop(),
            )
          else
            ...groupedFiles.map(
              (group) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _UploadGroupCard(
                  group: group,
                  onRemove: (file) {
                    final next = [...files]..remove(file);
                    ref.read(selectedUploadFilesProvider.notifier).state = next;
                  },
                ),
              ),
            ),
        ],
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
}

class _UploadHeroCard extends StatelessWidget {
  const _UploadHeroCard({
    required this.fileCount,
    required this.totalSizeText,
  });

  final int fileCount;
  final String totalSizeText;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0C6D4F),
            Color(0xFF19815E),
            Color(0xFF3AA177),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1B0D3E2C),
            blurRadius: 24,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '上传前最后确认',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              fileCount == 0 ? '当前没有待上传文件' : '本次将提交 $fileCount 份 PDF',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '系统会自动完成字段抽取、税站核验、证据截图与台账沉淀。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.84),
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _HeroIndicator(
                  label: '总大小',
                  value: totalSizeText,
                ),
                const SizedBox(width: 12),
                _HeroIndicator(
                  label: '状态',
                  value: fileCount == 0 ? '待选择' : '待确认',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadChecklistCard extends StatelessWidget {
  const _UploadChecklistCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _UploadPalette.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _ChecklistRow(
              icon: Icons.fact_check_outlined,
              title: '文件清单已核对',
              subtitle: '确认本次仅包含需要入账核验的 PDF 发票。',
            ),
            SizedBox(height: 14),
            _ChecklistRow(
              icon: Icons.folder_open_outlined,
              title: '分组已复核',
              subtitle: '重点查看大文件分组，避免遗漏合并扫描件。',
            ),
            SizedBox(height: 14),
            _ChecklistRow(
              icon: Icons.photo_camera_back_outlined,
              title: '证据链会自动生成',
              subtitle: '上传后任务详情页会展示抽取截图与核验截图。',
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadGroupCard extends StatelessWidget {
  const _UploadGroupCard({
    required this.group,
    required this.onRemove,
  });

  final _UploadGroup group;
  final ValueChanged<UploadDraft> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _UploadPalette.outline),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: _UploadPalette.brand,
          collapsedIconColor: _UploadPalette.brand,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: _UploadPalette.ink,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _GroupBadge(label: group.badge, tone: group.tone),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                group.subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _UploadPalette.subtleInk,
                    ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(
                  label: '文件数',
                  value: '${group.files.length}',
                  tone: group.tone,
                ),
                _MetaChip(
                  label: '组大小',
                  value: _formatSize(group.totalSizeBytes),
                  tone: _UploadPalette.brand,
                ),
              ],
            ),
          ),
          children: [
            ...List.generate(group.files.length, (index) {
              final file = group.files[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == group.files.length - 1 ? 0 : 10,
                ),
                child: _UploadFileTile(
                  index: index + 1,
                  file: file,
                  tone: group.tone,
                  onRemove: () => onRemove(file),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _UploadFileTile extends StatelessWidget {
  const _UploadFileTile({
    required this.index,
    required this.file,
    required this.tone,
    required this.onRemove,
  });

  final int index;
  final UploadDraft file;
  final Color tone;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _UploadPalette.cardSubtle,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                '$index',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: _UploadPalette.ink,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatSize(file.sizeBytes),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _UploadPalette.subtleInk,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '移除此文件',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
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

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _UploadPalette.brand.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: _UploadPalette.brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _UploadPalette.ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _UploadPalette.subtleInk,
                      height: 1.45,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroIndicator extends StatelessWidget {
  const _HeroIndicator({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupBadge extends StatelessWidget {
  const _GroupBadge({
    required this.label,
    required this.tone,
  });

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tone,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
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
                  color: _UploadPalette.ink,
                ),
            children: [
              TextSpan(text: '$label '),
              TextSpan(
                text: value,
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

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
                      color: _UploadPalette.ink,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _UploadPalette.subtleInk,
                    ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

List<_UploadGroup> _buildUploadGroups(List<UploadDraft> files) {
  final groups = <_UploadGroup>[];
  final light = files.where((file) => file.sizeBytes < 1024 * 1024).toList();
  final standard = files
      .where((file) =>
          file.sizeBytes >= 1024 * 1024 && file.sizeBytes < 5 * 1024 * 1024)
      .toList();
  final large =
      files.where((file) => file.sizeBytes >= 5 * 1024 * 1024).toList();

  if (light.isNotEmpty) {
    groups.add(
      _UploadGroup(
        title: '轻量文件',
        subtitle: '通常为单页或规则发票，适合快速完成核验。',
        badge: '1 MB 以下',
        tone: _UploadPalette.success,
        files: light,
      ),
    );
  }
  if (standard.isNotEmpty) {
    groups.add(
      _UploadGroup(
        title: '常规文件',
        subtitle: '常见上传区间，建议按名称再次确认来源。',
        badge: '1 - 5 MB',
        tone: _UploadPalette.brand,
        files: standard,
      ),
    );
  }
  if (large.isNotEmpty) {
    groups.add(
      _UploadGroup(
        title: '重点复核文件',
        subtitle: '体积较大，可能包含多页扫描件，上传前建议重点确认。',
        badge: '5 MB 以上',
        tone: _UploadPalette.warning,
        files: large,
      ),
    );
  }
  return groups;
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

class _UploadGroup {
  const _UploadGroup({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.tone,
    required this.files,
  });

  final String title;
  final String subtitle;
  final String badge;
  final Color tone;
  final List<UploadDraft> files;

  int get totalSizeBytes =>
      files.fold<int>(0, (sum, file) => sum + file.sizeBytes);
}

class _UploadPalette {
  static const Color canvas = Color(0xFFF4F7F2);
  static const Color cardSubtle = Color(0xFFF7FAF8);
  static const Color brand = Color(0xFF0B6E4F);
  static const Color success = Color(0xFF1A7A5C);
  static const Color warning = Color(0xFFAA7415);
  static const Color ink = Color(0xFF173229);
  static const Color subtleInk = Color(0xFF5F756D);
  static const Color outline = Color(0xFFDCE8E1);
}
