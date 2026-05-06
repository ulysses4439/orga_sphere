import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';
import '../widgets/reminder_picker_dialog.dart';

class CreateTaskScreen extends StatefulWidget {
  final String? domainId;
  const CreateTaskScreen({super.key, this.domainId});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  late String? _selectedDomainId = widget.domainId;
  DateTime _startDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  DateTime? _reminderAt;
  RecurrenceFrequency _frequency = RecurrenceFrequency.none;
  int _interval = 1;
  bool _saving = false;

  final TaskService _taskService = TaskService();

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _startDate : _dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_dueDate.isBefore(_startDate)) _dueDate = _startDate;
      } else {
        _dueDate = picked;
      }
    });
  }

  Future<void> _pickReminder() async {
    final result = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => ReminderPickerDialog(initialDateTime: _reminderAt),
    );
    if (result == null) return;
    setState(() => _reminderAt = result);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final task = await _taskService.createTask(
        domainId: _selectedDomainId!,
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        startDate: _startDate,
        dueDate: _dueDate,
        recurrence: RecurrencePattern(
          frequency: _frequency,
          interval: _interval,
        ),
      );
      if (_reminderAt != null) {
        await _taskService.setReminder(task.id, _reminderAt);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  String _frequencyLabel(RecurrenceFrequency f) {
    switch (f) {
      case RecurrenceFrequency.none:    return 'Einmalig';
      case RecurrenceFrequency.daily:   return 'Täglich';
      case RecurrenceFrequency.weekly:  return 'Wöchentlich';
      case RecurrenceFrequency.monthly: return 'Monatlich';
      case RecurrenceFrequency.yearly:  return 'Jährlich';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sphere anlegen')),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Titel *',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    autofocus: true,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Titel ist erforderlich' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  _DateTile(
                    label: 'Startdatum',
                    date: _startDate,
                    onTap: () => _pickDate(true),
                  ),
                  const SizedBox(height: 16),
                  _DateTile(
                    label: 'Fälligkeitsdatum *',
                    date: _dueDate,
                    onTap: () => _pickDate(false),
                  ),
                  const SizedBox(height: 16),
                  _ReminderTile(
                    reminderAt: _reminderAt,
                    onTap: _pickReminder,
                    onClear: () => setState(() => _reminderAt = null),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<RecurrenceFrequency>(
                    initialValue: _frequency,
                    decoration: const InputDecoration(
                      labelText: 'Wiederholung',
                      border: OutlineInputBorder(),
                    ),
                    items: RecurrenceFrequency.values
                        .map((f) => DropdownMenuItem(value: f, child: Text(_frequencyLabel(f))))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _frequency = v ?? RecurrenceFrequency.none;
                      if (_frequency == RecurrenceFrequency.none) _interval = 1;
                    }),
                  ),
                  if (_frequency != RecurrenceFrequency.none) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Intervall:'),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: _interval > 1 ? () => setState(() => _interval--) : null,
                        ),
                        Text('$_interval', style: Theme.of(context).textTheme.titleLarge),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setState(() => _interval++),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Speichern'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DateTile({required this.label, required this.date, required this.onTap});

  String get _formatted =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(_formatted),
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  final DateTime? reminderAt;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _ReminderTile({
    required this.reminderAt,
    required this.onTap,
    required this.onClear,
  });

  String _formatted(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
      'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
    ];
    return '${local.day}. ${months[local.month - 1]} ${local.year}, '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} Uhr';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Erinnerung',
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.notifications_outlined),
          suffixIcon: reminderAt != null
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                  tooltip: 'Erinnerung entfernen',
                )
              : null,
        ),
        child: Text(
          reminderAt != null ? _formatted(reminderAt!) : 'Keine Erinnerung',
          style: reminderAt == null
              ? TextStyle(color: Theme.of(context).hintColor)
              : null,
        ),
      ),
    );
  }
}
