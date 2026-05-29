class AuthState {
  const AuthState({
    required this.isLoading,
    required this.isAuthenticated,
    this.accessToken,
    this.username,
    this.role,
    this.pendingRouteAfterLogin,
    this.errorMessage,
  });

  const AuthState.initial()
      : isLoading = true,
        isAuthenticated = false,
        accessToken = null,
        username = null,
        role = null,
        pendingRouteAfterLogin = null,
        errorMessage = null;

  final bool isLoading;
  final bool isAuthenticated;
  final String? accessToken;
  final String? username;
  final String? role;
  final String? pendingRouteAfterLogin;
  final String? errorMessage;

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    String? accessToken,
    String? username,
    String? role,
    String? pendingRouteAfterLogin,
    String? errorMessage,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      accessToken: accessToken ?? this.accessToken,
      username: username ?? this.username,
      role: role ?? this.role,
      pendingRouteAfterLogin:
          pendingRouteAfterLogin ?? this.pendingRouteAfterLogin,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class PageInfo {
  const PageInfo({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrev,
  });

  const PageInfo.initial()
      : page = 1,
        pageSize = 20,
        total = 0,
        totalPages = 0,
        hasNext = false,
        hasPrev = false;

  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final bool hasNext;
  final bool hasPrev;
}

class LoginResult {
  const LoginResult({
    required this.accessToken,
    required this.username,
    required this.role,
  });

  final String accessToken;
  final String username;
  final String role;
}

class TaskCardModel {
  const TaskCardModel({
    required this.jobId,
    required this.title,
    required this.status,
    required this.stage,
    required this.progressPercent,
    required this.sourceFileCount,
    required this.totalRecords,
    required this.successCount,
    required this.failedCount,
    required this.skippedCount,
    required this.createdAtText,
    required this.updatedAtText,
    required this.sourceFileNames,
    required this.deletable,
    required this.deleteBlockReason,
  });

  final String jobId;
  final String title;
  final String status;
  final String stage;
  final int progressPercent;
  final int sourceFileCount;
  final int totalRecords;
  final int successCount;
  final int failedCount;
  final int skippedCount;
  final String createdAtText;
  final String updatedAtText;
  final List<String> sourceFileNames;
  final bool deletable;
  final String? deleteBlockReason;

  factory TaskCardModel.fromJson(Map<String, dynamic> json) {
    final files = (json['source_files'] as List<dynamic>? ?? const [])
        .map((entry) => entry['file_name'] as String? ?? '')
        .where((entry) => entry.isNotEmpty)
        .toList();
    return TaskCardModel(
      jobId: json['job_id'] as String,
      title: json['display_title'] as String? ??
          '${json['source_file_count']}个PDF',
      status: json['status'] as String? ?? '',
      stage: json['stage'] as String? ?? '',
      progressPercent: json['progress_percent'] as int? ?? 0,
      sourceFileCount: json['source_file_count'] as int? ?? 0,
      totalRecords: json['total_records'] as int? ?? 0,
      successCount: json['success_count'] as int? ?? 0,
      failedCount: json['failed_count'] as int? ?? 0,
      skippedCount: json['skipped_count'] as int? ?? 0,
      createdAtText: json['created_at'] as String? ?? '',
      updatedAtText: json['updated_at'] as String? ?? '',
      sourceFileNames: files,
      deletable: json['deletable'] as bool? ?? false,
      deleteBlockReason: json['delete_block_reason'] as String?,
    );
  }
}

class LedgerFilterState {
  const LedgerFilterState({
    this.invoiceNumber,
    this.dateRangeLabel,
    this.sellerName,
    this.buyerName,
    this.quickRange,
    this.isExpanded = false,
  });

  final String? invoiceNumber;
  final String? dateRangeLabel;
  final String? sellerName;
  final String? buyerName;
  final String? quickRange;
  final bool isExpanded;
}

class UploadDraft {
  const UploadDraft({
    required this.name,
    required this.bytes,
    required this.sizeBytes,
  });

  final String name;
  final List<int> bytes;
  final int sizeBytes;
}

class TaskListState {
  const TaskListState({
    required this.isLoading,
    required this.isRefreshing,
    required this.runningTasks,
    required this.completedTasks,
    required this.completedPageInfo,
    this.isLoadingMore = false,
    this.errorMessage,
  });

  const TaskListState.initial()
      : isLoading = true,
        isRefreshing = false,
        runningTasks = const [],
        completedTasks = const [],
        completedPageInfo = const PageInfo.initial(),
        isLoadingMore = false,
        errorMessage = null;

  final bool isLoading;
  final bool isRefreshing;
  final List<TaskCardModel> runningTasks;
  final List<TaskCardModel> completedTasks;
  final PageInfo completedPageInfo;
  final bool isLoadingMore;
  final String? errorMessage;

  TaskListState copyWith({
    bool? isLoading,
    bool? isRefreshing,
    List<TaskCardModel>? runningTasks,
    List<TaskCardModel>? completedTasks,
    PageInfo? completedPageInfo,
    bool? isLoadingMore,
    String? errorMessage,
  }) {
    return TaskListState(
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      runningTasks: runningTasks ?? this.runningTasks,
      completedTasks: completedTasks ?? this.completedTasks,
      completedPageInfo: completedPageInfo ?? this.completedPageInfo,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: errorMessage,
    );
  }
}

extension TaskCardModelPresentation on TaskCardModel {
  bool get isFinished =>
      status == 'succeeded' ||
      status == 'partially_failed' ||
      status == 'failed';

  bool get hasFailures => failedCount > 0;

  int get safeSourceFileCount =>
      sourceFileCount > 0 ? sourceFileCount : sourceFileNames.length;

  double get progressValue {
    final clamped = progressPercent.clamp(0, 100);
    return clamped / 100;
  }

  String get stageLabel {
    return switch (stage) {
      'uploaded' => '等待排队',
      'extracting' => '抽取识别中',
      'verifying' => '税站核验中',
      'persisting' => '结果入账中',
      'completed' => '处理完成',
      _ => stage.isEmpty ? '状态同步中' : stage,
    };
  }

  String get sourceSummary {
    if (sourceFileNames.isEmpty) {
      return '$safeSourceFileCount 个 PDF';
    }
    if (sourceFileNames.length == 1) {
      return sourceFileNames.first;
    }
    return '${sourceFileNames.first} 等 $safeSourceFileCount 个 PDF';
  }

  String get resultSummary =>
      '成功 $successCount / 失败 $failedCount / 跳过 $skippedCount';

  String get timelineSummary {
    if (updatedAtText.isNotEmpty) {
      return '更新于 $updatedAtText';
    }
    if (createdAtText.isNotEmpty) {
      return '创建于 $createdAtText';
    }
    return '时间待同步';
  }
}

extension TaskListStatePresentation on TaskListState {
  Iterable<TaskCardModel> get allTasks sync* {
    yield* runningTasks;
    yield* completedTasks;
  }

  int get totalTaskCount => runningTasks.length + completedTasks.length;

  int get totalSourceFileCount => allTasks.fold<int>(
        0,
        (sum, task) => sum + task.safeSourceFileCount,
      );

  int get totalSuccessCount => allTasks.fold<int>(
        0,
        (sum, task) => sum + task.successCount,
      );

  int get totalFailedCount => allTasks.fold<int>(
        0,
        (sum, task) => sum + task.failedCount,
      );

  int get totalSkippedCount => allTasks.fold<int>(
        0,
        (sum, task) => sum + task.skippedCount,
      );

  int get totalProcessedRecords =>
      totalSuccessCount + totalFailedCount + totalSkippedCount;
}

class TaskItemModel {
  const TaskItemModel({
    required this.jobItemId,
    required this.invoiceKey,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.amount,
    required this.status,
    required this.statusLabel,
    required this.failureSummary,
  });

  final int jobItemId;
  final String? invoiceKey;
  final String? invoiceNumber;
  final String? invoiceDate;
  final String? amount;
  final String status;
  final String statusLabel;
  final String? failureSummary;

  factory TaskItemModel.fromJson(Map<String, dynamic> json) {
    return TaskItemModel(
      jobItemId: json['job_item_id'] as int,
      invoiceKey: json['invoice_key'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      invoiceDate: json['invoice_date'] as String?,
      amount: json['amount'] as String?,
      status: json['status'] as String? ?? '',
      statusLabel: json['status_label'] as String? ?? '',
      failureSummary: json['failure_summary'] as String?,
    );
  }
}

class FileGroupModel {
  const FileGroupModel({
    required this.fileId,
    required this.fileName,
    required this.status,
    required this.successCount,
    required this.failedCount,
    required this.skippedCount,
    required this.retryable,
    required this.items,
  });

  final String fileId;
  final String fileName;
  final String status;
  final int successCount;
  final int failedCount;
  final int skippedCount;
  final bool retryable;
  final List<TaskItemModel> items;

  factory FileGroupModel.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .map((entry) => TaskItemModel.fromJson(entry as Map<String, dynamic>))
        .toList();
    return FileGroupModel(
      fileId: json['file_id'] as String,
      fileName: json['file_name'] as String? ?? '',
      status: json['status'] as String? ?? '',
      successCount: json['success_count'] as int? ?? 0,
      failedCount: json['failed_count'] as int? ?? 0,
      skippedCount: json['skipped_count'] as int? ?? 0,
      retryable: json['retryable'] as bool? ?? false,
      items: items,
    );
  }
}

class TaskDetailModel {
  const TaskDetailModel({
    required this.jobId,
    required this.status,
    required this.stage,
    required this.progressPercent,
    required this.createdAtText,
    required this.startedAtText,
    required this.finishedAtText,
    required this.sourceFileCount,
    required this.totalRecords,
    required this.successCount,
    required this.failedCount,
    required this.skippedCount,
    required this.timeline,
    required this.fileGroups,
  });

  final String jobId;
  final String status;
  final String stage;
  final int progressPercent;
  final String createdAtText;
  final String? startedAtText;
  final String? finishedAtText;
  final int sourceFileCount;
  final int totalRecords;
  final int successCount;
  final int failedCount;
  final int skippedCount;
  final List<String> timeline;
  final List<FileGroupModel> fileGroups;

  bool get isFinished =>
      status == 'succeeded' ||
      status == 'partially_failed' ||
      status == 'failed';

  String get stageLabel {
    return switch (stage) {
      'uploaded' => '已上传，等待处理',
      'extracting' => '正在抽取发票信息',
      'verifying' => '正在进入税站核验',
      'persisting' => '正在保存核验结果',
      'completed' => '处理完成',
      _ => stage,
    };
  }

  factory TaskDetailModel.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>? ?? const {};
    final groups = (json['file_groups'] as List<dynamic>? ?? const [])
        .map((entry) => FileGroupModel.fromJson(entry as Map<String, dynamic>))
        .toList();
    final timeline = (json['timeline'] as List<dynamic>? ?? const [])
        .map((entry) => entry['label'] as String? ?? '')
        .where((entry) => entry.isNotEmpty)
        .toList();
    return TaskDetailModel(
      jobId: json['job_id'] as String,
      status: json['status'] as String? ?? '',
      stage: json['stage'] as String? ?? '',
      progressPercent: json['progress_percent'] as int? ?? 0,
      createdAtText: json['created_at'] as String? ?? '',
      startedAtText: json['started_at'] as String?,
      finishedAtText: json['finished_at'] as String?,
      sourceFileCount: summary['source_file_count'] as int? ?? 0,
      totalRecords: summary['total_records'] as int? ?? 0,
      successCount: summary['success_count'] as int? ?? 0,
      failedCount: summary['failed_count'] as int? ?? 0,
      skippedCount: summary['skipped_count'] as int? ?? 0,
      timeline: timeline,
      fileGroups: groups,
    );
  }
}

