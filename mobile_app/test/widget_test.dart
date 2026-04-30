import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:verify_vat_invoices_app/src/app.dart';

void main() {
  testWidgets('app renders login page by default', (tester) async {
    await tester
        .pumpWidget(const ProviderScope(child: InvoiceVerificationApp()));
    expect(find.text('发票核验'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}
