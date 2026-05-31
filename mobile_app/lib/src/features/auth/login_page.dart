import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../router.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _checkingBackend = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final apiBaseUrl = ref.watch(apiBaseUrlProvider);
    final endpointState = ref.watch(apiEndpointControllerProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isBusy = _submitting || _checkingBackend || authState.isLoading;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFF8FBF8),
              colorScheme.surface,
              const Color(0xFFE8F0EA),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -72,
              right: -32,
              child: _BackdropOrb(
                size: 220,
                color: colorScheme.primaryContainer.withValues(alpha: 0.88),
              ),
            ),
            Positioned(
              top: 180,
              left: -56,
              child: _BackdropOrb(
                size: 168,
                color: colorScheme.tertiaryContainer.withValues(alpha: 0.38),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '登录',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  '欢迎回来',
                                  style: theme.textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '登录后可继续处理任务进度、发票台账与导出记录。',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: const [
                                    _FeatureBadge(
                                      icon: Icons.shield_outlined,
                                      label: '账号权限控制',
                                    ),
                                    _FeatureBadge(
                                      icon: Icons.fact_check_outlined,
                                      label: '任务全程留痕',
                                    ),
                                    _FeatureBadge(
                                      icon: Icons.inventory_2_outlined,
                                      label: '台账导出可追溯',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 22),
                                TextField(
                                  controller: _usernameController,
                                  enabled: !isBusy,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: '用户名',
                                    hintText: '请输入用户名',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _passwordController,
                                  enabled: !isBusy,
                                  obscureText: true,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: '密码',
                                    hintText: '请输入密码',
                                    prefixIcon: Icon(Icons.lock_outline),
                                  ),
                                  onSubmitted: (_) => _handleLogin(context),
                                ),
                                if (authState.errorMessage != null) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.error_outline,
                                          size: 18,
                                          color: colorScheme.error,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            authState.errorMessage!,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color:
                                                  colorScheme.onErrorContainer,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                FilledButton(
                                  onPressed: isBusy
                                      ? null
                                      : () => _handleLogin(context),
                                  child: isBusy
                                      ? SizedBox(
                                          height: 20,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const SizedBox.square(
                                                dimension: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                '正在登录',
                                                style: theme
                                                    .textTheme.labelLarge
                                                    ?.copyWith(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : const Text('登录'),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '支持上传 PDF、查看任务进度、删除可清理任务并联动台账导出。',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'API：${endpointState.label} · $apiBaseUrl',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: isBusy
                                      ? null
                                      : () => ref
                                          .read(apiEndpointControllerProvider
                                              .notifier)
                                          .togglePreset(),
                                  icon: const Icon(Icons.swap_horiz_rounded),
                                  label: Text(
                                    endpointState.isLocal ? '切换到服务器' : '切换到本地',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: isBusy
                                      ? null
                                      : () => _checkBackend(context),
                                  icon: _checkingBackend
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.wifi_find_rounded),
                                  label: Text(
                                    _checkingBackend ? '正在检测后端' : '检测后端连接',
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: isBusy
                                      ? null
                                      : () => _openHealthInBrowser(context),
                                  icon:
                                      const Icon(Icons.open_in_browser_rounded),
                                  label: const Text('用 Safari 测试后端'),
                                ),
                              ],
                            ),
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
      ),
    );
  }

  Future<void> _handleLogin(BuildContext context) async {
    setState(() {
      _submitting = true;
    });
    final success = await ref.read(authControllerProvider.notifier).login(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
    if (!context.mounted) {
      return;
    }
    setState(() {
      _submitting = false;
    });
    if (success) {
      context.go('/tasks');
    }
  }

  Future<void> _checkBackend(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final apiBaseUrl = ref.read(apiBaseUrlProvider);
    setState(() {
      _checkingBackend = true;
    });
    final results = <String>[];
    try {
      try {
        await ref.read(rawApiClientProvider).checkHealth();
        results.add('Dio：成功');
      } catch (error) {
        results.add('Dio：失败 $error');
      }
      try {
        await checkHealthWithDartHttpClient(apiBaseUrl);
        results.add('Dart HttpClient：成功');
      } catch (error) {
        results.add('Dart HttpClient：失败 $error');
      }
      if (!context.mounted) {
        return;
      }
      final anySuccess = results.any((entry) => entry.contains('成功'));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            anySuccess
                ? '后端连接诊断：$apiBaseUrl；${results.join('；')}'
                : '后端连接失败：$apiBaseUrl；${results.join('；')}',
          ),
          duration: const Duration(seconds: 12),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingBackend = false;
        });
      }
    }
  }

  Future<void> _openHealthInBrowser(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final apiBaseUrl = ref.read(apiBaseUrlProvider);
    final uri = Uri.parse('$apiBaseUrl/api/health').replace(
      queryParameters: {
        'source': 'safari_button',
        'ts': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('无法打开浏览器：$uri')),
      );
    }
  }
}

class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _BackdropOrb extends StatelessWidget {
  const _BackdropOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
