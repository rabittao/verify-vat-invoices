import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_layout.dart';
import '../../core/theme/app_palette.dart';

const _configCanvas = AppPalette.canvas;

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
  final _modelController = TextEditingController();

  bool _showQwenSecret = false;
  bool _isValidating = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _qwenController.dispose();
    _invoiceModelController.dispose();
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
            captchaModel: _modelController.text.trim().isEmpty
                ? null
                : _modelController.text.trim(),
          );
      _qwenController.clear();
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
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: '返回设置',
          onPressed: () => context.go('/settings'),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: const Text(
          '系统配置',
          style: TextStyle(
            color: AppPalette.text,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppPalette.pageGradient),
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

            return LayoutBuilder(
              builder: (context, constraints) => ListView(
                padding: AppLayout.pageInsets(
                  constraints.maxWidth,
                  top: 8,
                  bottom: 118,
                ),
                children: [
                  const _SystemConfigHero(),
                  const SizedBox(height: 14),
                  _SystemConfigBoard(
                    config: value,
                    qwenController: _qwenController,
                    invoiceModelController: _invoiceModelController,
                    captchaModelController: _modelController,
                    showSecret: _showQwenSecret,
                    validating: _isValidating,
                    saving: _isSaving,
                    onToggleSecret: () {
                      setState(() => _showQwenSecret = !_showQwenSecret);
                    },
                    onValidate: _validateConfig,
                    onSave: _saveConfig,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SystemConfigHero extends StatelessWidget {
  const _SystemConfigHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(
        gradient: AppPalette.heroGradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppPalette.lineSoft),
        boxShadow: AppPalette.softShadow(0.55),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -34,
            right: -12,
            child: Container(
              width: 132,
              height: 82,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '系统配置',
                style: TextStyle(
                  color: AppPalette.primaryDeep,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '维护 QWEN API Key、发票抽取模型与验证码识别模型。',
                style: TextStyle(
                  color: AppPalette.muted,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SystemConfigBoard extends StatelessWidget {
  const _SystemConfigBoard({
    required this.config,
    required this.qwenController,
    required this.invoiceModelController,
    required this.captchaModelController,
    required this.showSecret,
    required this.validating,
    required this.saving,
    required this.onToggleSecret,
    required this.onValidate,
    required this.onSave,
  });

  final SystemConfigModel config;
  final TextEditingController qwenController;
  final TextEditingController invoiceModelController;
  final TextEditingController captchaModelController;
  final bool showSecret;
  final bool validating;
  final bool saving;
  final VoidCallback onToggleSecret;
  final VoidCallback onValidate;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;
    return Container(
      decoration: AppPalette.softCardDecoration(radius: 24),
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ConfigIconTile(
                icon: Icons.settings_suggest_rounded,
                color: AppPalette.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '模型配置',
                      style: TextStyle(
                        color: AppPalette.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      config.qwenConfigured
                          ? '密钥已配置，当前模型可直接用于抽取与验证码识别'
                          : '请先配置 QWEN API Key，保存后再执行核验任务',
                      style: const TextStyle(
                        color: AppPalette.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              _ConfigStatePill(
                label: config.qwenConfigured ? '已配置' : '未配置',
                success: config.qwenConfigured,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SecretInputField(
            controller: qwenController,
            labelText: 'QWEN API Key',
            helperText: config.qwenConfigured
                ? '当前：${config.qwenMaskedValue ?? '已隐藏'}，留空则不更新'
                : '请输入百炼 DashScope API Key',
            visible: showSecret,
            onToggleVisibility: onToggleSecret,
          ),
          const SizedBox(height: 14),
          _ConfigTextField(
            controller: invoiceModelController,
            labelText: '发票抽取模型',
            helperText: '当前建议 qwen3.6-plus',
          ),
          const SizedBox(height: 14),
          _ConfigTextField(
            controller: captchaModelController,
            labelText: '验证码模型',
            helperText: '当前建议 qwen3.6-plus',
          ),
          const SizedBox(height: 18),
          _ConfigSummaryRows(config: config),
          const SizedBox(height: 20),
          if (compact)
            Column(
              children: [
                _SaveConfigButton(
                  saving: saving,
                  disabled: validating,
                  onPressed: onSave,
                ),
                const SizedBox(height: 10),
                _ValidateConfigButton(
                  validating: validating,
                  disabled: saving,
                  onPressed: onValidate,
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _ValidateConfigButton(
                    validating: validating,
                    disabled: saving,
                    onPressed: onValidate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SaveConfigButton(
                    saving: saving,
                    disabled: validating,
                    onPressed: onSave,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ConfigSummaryRows extends StatelessWidget {
  const _ConfigSummaryRows({required this.config});

  final SystemConfigModel config;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.cardSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.lineSoft),
      ),
      child: Column(
        children: [
          _ConfigReadonlyRow(
            label: '当前抽取模型',
            value: config.invoiceModelDisplay,
            icon: Icons.document_scanner_outlined,
          ),
          const Divider(height: 1, color: AppPalette.lineSoft),
          _ConfigReadonlyRow(
            label: '当前验证码模型',
            value: config.captchaModelDisplay,
            icon: Icons.password_rounded,
          ),
          const Divider(height: 1, color: AppPalette.lineSoft),
          _ConfigReadonlyRow(
            label: '密钥完成度',
            value: '${config.configuredSecretCount}/${config.totalSecretCount}',
            icon: Icons.verified_user_outlined,
          ),
        ],
      ),
    );
  }
}

class _ConfigReadonlyRow extends StatelessWidget {
  const _ConfigReadonlyRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: AppPalette.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppPalette.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppPalette.text,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigIconTile extends StatelessWidget {
  const _ConfigIconTile({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _ConfigStatePill extends StatelessWidget {
  const _ConfigStatePill({required this.label, required this.success});

  final String label;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: success ? AppPalette.successSoft : AppPalette.warningSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: success ? AppPalette.success : AppPalette.warning,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ValidateConfigButton extends StatelessWidget {
  const _ValidateConfigButton({
    required this.validating,
    required this.disabled,
    required this.onPressed,
  });

  final bool validating;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: validating || disabled ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppPalette.primary,
        side: const BorderSide(color: AppPalette.line),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: validating
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.fact_check_outlined),
      label: Text(validating ? '校验中...' : '校验配置'),
    );
  }
}

class _SaveConfigButton extends StatelessWidget {
  const _SaveConfigButton({
    required this.saving,
    required this.disabled,
    required this.onPressed,
  });

  final bool saving;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: saving || disabled ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppPalette.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.save_outlined),
      label: Text(saving ? '保存中...' : '保存配置'),
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
        fillColor: AppPalette.cardSoft,
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
        fillColor: AppPalette.cardSoft,
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
