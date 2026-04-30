import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';

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

  @override
  void dispose() {
    _qwenController.dispose();
    _invoiceModelController.dispose();
    _openrouterController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(systemConfigProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('系统配置')),
      body: config.when(
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
            padding: const EdgeInsets.all(16),
            children: [
              Text('第一版仅开放模型相关参数，不暴露 CHROME_USER_DATA_DIR。',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              _SecretStatusTile(
                  title: 'QWEN_API_KEY',
                  configured: value.qwenConfigured,
                  maskedValue: value.qwenMaskedValue),
              TextField(
                controller: _qwenController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新的 QWEN_API_KEY',
                  helperText: '留空则不更新',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _invoiceModelController,
                decoration: const InputDecoration(
                  labelText: 'QWEN_INVOICE_MODEL',
                  helperText: '发票抽取模型，例如 qwen3.5-plus',
                ),
              ),
              const SizedBox(height: 16),
              _SecretStatusTile(
                  title: 'OPENROUTER_API_KEY',
                  configured: value.openrouterConfigured,
                  maskedValue: value.openrouterMaskedValue),
              TextField(
                controller: _openrouterController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新的 OPENROUTER_API_KEY',
                  helperText: '留空则不更新',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: 'OPENROUTER_CAPTCHA_MODEL',
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final messages = await ref
                              .read(apiClientProvider)
                              .validateSystemConfig();
                          messenger.showSnackBar(
                              SnackBar(content: Text(messages.join('\n'))));
                        } catch (error) {
                          messenger.showSnackBar(
                              SnackBar(content: Text('校验失败：$error')));
                        }
                      },
                      child: const Text('校验配置'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref.read(apiClientProvider).updateSystemConfig(
                                qwenApiKey: _qwenController.text.trim().isEmpty
                                    ? null
                                    : _qwenController.text.trim(),
                                qwenInvoiceModel:
                                    _invoiceModelController.text.trim().isEmpty
                                        ? null
                                        : _invoiceModelController.text.trim(),
                                openrouterApiKey:
                                    _openrouterController.text.trim().isEmpty
                                        ? null
                                        : _openrouterController.text.trim(),
                                captchaModel:
                                    _modelController.text.trim().isEmpty
                                        ? null
                                        : _modelController.text.trim(),
                              );
                          _qwenController.clear();
                          _openrouterController.clear();
                          ref.invalidate(systemConfigProvider);
                          messenger.showSnackBar(
                              const SnackBar(content: Text('配置已保存')));
                        } catch (error) {
                          messenger.showSnackBar(
                              SnackBar(content: Text('保存失败：$error')));
                        }
                      },
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SecretStatusTile extends StatelessWidget {
  const _SecretStatusTile({
    required this.title,
    required this.configured,
    required this.maskedValue,
  });

  final String title;
  final bool configured;
  final String? maskedValue;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(configured ? '已配置：${maskedValue ?? '******'}' : '未配置'),
      leading: Icon(configured
          ? Icons.check_circle_outline
          : Icons.warning_amber_outlined),
    );
  }
}
