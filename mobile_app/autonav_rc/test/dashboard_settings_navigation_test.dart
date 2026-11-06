import 'package:flutter_test/flutter_test.dart';
import 'package:autonav_rc/main.dart';

void main() {
  testWidgets('Dashboard bottom Settings opens Pair Device screen', (
    tester,
  ) async {
    await tester.pumpWidget(const AutoNavApp());
    await tester.pumpAndSettle();

    final settings = find.text('Settings');
    expect(settings, findsOneWidget);

    await tester.ensureVisible(settings);
    await tester.pumpAndSettle();

    await tester.tap(settings);
    await tester.pumpAndSettle();

    expect(find.text('Pair AutoNav RC'), findsOneWidget);
    expect(find.text('PAIR DEVICE'), findsOneWidget);
    expect(find.text('CONTROLLER CONNECTION'), findsOneWidget);
  });
}
