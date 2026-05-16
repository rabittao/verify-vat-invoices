import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:verify_vat_invoices_app/src/app.dart';
import 'package:verify_vat_invoices_app/src/core/models/app_state_models.dart';
import 'package:verify_vat_invoices_app/src/core/network/api_client.dart';
import 'package:verify_vat_invoices_app/src/features/tasks/task_list_page.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(Dio());

  @override
  Future<TaskListState> getTasks({
    int completedPage = 1,
    int completedPageSize = 20,
  }) async {
    return const TaskListState(
      isLoading: false,
      isRefreshing: false,
      runningTasks: [],
      completedTasks: [
        TaskCardModel(
          jobId: 'job-completed',
          title: '1个PDF，1条记录',
          status: 'succeeded',
          stage: 'completed',
          progressPercent: 100,
          sourceFileCount: 1,
          totalRecords: 1,
          successCount: 1,
          failedCount: 0,
          skippedCount: 0,
          createdAtText: '2026-05-01T08:00:00',
          updatedAtText: '2026-05-01T08:10:00',
          sourceFileNames: ['hotel.pdf'],
          deletable: false,
          deleteBlockReason: '该任务当前不可删除',
        ),
      ],
      completedPageInfo: PageInfo(
        page: 1,
        pageSize: 20,
        total: 1,
        totalPages: 1,
        hasNext: false,
        hasPrev: false,
      ),
      errorMessage: null,
    );
  }
}

class _PagedFakeApiClient extends ApiClient {
  _PagedFakeApiClient() : super(Dio());

  final requestedPages = <int>[];

  @override
  Future<TaskListState> getTasks({
    int completedPage = 1,
    int completedPageSize = 20,
  }) async {
    requestedPages.add(completedPage);
    final tasks = switch (completedPage) {
      1 => [
          _task('job-page-1-a', '住宿费_第一页_A.pdf'),
          _task('job-page-1-b', '住宿费_第一页_B.pdf'),
        ],
      2 => [
          _task('job-page-2-a', '住宿费_第二页_A.pdf'),
          _task('job-page-2-b', '住宿费_第二页_B.pdf'),
        ],
      _ => <TaskCardModel>[],
    };
    return TaskListState(
      isLoading: false,
      isRefreshing: false,
      runningTasks: const [],
      completedTasks: tasks,
      completedPageInfo: PageInfo(
        page: completedPage,
        pageSize: completedPageSize,
        total: 4,
        totalPages: 2,
        hasNext: completedPage < 2,
        hasPrev: completedPage > 1,
      ),
      errorMessage: null,
    );
  }

  static TaskCardModel _task(String jobId, String fileName) {
    return TaskCardModel(
      jobId: jobId,
      title: '1个PDF，1条记录',
      status: 'succeeded',
      stage: 'completed',
      progressPercent: 100,
      sourceFileCount: 1,
      totalRecords: 1,
      successCount: 1,
      failedCount: 0,
      skippedCount: 0,
      createdAtText: '2026-05-01T08:00:00',
      updatedAtText: '2026-05-01T08:10:00',
      sourceFileNames: [fileName],
      deletable: false,
      deleteBlockReason: '该任务当前不可删除',
    );
  }
}

void main() {
  test('api base url supports dart define override', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
    final baseUrl = container.read(apiBaseUrlProvider);

    if (configuredApiBaseUrl.isNotEmpty) {
      final expected = configuredApiBaseUrl.trim().endsWith('/')
          ? configuredApiBaseUrl.trim().substring(
                0,
                configuredApiBaseUrl.trim().length - 1,
              )
          : configuredApiBaseUrl.trim();
      expect(baseUrl, expected);
    } else {
      expect(baseUrl, startsWith('http://'));
    }
  });

  testWidgets('app renders redesigned login page', (tester) async {
    await tester
        .pumpWidget(const ProviderScope(child: InvoiceVerificationApp()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('登录'), findsAtLeastNWidgets(1));
    expect(find.text('欢迎回来'), findsOneWidget);
    expect(find.text('账号权限控制'), findsOneWidget);
    expect(find.text('任务全程留痕'), findsOneWidget);
    expect(find.text('台账导出可追溯'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
  });

  testWidgets('task list page renders redesigned summary layout',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_FakeApiClient()),
        ],
        child: const MaterialApp(home: TaskListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('任务'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('今日完成'), findsOneWidget);
    expect(find.text('成功入台账'), findsOneWidget);
    expect(find.text('进行中任务'), findsOneWidget);
    expect(find.text('上传发票'), findsOneWidget);
    expect(find.textContaining('共 1 个历史任务'), findsOneWidget);
  });

  testWidgets('task list loads more completed task pages', (tester) async {
    final apiClient = _PagedFakeApiClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
        ],
        child: const MaterialApp(home: TaskListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('住宿费_第一页_A.pdf'), findsAtLeastNWidgets(1));
    expect(find.text('住宿费_第二页_A.pdf'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('已加载 2 / 4 个历史任务'), findsOneWidget);
    expect(find.text('加载更多历史任务'), findsOneWidget);

    await tester.ensureVisible(find.text('加载更多历史任务'));
    await tester.tap(find.text('加载更多历史任务'));
    await tester.pumpAndSettle();

    expect(apiClient.requestedPages, [1, 2]);
    expect(find.text('住宿费_第一页_A.pdf'), findsAtLeastNWidgets(1));
    expect(find.text('住宿费_第二页_A.pdf'), findsAtLeastNWidgets(1));
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('没有更多历史任务了'), findsOneWidget);
  });
}