class TaskItemDetailModel {
  const TaskItemDetailModel({
    required this.invoiceType,
    required this.invoiceCode,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.pretaxAmount,
    required this.taxAmount,
    required this.totalAmount,
    required this.sellerName,
    required this.buyerName,
    required this.checkCode,
    required this.extractionStatus,
    required this.extractionMessage,
    required this.validationStatus,
    required this.verificationStatus,
    required this.verificationMessage,
    required this.humanSummary,
    required this.extractScreenshotUrl,
    required this.verifyScreenshotUrl,
    required this.resultText,
    required this.validationErrors,
  });

  final String? invoiceType;
  final String? invoiceCode;
  final String? invoiceNumber;
  final String? invoiceDate;
  final String? pretaxAmount;
  final String? taxAmount;
  final String? totalAmount;
  final String? sellerName;
  final String? buyerName;
  final String? checkCode;
  final String? extractionStatus;
  final String? extractionMessage;
  final String? validationStatus;
  final String? verificationStatus;
  final String? verificationMessage;
  final String? humanSummary;
  final String? extractScreenshotUrl;
  final String? verifyScreenshotUrl;
  final String? resultText;
  final List<String> validationErrors;

  factory TaskItemDetailModel.fromJson(Map<String, dynamic> json) {
    final basic = json['basic_info'] as Map<String, dynamic>? ?? const {};
    final processing =
        json['processing_info'] as Map<String, dynamic>? ?? const {};
    final evidence = json['evidence'] as Map<String, dynamic>? ?? const {};
    final technical =
        json['technical_details'] as Map<String, dynamic>? ?? const {};
    return TaskItemDetailModel(
      invoiceType: basic['invoice_type'] as String?,
      invoiceCode: basic['invoice_code'] as String?,
      invoiceNumber: basic['invoice_number'] as String?,
      invoiceDate: basic['invoice_date'] as String?,
      pretaxAmount: basic['pretax_amount'] as String?,
      taxAmount: basic['tax_amount'] as String?,
      totalAmount: basic['total_amount'] as String?,
      sellerName: basic['seller_name'] as String?,
      buyerName: basic['buyer_name'] as String?,
      checkCode: basic['check_code'] as String?,
      extractionStatus: processing['extraction_status'] as String?,
      extractionMessage: processing['extraction_message'] as String?,
      validationStatus: processing['validation_status'] as String?,
      verificationStatus: processing['verification_status'] as String?,
      verificationMessage: processing['verification_message'] as String?,
      humanSummary: processing['human_summary'] as String?,
      extractScreenshotUrl: evidence['extract_screenshot_url'] as String?,
      verifyScreenshotUrl: evidence['verify_screenshot_url'] as String?,
      resultText: technical['result_text'] as String?,
      validationErrors:
          (technical['validation_errors'] as List<dynamic>? ?? const [])
              .map((entry) => '$entry')
              .toList(),
    );
  }
}

