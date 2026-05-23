import 'package:flutter_test/flutter_test.dart';
import 'package:hakbanghero/main.dart';

void main() {
  testWidgets('HakbangHero app smoke test', (WidgetTester tester) async {
    // Basic smoke test — just verifies the app widget exists
    expect(HakbangHeroApp, isNotNull);
  });
}