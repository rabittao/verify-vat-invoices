import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_layout.dart';
import '../../core/theme/app_palette.dart';
import '../../router.dart';

const _settingsCanvas = AppPalette.canvas;
const _settingsLine = AppPalette.lineSoft;
const _settingsMuted = AppPalette.muted;

final settingsExportPreviewProvider =
    FutureProvider.autoDispose<List<ExportRecordModel>>((ref) {
  return ref.watch(apiClientProvider).getExports();
});

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final endpointState = ref.watch(apiEndpointControllerProvider);
    final exportPreview = ref.watch(settingsExportPreviewProvider);
    return Scaffold(
      backgroundColor: _settingsCanvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppPalette.pageGradient),
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            physics: const BouncingScrollPhysics(),
            padding: AppLayout.pageInsets(
              constraints.maxWidth,
              top: 18,
              bottom: AppLayout.bottomNavHeight,
            ),
            children: [
              _SettingsResponsiveDashboard(
                username: auth.username ?? '-',
                role: auth.role ?? '-',
                endpointLabel: endpointState.label,
                baseUrl: baseUrl,
                isLocal: endpointState.isLocal,
                exportPreview: exportPreview,
                onEndpointChanged: (useLocal) async {
                  final controller =
                      ref.read(apiEndpointControllerProvider.notifier);
                  if (useLocal) {
                    await controller.useLocal();
                  } else {
                    await controller.useServer();
                  }
                  await ref.read(authControllerProvider.notifier).logout();
                  if (context.mounted) {
                    context.go('/login');
                  }
                },
                onModelTap: () => context.go('/settings/system-config'),
                onExportsTap: () => context.go('/exports'),
                onLogoutTap: () async {
                  await ref.read(authControllerProvider.notifier).logout();
                  if (context.mounted) {
                    context.go('/login');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsResponsiveDashboard extends StatelessWidget {
  const _SettingsResponsiveDashboard({
    required this.username,
    required this.role,
    required this.endpointLabel,
    required this.baseUrl,
    required this.isLocal,
    required this.exportPreview,
    required this.onEndpointChanged,
    required this.onModelTap,
    required this.onExportsTap,
    required this.onLogoutTap,
  });

  final String username;
  final String role;
  final String endpointLabel;
  final String baseUrl;
  final bool isLocal;
  final AsyncValue<List<ExportRecordModel>> exportPreview;
  final ValueChanged<bool> onEndpointChanged;
  final VoidCallback onModelTap;
  final VoidCallback onExportsTap;
  final VoidCallback onLogoutTap;

  @override
  Widget build(BuildContext context) {
    final hero = _SettingsHeroCard(username: username, role: role);
    final board = _SettingsWorkbenchBoard(
      endpointLabel: endpointLabel,
      baseUrl: baseUrl,
      isLocal: isLocal,
      exportPreview: exportPreview,
      onEndpointChanged: onEndpointChanged,
      onModelTap: onModelTap,
      onExportsTap: onExportsTap,
      onLogoutTap: onLogoutTap,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 880) {
          return Column(
            children: [
              hero,
              const SizedBox(height: 12),
              board,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 360, child: hero),
            const SizedBox(width: 16),
            Expanded(child: board),
          ],
        );
      },
    );
  }
}

class _SettingsWorkbenchBoard extends StatelessWidget {
  const _SettingsWorkbenchBoard({
    required this.endpointLabel,
    required this.baseUrl,
    required this.isLocal,
    required this.exportPreview,
    required this.onEndpointChanged,
    required this.onModelTap,
    required this.onExportsTap,
    required this.onLogoutTap,
  });

  final String endpointLabel;
  final String baseUrl;
  final bool isLocal;
  final AsyncValue<List<ExportRecordModel>> exportPreview;
  final ValueChanged<bool> onEndpointChanged;
  final VoidCallback onModelTap;
  final VoidCallback onExportsTap;
  final VoidCallback onLogoutTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final endpointCard = _EndpointSwitchCard(
          label: endpointLabel,
          baseUrl: baseUrl,
          isLocal: isLocal,
          onChanged: onEndpointChanged,
        );
        final modelCard = _SettingsPreviewSection(
          icon: Icons.settings_suggest_rounded,
          title: '模型配置',
          trailingText: 'Qwen3.6 Plus',
          onTap: onModelTap,
          rows: const [
            _SettingsInfoRow(label: '当前模型', value: 'Qwen3.6 Plus'),
            _SettingsInfoRow(label: '模型 Code', value: 'qwen3.6-plus'),
          ],
        );
        final exportCard = _SettingsExportPreviewSection(
          icon: Icons.file_download_done_rounded,
          title: '导出记录',
          trailingText: '全部记录',
          onTap: onExportsTap,
          exports: exportPreview,
        );
        final miscCard = _SettingsPreviewSection(
          icon: Icons.tune_rounded,
          title: '其他设置',
          trailingText: '管理',
          onTap: onLogoutTap,
          rows: const [
            _SettingsInfoRow(label: '清除缓存', value: '约 12.4 MB'),
            _SettingsInfoRow(label: '退出登录', value: '切换账号或交班'),
          ],
        );

        if (constraints.maxWidth < 780) {
          return Column(
            children: [
              endpointCard,
              const SizedBox(height: 12),
              modelCard,
              const SizedBox(height: 12),
              exportCard,
              const SizedBox(height: 12),
              miscCard,
            ],
          );
        }
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: endpointCard),
                const SizedBox(width: 14),
                Expanded(child: modelCard),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: exportCard),
                const SizedBox(width: 14),
                Expanded(child: miscCard),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SettingsAccountCard extends StatelessWidget {
  const _SettingsAccountCard({
    required this.username,
    required this.role,
  });

  final String username;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(16),
      decoration: AppPalette.softCardDecoration(radius: 22, shadowAlpha: 0.55),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppPalette.primaryGradient,
              boxShadow: AppPalette.softShadow(0.45),
            ),
            child: const Icon(Icons.person_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  username,
                  style: const TextStyle(
                    color: AppPalette.primaryDeep,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  role,
                  style: const TextStyle(
                    color: AppPalette.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppPalette.primaryDeep),
        ],
      ),
    );
  }
}