class LedgerItemModel {
  const LedgerItemModel({
    required this.invoiceId,
    required this.invoiceKey,
    required this.invoiceType,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.pretaxAmount,
    required this.taxAmount,
    required this.totalAmount,
    required this.sellerName,
    required this.buyerName,
    required this.lastVerifiedAt,
    required this.hasScreenshot,
    required this.sourceJobId,
    required this.sourceJobLabel,
  });

  final int invoiceId;
  final String invoiceKey;
  final String? invoiceType;
  final String invoiceNumber;
  final String invoiceDate;
  final String? pretaxAmount;
  final String? taxAmount;
  final String totalAmount;
  final String? sellerName;
  final String? buyerName;
  final String lastVerifiedAt;
  final bool hasScreenshot;
  final String? sourceJobId;
  final String? sourceJobLabel;

  factory LedgerItemModel.fromJson(Map<String, dynamic> json) {
    final sourceJob = json['source_job'] as Map<String, dynamic>?;
    return LedgerItemModel(
      invoiceId: json['invoice_id'] as int,
      invoiceKey: json['invoice_key'] as String? ?? '',
      invoiceType: json['invoice_type'] as String?,
      invoiceNumber: json['invoice_number'] as String? ?? '',
      invoiceDate: json['invoice_date'] as String? ?? '',
      pretaxAmount: json['pretax_amount'] as String?,
      taxAmount: json['tax_amount'] as String?,
      totalAmount: (json['total_amount'] as String?) ??
          (json['pretax_amount'] as String? ?? ''),
      sellerName: json['seller_name'] as String?,
      buyerName: json['buyer_name'] as String?,
      lastVerifiedAt: json['last_verified_at'] as String? ?? '',
      hasScreenshot: json['has_screenshot'] as bool? ?? false,
      sourceJobId: sourceJob?['job_id'] as String?,
      sourceJobLabel: sourceJob?['label'] as String?,
    );
  }
}

