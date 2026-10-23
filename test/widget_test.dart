// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:medsafe/main.dart';

void main() {
  setUpAll(() async {
    Hive.init('/tmp/medsafe_widget_test');
    await Hive.openBox('medications');
    await Hive.openBox('profile');
  });

  testWidgets('MedSafe opens the medication list', (WidgetTester tester) async {
    await tester.pumpWidget(const MedApp());
    expect(find.text('Sign in to MedSafe'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
