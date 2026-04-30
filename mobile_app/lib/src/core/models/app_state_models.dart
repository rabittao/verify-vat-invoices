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
    this.errorMessage,
  });

  const TaskListState.initial()
      : isLoading = true,
        isRefreshing = false,
        runningTasks = const [],
        completedTasks = const [],
        completedPageInfo = const PageInfo.initial(),
        errorMessage = null;

  final bool isLoading;
  final bool isRefreshing;
  final List<TaskCardModel> runningTasks;
  final List<TaskCardModel> completedTasks;
  final PageInfo completedPageInfo;
  final String? errorMessage;

  TaskListState copyWith({
    bool? isLoading,
    bool? isRefreshing,
    List<TaskCardModel>? runningTasks,
    List<TaskCardModel>? completedTasks,
    PageInfo? completedPageInfo,
    String? errorMessage,
  }) {
    return TaskListState(
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      runningTasks: runningTasks ?? this.runningTasks,
      completedTasks: completedTasks ?? this.completedTasks,
      completedPageInfo: completedPageInfo ?? this.completedPageInfo,
      errorMessage: errorMessage,
    );
  }
}

class TaskItemModel {
  const TaskItemModel({
    required this.jobItemId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.amount,
    required this.statusLabel,
    required this.failureSummary,
  });

  final int jobItemId;
  final String? invoiceNumber;
  final String? invoiceDate;
  final String? amount;
  final String statusLabel;
  final String? failureSummary;

  factory TaskItemModel.fromJson(Map<String, dynamic> json) {
    return TaskItemModel(
      jobItemId: json['job_item_id'] as int,
      invoiceNumber: json['invoice_number'] as String?,
      invoiceDate: json['invoice_date'] as String?,
      amount: json['amount'] as String?,
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
    required this.sourceFileCount,
    required this.totalRecords,
    required this.successCount,
    required this.failedCount,
    required this.skippedCount,
    required this.fileGroups,
  });

  final String jobId;
  final String status;
  final String stage;
  final int progressPercent;
  final int sourceFileCount;
  final int totalRecords;
  final int successCount;
  final int failedCount;
  final int skippedCount;
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
    return TaskDetailModel(
      jobId: json['job_id'] as String,
      status: json['status'] as String? ?? '',
      stage: json['stage'] as String? ?? '',
      progressPercent: json['progress_percent'] as int? ?? 0,
      sourceFileCount: summary['source_file_count'] as int? ?? 0,
      totalRecords: summary['total_records'] as int? ?? 0,
      successCount: summary['success_count'] as int? ?? 0,
      failedCount: summary['failed_count'] as int? ?? 0,
      skippedCount: summary['skipped_count'] as int? ?? 0,
      fileGroups: groups,
    );
  }
}

class LedgerItemModel {
  const LedgerItemModel({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.totalAmount,
    required this.sellerName,
    required this.buyerName,
    required this.lastVerifiedAt,
    required this.hasScreenshot,
    required this.sourceJobLabel,
  });

  final int invoiceId;
  final String invoiceNumber;
  final String invoiceDate;
  final String totalAmount;
  final String? sellerName;
  final String? buyerName;
  final String lastVerifiedAt;
  final bool hasScreenshot;
  final String? sourceJobLabel;

  factory LedgerItemModel.fromJson(Map<String, dynamic> json) {
    final sourceJob = json['source_job'] as Map<String, dynamic>?;
    return LedgerItemModel(
      invoiceId: json['invoice_id'] as int,
      invoiceNumber: json['invoice_number'] as String? ?? '',
      invoiceDate: json['invoice_date'] as String? ?? '',
      totalAmount: (json['total_amount'] as String?) ??
          (json['pretax_amount'] as String? ?? ''),
      sellerName: json['seller_name'] as String?,
      buyerName: json['buyer_name'] as String?,
      lastVerifiedAt: json['last_verified_at'] as String? ?? '',
      hasScreenshot: json['has_screenshot'] as bool? ?? false,
      sourceJobLabel: sourceJob?['label'] as String?,
    );
  }
}

class LedgerDetailModel {
  const LedgerDetailModel({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.totalAmount,
    required this.sellerName,
    required this.buyerName,
    required this.screenshotUrl,
    required this.sourceJobLabel,
  });

  final String invoiceNumber;
  final String invoiceDate;
  final String? totalAmount;
  final String? sellerName;
  final String? buyerName;
  final String? screenshotUrl;
  final String? sourceJobLabel;

  factory LedgerDetailModel.fromJson(Map<String, dynamic> json) {
    final screenshot = json['screenshot'] as Map<String, dynamic>? ?? const {};
    final core = json['core_fields'] as Map<String, dynamic>? ?? const {};
    final party = json['party_fields'] as Map<String, dynamic>? ?? const {};
    final sourceJob = json['source_job'] as Map<String, dynamic>?;
    return LedgerDetailModel(
      invoiceNumber: core['invoice_number'] as String? ?? '',
      invoiceDate: core['invoice_date'] as String? ?? '',
      totalAmount: core['total_amount'] as String?,
      sellerName: party['seller_name'] as String?,
      buyerName: party['buyer_name'] as String?,
      screenshotUrl: screenshot['preview_url'] as String?,
      sourceJobLabel: sourceJob?['label'] as String?,
    );
  }
}

class ExportRecordModel {
  const ExportRecordModel({
    required this.exportId,
    required this.exportType,
    required this.status,
    required this.fileName,
    required this.downloadUrl,
  });

  final String exportId;
  final String exportType;
  final String status;
  final String? fileName;
  final String? downloadUrl;

  factory ExportRecordModel.fromJson(Map<String, dynamic> json) {
    return ExportRecordModel(
      exportId: json['export_id'] as String,
      exportType: json['export_type'] as String? ?? '',
      status: json['status'] as String? ?? '',
      fileName: json['file_name'] as String?,
      downloadUrl: json['download_url'] as String?,
    );
  }
}

class SystemConfigModel {
  const SystemConfigModel({
    required this.qwenConfigured,
    required this.qwenMaskedValue,
    required this.invoiceModel,
    required this.openrouterConfigured,
    required this.openrouterMaskedValue,
    required this.captchaModel,
  });

  final bool qwenConfigured;
  final String? qwenMaskedValue;
  final String invoiceModel;
  final bool openrouterConfigured;
  final String? openrouterMaskedValue;
  final String captchaModel;

  factory SystemConfigModel.fromJson(Map<String, dynamic> json) {
    final qwen = json['qwen_api_key'] as Map<String, dynamic>? ?? const {};
    final openrouter =
        json['openrouter_api_key'] as Map<String, dynamic>? ?? const {};
    return SystemConfigModel(
      qwenConfigured: qwen['is_configured'] as bool? ?? false,
      qwenMaskedValue: qwen['masked_value'] as String?,
      invoiceModel: json['qwen_invoice_model'] as String? ?? '',
      openrouterConfigured: openrouter['is_configured'] as bool? ?? false,
      openrouterMaskedValue: openrouter['masked_value'] as String?,
      captchaModel: json['openrouter_captcha_model'] as String? ?? '',
    );
  }
}
