import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_state_models.dart';
import '../../router.dart';

const localApiBaseUrl = String.fromEnvironment(
  'LOCAL_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);
const serverApiBaseUrl = 'http://124.221.241.208';
const defaultApiBaseUrl = serverApiBaseUrl;
const _apiBaseUrlPrefsKey = 'api_base_url';
const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');

String _initialApiBaseUrl() {
  if (_configuredApiBaseUrl.trim().isNotEmpty) {
    return _normalizeBaseUrl(_configuredApiBaseUrl);
  }
  return defaultApiBaseUrl;
}

class ApiEndpointState {
  const ApiEndpointState({
    required this.baseUrl,
    required this.isLoading,
  });

  final String baseUrl;
  final bool isLoading;

  bool get isLocal => baseUrl == localApiBaseUrl;
  bool get isServer => baseUrl == serverApiBaseUrl;
  String get label => isLocal ? '本地后端' : (isServer ? '服务器后端' : '自定义后端');

  ApiEndpointState copyWith({
    String? baseUrl,
    bool? isLoading,
  }) {
    return ApiEndpointState(
      baseUrl: baseUrl ?? this.baseUrl,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ApiEndpointController extends StateNotifier<ApiEndpointState> {
  ApiEndpointController()
      : super(
            ApiEndpointState(baseUrl: _initialApiBaseUrl(), isLoading: true)) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (_configuredApiBaseUrl.trim().isNotEmpty) {
      final configured = _normalizeBaseUrl(_configuredApiBaseUrl);
      await prefs.setString(_apiBaseUrlPrefsKey, configured);
      state = state.copyWith(baseUrl: configured, isLoading: false);
      return;
    }
    final savedBaseUrl = prefs.getString(_apiBaseUrlPrefsKey);
    state = state.copyWith(
      baseUrl: savedBaseUrl == null
          ? state.baseUrl
          : _normalizeBaseUrl(savedBaseUrl),
      isLoading: false,
    );
  }

  Future<void> useLocal() => setBaseUrl(localApiBaseUrl);

  Future<void> useServer() => setBaseUrl(serverApiBaseUrl);

  Future<void> togglePreset() {
    return state.isLocal ? useServer() : useLocal();
  }

  Future<void> setBaseUrl(String baseUrl) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiBaseUrlPrefsKey, normalized);
    state = state.copyWith(baseUrl: normalized, isLoading: false);
  }
}

final apiEndpointControllerProvider =
    StateNotifierProvider<ApiEndpointController, ApiEndpointState>((ref) {
  return ApiEndpointController();
});

final apiBaseUrlProvider = Provider<String>((ref) {
  return ref.watch(apiEndpointControllerProvider).baseUrl;
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
  _configureIoHttpClient(dio, options.baseUrl);
  return dio;
}

void _configureIoHttpClient(Dio dio, String baseUrl) {
  if (kIsWeb) {
    return;
  }
  final uri = Uri.tryParse(baseUrl);
  if (uri == null) {
    return;
  }
  final forceDirect = _isLanOrLoopbackHost(uri.host);
  final allowBadServerIpCert = kDebugMode &&
      _allowInsecureApiCert &&
      uri.scheme == 'https' &&
      uri.host == '124.221.241.208';
  if (!forceDirect && !allowBadServerIpCert) {
    return;
  }
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      if (forceDirect) {
        // Local backend debugging must bypass system proxy/TUN rules; otherwise
        // iOS can report "No route to host" even while Safari reaches the LAN IP.
        client.findProxy = (_) => 'DIRECT';
      }
      if (allowBadServerIpCert) {
        client.badCertificateCallback = (_, host, __) {
          return host == '124.221.241.208';
        };
      }
      return client;
    },
  );
}

bool _isLanOrLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost') {
    return true;
  }
  final address = InternetAddress.tryParse(normalized);
  if (address == null) {
    return false;
  }
  if (address.isLoopback || address.isLinkLocal) {
    return true;
  }
  if (address.type != InternetAddressType.IPv4) {
    return false;
  }
  final parts = normalized.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((part) => part == null)) {
    return false;
  }
  final first = parts[0]!;
  final second = parts[1]!;
  return first == 10 ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
}

Uri buildHealthProbeUri(String baseUrl, String source) {
  return Uri.parse('$baseUrl/api/health').replace(
    queryParameters: {
      'source': source,
      'ts': DateTime.now().millisecondsSinceEpoch.toString(),
    },
  );
}

Future<void> checkHealthWithDartHttpClient(String baseUrl) async {
  if (kIsWeb) {
    throw UnsupportedError('Dart HttpClient is not available on web');
  }
  final uri = buildHealthProbeUri(baseUrl, 'dart_http_client');
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 15);
  if (_isLanOrLoopbackHost(uri.host)) {
    client.findProxy = (_) => 'DIRECT';
  }
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
  } finally {
    client.close(force: true);
  }
}

class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<void> checkHealth() async {
    await _dio
        .getUri(buildHealthProbeUri(_dio.options.baseUrl, 'dio_flutter_app'));
  }

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

  Future<QrInvoiceParseResult> parseInvoiceQr(String rawText) async {
    final response = await _dio.post(
      '/api/qr-invoices/parse',
      data: {'raw_text': rawText},
    );
    return QrInvoiceParseResult.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<String> verifyInvoiceQr(String rawText) async {
    final response = await _dio.post(
      '/api/qr-invoices/verify',
      data: {'raw_text': rawText},
    );
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
