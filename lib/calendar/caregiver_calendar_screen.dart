import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class CaregiverCalendarScreen extends StatefulWidget {
  const CaregiverCalendarScreen({super.key, required this.patientName});

  final String patientName;

  @override
  State<CaregiverCalendarScreen> createState() =>
      _CaregiverCalendarScreenState();
}

class _CaregiverCalendarScreenState extends State<CaregiverCalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = DateTime.now();

  Box get _events => Hive.box('calendar_events');

  List<Map<String, dynamic>> _eventsForPatient() => _events
      .toMap()
      .entries
      .where((entry) => entry.value is Map)
      .map(
        (entry) => {
          ...Map<String, dynamic>.from(entry.value as Map),
          '_hiveKey': entry.key,
        },
      )
      .where((event) => event['patientName'] == widget.patientName)
      .toList();

  Future<void> _addEvent() async {
    final titleController = TextEditingController();
    final detailsController = TextEditingController();
    var day = _selectedDay;
    var time = TimeOfDay.fromDateTime(DateTime.now());
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add event for ${widget.patientName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Event',
                    hintText: 'Appointment, refill pickup, check-in',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: detailsController,
                  decoration: const InputDecoration(labelText: 'Details'),
                  maxLines: 3,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Date'),
                  subtitle: Text(
                    MaterialLocalizations.of(context).formatMediumDate(day),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: day,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null) setDialogState(() => day = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: const Text('Time'),
                  subtitle: Text(time.format(context)),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: time,
                    );
                    if (picked != null) setDialogState(() => time = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                titleController.text.trim().isNotEmpty,
              ),
              child: const Text('Save event'),
            ),
          ],
        ),
      ),
    );
    final title = titleController.text.trim();
    final details = detailsController.text.trim();
    titleController.dispose();
    detailsController.dispose();
    if (saved != true || title.isEmpty) return;

    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    _events.add({
      'patientName': widget.patientName,
      'title': title,
      'details': details,
      'startsAt': at.toIso8601String(),
      'createdBy': Hive.box(
        'profile',
      ).get('accountName', defaultValue: 'Caregiver').toString(),
    });
    if (mounted)
      setState(() => _selectedDay = DateTime(day.year, day.month, day.day));
  }

  Future<void> _deleteEvent(dynamic key) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove event?'),
        content: const Text('This event will be removed from the calendar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove == true) await _events.delete(key);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.patientName} calendar'),
        actions: [
          IconButton(
            tooltip: 'Add calendar event',
            onPressed: _addEvent,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ValueListenableBuilder<Box>(
        valueListenable: _events.listenable(),
        builder: (_, _, _) => _CalendarBody(
          month: _month,
          selectedDay: _selectedDay,
          events: _eventsForPatient(),
          canDelete: true,
          onMonthChanged: (month) => setState(() => _month = month),
          onDaySelected: (day) => setState(() => _selectedDay = day),
          onDelete: _deleteEvent,
        ),
      ),
    );
  }
}

class PatientCalendarScreen extends StatefulWidget {
  const PatientCalendarScreen({super.key});

  @override
  State<PatientCalendarScreen> createState() => _PatientCalendarScreenState();
}

class _PatientCalendarScreenState extends State<PatientCalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final patientName = Hive.box(
      'profile',
    ).get('accountName', defaultValue: '').toString();
    final events = Hive.box('calendar_events');
    return Scaffold(
      appBar: AppBar(title: const Text('My calendar')),
      body: ValueListenableBuilder<Box>(
        valueListenable: events.listenable(),
        builder: (context, box, _) {
          final rows = box
              .toMap()
              .entries
              .where((entry) => entry.value is Map)
              .map(
                (entry) => {
                  ...Map<String, dynamic>.from(entry.value as Map),
                  '_hiveKey': entry.key,
                },
              )
              .where((event) => event['patientName'] == patientName)
              .toList();
          return _CalendarBody(
            month: _month,
            selectedDay: _selectedDay,
            events: rows,
            canDelete: false,
            onMonthChanged: (month) => setState(() => _month = month),
            onDaySelected: (day) => setState(() => _selectedDay = day),
          );
        },
      ),
    );
  }
}

class _CalendarBody extends StatelessWidget {
  const _CalendarBody({
    required this.month,
    required this.selectedDay,
    required this.events,
    required this.canDelete,
    required this.onMonthChanged,
    required this.onDaySelected,
    this.onDelete,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<Map<String, dynamic>> events;
  final bool canDelete;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;
  final Future<void> Function(dynamic key)? onDelete;

  static String _dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month);
    final gridStart = firstDay.subtract(Duration(days: firstDay.weekday % 7));
    final selectedEvents =
        events.where((event) {
          final date = DateTime.tryParse(event['startsAt']?.toString() ?? '');
          return date != null && _dayKey(date) == _dayKey(selectedDay);
        }).toList()..sort(
          (a, b) => (a['startsAt'] ?? '').compareTo(b['startsAt'] ?? ''),
        );
    final loc = MaterialLocalizations.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: () =>
                  onMonthChanged(DateTime(month.year, month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Center(
                child: Text(
                  loc.formatMonthYear(month),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () =>
                  onMonthChanged(DateTime(month.year, month.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: const ['S', 'M', 'T', 'W', 'T', 'F', 'S']
              .map(
                (day) => Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        day,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 42,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.12,
          ),
          itemBuilder: (context, index) {
            final day = gridStart.add(Duration(days: index));
            final key = _dayKey(day);
            final hasEvents = events.any((event) {
              final date = DateTime.tryParse(
                event['startsAt']?.toString() ?? '',
              );
              return date != null && _dayKey(date) == key;
            });
            final isSelected = _dayKey(selectedDay) == key;
            final isCurrentMonth = day.month == month.month;
            return Semantics(
              button: true,
              selected: isSelected,
              label:
                  '${loc.formatMediumDate(day)}${hasEvents ? ', has events' : ''}',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onDaySelected(day),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    border: _dayKey(DateTime.now()) == key
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          color: isCurrentMonth
                              ? null
                              : Theme.of(context).colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.55),
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasEvents
                              ? Theme.of(context).colorScheme.tertiary
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const Divider(height: 28),
        Text(
          loc.formatMediumDate(selectedDay),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (selectedEvents.isEmpty)
          const Text('No calendar events for this day.')
        else
          ...selectedEvents.map((event) {
            final startsAt = DateTime.tryParse(
              event['startsAt']?.toString() ?? '',
            );
            final time = startsAt == null
                ? ''
                : loc.formatTimeOfDay(TimeOfDay.fromDateTime(startsAt));
            final key = event['_hiveKey'];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(event['title']?.toString() ?? 'Event'),
              subtitle: Text(
                [
                  if (time.isNotEmpty) time,
                  if ((event['details'] ?? '').toString().isNotEmpty)
                    event['details'].toString(),
                  if (!canDelete &&
                      (event['createdBy'] ?? '').toString().isNotEmpty)
                    'Added by ${event['createdBy']}',
                ].join(' · '),
              ),
              trailing: canDelete && onDelete != null && key != null
                  ? IconButton(
                      tooltip: 'Remove event',
                      onPressed: () => onDelete!(key),
                      icon: const Icon(Icons.delete_outline),
                    )
                  : null,
            );
          }),
      ],
    );
  }
}
