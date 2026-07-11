import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/models/app_state_models.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_palette.dart';
import '../../router.dart';

final taskListProvider =
    AutoDisposeAsyncNotifierProvider<TaskListController, TaskListState>(
  TaskListController.new,
);

bool get _supportsCameraQrScan {
  if (kIsWeb) {
    return false;
  }
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

class TaskListController extends AutoDisposeAsyncNotifier<TaskListState> {
  static const _defaultCompletedPageSize = 20;

  @override
  Future<TaskListState> build() async {
    final taskState = await ref.watch(apiClientProvider).getTasks(
          completedPage: 1,
          completedPageSize: _defaultCompletedPageSize,
        );
    if (taskState.runningTasks.isNotEmpty) {
      final timer = Timer(const Duration(seconds: 3), ref.invalidateSelf);
      ref.onDispose(timer.cancel);
    }
    return taskState;
  }

  Future<void> refreshTasks() async {
    final current = state.valueOrNull;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    state = AsyncData(
      current.copyWith(
        isRefreshing: true,
        isLoadingMore: false,
        errorMessage: null,
      ),
    );
    try {
      final refreshed = await ref.read(apiClientProvider).getTasks(
            completedPage: 1,
            completedPageSize: current.completedPageInfo.pageSize,
          );
      state = AsyncData(refreshed);
    } catch (error) {
      state = AsyncData(
        current.copyWith(
          isRefreshing: false,
          isLoadingMore: false,
          errorMessage: _humanizeTaskListError(error),
        ),
      );
    }
  }

  Future<void> loadMoreCompletedTasks() async {
    final current = state.valueOrNull;
    if (current == null ||
        current.isLoadingMore ||
        !current.completedPageInfo.hasNext) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        isLoadingMore: true,
        errorMessage: null,
      ),
    );
    try {
      final nextPage = current.completedPageInfo.page + 1;
      final next = await ref.read(apiClientProvider).getTasks(
            completedPage: nextPage,
            completedPageSize: current.completedPageInfo.pageSize,
          );
      state = AsyncData(
        next.copyWith(
          completedTasks: [
            ...current.completedTasks,
            ...next.completedTasks,
          ],
          isLoadingMore: false,
          errorMessage: null,
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(
          isLoadingMore: false,
          errorMessage: _humanizeTaskListError(error),
        ),
      );
    }
  }
}

String _humanizeTaskListError(Object error) {
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return '后端服务暂时无法连接，请确认本地服务已经启动。';
    }
    if (error.response?.statusCode == 401) {
      return '登录状态已失效，请重新登录后再查看任务列表。';
    }
    final detail = error.response?.data;
    if (detail is Map<String, dynamic>) {
      final message = detail['detail'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    }
  }
  return '请检查网络或后端服务状态。';
}

class TaskListPage extends ConsumerWidget {
  const TaskListPage({super.key});

  static const maxUploadFiles = 10;
  static const maxTotalBytes = 50 * 1024 * 1024;
  static const maxSingleBytes = 15 * 1024 * 1024;