class _SettingsPreviewSection extends StatelessWidget {
  const _SettingsPreviewSection({
    required this.icon,
    required this.title,
    required this.trailingText,
    required this.rows,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String trailingText;
  final List<_SettingsInfoRow> rows;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          decoration:
              AppPalette.softCardDecoration(radius: 22, shadowAlpha: 0.5),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppPalette.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 19, color: AppPalette.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppPalette.primaryDeep,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    trailingText,
                    style: const TextStyle(
                      color: AppPalette.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppPalette.primaryDeep,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final row in rows) row,
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  const _SettingsInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppPalette.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppPalette.primaryDeep,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsExportPreviewSection extends StatelessWidget {
  const _SettingsExportPreviewSection({
    required this.icon,
    required this.title,
    required this.trailingText,
    required this.exports,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String trailingText;
  final AsyncValue<List<ExportRecordModel>> exports;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          decoration:
              AppPalette.softCardDecoration(radius: 22, shadowAlpha: 0.5),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppPalette.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 19, color: AppPalette.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppPalette.primaryDeep,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    trailingText,
                    style: const TextStyle(
                      color: AppPalette.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppPalette.primaryDeep,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              exports.when(
                loading: () => const _SettingsExportPlaceholder(
                  label: '正在同步导出记录',
                  value: '请稍候',
                  icon: Icons.sync_rounded,
                ),
                error: (_, __) => const _SettingsExportPlaceholder(
                  label: '导出记录暂不可用',
                  value: '点击查看',
                  icon: Icons.cloud_off_outlined,
                ),
                data: (items) {
                  final latest = items.take(3).toList();
                  if (latest.isEmpty) {
                    return const _SettingsExportPlaceholder(
                      label: '暂无导出记录',
                      value: '点击创建',
                      icon: Icons.inbox_outlined,
                    );
                  }
                  return Column(
                    children: [
                      for (var index = 0; index < latest.length; index++) ...[
                        _SettingsExportRow(item: latest[index]),
                        if (index != latest.length - 1)
                          const Divider(
                            height: 1,
                            color: AppPalette.lineSoft,
                          ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsExportRow extends StatelessWidget {
  const _SettingsExportRow({required this.item});

  final ExportRecordModel item;

  @override
  Widget build(BuildContext context) {
    final completed = item.status == 'completed';
    final processing = item.status == 'pending' || item.status == 'processing';
    final tone = completed
        ? AppPalette.success
        : processing
            ? AppPalette.primary
            : AppPalette.danger;
    final toneSoft = completed
        ? AppPalette.successSoft
        : processing
            ? AppPalette.primarySoft
            : AppPalette.dangerSoft;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: toneSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              item.exportType == 'invoice_list_excel'
                  ? Icons.grid_on_rounded
                  : Icons.picture_as_pdf_outlined,
              size: 18,
              color: tone,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.fileDisplayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppPalette.primaryDeep,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.createdAt.trim().isEmpty
                      ? item.exportTypeLabel
                      : item.createdAt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppPalette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: toneSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (completed)
                  Icon(Icons.check_circle_rounded, color: tone, size: 14)
                else if (processing)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tone,
                    ),
                  )
                else
                  Icon(Icons.error_rounded, color: tone, size: 14),
                const SizedBox(width: 4),
                Text(
                  item.statusLabel,
                  style: TextStyle(
                    color: tone,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsExportPlaceholder extends StatelessWidget {
  const _SettingsExportPlaceholder({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppPalette.cardSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.lineSoft),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppPalette.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppPalette.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppPalette.primaryDeep,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsHeroCard extends StatelessWidget {
  const _SettingsHeroCard({
    required this.username,
    required this.role,
  });

  final String username;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 224),
      padding: const EdgeInsets.fromLTRB(22, 54, 22, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFCFF0FF), Color(0xFFF8FDFF), Color(0xFFEAF8FF)],
        ),
        boxShadow: AppPalette.softShadow(0.65),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            top: -42,
            right: 4,
            child: _HeaderCloud(size: 120),
          ),
          const Positioned(
            top: 28,
            right: -18,
            child: _HeaderCloud(size: 82),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '导出与配置',
                style: TextStyle(
                  color: AppPalette.primaryDeep,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '管理应用配置与导出历史',
                style: TextStyle(
                  color: AppPalette.primaryDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              _SettingsAccountCard(
                username: username,
                role: role,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderCloud extends StatelessWidget {
  const _HeaderCloud({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size * 0.58,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(size),
        ),
      ),
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppPalette.primarySoft,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: AppPalette.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppPalette.primaryDeep,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _EndpointSwitchCard extends StatelessWidget {
  const _EndpointSwitchCard({
    required this.label,
    required this.baseUrl,
    required this.isLocal,
    required this.onChanged,
  });

  final String label;
  final String baseUrl;
  final bool isLocal;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _settingsLine),
        boxShadow: const [
          BoxShadow(
            color: AppPalette.shadow,
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SettingsSectionTitle(
            icon: Icons.dns_rounded,
            title: 'API 环境',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _EndpointOption(
                  title: '本地后端',
                  value: localApiBaseUrl,
                  selected: isLocal,
                  onTap: () => onChanged(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EndpointOption(
                  title: '服务器后端',
                  value: serverApiBaseUrl,
                  selected: !isLocal,
                  onTap: () => onChanged(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '当前：$label · $baseUrl',
            style: const TextStyle(
              color: _settingsMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EndpointOption extends StatelessWidget {
  const _EndpointOption({
    required this.title,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: selected ? null : onTap,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AppPalette.skySoft : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppPalette.primary : AppPalette.lineSoft,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppPalette.primaryDeep,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? AppPalette.primary : AppPalette.line,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppPalette.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
