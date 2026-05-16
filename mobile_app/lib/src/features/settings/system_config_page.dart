import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';

const _configGreen = Color(0xFF0B6E4F);
const _configGreenDeep = Color(0xFF073B2A);
const _configCanvas = Color(0xFFF4F8F5);
const _configLine = Color(0xFFD7E4DC);
const _configMuted = Color(0xFF5F746A);

final systemConfigProvider =
    FutureProvider.autoDispose<SystemConfigModel>((ref) {
  return ref.watch(apiClientProvider).getSystemConfig();
});

class SystemConfigPage extends ConsumerStatefulWidget {
  const SystemConfigPage({super.key});

  @override
  ConsumerState<SystemConfigPage> createState() => _SystemConfigPageState();
}

class _SystemConfigPageState extends ConsumerState<SystemConfigPage> {
  final _qwenController = TextEditingController();
  final _invoiceModelController = TextEditingController();
  final _openrouterController = TextEditingController();
  final _modelController = TextEditingController();

  bool _showQwenSecret = false;
  bool _showOpenRouterSecret = false;
  bool _isValidating = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _qwenController.dispose();
    _invoiceModelController.dispose();
    _openrouterController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _validateConfig() async {
    setState(() => _isValidating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final messages = await ref.read(apiClientProvider).validateSystemConfig();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(messages.join('\n'))),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('校验失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isValidating = false);
      }
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).updateSystemConfig(
            qwenApiKey: _qwenController.text.trim().isEmpty
                ? null
                : _qwenController.text.trim(),
            qwenInvoiceModel: _invoiceModelController.text.trim().isEmpty
                ? null
                : _invoiceModelController.text.trim(),
            openrouterApiKey: _openrouterController.text.trim().isEmpty
                ? null
                : _openrouterController.text.trim(),
            captchaModel: _modelController.text.trim().isEmpty
                ? null
                : _modelController.text.trim(),
          );
      _qwenController.clear();
      _openrouterController.clear();
      ref.invalidate(systemConfigProvider);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('配置已保存')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(systemConfigProvider);
    return Scaffold(
      backgroundColor: _configCanvas,
      appBar: AppBar(
        backgroundColor: _configCanvas,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('系统配置'),
            SizedBox(height: 2),
            Text(
              '模型与密钥控制台',
              style: TextStyle(fontSize: 12, color: _configMuted),
            ),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FBF9), Color(0xFFF2F7F3)],
          ),
        ),
        child: config.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('系统配置加载失败：$error')),
          data: (value) {
            if (_invoiceModelController.text.isEmpty) {
              _invoiceModelController.text = value.invoiceModel;
            }
            if (_modelController.text.isEmpty) {
              _modelController.text = value.captchaModel;
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _ConfigHeroCard(config: value),
                const SizedBox(height: 18),
                const _SectionHeader(
                  title: '密钥状态',
                  caption: '第一版仅开放模型相关参数，不暴露 CHROME_USER_DATA_DIR 等运行时路径。',
                ),
                const SizedBox(height: 12),
                _SecretStatusCard(
                  title: 'QWEN_API_KEY',
                  configured: value.qwenConfigured,
                  maskedValue: value.qwenMaskedValue,
                  description: '用于发票字段抽取能力。',
                ),
                const SizedBox(height: 12),
                _SecretStatusCard(
                  title: 'OPENROUTER_API_KEY',
                  configured: value.openrouterConfigured,
                  maskedValue: value.openrouterMaskedValue,
                  description: '用于验证码识别与相关模型调用。',
                ),
                const SizedBox(height: 20),
                const _SectionHeader(
                  title: '参数面板',
                  caption: '把密钥更新和模型切换收束成财务人员可读的配置录入区。',
                ),
                const SizedBox(height: 12),
                _InputPanel(
                  title: 'QWEN 发票抽取',
                  description: '更新抽取密钥或切换当前发票抽取模型。',
                  children: [
                    _SecretInputField(
                      controller: _qwenController,
                      labelText: '新的 QWEN_API_KEY',
                      helperText: '留空则不更新',
                      visible: _showQwenSecret,
                      onToggleVisibility: () {
                        setState(() => _showQwenSecret = !_showQwenSecret);
                      },
                    ),
                    const SizedBox(height: 14),
                    _ConfigTextField(
                      controller: _invoiceModelController,
                      labelText: 'QWEN_INVOICE_MODEL',
                      helperText: '例如 qwen3.5-plus',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InputPanel(
                  title: 'OPENROUTER 验证码模型',
                  description: '更新 OpenRouter 密钥或切换当前验证码识别模型。',
                  children: [
                    _SecretInputField(
                      controller: _openrouterController,
                      labelText: '新的 OPENROUTER_API_KEY',
                      helperText: '留空则不更新',
                      visible: _showOpenRouterSecret,
                      onToggleVisibility: () {
                        setState(
                          () => _showOpenRouterSecret = !_showOpenRouterSecret,
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    _ConfigTextField(
                      controller: _modelController,
                      labelText: 'OPENROUTER_CAPTCHA_MODEL',
                      helperText: '填写验证码模型标识',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _isValidating || _isSaving ? null : _validateConfig,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _configGreenDeep,
                          side: const BorderSide(color: _configLine),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        icon: _isValidating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.fact_check_outlined),
                        label: Text(_isValidating ? '校验中...' : '校验配置'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            _isSaving || _isValidating ? null : _saveConfig,
                        style: FilledButton.styleFrom(
                          backgroundColor: _configGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_isSaving ? '保存中...' : '保存配置'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ConfigHeroCard extends StatelessWidget {
  const _ConfigHeroCard({required this.config});

  final SystemConfigModel config;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_configGreen, _configGreenDeep],
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
              '配置总览',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '模型与密钥一屏管理',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '强调已配置状态、当前模型与操作动作，让配置页更像真实工作台控制面板。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  label: '密钥完成度',
                  value:
                      '${config.configuredSecretCount}/${config.totalSecretCount}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HeroMetric(
                  label: '抽取模型',
                  value: config.invoiceModelDisplay,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _HeroMetric(
            label: '验证码模型',
            value: config.captchaModelDisplay,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    this.fullWidth = false,
  });

  final String label;
  final String value;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
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
              fontSize: 18,
              fontWeight: FontWeight.w700,
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
    required this.caption,
  });

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _configGreenDeep,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: const TextStyle(color: _configMuted, height: 1.45),
        ),
      ],
    );
  }
}

class _SecretStatusCard extends StatelessWidget {
  const _SecretStatusCard({
    required this.title,
    required this.configured,
    required this.maskedValue,
    required this.description,
  });

  final String title;
  final bool configured;
  final String? maskedValue;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _configLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10073B2A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: configured
                  ? const Color(0xFFE8F3EE)
                  : const Color(0xFFF7F0E1),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(
              configured
                  ? Icons.check_circle_outline_rounded
                  : Icons.warning_amber_rounded,
              color: configured ? _configGreenDeep : const Color(0xFF7D6126),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _configGreenDeep,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  configured ? '已配置：${maskedValue ?? '******'}' : '未配置',
                  style: TextStyle(
                    color: configured
                        ? const Color(0xFF20332B)
                        : const Color(0xFF7D6126),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(color: _configMuted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InputPanel extends StatelessWidget {
  const _InputPanel({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _configLine),
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
          Text(
            title,
            style: const TextStyle(
              color: _configGreenDeep,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(color: _configMuted, height: 1.45),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _SecretInputField extends StatelessWidget {
  const _SecretInputField({
    required this.controller,
    required this.labelText,
    required this.helperText,
    required this.visible,
    required this.onToggleVisibility,
  });

  final TextEditingController controller;
  final String labelText;
  final String helperText;
  final bool visible;
  final VoidCallback onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF5F8F6),
        labelText: labelText,
        helperText: helperText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        suffixIcon: IconButton(
          tooltip: visible ? '隐藏' : '显示',
          onPressed: onToggleVisibility,
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
        ),
      ),
    );
  }
}

class _ConfigTextField extends StatelessWidget {
  const _ConfigTextField({
    required this.controller,
    required this.labelText,
    required this.helperText,
  });

  final TextEditingController controller;
  final String labelText;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF5F8F6),
        labelText: labelText,
        helperText: helperText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
