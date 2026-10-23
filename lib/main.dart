// yo am i cool or nah
// pulled info from fda drug database, used google ocr, and tf lite for recognizing medicine
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'calendar/caregiver_calendar_screen.dart';
import 'chat/chat_screen.dart';
import 'models/medicine_identification.dart';
import 'services/notification_service.dart';
import 'services/medication_image_matcher.dart';
import 'services/rxnorm_medication_service.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('medications');
  await Hive.openBox('profile');
  await Hive.openBox('chat_messages');
  await Hive.openBox('calendar_events');
  await NotificationService.instance.initialize();
  await SupabaseService.instance.initialize();
  runApp(const MedApp());
}

class MedApp extends StatelessWidget {
  const MedApp({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = Hive.box('profile');
    return ValueListenableBuilder<Box>(
      valueListenable: profile.listenable(),
      builder: (context, box, _) {
        final isDark = box.get('darkMode', defaultValue: false) == true;
        final background = isDark
            ? const Color(0xFF211D17)
            : const Color(0xFFFFFBF3);
        final surface = isDark ? const Color(0xFF2B261F) : Colors.white;
        final border = isDark
            ? const Color(0xFF51483A)
            : const Color(0xFFE7DDC9);
        final text = isDark ? const Color(0xFFFFF2D8) : const Color(0xFF342A1C);
        final gold = isDark ? const Color(0xFFF0B83F) : const Color(0xFFB77913);
        return MaterialApp(
          title: 'MedSafe',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: gold,
              brightness: isDark ? Brightness.dark : Brightness.light,
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: background,
            appBarTheme: AppBarTheme(
              backgroundColor: background,
              foregroundColor: text,
              elevation: 0,
              scrolledUnderElevation: 1,
              centerTitle: false,
              titleTextStyle: TextStyle(
                color: text,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
            cardTheme: CardThemeData(
              color: surface,
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                side: BorderSide(color: border),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: gold, width: 2),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 50),
                backgroundColor: gold,
                foregroundColor: isDark
                    ? const Color(0xFF33230A)
                    : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            navigationBarTheme: NavigationBarThemeData(
              height: 72,
              backgroundColor: surface,
              indicatorColor: isDark
                  ? const Color(0xFF5D471F)
                  : const Color(0xFFF4DEAD),
              labelTextStyle: const WidgetStatePropertyAll(
                TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ),
          builder: (context, child) {
            final scale = (box.get('textScale', defaultValue: 1.0) as num)
                .toDouble();
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const AuthGate(),
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = Hive.box('profile');
    final cloudSignedIn = SupabaseService.instance.currentUser != null;
    return (SupabaseService.instance.isConfigured && !cloudSignedIn) ||
            profile.get('accountName') == null
        ? const LoginScreen()
        : const HomeScreen();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = 'Patient';
  bool _busy = false;

  Future<void> _continue() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (name.isEmpty ||
        (SupabaseService.instance.isConfigured &&
            (email.isEmpty || password.length < 6))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your name and a valid email/password.'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (SupabaseService.instance.isConfigured) {
        await SupabaseService.instance.signInOrCreate(
          email: email,
          password: password,
          displayName: name,
          role: _role,
        );
      }
      Hive.box('profile').putAll({'accountName': name, 'role': _role});
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not sign in: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MedSafe account')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(
            Icons.health_and_safety,
            size: 72,
            color: Color(0xFF2A7FFF),
          ),
          const SizedBox(height: 20),
          const Text(
            'Sign in to MedSafe',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'This local account keeps your profile and medications on this device. Server sync can be connected later.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          if (SupabaseService.instance.isConfigured) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                hintText: 'At least 6 characters',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(
              labelText: 'Role',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Patient', child: Text('Patient')),
              DropdownMenuItem(value: 'Caregiver', child: Text('Caregiver')),
            ],
            onChanged: (value) => setState(() => _role = value ?? 'Patient'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : _continue,
            child: Text(_busy ? 'Signing in...' : 'Continue'),
          ),
        ],
      ),
    );
  }
}

class BottleScanResult {
  const BottleScanResult({this.code, this.text});

  final String? code;
  final String? text;
}

class MedicationCodeScannerScreen extends StatefulWidget {
  const MedicationCodeScannerScreen({super.key});

  @override
  State<MedicationCodeScannerScreen> createState() =>
      _MedicationCodeScannerScreenState();
}

class _MedicationCodeScannerScreenState
    extends State<MedicationCodeScannerScreen> {
  final _controller = MobileScannerController();
  final _picker = ImagePicker();
  bool _foundCode = false;

  void _onDetect(BarcodeCapture capture) {
    if (_foundCode || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue?.trim();
    if (value == null || value.isEmpty) return;
    _foundCode = true;
    Navigator.pop(context, BottleScanResult(code: value));
  }

  Future<void> _uploadCodePicture() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (image == null || !mounted) return;
    try {
      final capture = await _controller.analyzeImage(image.path);
      if (capture != null) {
        _onDetect(capture);
      } else {
        final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
        try {
          final recognized = await recognizer.processImage(
            InputImage.fromFilePath(image.path),
          );
          final text = recognized.text.trim();
          if (text.isNotEmpty && mounted && !_foundCode) {
            _foundCode = true;
            Navigator.pop(context, BottleScanResult(text: text));
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No code or readable medication label was found.',
                ),
              ),
            );
          }
        } finally {
          await recognizer.close();
        }
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This device could not read a code from that picture.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pharmacy bottle')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 260,
              height: 170,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Text(
              'Align the QR code or barcode on the pharmacy label inside the frame.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(blurRadius: 4)],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 82,
            child: Center(
              child: OutlinedButton.icon(
                onPressed: _uploadCodePicture,
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload a bottle picture'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Home screen with bottom nav ───────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  List<Widget> get _screens {
    final isCaregiver = Hive.box('profile').get('role') == 'Caregiver';
    return isCaregiver
        ? const [
            CaregiverDashboard(),
            ManagePatientsScreen(),
            AllergyProfileScreen(),
          ]
        : const [
            MedicationListScreen(),
            PillCheckerScreen(),
            PatientCalendarScreen(),
            AllergyProfileScreen(),
          ];
  }

  @override
  Widget build(BuildContext context) {
    final isCaregiver = Hive.box('profile').get('role') == 'Caregiver';
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: isCaregiver
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.medication_outlined),
                  selectedIcon: Icon(Icons.medication),
                  label: 'Patient overview',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search_outlined),
                  selectedIcon: Icon(Icons.search),
                  label: 'Manage patients',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'My Profile',
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Icons.medication_outlined),
                  selectedIcon: Icon(Icons.medication),
                  label: 'Medications',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search_outlined),
                  selectedIcon: Icon(Icons.search),
                  label: 'Pill Checker',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: 'Calendar',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'My Profile',
                ),
              ],
      ),
    );
  }
}

List<Map<String, dynamic>> _storedPatients() {
  final raw = Hive.box('profile').get('patients', defaultValue: const []);
  return (raw as List)
      .whereType<Map>()
      .map((patient) => Map<String, dynamic>.from(patient))
      .toList();
}

Set<String> _knownPersonNames() {
  final profile = Hive.box('profile');
  final names = <String>{
    profile.get('accountName', defaultValue: '').toString(),
    ..._storedPatients().map((patient) => patient['name']?.toString() ?? ''),
    ...Hive.box('medications').values.whereType<Map>().map(
      (medication) => medication['patientName']?.toString() ?? '',
    ),
  };
  return names.map(_normalizeOcrName).where((name) => name.isNotEmpty).toSet();
}

