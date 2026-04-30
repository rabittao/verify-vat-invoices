import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../router.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final baseUrl = ref.watch(apiBaseUrlProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('当前用户'),
            subtitle: Text('${auth.username ?? '-'} | ${auth.role ?? '-'}'),
          ),
          ListTile(
            leading: const Icon(Icons.link_outlined),
            title: const Text('后端地址'),
            subtitle: Text(baseUrl),
          ),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('系统配置'),
            subtitle: const Text('管理员可配置模型相关参数'),
            onTap: () => context.go('/settings/system-config'),
          ),
          ListTile(
            leading: const Icon(Icons.logout_outlined),
            title: const Text('退出登录'),
            onTap: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
    );
  }
}