  Future<void> _pickPdfFiles(BuildContext context, WidgetRef ref) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, '打开文件选择器失败：$error');
      }
      return;
    }
    if (result == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final files = result.files;
    final drafts = <UploadDraft>[];
    final totalBytes = files.fold<int>(0, (sum, file) => sum + file.size);
    if (files.length > maxUploadFiles) {
      _showMessage(context, '最多上传 10 个 PDF');
      return;
    }
    if (totalBytes > maxTotalBytes ||
        files.any((file) => file.size > maxSingleBytes)) {
      _showMessage(context, '文件数量或大小超过限制');
      return;
    }
    for (final file in files) {
      final bytes = file.bytes;
      if (bytes == null) {
        _showMessage(context, '无法读取文件：${file.name}');
        return;
      }
      drafts.add(
        UploadDraft(name: file.name, bytes: bytes, sizeBytes: file.size),
      );
    }
    if (drafts.length == 1) {
      await _uploadAndOpenTask(context, ref, drafts);
      return;
    }
    if (!context.mounted) {
      return;
    }
    ref.read(selectedUploadFilesProvider.notifier).state = drafts;
    context.go('/tasks/upload-review');
  }

  Future<void> _uploadAndOpenTask(
    BuildContext context,
    WidgetRef ref,
    List<UploadDraft> drafts,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        const SnackBar(content: Text('正在上传并创建核验任务...')),
      );
      final jobId = await ref.read(apiClientProvider).uploadTask(drafts);
      ref.invalidate(taskListProvider);
      if (context.mounted) {
        context.go('/tasks/$jobId');
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('上传失败：$error')));
    }
  }

  Future<void> _showQrUploadDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _QrUploadDialog(cameraScanEnabled: _supportsCameraQrScan),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh(WidgetRef ref) async {
    await ref.read(taskListProvider.notifier).refreshTasks();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskList = ref.watch(taskListProvider);
    const background = AppPalette.canvas;

    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          RefreshIndicator(
            edgeOffset: 12,
            onRefresh: () => _refresh(ref),
            child: taskList.when(
              loading: () => const _LoadingState(),
              error: (error, _) => _OfflineTaskWorkbench(
                message: _humanizeTaskListError(error),
                onRetry: () => ref.invalidate(taskListProvider),
                onQrPressed: () => _showQrUploadDialog(context),
                onUploadPressed: () => _pickPdfFiles(context, ref),
              ),
              data: (state) => LayoutBuilder(
                builder: (context, constraints) => ListView(
                  key: const ValueKey('invoice-workbench-v3'),
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: _homePageInsets(constraints.maxWidth),
                  children: [
                    _TaskHomeHero(state: state),
                    if (state.isRefreshing) ...[
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(minHeight: 3),
                    ],
                    const SizedBox(height: 14),
                    _TaskPanelsGrid(
                      state: state,
                      onQrPressed: () => _showQrUploadDialog(context),
                      onUploadPressed: () => _pickPdfFiles(context, ref),
                      onLoadMore: () => ref
                          .read(taskListProvider.notifier)
                          .loadMoreCompletedTasks(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _offlineTaskListState = TaskListState(
  isLoading: false,
  isRefreshing: false,
  runningTasks: [],
  completedTasks: [],
  completedPageInfo: PageInfo.initial(),
);

EdgeInsets _homePageInsets(double viewportWidth) {
  final side = switch (viewportWidth) {
    >= 1200 => 48.0,
    >= 900 => 36.0,
    >= 600 => 28.0,
    _ => 16.0,
  };
  return EdgeInsets.fromLTRB(side, 18, side, 164);
}

class _TaskPanelsGrid extends StatelessWidget {
  const _TaskPanelsGrid({
    required this.state,
    required this.onQrPressed,
    required this.onUploadPressed,
    required this.onLoadMore,
  });

  final TaskListState state;
  final VoidCallback onQrPressed;
  final VoidCallback onUploadPressed;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final runningPanel = _RunningTasksPanel(
          state: state,
          onQrPressed: onQrPressed,
          onUploadPressed: onUploadPressed,
        );
        final completedPanel = _CompletedTasksPreview(
          state: state,
          onLoadMore: onLoadMore,
        );
        if (constraints.maxWidth < 700) {
          return Column(
            children: [
              runningPanel,
              const SizedBox(height: 18),
              completedPanel,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: runningPanel),
            const SizedBox(width: 18),
            Expanded(flex: 5, child: completedPanel),
          ],
        );
      },
    );
  }
}

class _TaskHomeHero extends StatelessWidget {
  const _TaskHomeHero({required this.state});

  final TaskListState state;

  @override
  Widget build(BuildContext context) {
    final total = state.totalProcessedRecords;
    final progress =
        total == 0 ? 0.72 : (state.totalSuccessCount / total).clamp(0.0, 1.0);
    return Container(
      constraints: const BoxConstraints(minHeight: 300),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFCFF0FF), Color(0xFFF8FDFF), Color(0xFFEAF8FF)],
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Stack(
        children: [
          const Positioned(top: 84, right: 14, child: _CloudBlob(size: 122)),
          const Positioned(top: 28, right: -30, child: _CloudBlob(size: 78)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 28, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '发票核验工作台',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: AppPalette.primaryDeep,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.8,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '今日任务进度一目了然',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppPalette.primaryDeep,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '通知',
                      onPressed: () {},
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                        color: AppPalette.primaryDeep,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.schedule_rounded,
                        title: '进行中',
                        value: '${state.runningTasks.length}',
                        subtitle: '个任务',
                        highlighted: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.check_circle_rounded,
                        title: '今日完成',
                        value: '${state.completedTasks.length}',
                        subtitle: '个任务',
                        tone: AppPalette.success,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.description_rounded,
                        title: '成功入台账',
                        value: '${state.totalSuccessCount}',
                        subtitle: '张发票',
                        tone: AppPalette.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: AppPalette.softCardDecoration(radius: 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '今日总体进度',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: AppPalette.primaryDeep,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          Text(
                            '${(progress * 100).round()}%',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: AppPalette.primaryDeep,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: progress,
                          backgroundColor: AppPalette.progressTrack,
                          color: AppPalette.primary,
                        ),
                      ),
                    ],
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

class _CloudBlob extends StatelessWidget {
  const _CloudBlob({required this.size});

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

class _QrUploadDialog extends ConsumerStatefulWidget {
  const _QrUploadDialog({
    required this.cameraScanEnabled,
  });

  final bool cameraScanEnabled;

  @override
  ConsumerState<_QrUploadDialog> createState() => _QrUploadDialogState();
}

class _QrUploadDialogState extends ConsumerState<_QrUploadDialog> {
  final _controller = TextEditingController();
  MobileScannerController? _scannerController;
  QrInvoiceParseResult? _result;
  String? _parsedRawText;
  String? _errorMessage;
  bool _submitting = false;
  bool _cameraMode = false;

  @override
  void dispose() {
    _controller.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  void _openCameraScanner() {
    setState(() {
      _scannerController ??= MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        formats: const [BarcodeFormat.qrCode],
      );
      _cameraMode = true;
      _errorMessage = null;
      _result = null;
      _parsedRawText = null;
    });
  }

  Future<void> _closeCameraScanner() async {
    await _scannerController?.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _cameraMode = false;
    });
  }

  Future<void> _handleBarcodeCapture(BarcodeCapture capture) async {
    if (_submitting || !_cameraMode) {
      return;
    }
    String? rawValue;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        rawValue = value;
        break;
      }
    }
    if (rawValue == null) {
      return;
    }
    _controller.text = rawValue;
    await _parse(closeScanner: true);
  }

  Future<void> _parse({bool closeScanner = false}) async {
    final rawText = _controller.text.trim();
    await _parseRawText(rawText, closeScanner: closeScanner);
  }

  Future<QrInvoiceParseResult?> _parseRawText(
    String rawText, {
    bool closeScanner = false,
  }) async {
    if (rawText.isEmpty) {
      setState(() {
        _errorMessage = '请先扫码或粘贴二维码内容';
        _result = null;
        _parsedRawText = null;
      });
      return null;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    if (closeScanner) {
      await _scannerController?.stop();
      if (!mounted) {
        return null;
      }
      setState(() {
        _cameraMode = false;
      });
    }
    try {
      final result = await ref.read(apiClientProvider).parseInvoiceQr(rawText);
      if (!mounted) {
        return null;
      }
      setState(() {
        _result = result;
        _parsedRawText = rawText;
        _submitting = false;
      });
      return result;
    } catch (error) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _errorMessage = '二维码解析失败：${_humanizeTaskListError(error)}';
        _result = null;
        _parsedRawText = null;
        _submitting = false;
      });
      return null;
    }
  }

  Future<void> _verify() async {
    final rawText = _controller.text.trim();
    var result = _result;
    if (result == null || _parsedRawText != rawText) {
      result = await _parseRawText(rawText);
      if (!mounted || result == null) {
        return;
      }
    }
    if (result.validationStatus != 'pass') {
      setState(() {
        _errorMessage = '二维码字段不完整，不能创建核验任务';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final jobId = await ref.read(apiClientProvider).verifyInvoiceQr(rawText);
      ref.invalidate(taskListProvider);
      if (!mounted) {
        return;
      }
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.go('/tasks/$jobId');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '创建核验任务失败：${_humanizeTaskListError(error)}';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.88;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: maxDialogHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppPalette.lineSoft),
            boxShadow: AppPalette.softShadow(0.95),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Center(
                            child: Text(
                              '扫码上传发票信息',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: AppPalette.primaryDeep,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          Positioned(
                            right: -8,
                            top: -8,
                            child: IconButton(
                              tooltip: '关闭',
                              onPressed: _submitting
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (_result == null) ...[
                        _QrCameraButton(
                          cameraMode: _cameraMode,
                          enabled: widget.cameraScanEnabled && !_submitting,
                          onPressed: _cameraMode
                              ? _closeCameraScanner
                              : _openCameraScanner,
                        ),
                      ],
                      if (_cameraMode) ...[
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: SizedBox(
                            height: 260,
                            child: MobileScanner(
                              controller: _scannerController,
                              onDetect: _handleBarcodeCapture,
                            ),
                          ),
                        ),
                      ],
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        _QrFeedbackBox(
                          color: AppPalette.dangerSoft,
                          textColor: AppPalette.danger,
                          icon: Icons.error_outline_rounded,
                          message: _errorMessage!,
                        ),
                      ],
                      if (_result != null) ...[
                        const SizedBox(height: 12),
                        _QrResultCard(result: _result!),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              if (_result != null)
                _QrDialogActions(
                  submitting: _submitting,
                  onClose: () => Navigator.of(context).pop(),
                  onVerify: _verify,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrDialogActions extends StatelessWidget {
  const _QrDialogActions({
    required this.submitting,
    required this.onClose,
    required this.onVerify,
  });

  final bool submitting;
  final VoidCallback onClose;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppPalette.lineSoft)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: submitting ? null : onClose,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 50),
                foregroundColor: AppPalette.primaryDeep,
                side: const BorderSide(color: AppPalette.lineSoft),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
              child: const Text('关闭'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: submitting ? null : onVerify,
              icon: submitting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified_rounded),
              label: Text(submitting ? '处理中' : '确认核验'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 50),
                backgroundColor: AppPalette.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrCameraButton extends StatelessWidget {
  const _QrCameraButton({
    required this.cameraMode,
    required this.enabled,
    required this.onPressed,
  });

  final bool cameraMode;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = cameraMode ? '关闭摄像头' : '打开摄像头扫码';
    return Opacity(
      opacity: enabled ? 1 : 0.58,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          gradient: AppPalette.primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppPalette.softShadow(0.7),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  cameraMode
                      ? Icons.keyboard_rounded
                      : Icons.photo_camera_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QrResultCard extends StatelessWidget {
  const _QrResultCard({required this.result});

  final QrInvoiceParseResult result;

  @override
  Widget build(BuildContext context) {
    final passed = result.validationStatus == 'pass';
    final amount = result.totalAmount?.trim().isNotEmpty == true
        ? result.totalAmount
        : result.pretaxAmount;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FDFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.lineSoft),
        boxShadow: AppPalette.softShadow(0.22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color:
                      passed ? AppPalette.successSoft : AppPalette.warningSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  passed ? Icons.check_rounded : Icons.info_outline_rounded,
                  size: 18,
                  color: passed ? AppPalette.success : AppPalette.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  passed ? '二维码解析成功' : '二维码解析待补充',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppPalette.primaryDeep,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            result.cacheHit
                ? '${result.parseMessage}（缓存命中）'
                : result.parseMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppPalette.muted,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          _QrResultRow(label: '发票号码', value: result.invoiceNumber),
          _QrResultRow(label: '开票日期', value: result.invoiceDate),
          _QrResultRow(label: '金额（含税）', value: amount),
          _QrResultRow(label: '校验码', value: result.checkCode),
          if (result.validationErrors.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '缺失字段：${result.validationErrors.join('、')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF955B20),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QrResultRow extends StatelessWidget {
  const _QrResultRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.muted,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value?.trim().isNotEmpty == true ? value! : '-',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppPalette.primaryDeep,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrFeedbackBox extends StatelessWidget {
  const _QrFeedbackBox({
    required this.color,
    required this.textColor,
    required this.icon,
    required this.message,
  });

  final Color color;
  final Color textColor;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.tone = AppPalette.primary,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color tone;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.lineSoft),
        boxShadow: AppPalette.softShadow(0.48),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: tone),
            const SizedBox(height: 7),
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppPalette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppPalette.primary,
                fontWeight: FontWeight.w900,
                height: 0.95,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunningTasksPanel extends StatelessWidget {
  const _RunningTasksPanel({
    required this.state,
    required this.onQrPressed,
    required this.onUploadPressed,
  });

  final TaskListState state;
  final VoidCallback onQrPressed;
  final VoidCallback onUploadPressed;

  @override
  Widget build(BuildContext context) {
    final runningTasks = state.runningTasks;
    final leadTask = runningTasks.isNotEmpty
        ? runningTasks.first
        : state.completedTasks.isNotEmpty
            ? state.completedTasks.first
            : null;
    final overflowTasks = runningTasks.skip(1).take(2).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppPalette.softCardDecoration(radius: 22, shadowAlpha: 0.64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '进行中的任务',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppPalette.primaryDeep,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              Text(
                '${runningTasks.length}个',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppPalette.muted,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (leadTask == null)
            const _PanelEmptyState()
          else ...[
            _ActiveTaskFeatureCard(
              task: leadTask,
              isFallbackCompleted: runningTasks.isEmpty,
            ),
            if (overflowTasks.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...overflowTasks.map(
                (task) => _CompactTaskStrip(task: task),
              ),
            ],
          ],
          const SizedBox(height: 12),
          _TaskCardActions(
            onQrPressed: onQrPressed,
            onUploadPressed: onUploadPressed,
          ),
        ],
      ),
    );
  }
}

class _ActiveTaskFeatureCard extends StatelessWidget {
  const _ActiveTaskFeatureCard({
    required this.task,
    required this.isFallbackCompleted,
  });

  final TaskCardModel task;
  final bool isFallbackCompleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = task.isFinished ? 1.0 : task.progressValue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.go('/tasks/${task.jobId}'),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppPalette.lineSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppPalette.primarySoft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.description_rounded,
                      color: AppPalette.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.sourceSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppPalette.primaryDeep,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '任务编号  ${task.jobId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppPalette.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _StatusChip(
                    label: isFallbackCompleted ? '最近完成' : task.stageLabel,
                    foreground: AppPalette.primary,
                    background: AppPalette.primarySoft,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  _TaskInlineMetric(
                    label: '发票数量',
                    value: '${task.totalRecords} 张',
                  ),
                  _TaskInlineMetric(
                    label: '开始时间',
                    value:
                        task.createdAtText.isEmpty ? '待同步' : task.createdAtText,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 7,
                        value: task.progressPercent <= 0 && !task.isFinished
                            ? null
                            : progress,
                        backgroundColor: AppPalette.progressTrack,
                        color: AppPalette.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    '${task.progressPercent}%',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppPalette.primaryDeep,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppPalette.skySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 18,
                      color: AppPalette.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.isFinished
                            ? '任务已处理完成，可进入详情查看截图和入账结果。'
                            : '正在核验中，请稍候，完成后会自动入账。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppPalette.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactTaskStrip extends StatelessWidget {
  const _CompactTaskStrip({required this.task});

  final TaskCardModel task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => context.go('/tasks/${task.jobId}'),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppPalette.cardSoft,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppPalette.lineSoft),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.receipt_long_rounded,
                  color: AppPalette.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    task.sourceSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppPalette.primaryDeep,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${task.progressPercent}%',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletedTasksPreview extends StatelessWidget {
  const _CompletedTasksPreview({
    required this.state,
    required this.onLoadMore,
  });

  final TaskListState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final tasks = state.completedTasks.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppPalette.softCardDecoration(radius: 22, shadowAlpha: 0.36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '已完成任务',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppPalette.primaryDeep,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              Text(
                '共 ${state.completedPageInfo.total} 个',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppPalette.muted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (tasks.isEmpty)
            const _PanelEmptyState(
              message: '完成后的核验任务会自动归档在这里，便于后续追踪。',
            )
          else
            ...tasks.map(
              (task) => _TaskCard(
                task: task,
                isCompleted: true,
                compactInPanel: true,
              ),
            ),
          _CompletedTasksFooter(
            state: state,
            onLoadMore: onLoadMore,
          ),
        ],
      ),
    );
  }
}

class _PanelEmptyState extends StatelessWidget {
  const _PanelEmptyState({
    this.message = '当前没有核验队列，可扫码或上传 PDF 创建新任务。',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: AppPalette.skySoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.lineSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.inbox_outlined,
              color: AppPalette.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.muted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedTasksFooter extends StatelessWidget {
  const _CompletedTasksFooter({
    required this.state,
    required this.onLoadMore,
  });

  final TaskListState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final pageInfo = state.completedPageInfo;
    if (state.completedTasks.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final loaded = state.completedTasks.length;
    final total = pageInfo.total;
    final message =
        total <= loaded ? '已加载全部历史任务' : '已加载 $loaded / $total 个历史任务';

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Column(
        children: [
          if (state.errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF2D2B6)),
              ),
              child: Text(
                '加载更多失败：${state.errorMessage}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8A4A22),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppPalette.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (pageInfo.hasNext)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: state.isLoadingMore ? null : onLoadMore,
                icon: state.isLoadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(state.isLoadingMore ? '正在加载历史任务...' : '加载更多历史任务'),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppPalette.cardSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppPalette.lineSoft),
              ),
              child: Text(
                '没有更多历史任务了',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    this.isCompleted = false,
    this.compactInPanel = false,
  });

  final TaskCardModel task;
  final bool isCompleted;
  final bool compactInPanel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final palette = _TaskPalette.resolve(
      colorScheme,
      task: task,
      isCompleted: isCompleted,
    );

    final card = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(compactInPanel ? 16 : 18),
          onTap: () => context.go('/tasks/${task.jobId}'),
          child: Ink(
            decoration: BoxDecoration(
              color: compactInPanel ? AppPalette.cardSoft : Colors.white,
              borderRadius: BorderRadius.circular(compactInPanel ? 16 : 18),
              border: Border.all(color: AppPalette.lineSoft),
              boxShadow:
                  compactInPanel ? const [] : AppPalette.softShadow(0.36),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  task.sourceSummary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: AppPalette.primaryDeep,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                _StatusChip(
                                  label: isCompleted ? '已完成' : '进行中',
                                  foreground: palette.foreground,
                                  background: palette.container,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '任务编号 ${task.jobId}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppPalette.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 18,
                              runSpacing: 8,
                              children: [
                                _TaskInlineMetric(
                                    label: '文件数',
                                    value: '${task.safeSourceFileCount}'),
                                _TaskInlineMetric(
                                    label: '记录数',
                                    value: '${task.totalRecords}'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 18,
                              runSpacing: 8,
                              children: [
                                _TaskInlineMetric(
                                    label: '成功',
                                    value: '${task.successCount}',
                                    success: true),
                                _TaskInlineMetric(
                                    label: '失败',
                                    value: '${task.failedCount}',
                                    error: true),
                                _TaskInlineMetric(
                                    label: '跳过', value: '${task.skippedCount}'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              task.timelineSummary
                                  .replaceFirst('更新于 ', '开始时间 ')
                                  .replaceFirst('创建于 ', '开始时间 '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppPalette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: palette.container,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${task.progressPercent}%',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: palette.foreground,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  task.stageLabel,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: palette.foreground.withValues(
                                      alpha: 0.82,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: task.isFinished
                          ? 1
                          : task.progressPercent <= 0
                              ? null
                              : task.progressValue,
                      backgroundColor: AppPalette.progressTrack,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        palette.foreground,
                      ),
                    ),
                  ),
                  if (!compactInPanel && task.sourceFileNames.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: task.sourceFileNames
                          .take(3)
                          .map(
                            (fileName) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                fileName,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!isCompleted) {
      return card;
    }
    return _CompletedTaskSwipeDelete(task: task, child: card);
  }
}

class _TaskInlineMetric extends StatelessWidget {
  const _TaskInlineMetric({
    required this.label,
    required this.value,
    this.success = false,
    this.error = false,
  });

  final String label;
  final String value;
  final bool success;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error
        ? AppPalette.danger
        : success
            ? AppPalette.success
            : AppPalette.text;
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.muted,
            ),
        children: [
          TextSpan(text: '$label  '),
          TextSpan(
            text: value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedTaskSwipeDelete extends ConsumerWidget {
  const _CompletedTaskSwipeDelete({
    required this.task,
    required this.child,
  });

  final TaskCardModel task;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('completed-task-${task.jobId}'),
      direction: DismissDirection.endToStart,
      background: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppPalette.danger,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(right: 22),
              child: Icon(
                Icons.delete_outline_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
      confirmDismiss: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        if (!task.deletable) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(task.deleteBlockReason ?? '该任务当前不可删除'),
            ),
          );
          return false;
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除已完成任务'),
            content: Text('确认删除任务 ${task.jobId} 吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) {
          return false;
        }
        try {
          await ref.read(apiClientProvider).deleteTask(task.jobId);
          ref.invalidate(taskListProvider);
          messenger.showSnackBar(
            const SnackBar(content: Text('任务已删除')),
          );
          return true;
        } on DioException catch (error) {
          final responseData = error.response?.data;
          final detail = responseData is Map<String, dynamic>
              ? responseData['detail'] as String?
              : null;
          messenger.showSnackBar(
            SnackBar(
              content: Text('删除失败：${detail ?? error.message ?? error}'),
            ),
          );
          return false;
        } catch (error) {
          messenger.showSnackBar(
            SnackBar(content: Text('删除失败：$error')),
          );
          return false;
        }
      },
      child: child,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: foreground),
      ),
    );
  }
}

class _TaskCardActions extends StatelessWidget {
  const _TaskCardActions({
    required this.onQrPressed,
    required this.onUploadPressed,
  });

  final VoidCallback onQrPressed;
  final VoidCallback onUploadPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: onQrPressed,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('扫码上传'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.primary,
                side: const BorderSide(color: AppPalette.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: onUploadPressed,
              icon: const Icon(Icons.upload_rounded),
              label: const Text('上传发票'),
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OfflineTaskWorkbench extends StatelessWidget {
  const _OfflineTaskWorkbench({
    required this.message,
    required this.onRetry,
    required this.onQrPressed,
    required this.onUploadPressed,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onQrPressed;
  final VoidCallback onUploadPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: _homePageInsets(MediaQuery.sizeOf(context).width),
      children: [
        const _TaskHomeHero(state: _offlineTaskListState),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppPalette.softCardDecoration(radius: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppPalette.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.cloud_off_outlined,
                      color: AppPalette.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '任务列表暂时不可用',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppPalette.primaryDeep,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppPalette.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _TaskCardActions(
                onQrPressed: onQrPressed,
                onUploadPressed: onUploadPressed,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新加载任务列表'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 118),
      children: [
        Container(
          height: 220,
          decoration: BoxDecoration(
            gradient: AppPalette.heroGradient,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: AppPalette.lineSoft),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '正在载入任务工作台',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: AppPalette.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '正在同步最新任务、核验结果与历史记录。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppPalette.muted,
                ),
              ),
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(minHeight: 8),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Card(
              child: SizedBox(
                height: 148,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 18,
                        width: 160,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 12,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 220,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const Spacer(),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 7,
                          value: 0.5,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TaskPalette {
  const _TaskPalette({
    required this.surface,
    required this.container,
    required this.foreground,
    required this.border,
  });

  final Color surface;
  final Color container;
  final Color foreground;
  final Color border;

  factory _TaskPalette.resolve(
    ColorScheme scheme, {
    required TaskCardModel task,
    required bool isCompleted,
  }) {
    if (!isCompleted) {
      return _TaskPalette(
        surface: scheme.primaryContainer.withValues(alpha: 0.34),
        container: scheme.primaryContainer,
        foreground: scheme.primary,
        border: scheme.primaryContainer.withValues(alpha: 0.8),
      );
    }
    if (task.hasFailures) {
      return _TaskPalette(
        surface: scheme.tertiaryContainer.withValues(alpha: 0.42),
        container: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
        border: scheme.tertiaryContainer.withValues(alpha: 0.92),
      );
    }
    return _TaskPalette(
      surface: scheme.secondaryContainer.withValues(alpha: 0.34),
      container: scheme.secondaryContainer,
      foreground: scheme.secondary,
      border: scheme.secondaryContainer.withValues(alpha: 0.9),
    );
  }
}
