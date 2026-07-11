import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/models/app_state_models.dart';
import 'core/network/api_client.dart';
import 'features/auth/login_page.dart';
import 'features/exports/export_history_page.dart';
import 'features/ledger/ledger_detail_page.dart';
import 'features/ledger/ledger_page.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/system_config_page.dart';
import 'features/shell/app_shell.dart';
import 'features/tasks/batch_upload_review_page.dart';
import 'features/tasks/task_detail_page.dart';
import 'features/tasks/task_list_page.dart';

final authStorageProvider = Provider<AuthStorage>((ref) {
  return AuthStorage();
});

class AuthStorage {
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('username');
    await prefs.remove('role');
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState.initial()) {
    restoreSession();
  }

  final Ref _ref;

  Future<void> restoreSession() async {
    state = state.copyWith(isLoading: true);
    final storage = _ref.read(authStorageProvider);
    final token = await storage.read('access_token');
    final username = await storage.read('username');
    final role = await storage.read('role');
    if (token == null) {
      _ref.read(authTokenProvider.notifier).state = null;
      state = const AuthState.initial().copyWith(isLoading: false);
      return;
    }
    _ref.read(authTokenProvider.notifier).state = token;
    state = AuthState(
      isLoading: false,
      isAuthenticated: true,
      accessToken: token,
      username: username,
      role: role,
      pendingRouteAfterLogin: null,
      errorMessage: null,
    );
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty || password.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '请输入用户名和密码',
      );
      return false;
    }

    state = state.copyWith(isLoading: true, clearErrorMessage: true);
    try {
      final result = await _ref
          .read(rawApiClientProvider)
          .login(username: normalizedUsername, password: password);
      final storage = _ref.read(authStorageProvider);
      await storage.write('access_token', result.accessToken);
      await storage.write('username', result.username);
      await storage.write('role', result.role);
      _ref.read(authTokenProvider.notifier).state = result.accessToken;
      state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        accessToken: result.accessToken,
        username: result.username,
        role: result.role,
        pendingRouteAfterLogin: null,
        errorMessage: null,
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '登录失败：${_formatLoginError(error)}',
      );
      return false;
    }
  }

  Future<void> logout() async {
    final storage = _ref.read(authStorageProvider);
    await storage.clear();
    _ref.read(authTokenProvider.notifier).state = null;
    state = const AuthState.initial().copyWith(isLoading: false);
  }

  Future<void> handleUnauthorized() async {
    if (!state.isAuthenticated && state.accessToken == null) {
      return;
    }
    await logout();
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});

String _formatLoginError(Object error) {
  if (error is DioException) {
    final baseUrl = error.requestOptions.baseUrl;
    final response = error.response;
    final data = response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail;
      }
    }
    if (response?.statusCode == 401) {
      return '用户名或密码错误';
    }
    if (response?.statusCode != null) {
      return '服务器返回 ${response!.statusCode}';
    }
    final message = error.message ?? error.error?.toString() ?? '网络连接失败';
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return '无法连接后端 $baseUrl。请确认手机和 Mac 在同一网络、Mac 后端监听 0.0.0.0:8000，并允许本地网络访问。原始错误：$message';
    }
    return '$message（API：$baseUrl）';
  }
  return error.toString();
}

final selectedUploadFilesProvider =
    StateProvider<List<UploadDraft>>((ref) => const []);

class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(this.ref) {
    ref.listen<AuthState>(authControllerProvider, (_, __) {
      notifyListeners();
    });
  }

  final Ref ref;
}

final routerRefreshProvider = Provider<RouterRefreshNotifier>((ref) {
  return RouterRefreshNotifier(ref);
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);
  final refreshListenable = ref.watch(routerRefreshProvider);
  return GoRouter(
    refreshListenable: refreshListenable,
    initialLocation: '/tasks',
    redirect: (context, state) {
      if (authState.isLoading) {
        return state.matchedLocation == '/login' ? null : '/login';
      }
      final isLogin = state.matchedLocation == '/login';
      if (!authState.isAuthenticated && !isLogin) {
        return '/login';
      }
      if (authState.isAuthenticated && isLogin) {
        return '/tasks';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(
          location: state.uri.toString(),
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/tasks',
            builder: (context, state) => const TaskListPage(),
            routes: [
              GoRoute(
                path: 'upload-review',
                builder: (context, state) => const BatchUploadReviewPage(),
              ),
              GoRoute(
                path: ':jobId',
                builder: (context, state) =>
                    TaskDetailPage(jobId: state.pathParameters['jobId']!),
              ),
            ],
          ),
          GoRoute(
            path: '/ledger',
            builder: (context, state) => const LedgerPage(),
            routes: [
              GoRoute(
                path: ':invoiceId',
                builder: (context, state) => LedgerDetailPage(
                    invoiceId: int.parse(state.pathParameters['invoiceId']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
            routes: [
              GoRoute(
                path: 'system-config',
                builder: (context, state) => const SystemConfigPage(),
              ),
            ],
          ),
          GoRoute(
            path: '/exports',
            builder: (context, state) => const ExportHistoryPage(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('页面不存在：${state.error}'),
      ),
    ),
  );
});
