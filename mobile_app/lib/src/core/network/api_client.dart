import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_state_models.dart';
import '../../router.dart';

const defaultApiBaseUrl = 'http://124.221.241.208';

final apiBaseUrlProvider = StateProvider<String>((ref) {
  const configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  if (configuredApiBaseUrl.trim().isNotEmpty) {
    return _normalizeBaseUrl(configuredApiBaseUrl);
  }
  return defaultApiBaseUrl;
});

const _allowInsecureApiCert = bool.fromEnvironment('ALLOW_INSECURE_API_CERT');

String _normalizeBaseUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

final authTokenProvider = StateProvider<String?>((ref) => null);

final rawApiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  final dio = _buildDio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );
  return ApiClient(dio);
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  final token = ref.watch(authTokenProvider);
  final dio = _buildDio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          ref.read(authControllerProvider.notifier).handleUnauthorized();
        }
        handler.next(error);
      },
    ),
  );
  return ApiClient(dio);
});

Dio _buildDio(BaseOptions options) {
  final dio = Dio(options);
  _configureDebugCertificateBypass(dio, options.baseUrl);
  return dio;
}

void _configureDebugCertificateBypass(Dio dio, String baseUrl) {
  if (!kDebugMode || !_allowInsecureApiCert) {
    return;
  }
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || uri.scheme != 'https' || uri.host != '124.221.241.208') {
    return;
  }
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.badCertificateCallback = (_, host, __) {
        return host == '124.221.241.208';
      };
      return client;
    },
  );
}

class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    final response = await _dio.post('/api/auth/login', data: {
      'username': username,
      'password': password,
    });
    final data = response.data as Map<String, dynamic>;
    final user = data['user'] as Map<String, dynamic>? ?? const {};
    return LoginResult(
      accessToken: data['access_token'] as String,
      username: user['username'] as String? ?? username,
      role: user['role'] as String? ?? 'user',
    );
  }

  Future<TaskListState> getTasks({
    int completedPage = 1,
    int completedPageSize = 20,
  }) async {
    final response = await _dio.get(
      '/api/tasks',
      queryParameters: {
        'completed_page': completedPage,
        'completed_page_size': completedPageSize,
      },
    );
    final data = response.data as Map<String, dynamic>;
    return TaskListState(
      isLoading: false,
      isRefreshing: false,
      runningTasks: (data['running_items'] as List<dynamic>? ?? const [])
          .map((entry) => TaskCardModel.fromJson(entry as Map<String, dynamic>))
          .toList(),
      completedTasks: (data['completed_items'] as List<dynamic>? ?? const [])
          .map((entry) => TaskCardModel.fromJson(entry as Map<String, dynamic>))
          .toList(),
      completedPageInfo: _pageInfoFromJson(
          data['completed_pagination'] as Map<String, dynamic>?),
      errorMessage: null,
    );
  }

  Future<String> uploadTask(List<UploadDraft> files) async {
    final form = FormData();
    for (final file in files) {
      form.files.add(
        MapEntry(
          'files',
          MultipartFile.fromBytes(file.bytes, filename: file.name),
        ),
      );
    }
    final response = await _dio.post('/api/tasks', data: form);
    return (response.data as Map<String, dynamic>)['job_id'] as String;
  }

  Future<TaskDetailModel> getTaskDetail(String jobId) async {
    final response = await _dio.get('/api/tasks/$jobId');
    return TaskDetailModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TaskItemDetailModel> getTaskItemDetail(
    String jobId,
    int jobItemId,
  ) async {
    final response = await _dio.get('/api/tasks/$jobId/items/$jobItemId');
    return TaskItemDetailModel.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<String> retryTaskFile(String jobId, String fileId) async {
    final response = await _dio.post('/api/tasks/$jobId/files/$fileId/retry');
    return (response.data as Map<String, dynamic>)['job_id'] as String;
  }

  Future<void> deleteTask(String jobId) async {
    await _dio.delete('/api/tasks/$jobId');
  }

  Future<List<LedgerItemModel>> getInvoices({
    String? invoiceNumber,
  }) async {
    final response = await _dio.get(
      '/api/invoices',
      queryParameters: {
        if (invoiceNumber != null && invoiceNumber.trim().isNotEmpty)
          'invoice_number': invoiceNumber.trim(),
      },
    );
    final data = response.data as Map<String, dynamic>;
    return (data['items'] as List<dynamic>? ?? const [])
        .map((entry) => LedgerItemModel.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<LedgerDetailModel> getInvoiceDetail(int invoiceId) async {
    final response = await _dio.get('/api/invoices/$invoiceId');
    return LedgerDetailModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<ExportRecordModel>> getExports() async {
    final response = await _dio.get('/api/exports');
    final data = response.data as Map<String, dynamic>;
    return (data['items'] as List<dynamic>? ?? const [])
        .map((entry) =>
            ExportRecordModel.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<String> createExport({
    required String exportType,
    String? invoiceNumber,
    int? invoiceId,
  }) async {
    final response = await _dio.post('/api/exports', data: {
      'export_type': exportType,
      if (invoiceId != null) 'invoice_id': invoiceId,
      if (invoiceNumber != null && invoiceNumber.trim().isNotEmpty)
        'filters': {
          'invoice_number': invoiceNumber.trim(),
        },
    });
    return (response.data as Map<String, dynamic>)['export_id'] as String;
  }

  Future<String> downloadProtectedFile({
    required String fileUrl,
    required String fallbackFileName,
  }) async {
    final resolvedUrl =
        Uri.parse(_dio.options.baseUrl).resolve(fileUrl).toString();
    final response = await _dio.get<List<int>>(
      resolvedUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null) {
      throw Exception('文件内容为空');
    }
    final safeName =
        fallbackFileName.replaceAll(RegExp(r'[\\\\/:*?"<>|]'), '_').trim();
    final cacheDir =
        Directory('${Directory.systemTemp.path}/verify_vat_invoice_exports');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    final file =
        File('${cacheDir.path}/${safeName.isEmpty ? 'export.bin' : safeName}');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<SystemConfigModel> getSystemConfig() async {
    final response = await _dio.get('/api/admin/system-config');
    return SystemConfigModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> updateSystemConfig({
    String? qwenApiKey,
    String? qwenInvoiceModel,
    String? captchaModel,
  }) async {
    await _dio.put('/api/admin/system-config', data: {
      if (qwenApiKey != null) 'qwen_api_key': qwenApiKey,
      if (qwenInvoiceModel != null) 'qwen_invoice_model': qwenInvoiceModel,
      if (captchaModel != null) 'qwen_captcha_model': captchaModel,
    });
  }

  Future<List<String>> validateSystemConfig() async {
    final response = await _dio.post('/api/admin/system-config/validate');
    final data = response.data as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .map((entry) => '${entry['key']}: ${entry['message']}')
        .toList();
  }
}

PageInfo _pageInfoFromJson(Map<String, dynamic>? json) {
  if (json == null) {
    return const PageInfo.initial();
  }
  return PageInfo(
    page: json['page'] as int? ?? 1,
    pageSize: json['page_size'] as int? ?? 20,
    total: json['total'] as int? ?? 0,
    totalPages: json['total_pages'] as int? ?? 0,
    hasNext: json['has_next'] as bool? ?? false,
    hasPrev: json['has_prev'] as bool? ?? false,
  );
}
