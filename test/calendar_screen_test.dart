import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:medsafe/calendar/caregiver_calendar_screen.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('medsafe-calendar-');
    Hive.init(hiveDirectory.path);
    await Hive.openBox('profile');
    await Hive.openBox('calendar_events');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('caregiver event is saved and appears on the matching patient calendar', (
    tester,
  ) async {
    Hive.box('profile').put('accountName', 'Caregiver');
    await tester.pumpWidget(
      const MaterialApp(
        home: CaregiverCalendarScreen(patientName: 'Patient A'),
      ),
    );

    await tester.tap(find.byTooltip('Add calendar event'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Clinic appointment');
    await tester.enterText(find.byType(TextField).at(1), 'Bring medication list');
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();

    final events = Hive.box('calendar_events');
    expect(events.length, 1);
    expect(events.values.first['patientName'], 'Patient A');

    events.add({
      'patientName': 'Different Patient',
      'title': 'Private event',
      'details': '',
      'startsAt': DateTime.now().toIso8601String(),
      'createdBy': 'Caregiver',
    });
    Hive.box('profile').put('accountName', 'Patient A');
    await tester.pumpWidget(const MaterialApp(home: PatientCalendarScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Clinic appointment'), findsOneWidget);
    expect(find.text('Private event'), findsNothing);
  });
}
