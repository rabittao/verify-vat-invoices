import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_state_models.dart';

final apiBaseUrlProvider = StateProvider<String>((ref) {
  if (Platform.isAndroid) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
});

final authTokenProvider = StateProvider<String?>((ref) => null);

final rawApiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  final dio = Dio(
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
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    ),
  );
  return ApiClient(dio);
});

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

  Future<TaskListState> getTasks() async {
    final response = await _dio.get('/api/tasks');
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

  Future<SystemConfigModel> getSystemConfig() async {
    final response = await _dio.get('/api/admin/system-config');
    return SystemConfigModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> updateSystemConfig({
    String? qwenApiKey,
    String? qwenInvoiceModel,
    String? openrouterApiKey,
    String? captchaModel,
  }) async {
    await _dio.put('/api/admin/system-config', data: {
      if (qwenApiKey != null) 'qwen_api_key': qwenApiKey,
      if (qwenInvoiceModel != null) 'qwen_invoice_model': qwenInvoiceModel,
      if (openrouterApiKey != null) 'openrouter_api_key': openrouterApiKey,
      if (captchaModel != null) 'openrouter_captcha_model': captchaModel,
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
