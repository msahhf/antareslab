import 'package:flutter_test/flutter_test.dart';
import 'package:antares_studio_iot/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const AntaresStudioApp());
    expect(find.text('ANTARES KAPSÜL'), findsOneWidget);
  });
}