String _normalizeOcrName(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

bool _isKnownPersonName(String candidate, Set<String> knownNames) {
  final normalized = _normalizeOcrName(candidate);
  return normalized.isNotEmpty &&
      knownNames.any((name) => normalized == name || normalized.contains(name));
}

Future<void> _scheduleMedicationReminder(
  int id,
  Map<String, String> medication,
) async {
  final hour = int.tryParse(medication['reminderHour'] ?? '') ?? 8;
  final minute = int.tryParse(medication['reminderMinute'] ?? '') ?? 0;
  final now = DateTime.now();
  await NotificationService.instance.scheduleMedication(
    id: id,
    medicationName: medication['name'] ?? 'medication',
    time: DateTime(now.year, now.month, now.day, hour, minute),
  );
  await NotificationService.instance.scheduleMissedDoseSummary(
    id: 10000 + id,
    medicationName: medication['name'] ?? 'medication',
    time: const TimeOfDayValue(21, 0),
  );
  final remaining = _medicationDaysRemaining(medication);
  if (remaining != null) {
    await NotificationService.instance.scheduleRefillReminder(
      id: 20000 + id,
      medicationName: medication['name'] ?? 'medication',
      runOutDate: DateTime.now().add(Duration(days: remaining.ceil())),
    );
  }
}

double? _medicationDailyDoses(Map<String, String> medication) {
  final interval = int.tryParse(medication['frequencyInterval'] ?? '') ?? 1;
  if (interval <= 0) return null;
  final unit = medication['frequencyUnit'] ?? 'day';
  return switch (unit) {
    'hour' => 24 / interval,
    'day' => 1 / interval,
    'week' => 1 / (7 * interval),
    'month' => 1 / (30 * interval),
    _ => null,
  };
}

double? _medicationDaysRemaining(Map<String, String> medication) {
  final supply = int.tryParse(medication['supplyCount'] ?? '');
  final dailyDoses = _medicationDailyDoses(medication);
  if (supply == null || supply <= 0 || dailyDoses == null || dailyDoses <= 0)
    return null;
  final dosesPerReminder = int.tryParse(medication['doseAmount'] ?? '') ?? 1;
  return supply / (dailyDoses * dosesPerReminder);
}

String? _supplyEstimateLabel(Map<String, String> medication) {
  final days = _medicationDaysRemaining(medication);
  if (days == null) return null;
  return 'Estimated supply: about ${days.floor()} days';
}

bool _isRefillSoon(Map<String, String> medication) {
  final days = _medicationDaysRemaining(medication);
  return days != null && days <= 7;
}

Widget _medicationSupplyStatus(Map<String, String> medication) {
  final estimate = _supplyEstimateLabel(medication);
  if (estimate == null) return const SizedBox.shrink();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(estimate),
      if (_isRefillSoon(medication))
        const Text(
          'Refill soon',
          style: TextStyle(
            color: Colors.deepOrange,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
    ],
  );
}

class CaregiverDashboard extends StatefulWidget {
  const CaregiverDashboard({super.key});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  String? _selectedPatient;

  Widget _patientPicker(List<String> names, String? selected) {
    return DropdownButtonFormField<String>(
      initialValue: selected,
      decoration: const InputDecoration(
        labelText: 'Select patient from group',
        prefixIcon: Icon(Icons.person_search),
        border: OutlineInputBorder(),
      ),
      items: names
          .map((name) => DropdownMenuItem(value: name, child: Text(name)))
          .toList(),
      onChanged: (value) => setState(() => _selectedPatient = value),
    );
  }

  Widget _overview(List<String> names, String? selected) {
    final patients = _storedPatients();
    final medications = Hive.box('medications').values
        .map((item) => Map<String, String>.from(item as Map))
        .where(
          (medication) =>
              selected == null || medication['patientName'] == selected,
        )
        .toList();
    final patient = patients
        .where((item) => item['name'] == selected)
        .firstOrNull;
    final allergies = List<String>.from(patient?['allergies'] ?? const []);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _patientPicker(names, selected),
        const SizedBox(height: 20),
        if (selected == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Add patients in Manage patients to view their medication status.',
              ),
            ),
          )
        else ...[
          Text(
            selected,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.warning_amber, color: Colors.orange),
            title: const Text('Allergies'),
            subtitle: Text(
              allergies.isEmpty ? 'None recorded' : allergies.join(', '),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Medication status',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          ...medications.map((medication) {
            final today = DateTime.now().toIso8601String().substring(0, 10);
            final taken = medication['checkedDate'] == today
                ? (medication['checkedDoses'] ?? '')
                      .split(',')
                      .where((value) => value.isNotEmpty)
                      .length
                : 0;
            final total = int.tryParse(medication['doseAmount'] ?? '') ?? 1;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                taken >= total ? Icons.check_circle : Icons.schedule,
                color: taken >= total ? Colors.green : Colors.orange,
              ),
              title: Text(medication['name'] ?? 'Medication'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$taken of $total doses checked · ${medication['dosage'] ?? ''}',
                  ),
                  _medicationSupplyStatus(medication),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _history(List<String> names, String? selected) {
    final medications = Hive.box('medications').values
        .map((item) => Map<String, String>.from(item as Map))
        .where((medication) => medication['patientName'] == selected)
        .toList();
    final days = List.generate(
      28,
      (index) => DateTime.now().subtract(Duration(days: 27 - index)),
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _patientPicker(names, selected),
        const SizedBox(height: 18),
        if (selected == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select a patient to review the last 28 days.'),
            ),
          )
        else ...[
          Text(
            'Last 28 days',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            selected,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          const SizedBox(height: 8),
          Row(
            children: const ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 28,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.82,
            ),
            itemBuilder: (context, index) {
              final day = days[index];
              final key = day.toIso8601String().substring(0, 10);
              var taken = 0;
              var expected = 0;
              for (final medication in medications) {
                expected += int.tryParse(medication['doseAmount'] ?? '') ?? 1;
                final history =
                    jsonDecode(medication['doseHistory'] ?? '{}')
                        as Map<String, dynamic>;
                taken += (history[key] as num?)?.toInt() ?? 0;
              }
              final complete = expected > 0 && taken >= expected;
              final isToday =
                  key == DateTime.now().toIso8601String().substring(0, 10);
              return Container(
                decoration: BoxDecoration(
                  color: complete
                      ? Colors.green.withValues(alpha: 0.16)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isToday
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: isToday ? 2 : 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  children: [
                    Text(
                      '${day.day}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Icon(
                      complete ? Icons.check_circle : Icons.circle_outlined,
                      size: 19,
                      color: complete ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$taken/$expected',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final patients = _storedPatients();
    final names = patients.map((patient) => patient['name'] as String).toList();
    final selected = names.contains(_selectedPatient) ? _selectedPatient : null;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Patient overview'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Last 28 days'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_overview(names, selected), _history(names, selected)],
        ),
      ),
    );
  }
}

class ManagePatientsScreen extends StatefulWidget {
  const ManagePatientsScreen({super.key});

  @override
  State<ManagePatientsScreen> createState() => _ManagePatientsScreenState();
}

class _ManagePatientsScreenState extends State<ManagePatientsScreen> {
  final _patientController = TextEditingController();
  String? _selectedPatient;

  void _addPatient() {
    final name = _patientController.text.trim();
    if (name.isEmpty) return;
    final patients = _storedPatients();
    if (patients.any((patient) => patient['name'] == name)) return;
    patients.add({'name': name, 'allergies': <String>[]});
    Hive.box('profile').put('patients', patients);
    _patientController.clear();
    setState(() => _selectedPatient = name);
  }

  Future<void> _addMedicationForPatient() async {
    if (_selectedPatient == null) return;
    final medication = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(builder: (_) => const AddMedicationScreen()),
    );
    if (medication != null) {
      medication['patientName'] = _selectedPatient!;
      final box = Hive.box('medications');
      final index = box.length;
      box.add(medication);
      _scheduleMedicationReminder(index, medication);
      setState(() {});
    }
  }

  Future<void> _editMedication(Map<String, String> medication) async {
    final updated = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(initialMedication: medication),
      ),
    );
    if (updated == null) return;
    final box = Hive.box('medications');
    final index = box.values.toList().indexWhere((item) {
      final stored = Map<String, String>.from(item as Map);
      return stored['name'] == medication['name'] &&
          stored['patientName'] == medication['patientName'];
    });
    if (index >= 0) {
      box.putAt(index, updated);
      _scheduleMedicationReminder(index, updated);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _patientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patients = _storedPatients();
    final names = patients.map((patient) => patient['name'] as String).toList();
    final medications = Hive.box('medications').values
        .map((item) => Map<String, String>.from(item as Map))
        .where((medication) => medication['patientName'] == _selectedPatient)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Manage patients')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _patientController,
                  decoration: const InputDecoration(
                    labelText: 'Add patient name',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Add patient',
                onPressed: _addPatient,
                icon: const Icon(Icons.person_add),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: names.contains(_selectedPatient)
                ? _selectedPatient
                : null,
            decoration: const InputDecoration(
              labelText: 'Select patient',
              border: OutlineInputBorder(),
            ),
            items: names
                .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                .toList(),
            onChanged: (value) => setState(() => _selectedPatient = value),
          ),
          const SizedBox(height: 16),
          if (_selectedPatient != null) ...[
            ElevatedButton.icon(
              onPressed: _addMedicationForPatient,
              icon: const Icon(Icons.add),
              label: const Text('Add medicine for patient'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CaregiverCalendarScreen(patientName: _selectedPatient!),
                ),
              ),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Manage calendar events'),
            ),
            const SizedBox(height: 12),
            ...medications.map(
              (medication) => ListTile(
                title: Text(medication['name'] ?? 'Medication'),
                subtitle: Text(
                  '${medication['dosage'] ?? ''} · ${medication['frequency'] ?? ''}',
                ),
                trailing: IconButton(
                  tooltip: 'Edit medication',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editMedication(medication),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Pill checker screen ───────────────────────────────────────────────────────
class PillCheckerScreen extends StatefulWidget {
  const PillCheckerScreen({super.key});

  @override
  State<PillCheckerScreen> createState() => _PillCheckerScreenState();
}

class _PillCheckerScreenState extends State<PillCheckerScreen> {
  final Box _medBox = Hive.box('medications');
  final Box _profileBox = Hive.box('profile');

  final _imprintController = TextEditingController();
  final _nameController = TextEditingController();
  final _picker = ImagePicker();
  final _imageMatcher = const MedicationImageMatcher();

  bool _loading = false;
  bool _scanningImage = false;
  bool _readingLabel = false;
  File? _pillImage;
  File? _labelImage;
  MedicineIdentification? _result;
  String? _error;
  String? _selectedMedName;
  String? _imageMatchMessage;
  String? _recognizedOcrText;

  List<Map<String, String>> get _savedMeds =>
      _medBox.values.map((e) => Map<String, String>.from(e as Map)).toList();

  List<String> get _userAllergies =>
      List<String>.from(_profileBox.get('allergies', defaultValue: []));

  String _fdaSearchTerm(String name) {
    final words = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length >= 3)
        .toList();
    return words.isEmpty ? name : words.first;
  }

  @override
  void dispose() {
    _imprintController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<String> _readPillText(File image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      return recognized.text.trim();
    } finally {
      await recognizer.close();
    }
  }

  // ── Take or pick a photo and identify the pill ────────────────────────────
  Future<void> _scanPill({
    bool fromCamera = true,
    bool labelPhoto = false,
  }) async {
    if (fromCamera && !(Platform.isAndroid || Platform.isIOS)) {
      setState(
        () => _error =
            'Camera capture is unavailable on this device. Use From gallery instead.',
      );
      return;
    }
    try {
      final XFile? image = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        if (labelPhoto) {
          _labelImage = File(image.path);
        } else {
          _pillImage = File(image.path);
        }
        _scanningImage = true;
        _readingLabel = labelPhoto;
        _error = null;
        _result = null;
        _imageMatchMessage = null;
        if (labelPhoto) _recognizedOcrText = null;
      });

      final newPhoto = File(image.path);
      if (labelPhoto) {
        final recognizedText = await _readPillText(newPhoto);
        final knownPeople = _knownPersonNames();
        final lowerText = recognizedText.toLowerCase();
        final savedMatch = _savedMeds.where((medication) {
          final name = (medication['name'] ?? '').trim().toLowerCase();
          return name.isNotEmpty &&
              !_isKnownPersonName(name, knownPeople) &&
              lowerText.contains(name);
        }).firstOrNull;
        final candidateLines = recognizedText
            .split(RegExp(r'[\r\n]+'))
            .map((line) => line.trim())
            .where((line) => line.length >= 3)
            .where(
              (line) => !RegExp(
                r'\b(pharmacy|prescription|patient|address|rx only|ndc|refill|quantity|directions|warning|discard|lot number|take|use)\b',
                caseSensitive: false,
              ).hasMatch(line),
            )
            .where((line) => !_isKnownPersonName(line, knownPeople))
            .toList();
        final rxNormName = savedMatch == null
            ? await RxNormMedicationService.findLikelyMedicationName(
                candidateLines,
                excludedNames: knownPeople,
              )
            : null;
        final recognizedName = savedMatch?['name'] ?? rxNormName;

        if (!mounted) return;
        setState(() {
          _recognizedOcrText = recognizedText.isEmpty ? null : recognizedText;
          _selectedMedName = savedMatch?['name'];
          _nameController.text = recognizedName ?? '';
          _imprintController.clear();
          _scanningImage = false;
          _readingLabel = false;
        });
        if (recognizedName != null) {
          await _checkPill();
        } else {
          setState(
            () => _error =
                'Could not confidently identify a medication name on the label. Patient names and unverified text are not used as medication names; enter the name manually or try a clearer label photo.',
          );
        }
        return;
      }

      final matches = <Map<String, dynamic>>[];
      for (final medication in _savedMeds) {
        final path = medication['photoPath'];
        if (path == null || path.isEmpty) continue;
        final reference = File(path);
        if (!await reference.exists()) continue;
        try {
          final match = await _imageMatcher.compare(newPhoto, reference);
          matches.add({'medication': medication, 'match': match});
        } catch (_) {}
      }
      matches.sort(
        (left, right) => (right['match'] as MedicationImageMatch).score
            .compareTo((left['match'] as MedicationImageMatch).score),
      );
      if (matches.isNotEmpty) {
        final best = matches.first;
        final medication = best['medication'] as Map<String, String>;
        final match = best['match'] as MedicationImageMatch;
        final secondScore = matches.length > 1
            ? (matches[1]['match'] as MedicationImageMatch).score
            : 0.0;
        final isUnambiguous =
            matches.length == 1 || match.score - secondScore >= 0.06;
        if (mounted) {
          setState(() {
            _selectedMedName = match.isMatch && isUnambiguous
                ? medication['name']
                : null;
            _imageMatchMessage = match.isMatch && isUnambiguous
                ? 'This pill photo looks like the saved pill reference for ${medication['name']} (${match.confidenceText}). This is a visual comparison, not drug identification.'
                : 'The closest saved pill photo was ${match.confidenceText}. That is not enough to identify the pill; compare the imprint and bottle label.';
            _scanningImage = false;
          });
          return;
        }
      }

      final hasSavedReference = _savedMeds.any((medication) {
        final path = medication['photoPath'];
        return path != null && path.isNotEmpty;
      });
      if (hasSavedReference) {
        if (mounted) {
          setState(() {
            _scanningImage = false;
            _error =
                'No saved medication reference was close enough to confirm this photo. Review the bottle label instead of relying on an automatic drug name.';
          });
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _scanningImage = false;
        _imageMatchMessage =
            'No saved pill reference photos are available. Add pill-only photos to your medications to compare appearance.';
      });
    } catch (e) {
      setState(() {
        _scanningImage = false;
        _readingLabel = false;
        _error = 'Could not scan image: $e';
      });
    }
  }

  // ── FDA lookup ─────────────────────────────────────────────────────────────
  Future<void> _checkPill() async {
    final imprint = _imprintController.text.trim();
    final name = _nameController.text.trim();
    final selectedName = _selectedMedName?.trim();

    if (imprint.isEmpty && name.isEmpty && selectedName?.isNotEmpty != true) {
      setState(() => _error = 'Enter an imprint code or pill name to check.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _imageMatchMessage = null;
    });

    try {
      final lookupName = selectedName?.isNotEmpty == true
          ? selectedName!
          : name;
      final List<Map<String, dynamic>> foundResults = [];
      var similarNames = <String>[];
      if (selectedName?.isNotEmpty == true || imprint.isEmpty) {
        similarNames = await RxNormMedicationService.findSimilarNames(
          lookupName,
        );
        final searchNames = <String>{lookupName, ...similarNames.take(3)};
        final responses = await Future.wait([
          for (final candidate in searchNames)
            for (final field in ['openfda.brand_name', 'openfda.generic_name'])
              http
                  .get(
                    Uri.parse(
                      'https://api.fda.gov/drug/label.json?search=$field:${Uri.encodeComponent(_fdaSearchTerm(candidate))}&limit=10',
                    ),
                  )
                  .timeout(
                    const Duration(seconds: 8),
                    onTimeout: () => http.Response('', 408),
                  ),
        ]);
        for (final response in responses) {
          if (response.statusCode != 200) continue;
          final results = jsonDecode(response.body)['results'] as List? ?? [];
          foundResults.addAll(results.whereType<Map<String, dynamic>>());
        }
      } else {
        final encoded = Uri.encodeComponent(imprint);
        final response = await http.get(
          Uri.parse(
            'https://api.fda.gov/drug/label.json?search=openfda.imprint_code:$encoded&limit=1',
          ),
        );
        if (response.statusCode == 200) {
          final results = jsonDecode(response.body)['results'] as List? ?? [];
          foundResults.addAll(results.whereType<Map<String, dynamic>>());
        }
      }

      if (foundResults.isNotEmpty) {
        final labels = foundResults
            .map(MedicineIdentification.fromFdaLabel)
            .toList();
        final requestedName = selectedName?.isNotEmpty == true
            ? selectedName!
            : name;
        final matchingNames = <String>{requestedName, ...similarNames};
        final matchingLabel = requestedName.isNotEmpty
            ? labels
                  .where(
                    (label) => matchingNames.any(label.matchesMedicationName),
                  )
                  .firstOrNull
            : labels.first;

        if (matchingLabel != null) {
          setState(() {
            _result = matchingLabel;
            _loading = false;
          });
        } else {
          setState(() {
            _error =
                'The FDA result did not match $selectedName. Do not take it based on this scan.';
            _loading = false;
          });
        }
      } else {
        setState(() {
          _error = 'No FDA medication label matched the supplied information.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Something went wrong: $e';
        _loading = false;
      });
    }
  }

  bool _isMatch(MedicineIdentification result) {
    if (_selectedMedName == null) return false;
    return result.matchesMedicationName(_selectedMedName!);
  }

  bool _isAllergen(String ingredient) {
    final lower = ingredient.toLowerCase();
    return _userAllergies.any((a) => lower.contains(a.toLowerCase()));
  }

  void _reset() {
    setState(() {
      _result = null;
      _error = null;
      _selectedMedName = null;
      _pillImage = null;
      _labelImage = null;
      _imprintController.clear();
      _nameController.clear();
      _recognizedOcrText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final savedMeds = _savedMeds;
    final result = _result;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pill checker',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_result != null ||
              _error != null ||
              _pillImage != null ||
              _labelImage != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Start over',
              onPressed: _reset,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Camera buttons ─────────────────────────────────────────────────
          const Text(
            'Identify a medication',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Use a pill-only photo for visual comparison, or a separate bottle-label photo for text recognition. A visual match cannot identify a drug.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          const Text(
            'Pill photo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Photograph the pill by itself. This only compares it with pill photos saved in your medication list.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanningImage
                      ? null
                      : () => _scanPill(fromCamera: true),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take pill photo'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFF2A7FFF)),
                    foregroundColor: const Color(0xFF2A7FFF),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanningImage
                      ? null
                      : () => _scanPill(fromCamera: false),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Choose pill photo'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFF2A7FFF)),
                    foregroundColor: const Color(0xFF2A7FFF),
                  ),
                ),
              ),
            ],
          ),

          if (_pillImage != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                _pillImage!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'Bottle label photo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Photograph printed label text here. OCR reads this image separately and uses the text for a medication lookup.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanningImage
                      ? null
                      : () => _scanPill(fromCamera: true, labelPhoto: true),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan label'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanningImage
                      ? null
                      : () => _scanPill(fromCamera: false, labelPhoto: true),
                  icon: const Icon(Icons.image_search_outlined),
                  label: const Text('Choose label'),
                ),
              ),
            ],
          ),
          if (_labelImage != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                _labelImage!,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          if (_recognizedOcrText != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.text_snippet_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Text recognized from label',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(_recognizedOcrText!),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (_imageMatchMessage != null) ...[
            const SizedBox(height: 12),
            Card(
              color:
                  _imageMatchMessage!.contains('matches the saved') ||
                      _imageMatchMessage!.contains('looks like the saved')
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1D4329)
                        : const Color(0xFFE8F5E9))
                  : (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF492526)
                        : const Color(0xFFFFF3E0)),
              child: ListTile(
                leading: Icon(
                  _imageMatchMessage!.contains('matches the saved') ||
                          _imageMatchMessage!.contains('looks like the saved')
                      ? Icons.check_circle
                      : Icons.warning_amber,
                  color:
                      _imageMatchMessage!.contains('matches the saved') ||
                          _imageMatchMessage!.contains('looks like the saved')
                      ? Colors.green
                      : Colors.orange,
                ),
                title: const Text('Pill-photo comparison'),
                subtitle: Text(_imageMatchMessage!),
              ),
            ),
          ],

          // Scanning indicator
          if (_scanningImage) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  _readingLabel
                      ? 'Reading bottle label...'
                      : 'Comparing pill photos...',
                ),
              ],
            ),
          ],

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'or enter manually',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),

          // ── Manual inputs ──────────────────────────────────────────────────
          TextField(
            controller: _imprintController,
            decoration: const InputDecoration(
              labelText: 'Imprint code',
              hintText: 'e.g. L484, M367, 44 527',
              prefixIcon: Icon(Icons.fingerprint),
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('or', style: TextStyle(color: Colors.grey)),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Pill name',
              hintText: 'e.g. Ibuprofen, Metformin',
              prefixIcon: Icon(Icons.medication_outlined),
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 20),

          // ── Compare against saved med ──────────────────────────────────────
          if (savedMeds.isNotEmpty) ...[
            const Text(
              'Compare against my medications (optional)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedMedName,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.compare_arrows),
                border: OutlineInputBorder(),
                hintText: 'Select a saved medication',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                ...savedMeds.map(
                  (med) => DropdownMenuItem(
                    value: med['name'],
                    child: Text(med['name'] ?? ''),
                  ),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedMedName = val;
                  if (val != null) _nameController.text = val;
                });
              },
            ),
            const SizedBox(height: 20),
          ],

          // ── Check button ───────────────────────────────────────────────────
          ElevatedButton.icon(
            onPressed: _loading ? null : _checkPill,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF167D8D),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search),
            label: Text(_loading ? 'Checking...' : 'Check this pill'),
          ),

          // ── Error ──────────────────────────────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: 20),
            Card(
              color: const Color(0xFFFFF3E0),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
            ),
          ],

          // ── Result ────────────────────────────────────────────────────────
          if (result != null) ...[
            const SizedBox(height: 24),

            if (_selectedMedName != null) ...[
              _isMatch(result)
                  ? _banner(
                      color: Colors.green,
                      icon: Icons.check_circle,
                      title: '✅ This matches your medication',
                      subtitle: 'This pill appears to be $_selectedMedName.',
                    )
                  : _banner(
                      color: Colors.red,
                      icon: Icons.cancel,
                      title: '❌ This does NOT match',
                      subtitle:
                          'This pill does not appear to be $_selectedMedName. '
                          'Do not take it without checking with your doctor.',
                    ),
              const SizedBox(height: 16),
            ],

            const Text(
              'This pill is:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (result.brandNames.isNotEmpty) ...[
                      const Text(
                        'Brand name',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Text(
                        result.brandNames.join(', '),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (result.genericNames.isNotEmpty) ...[
                      const Text(
                        'Generic name',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Text(result.genericNames.join(', ')),
                    ],
                    if (result.purposes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Used for',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Text(result.purposes.join(', ')),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Allergy check
            const Text(
              'Allergy check',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_userAllergies.isEmpty)
              const Text(
                'Add your allergies in My Profile to get allergy warnings here.',
                style: TextStyle(color: Colors.grey),
              )
            else
              Builder(
                builder: (context) {
                  final allergenHits = result.ingredients
                      .where(_isAllergen)
                      .toList();
                  if (allergenHits.isEmpty) {
                    return Card(
                      color: const Color(0xFFE8F5E9),
                      child: const ListTile(
                        leading: Icon(Icons.check_circle, color: Colors.green),
                        title: Text('No allergy conflicts found'),
                        subtitle: Text(
                          'None of the ingredients match your allergy profile.',
                        ),
                      ),
                    );
                  } else {
                    return Card(
                      color: const Color(0xFFFFEBEE),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.warning_amber, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  '⚠️ Allergy warning!',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'This pill contains ingredients matching your allergy profile:',
                            ),
                            const SizedBox(height: 6),
                            ...allergenHits.map(
                              (i) => Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.circle,
                                      size: 6,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      i,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                },
              ),

            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Warnings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                color: const Color(0xFFFFEBEE),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.red),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          result.warnings.first.toString().length > 400
                              ? '${result.warnings.first.toString().substring(0, 400)}...'
                              : result.warnings.first.toString(),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),
            const Text(
              'ℹ️ Information sourced from the FDA drug label database. '
              'Always confirm with your pharmacist or doctor.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _banner({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bannerColor = color == Colors.green
        ? (isDark ? const Color(0xFF1D4329) : const Color(0xFFE8F5E9))
        : (isDark ? const Color(0xFF492526) : const Color(0xFFFFEBEE));
    final contentColor = color == Colors.green
        ? (isDark ? const Color(0xFFB7F0C0) : const Color(0xFF1B5E20))
        : (isDark ? const Color(0xFFFFDAD6) : const Color(0xFFB71C1C));
    return Card(
      color: bannerColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: contentColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: contentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: contentColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Medication list screen ────────────────────────────────────────────────────
class MedicationListScreen extends StatefulWidget {
  const MedicationListScreen({super.key});

  @override
  State<MedicationListScreen> createState() => _MedicationListScreenState();
}

class _MedicationListScreenState extends State<MedicationListScreen> {
  final Box _medBox = Hive.box('medications');

  List<Map<String, String>> get _medications {
    return _medBox.values
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  void _addMedication(Map<String, String> med) {
    _medBox.add(med);
    final id = _medBox.length - 1;
    _scheduleMedicationReminder(id, med);
    setState(() {});
  }

  void _deleteMedication(int index) {
    NotificationService.instance.cancelMedication(index);
    NotificationService.instance.cancelMedication(10000 + index);
    NotificationService.instance.cancelMedication(20000 + index);
    _medBox.deleteAt(index);
    setState(() {});
  }

  void _toggleDose(int index, Map<String, String> medication, int doseIndex) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final checked = medication['checkedDate'] == today
        ? (medication['checkedDoses'] ?? '')
              .split(',')
              .where((item) => item.isNotEmpty)
              .toSet()
        : <String>{};
    final key = doseIndex.toString();
    if (!checked.add(key)) checked.remove(key);
    medication['checkedDate'] = today;
    medication['checkedDoses'] = checked.join(',');
    final history =
        jsonDecode(medication['doseHistory'] ?? '{}') as Map<String, dynamic>;
    history[today] = checked.length;
    medication['doseHistory'] = jsonEncode(history);
    _medBox.putAt(index, medication);
    setState(() {});
  }

  void _goToAddScreen() async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(builder: (_) => const AddMedicationScreen()),
    );
    if (result != null) _addMedication(result);
  }

  void _goToDetailScreen(Map<String, String> med, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationDetailScreen(
          medication: med,
          onEdit: () async {
            final updated = await Navigator.push<Map<String, String>>(
              context,
              MaterialPageRoute(
                builder: (_) => AddMedicationScreen(initialMedication: med),
              ),
            );
            if (updated != null) {
              _medBox.putAt(index, updated);
              _scheduleMedicationReminder(index, updated);
              setState(() {});
              if (context.mounted) Navigator.pop(context);
            }
          },
          onDelete: () {
            _deleteMedication(index);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meds = _medications;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Medications',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Care chat',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Medication notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Medication notifications'),
                content: const Text(
                  'Dose reminders open this checklist. Check each circle after taking the dose. Unchecked doses are reviewed at the end of the day.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Open checklist'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: meds.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.medication_outlined, size: 72, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No medications added yet.',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap + to add your first one.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              itemCount: meds.length,
              itemBuilder: (context, index) {
                final med = meds[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    leading: med['photoPath']?.isNotEmpty == true
                        ? Image.file(
                            File(med['photoPath']!),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : const CircleAvatar(
                            backgroundColor: Color(0xFF2A7FFF),
                            child: Icon(Icons.medication, color: Colors.white),
                          ),
                    title: Text(
                      med['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${med['dosage']} · ${med['frequency']}'),
                        _medicationSupplyStatus(med),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        int.tryParse(med['doseAmount'] ?? '') ?? 1,
                        (doseIndex) {
                          final today = DateTime.now()
                              .toIso8601String()
                              .substring(0, 10);
                          final checked =
                              med['checkedDate'] == today &&
                              (med['checkedDoses'] ?? '')
                                  .split(',')
                                  .contains(doseIndex.toString());
                          return IconButton(
                            tooltip: checked ? 'Dose taken' : 'Mark dose taken',
                            icon: Icon(
                              checked
                                  ? Icons.check_circle
                                  : Icons.check_circle_outline,
                              color: checked ? Colors.green : Colors.grey,
                            ),
                            onPressed: () => _toggleDose(index, med, doseIndex),
                          );
                        },
                      ),
                    ),
                    onTap: () => _goToDetailScreen(med, index),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goToAddScreen,
        backgroundColor: const Color(0xFF167D8D),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Medication'),
      ),
    );
  }
}

// ── Medication detail screen ──────────────────────────────────────────────────
class MedicationDetailScreen extends StatefulWidget {
  final Map<String, String> medication;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const MedicationDetailScreen({
    super.key,
    required this.medication,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<MedicationDetailScreen> createState() => _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen> {
  final Box _profileBox = Hive.box('profile');

  bool _loading = true;
  String? _error;
  List<String> _ingredients = [];
  String? _purpose;
  String? _warnings;

  List<String> get _userAllergies =>
      List<String>.from(_profileBox.get('allergies', defaultValue: []));

  String _fdaSearchTerm(String name) {
    final words = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length >= 3)
        .toList();
    return words.isEmpty ? name : words.first;
  }

  @override
  void initState() {
    super.initState();
    _fetchIngredients();
  }

  Future<void> _fetchIngredients() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final medicationName = widget.medication['name']?.trim() ?? '';
      final encodedName = Uri.encodeComponent(_fdaSearchTerm(medicationName));
      final labels = <Map<String, dynamic>>[];
      for (final field in ['openfda.brand_name', 'openfda.generic_name']) {
        final response = await http.get(
          Uri.parse(
            'https://api.fda.gov/drug/label.json?search=$field:$encodedName&limit=10',
          ),
        );
        if (response.statusCode != 200) continue;
        final results = jsonDecode(response.body)['results'] as List? ?? [];
        labels.addAll(results.whereType<Map<String, dynamic>>());
      }

      final label = labels
          .map((value) => (value, MedicineIdentification.fromFdaLabel(value)))
          .where((entry) => entry.$2.matchesMedicationName(medicationName))
          .map((entry) => entry.$1)
          .firstOrNull;

      if (label != null) {
        final activeRaw =
            (label['active_ingredient'] as List?)?.join('\n') ?? '';
        final inactiveRaw =
            (label['inactive_ingredient'] as List?)?.join('\n') ?? '';

        final allIngredients = <String>[];
        for (final raw in [activeRaw, inactiveRaw]) {
          if (raw.isNotEmpty) {
            allIngredients.addAll(
              raw
                  .split(RegExp(r'[,\n]'))
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty),
            );
          }
        }

        setState(() {
          _ingredients = allIngredients;
          _purpose =
              (label['purpose'] as List?)?.join(' ') ??
              (label['indications_and_usage'] as List?)?.first ??
              '';
          _warnings = (label['warnings'] as List?)?.first;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'No verified FDA label matched this medication name.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Something went wrong: $e';
        _loading = false;
      });
    }
  }

  bool _isAllergen(String ingredient) {
    final lower = ingredient.toLowerCase();
    return _userAllergies.any((a) => lower.contains(a.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final med = widget.medication;
    final allergies = _userAllergies;

    return Scaffold(
      appBar: AppBar(
        title: Text(med['name'] ?? 'Medication'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit medication',
            onPressed: widget.onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Remove medication?'),
                content: Text('Remove ${med['name']}?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onDelete();
                    },
                    child: const Text(
                      'Remove',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(Icons.scale, 'Dosage', med['dosage'] ?? ''),
                  const SizedBox(height: 10),
                  _infoRow(Icons.schedule, 'Frequency', med['frequency'] ?? ''),
                  if ((med['notes'] ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _infoRow(Icons.notes, 'Notes', med['notes'] ?? ''),
                  ],
                ],
              ),
            ),
          ),
          if ((med['qrCodeId'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    QrImageView(
                      data: med['qrCodeId']!,
                      size: 84,
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Medication ID',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            med['qrCodeId']!,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Use this code to identify this medication when adding it to a patient.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (_purpose != null && _purpose!.isNotEmpty) ...[
            const Text(
              'What it\'s for',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_purpose!),
              ),
            ),
            const SizedBox(height: 20),
          ],
          const Text(
            'Ingredients',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          if (allergies.isNotEmpty)
            const Text(
              'Ingredients matching your allergies are highlighted in red.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          const SizedBox(height: 10),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            Card(
              color: const Color(0xFFFFF3E0),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
            )
          else if (_ingredients.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('No ingredient list available.'),
              ),
            )
          else
            Card(
              child: Column(
                children: _ingredients.map((ingredient) {
                  final isAllergen = _isAllergen(ingredient);
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isAllergen ? Icons.warning_amber : Icons.circle,
                      color: isAllergen ? Colors.red : const Color(0xFF2A7FFF),
                      size: isAllergen ? 20 : 10,
                    ),
                    title: Text(
                      ingredient,
                      style: TextStyle(
                        color: isAllergen ? Colors.red : null,
                        fontWeight: isAllergen
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: isAllergen
                        ? const Text(
                            '⚠️ Matches your allergy profile',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          )
                        : null,
                  );
                }).toList(),
              ),
            ),
          if (_warnings != null) ...[
            const SizedBox(height: 20),
            const Text(
              'Warnings',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF492526)
                  : const Color(0xFFFFEBEE),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFFFFB4AB)
                          : Colors.red,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _warnings!.length > 500
                            ? '${_warnings!.substring(0, 500)}...'
                            : _warnings!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFFFFDAD6)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'ℹ️ Information sourced from the FDA drug label database. '
            'Always confirm with your pharmacist or doctor.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2A7FFF)),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}

// ── Add medication screen ─────────────────────────────────────────────────────
class AddMedicationScreen extends StatefulWidget {
  final Map<String, String>? initialMedication;

  const AddMedicationScreen({super.key, this.initialMedication});

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _supplyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  List<String> _suggestions = [];
  bool _searching = false;
  String? _selectedName;
  final _strengthController = TextEditingController();
  final _dosageQuantityFieldKey = GlobalKey<FormFieldState<int>>();
  final _dosageUnitFieldKey = GlobalKey<FormFieldState<String>>();
  String? _photoPath;
  String? _labelPhotoPath;
  String? _qrCodeId;
  int _dosageQuantity = 1;
  String _dosageUnit = 'tablet';
  int _frequencyInterval = 1;
  String _frequencyUnit = 'day';
  TimeOfDay _reminderTime = const TimeOfDay(hour: 8, minute: 0);

  static const _dosageUnits = [
    'tablet',
    'capsule',
    'mL',
    'drop',
    'puff',
    'patch',
    'injection',
  ];

  static const _frequencyUnits = ['hour', 'day', 'week', 'month'];

  @override
  void initState() {
    super.initState();
    final medication = widget.initialMedication;
    if (medication == null) return;
    _nameController.text = medication['name'] ?? '';
    _strengthController.text = medication['strength'] ?? '';
    _qrCodeId = medication['qrCodeId'];
    _reminderTime = TimeOfDay(
      hour: int.tryParse(medication['reminderHour'] ?? '') ?? 8,
      minute: int.tryParse(medication['reminderMinute'] ?? '') ?? 0,
    );
    _notesController.text = medication['notes'] ?? '';
    _supplyController.text = medication['supplyCount'] ?? '';
    _photoPath = medication['photoPath'];
    _labelPhotoPath = medication['labelPhotoPath'];
    final dosage = (medication['dosage'] ?? '').split(' ');
    _dosageQuantity = int.tryParse(dosage.first) ?? 1;
    if (dosage.length > 1 && _dosageUnits.contains(dosage[1])) {
      _dosageUnit = dosage[1];
    }
    final frequency = RegExp(
      r'Every (\d+) (\w+)',
    ).firstMatch(medication['frequency'] ?? '');
    if (frequency != null) {
      _frequencyInterval = int.tryParse(frequency.group(1)!) ?? 1;
      final unit = frequency.group(2)!.replaceFirst(RegExp(r's$'), '');
      if (_frequencyUnits.contains(unit)) _frequencyUnit = unit;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _strengthController.dispose();
    _notesController.dispose();
    _supplyController.dispose();
    super.dispose();
  }

  Future<void> _onNameChanged(String query) async {
    _selectedName = null;
    if (query.length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _searching = true);

    var rxNormNames = <String>[];
    try {
      rxNormNames = await RxNormMedicationService.findSimilarNames(query);
      final encoded = Uri.encodeComponent(query);
      final url = Uri.parse(
        'https://api.fda.gov/drug/label.json?search=openfda.brand_name:$encoded+openfda.generic_name:$encoded&limit=8',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List? ?? [];
        final names = <String>{...rxNormNames};

        for (final r in results) {
          final openfda = r['openfda'] as Map?;
          if (openfda != null) {
            final brands = openfda['brand_name'] as List?;
            final generics = openfda['generic_name'] as List?;
            if (brands != null) names.addAll(brands.cast<String>());
            if (generics != null) names.addAll(generics.cast<String>());
          }
        }

        final filtered =
            <String>[
              ...rxNormNames,
              ...names.where(
                (name) => name.toLowerCase().contains(query.toLowerCase()),
              ),
            ].fold<List<String>>([], (matches, name) {
              if (!matches.any(
                (match) => match.toLowerCase() == name.toLowerCase(),
              )) {
                matches.add(name);
              }
              return matches;
            });

        setState(() {
          _suggestions = filtered.take(6).toList();
          _searching = false;
        });
      } else {
        setState(() {
          _suggestions = rxNormNames.take(6).toList();
          _searching = false;
        });
      }
    } catch (_) {
      setState(() {
        _suggestions = rxNormNames.take(6).toList();
        _searching = false;
      });
    }
  }

  Future<void> _loadStrengthForMedication(String name) async {
    try {
      final encoded = Uri.encodeComponent(name);
      final response = await http.get(
        Uri.parse(
          'https://api.fda.gov/drug/label.json?search=openfda.brand_name:$encoded+openfda.generic_name:$encoded&limit=1',
        ),
      );
      if (response.statusCode != 200) return;
      final result = (jsonDecode(response.body)['results'] as List?)?.first;
      if (result is! Map) return;
      final raw = [
        ...(result['active_ingredient'] as List? ?? const []),
        ...(result['description'] as List? ?? const []),
      ].join(' ');
      final match = RegExp(
        r'\b\d+(?:\.\d+)?\s*(?:mg|mcg|g|mL|%)\b',
        caseSensitive: false,
      ).firstMatch(raw);
      if (match != null && mounted) {
        setState(
          () => _strengthController.text = match
              .group(0)!
              .replaceAll(RegExp(r'\s+'), ' '),
        );
      }
    } catch (_) {}
  }

  void _selectSuggestion(String name) {
    _selectedName = name;
    _nameController.text = name;
    final lowerName = name.toLowerCase();
    if (lowerName.contains('capsule')) {
      _dosageUnit = 'capsule';
    } else if (lowerName.contains('syrup') || lowerName.contains('solution')) {
      _dosageUnit = 'mL';
    } else if (lowerName.contains('inhal')) {
      _dosageUnit = 'puff';
    } else if (lowerName.contains('patch')) {
      _dosageUnit = 'patch';
    } else {
      _dosageUnit = 'tablet';
    }
    setState(() => _suggestions = []);
    _loadStrengthForMedication(name);
  }

  Future<void> _captureMedicationPhoto() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera capture is unavailable on this device. Upload a picture instead.',
          ),
        ),
      );
      return;
    }

    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() => _photoPath = image.path);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the camera: $error')),
        );
      }
    }
  }

  Future<void> _uploadMedicationPhoto() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() => _photoPath = image.path);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not choose a picture: $error')),
        );
      }
    }
  }

  Future<void> _captureMedicationLabelPhoto() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera capture is unavailable on this device. Upload a label picture instead.',
          ),
        ),
      );
      return;
    }

    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
      );
      if (image == null) return;
      setState(() => _labelPhotoPath = image.path);
      await _readMedicationLabel(image.path);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the label camera: $error')),
        );
      }
    }
  }

  Future<void> _uploadMedicationLabelPhoto() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (image == null) return;
      setState(() => _labelPhotoPath = image.path);
      await _readMedicationLabel(image.path);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not choose the label picture: $error')),
        );
      }
    }
  }

  Future<void> _scanMedicationCode() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bottle scanning is available on Android and iOS.'),
        ),
      );
      return;
    }
    final scan = await Navigator.push<BottleScanResult>(
      context,
      MaterialPageRoute(builder: (_) => const MedicationCodeScannerScreen()),
    );
    if (scan == null || !mounted) return;
    if (scan.code != null && scan.code!.isNotEmpty) {
      setState(() => _qrCodeId = scan.code);
      await _lookupMedicationCode(scan.code!);
      return;
    }
    final text = scan.text ?? '';
    final medicationFound = await _applyMedicationLabelText(text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          medicationFound
              ? 'Medication name recognized. Review the name and strength before saving.'
              : 'No medication name was confidently recognized. Enter it manually or try a clearer label.',
        ),
      ),
    );
  }

  Future<void> _readMedicationLabel(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      final medicationFound = await _applyMedicationLabelText(recognized.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            medicationFound
                ? 'Medication name recognized. Review the name, strength, and dose before saving.'
                : 'Could not confidently recognize a medication name. Enter it manually or try a clearer label photo.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not read the label. Try a clearer, closer photo.',
            ),
          ),
        );
      }
    } finally {
      await recognizer.close();
    }
  }

  Future<bool> _applyMedicationLabelText(String text) async {
    final strength = RegExp(
      r'\b\d+(?:\.\d+)?\s*(?:mg|mcg|g|mL|%)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (strength != null) {
      _strengthController.text = strength
          .group(0)!
          .replaceAll(RegExp(r'\s+'), ' ');
    }

    final dose = RegExp(
      r'\b(?:take|use|give)\s+(\d{1,2})\s+(tablets?|capsules?|pills?|drops?|puffs?)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (dose != null) {
      final quantity = int.tryParse(dose.group(1)!);
      final unitText = dose.group(2)!.toLowerCase();
      final unit = unitText.startsWith('capsule')
          ? 'capsule'
          : unitText.startsWith('drop')
          ? 'drop'
          : unitText.startsWith('puff')
          ? 'puff'
          : 'tablet';
      if (quantity != null && quantity > 0 && quantity <= 10) {
        _dosageQuantity = quantity;
        _dosageUnit = unit;
        _dosageQuantityFieldKey.currentState?.didChange(quantity);
        _dosageUnitFieldKey.currentState?.didChange(unit);
      }
    }

    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.length >= 3)
        .where(
          (line) => !RegExp(
            r'\b(pharmacy|prescription|patient|address|rx only|ndc|refill|quantity|directions|warning|discard|lot number)\b',
            caseSensitive: false,
          ).hasMatch(line),
        )
        .where(
          (line) => !RegExp(
            r'\b(?:take|use|give)\s+\d+\b',
            caseSensitive: false,
          ).hasMatch(line),
        )
        .map(
          (line) => line
              .replaceAll(
                RegExp(
                  r'\b\d+(?:\.\d+)?\s*(?:mg|mcg|g|mL|%)\b',
                  caseSensitive: false,
                ),
                ' ',
              )
              .replaceAll(
                RegExp(
                  r'\b(?:tablets?|capsules?|pills?)\b',
                  caseSensitive: false,
                ),
                ' ',
              )
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim(),
        )
        .where((line) => line.length >= 3 && RegExp(r'[a-zA-Z]').hasMatch(line))
        .where((line) => !_isKnownPersonName(line, _knownPersonNames()))
        .toList();
    if (lines.isNotEmpty) {
      final medicationName =
          await RxNormMedicationService.findLikelyMedicationName(
            lines,
            excludedNames: _knownPersonNames(),
          );
      if (medicationName == null) return false;
      _selectedName = null;
      _nameController.text = medicationName;
      if (mounted) setState(() {});
      await _onNameChanged(medicationName);
      return true;
    }
    return false;
  }

  Future<void> _lookupMedicationCode(String code) async {
    final encoded = Uri.encodeComponent(code);
    for (final field in ['openfda.package_ndc', 'openfda.product_ndc']) {
      try {
        final response = await http.get(
          Uri.parse(
            'https://api.fda.gov/drug/label.json?search=$field:$encoded&limit=1',
          ),
        );
        if (response.statusCode != 200) continue;
        final results = jsonDecode(response.body)['results'] as List?;
        if (results == null || results.isEmpty) continue;
        final label = results.first as Map;
        final openfda = label['openfda'] as Map? ?? {};
        final brands = (openfda['brand_name'] as List?) ?? const [];
        final generics = (openfda['generic_name'] as List?) ?? const [];
        final name = brands.isNotEmpty
            ? brands.first.toString()
            : generics.firstOrNull?.toString();
        final raw = [
          ...(label['active_ingredient'] as List? ?? const []),
          ...(label['description'] as List? ?? const []),
        ].join(' ');
        final strength = RegExp(
          r'\b\d+(?:\.\d+)?\s*(?:mg|mcg|g|mL|%)\b',
          caseSensitive: false,
        ).firstMatch(raw)?.group(0);
        if (name != null && name.isNotEmpty) _nameController.text = name;
        if (strength != null)
          _strengthController.text = strength.replaceAll(RegExp(r'\s+'), ' ');
        if (mounted) setState(() {});
        return;
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Code saved, but no matching FDA medication was found. Enter the name manually.',
          ),
        ),
      );
    }
  }

  Future<void> _chooseReminderTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
    );
    if (selected != null) setState(() => _reminderTime = selected);
  }

  void _save() {
    if (_formKey.currentState!.validate() && _photoPath != null) {
      final updated = <String, String>{
        'name': (_selectedName ?? _nameController.text).trim(),
        'dosage':
            '$_dosageQuantity $_dosageUnit${_strengthController.text.trim().isEmpty ? '' : ' (${_strengthController.text.trim()})'}',
        'strength': _strengthController.text.trim(),
        'frequency':
            'Every $_frequencyInterval $_frequencyUnit${_frequencyInterval == 1 ? '' : 's'}',
        'notes': _notesController.text.trim(),
        'photoPath': _photoPath!,
        'labelPhotoPath': _labelPhotoPath ?? '',
        'doseAmount': _dosageQuantity.toString(),
        'frequencyInterval': _frequencyInterval.toString(),
        'frequencyUnit': _frequencyUnit,
        'supplyCount': _supplyController.text.trim(),
        'reminderHour': _reminderTime.hour.toString(),
        'reminderMinute': _reminderTime.minute.toString(),
        'checkedDate': widget.initialMedication?['checkedDate'] ?? '',
        'checkedDoses': widget.initialMedication?['checkedDoses'] ?? '',
        'doseHistory': widget.initialMedication?['doseHistory'] ?? '{}',
        'qrCodeId': _qrCodeId ?? 'MED-${DateTime.now().microsecondsSinceEpoch}',
      };
      final patientName = widget.initialMedication?['patientName'];
      if (patientName != null) updated['patientName'] = patientName;
      Navigator.pop(context, updated);
    } else if (_photoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Take a photo of this medication before saving.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Medication')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Pill photo reference',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Photograph the pill by itself. This image is used only for visual comparison, not text recognition.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _captureMedicationPhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Take pill photo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploadMedicationPhoto,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Choose pill photo'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Optional bottle code',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Scanning a pharmacy QR code or barcode is optional. A medication photo is enough to continue.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _scanMedicationCode,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(
                _qrCodeId == null
                    ? 'Scan pharmacy bottle QR / barcode'
                    : 'Bottle code scanned',
              ),
            ),
            if (_photoPath == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'A medication picture is required. You can take one or upload an existing picture.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            if (_photoPath != null) ...[
              const SizedBox(height: 8),
              Image.file(File(_photoPath!), height: 140, fit: BoxFit.cover),
            ],
            const SizedBox(height: 18),
            const Text(
              'Read bottle label (optional)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Use a separate, clear picture of the printed label to fill in the medication name and strength.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _captureMedicationLabelPhoto,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Scan label'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploadMedicationLabelPhoto,
                    icon: const Icon(Icons.image_search_outlined),
                    label: const Text('Choose label'),
                  ),
                ),
              ],
            ),
            if (_labelPhotoPath != null) ...[
              const SizedBox(height: 8),
              Image.file(
                File(_labelPhotoPath!),
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Medication name *',
                hintText: 'Start typing (e.g. Metformin)...',
                prefixIcon: const Icon(Icons.medication),
                border: const OutlineInputBorder(),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _selectedName != null
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
              ),
              textCapitalization: TextCapitalization.words,
              onChanged: _onNameChanged,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Please enter the medication name'
                  : null,
            ),
            if (_suggestions.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 4),
                elevation: 4,
                child: Column(
                  children: _suggestions
                      .map(
                        (name) => ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.medication_outlined,
                            color: Color(0xFF2A7FFF),
                            size: 18,
                          ),
                          title: Text(name),
                          subtitle: const Text(
                            'FDA recognized name',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          onTap: () => _selectSuggestion(name),
                        ),
                      )
                      .toList(),
                ),
              ),
            if (_suggestions.isEmpty &&
                !_searching &&
                _nameController.text.length >= 3 &&
                _selectedName == null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  'No FDA matches found — you can still save manually.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _strengthController,
              decoration: const InputDecoration(
                labelText: 'Strength (optional)',
                hintText: 'e.g. 25 mg',
                prefixIcon: Icon(Icons.science_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: _dosageQuantityFieldKey,
                    initialValue: _dosageQuantity,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(10, (index) => index + 1)
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null)
                        setState(() => _dosageQuantity = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: _dosageUnitFieldKey,
                    initialValue: _dosageUnit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: _dosageUnits
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _dosageUnit = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _frequencyInterval,
                    decoration: const InputDecoration(
                      labelText: 'Every',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(24, (index) => index + 1)
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null)
                        setState(() => _frequencyInterval = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _frequencyUnit,
                    decoration: const InputDecoration(
                      labelText: 'Time unit',
                      border: OutlineInputBorder(),
                    ),
                    items: _frequencyUnits
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _frequencyUnit = value);
                    },
                  ),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alarm),
              title: const Text('Reminder time'),
              subtitle: Text(_reminderTime.format(context)),
              onTap: _chooseReminderTime,
            ),
            TextFormField(
              controller: _supplyController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Units on hand (optional)',
                hintText: 'e.g. 90 tablets',
                prefixIcon: const Icon(Icons.inventory_2_outlined),
                suffixText: _dosageUnit,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add the number of tablets, capsules, or other units currently available to get a refill reminder.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g. Take with food',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF167D8D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              icon: const Icon(Icons.save),
              label: const Text('Save Medication'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Allergy profile screen ────────────────────────────────────────────────────
class AllergyProfileScreen extends StatefulWidget {
  const AllergyProfileScreen({super.key});

  @override
  State<AllergyProfileScreen> createState() => _AllergyProfileScreenState();
}

class _AllergyProfileScreenState extends State<AllergyProfileScreen> {
  final Box _profileBox = Hive.box('profile');
  final FlutterTts _tts = FlutterTts();
  final _allergyController = TextEditingController();
  final _accountController = TextEditingController();
  final _groupController = TextEditingController();

  List<String> get _allergies =>
      List<String>.from(_profileBox.get('allergies', defaultValue: []));

  List<String> get _groups =>
      List<String>.from(_profileBox.get('groups', defaultValue: []));

  String get _role =>
      _profileBox.get('role', defaultValue: 'Patient') as String;

  bool get _isDarkMode =>
      _profileBox.get('darkMode', defaultValue: false) == true;

  double get _textScale =>
      (_profileBox.get('textScale', defaultValue: 1.0) as num).toDouble();

  bool get _ttsEnabled =>
      _profileBox.get('ttsEnabled', defaultValue: false) == true;

  Future<void> _readMedicationSummary() async {
    final medications = Hive.box(
      'medications',
    ).values.map((item) => Map<String, String>.from(item as Map)).toList();
    final summary = medications.isEmpty
        ? 'You have no medications saved.'
        : 'Your medications are: ${medications.map((medication) => '${medication['name']}, ${medication['dosage']}, ${medication['frequency']}').join('. ')}.';
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.speak(summary);
  }

  void _addAllergy() {
    final value = _allergyController.text.trim();
    if (value.isEmpty) return;
    _profileBox.put('allergies', [..._allergies, value]);
    _allergyController.clear();
    setState(() {});
  }

  void _deleteAllergy(int index) {
    final updated = [..._allergies]..removeAt(index);
    _profileBox.put('allergies', updated);
    setState(() {});
  }

  void _saveAccount() {
    final name = _accountController.text.trim();
    if (name.isEmpty) return;
    _profileBox.put('accountName', name);
    setState(() {});
  }

  void _addGroup() {
    if (_role != 'Caregiver') return;
    final group = _groupController.text.trim();
    if (group.isEmpty) return;
    _profileBox.put('groups', [..._groups, group]);
    _groupController.clear();
    setState(() {});
  }

  Future<void> _signOut() async {
    await SupabaseService.instance.signOut();
    _profileBox.delete('accountName');
    _profileBox.delete('role');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _allergyController.dispose();
    _accountController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allergies = _allergies;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Sign out?'),
                content: const Text(
                  'You will need to sign in again on this device.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _signOut();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                    style: FilledButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(
                    Icons.person_outline,
                    color: Theme.of(context).colorScheme.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hello, ${_profileBox.get('accountName', defaultValue: 'there')}',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: _isDarkMode
                              ? const Color(0xFFFFF2D8)
                              : const Color(0xFF4A3210),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _role == 'Caregiver'
                            ? 'Care team workspace'
                            : 'Personal medication space',
                        style: TextStyle(
                          color: _isDarkMode
                              ? const Color(0xFFE4D3B0)
                              : const Color(0xFF6A5737),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Personal details',
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _accountController,
            decoration: const InputDecoration(
              labelText: 'Your name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saveAccount(),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(
              labelText: 'Role',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Patient', child: Text('Patient')),
              DropdownMenuItem(value: 'Caregiver', child: Text('Caregiver')),
            ],
            onChanged: (value) {
              if (value != null) {
                _profileBox.put('role', value);
                setState(() {});
              }
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Dark mode',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Use a warmer dark theme for low-light settings.',
            ),
            secondary: Icon(_isDarkMode ? Icons.dark_mode : Icons.light_mode),
            value: _isDarkMode,
            onChanged: (enabled) {
              _profileBox.put('darkMode', enabled);
              setState(() {});
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.text_fields),
            title: const Text(
              'Text size',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('${(_textScale * 100).round()}%'),
          ),
          Slider(
            value: _textScale.clamp(0.85, 1.6),
            min: 0.85,
            max: 1.6,
            divisions: 5,
            label: '${(_textScale * 100).round()}%',
            onChanged: (value) {
              _profileBox.put('textScale', value);
              setState(() {});
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Read medication details aloud',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Enable text to speech for medication summaries.',
            ),
            secondary: const Icon(Icons.volume_up_outlined),
            value: _ttsEnabled,
            onChanged: (enabled) {
              _profileBox.put('ttsEnabled', enabled);
              setState(() {});
            },
          ),
          OutlinedButton.icon(
            onPressed: _ttsEnabled ? _readMedicationSummary : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Read my medications'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Patient and caregiver groups',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            _role == 'Caregiver'
                ? 'Create a group for patients and other caregivers.'
                : 'Enter a group name or invite code from your caregiver.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          if (_role == 'Caregiver')
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _groupController,
                    decoration: const InputDecoration(
                      labelText: 'New group name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Create group',
                  onPressed: _addGroup,
                  icon: const Icon(Icons.group_add),
                ),
              ],
            )
          else
            const Text(
              'Group joining will be available when a caregiver sends an invite.',
            ),
          if (_groups.isNotEmpty)
            ..._groups.map(
              (group) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.groups_outlined),
                title: Text(group),
                subtitle: Text('Joined as $_role'),
              ),
            ),
          const Divider(height: 32),
          Text(
            'Known Allergies',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add any medications or ingredients you are allergic to. '
            'MedSafe will warn you if a pill matches.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _allergyController,
                  decoration: InputDecoration(
                    labelText: 'Add allergy',
                    hintText: 'e.g. Penicillin',
                    labelStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    prefixIcon: const Icon(
                      Icons.warning_amber_outlined,
                      color: Color(0xFFD49A27),
                    ),
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _addAllergy(),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _addAllergy,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 20,
                  ),
                ),
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (allergies.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'No allergies added yet.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...allergies.asMap().entries.map(
              (entry) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: _isDarkMode
                    ? const Color(0xFF3B3020)
                    : const Color(0xFFFFF3E0),
                child: ListTile(
                  leading: const Icon(
                    Icons.warning_amber,
                    color: Color(0xFFD49A27),
                  ),
                  title: Text(
                    entry.value,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _deleteAllergy(entry.key),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