extension LedgerItemPresentation on LedgerItemModel {
  String get sellerDisplay =>
      sellerName?.trim().isNotEmpty == true ? sellerName!.trim() : '-';

  String get buyerDisplay =>
      buyerName?.trim().isNotEmpty == true ? buyerName!.trim() : '-';

  String get amountDisplay =>
      totalAmount.trim().isNotEmpty ? totalAmount.trim() : '-';

  String get verificationDisplay =>
      _formatDateTimeToSecond(lastVerifiedAt) ?? '待补充核验时间';

  String get sourceDisplay => sourceJobLabel?.trim().isNotEmpty == true
      ? sourceJobLabel!.trim()
      : '手工入库';
}

String? _formatDateTimeToSecond(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  final normalized =
      parsed == null ? raw.replaceFirst('T', ' ') : _formatDateTime(parsed);
  return normalized.length >= 19 ? normalized.substring(0, 19) : normalized;
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

class LedgerDetailModel {
  const LedgerDetailModel({
    required this.invoiceId,
    required this.invoiceType,
    required this.pretaxAmount,
    required this.taxAmount,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.totalAmount,
    required this.sellerName,
    required this.buyerName,
    required this.screenshotUrl,
    required this.fullscreenScreenshotUrl,
    required this.exportDetailPdfEnabled,
    required this.viewSourceJobEnabled,
    required this.sourceJobId,
    required this.sourceJobLabel,
    required this.verifiedAt,
    required this.firstVerifiedAt,
    required this.lastVerifiedAt,
  });

  final int invoiceId;
  final String? invoiceType;
  final String? pretaxAmount;
  final String? taxAmount;
  final String invoiceNumber;
  final String invoiceDate;
  final String? totalAmount;
  final String? sellerName;
  final String? buyerName;
  final String? screenshotUrl;
  final String? fullscreenScreenshotUrl;
  final bool exportDetailPdfEnabled;
  final bool viewSourceJobEnabled;
  final String? sourceJobId;
  final String? sourceJobLabel;
  final String? verifiedAt;
  final String? firstVerifiedAt;
  final String? lastVerifiedAt;

  factory LedgerDetailModel.fromJson(Map<String, dynamic> json) {
    final screenshot = json['screenshot'] as Map<String, dynamic>? ?? const {};
    final actions = json['actions'] as Map<String, dynamic>? ?? const {};
    final core = json['core_fields'] as Map<String, dynamic>? ?? const {};
    final party = json['party_fields'] as Map<String, dynamic>? ?? const {};
    final sourceJob = json['source_job'] as Map<String, dynamic>?;
    final system = json['system_fields'] as Map<String, dynamic>? ?? const {};
    return LedgerDetailModel(
      invoiceId: json['invoice_id'] as int? ?? 0,
      invoiceType: core['invoice_type'] as String?,
      pretaxAmount: core['pretax_amount'] as String?,
      taxAmount: core['tax_amount'] as String?,
      invoiceNumber: core['invoice_number'] as String? ?? '',
      invoiceDate: core['invoice_date'] as String? ?? '',
      totalAmount: core['total_amount'] as String?,
      sellerName: party['seller_name'] as String?,
      buyerName: party['buyer_name'] as String?,
      screenshotUrl: screenshot['preview_url'] as String?,
      fullscreenScreenshotUrl: screenshot['fullscreen_url'] as String?,
      exportDetailPdfEnabled:
          actions['export_detail_pdf_enabled'] as bool? ?? false,
      viewSourceJobEnabled:
          actions['view_source_job_enabled'] as bool? ?? false,
      sourceJobId: sourceJob?['job_id'] as String?,
      sourceJobLabel: sourceJob?['label'] as String?,
      verifiedAt: system['verified_at'] as String?,
      firstVerifiedAt: system['first_verified_at'] as String?,
      lastVerifiedAt: system['last_verified_at'] as String?,
    );
  }
}

extension LedgerDetailPresentation on LedgerDetailModel {
  bool get hasScreenshot => screenshotUrl?.trim().isNotEmpty == true;

  String get sellerDisplay =>
      sellerName?.trim().isNotEmpty == true ? sellerName!.trim() : '-';

  String get buyerDisplay =>
      buyerName?.trim().isNotEmpty == true ? buyerName!.trim() : '-';

  String get amountDisplay =>
      totalAmount?.trim().isNotEmpty == true ? totalAmount!.trim() : '-';

  String get sourceDisplay => sourceJobLabel?.trim().isNotEmpty == true
      ? sourceJobLabel!.trim()
      : '未关联任务';

  String get invoiceTypeDisplay =>
      invoiceType?.trim().isNotEmpty == true ? invoiceType!.trim() : '发票类型待补充';
}

class ExportRecordModel {
  const ExportRecordModel({
    required this.exportId,
    required this.exportType,
    required this.status,
    required this.createdAt,
    required this.finishedAt,
    required this.fileName,
    required this.fileSize,
    required this.errorMessage,
    required this.openUrl,
    required this.downloadUrl,
    required this.shareEnabled,
  });

  final String exportId;
  final String exportType;
  final String status;
  final String createdAt;
  final String? finishedAt;
  final String? fileName;
  final int? fileSize;
  final String? errorMessage;
  final String? openUrl;
  final String? downloadUrl;
  final bool shareEnabled;

  factory ExportRecordModel.fromJson(Map<String, dynamic> json) {
    return ExportRecordModel(
      exportId: json['export_id'] as String,
      exportType: json['export_type'] as String? ?? '',
      status: json['status'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      finishedAt: json['finished_at'] as String?,
      fileName: json['file_name'] as String?,
      fileSize: json['file_size'] as int?,
      errorMessage: json['error_message'] as String?,
      openUrl: json['open_url'] as String?,
      downloadUrl: json['download_url'] as String?,
      shareEnabled: json['share_enabled'] as bool? ?? false,
    );
  }
}

extension ExportRecordPresentation on ExportRecordModel {
  bool get isDownloadReady => downloadUrl?.trim().isNotEmpty == true;

  bool get isOpenReady => openUrl?.trim().isNotEmpty == true;

  String get fileDisplayName =>
      fileName?.trim().isNotEmpty == true ? fileName!.trim() : exportTypeLabel;

  String get exportTypeLabel {
    return switch (exportType) {
      'invoice_list_excel' => '发票台账 Excel',
      'invoice_list_summary_pdf' => '台账汇总 PDF',
      'invoice_detail_pdf' => '详情 PDF',
      _ => exportType.trim().isEmpty ? '未命名导出' : exportType,
    };
  }

  String get statusLabel {
    return switch (status) {
      'completed' => '已完成',
      'pending' => '排队中',
      'processing' => '生成中',
      'failed' => '失败',
      _ => status.trim().isEmpty ? '未知状态' : status,
    };
  }

  String get fileSizeLabel {
    final bytes = fileSize;
    if (bytes == null || bytes <= 0) {
      return '大小待生成';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

class SystemConfigModel {
  const SystemConfigModel({
    required this.qwenConfigured,
    required this.qwenMaskedValue,
    required this.invoiceModel,
    required this.captchaModel,
  });

  final bool qwenConfigured;
  final String? qwenMaskedValue;
  final String invoiceModel;
  final String captchaModel;

  factory SystemConfigModel.fromJson(Map<String, dynamic> json) {
    final qwen = json['qwen_api_key'] as Map<String, dynamic>? ?? const {};
    return SystemConfigModel(
      qwenConfigured: qwen['is_configured'] as bool? ?? false,
      qwenMaskedValue: qwen['masked_value'] as String?,
      invoiceModel: json['qwen_invoice_model'] as String? ?? '',
      captchaModel: json['qwen_captcha_model'] as String? ?? '',
    );
  }
}

extension SystemConfigPresentation on SystemConfigModel {
  int get configuredSecretCount => qwenConfigured ? 1 : 0;

  int get totalSecretCount => 1;

  String get invoiceModelDisplay =>
      invoiceModel.trim().isNotEmpty ? invoiceModel.trim() : '未设置发票抽取模型';

  String get captchaModelDisplay =>
      captchaModel.trim().isNotEmpty ? captchaModel.trim() : '未设置验证码模型';
}
