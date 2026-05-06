import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Combined date + time picker dialog for setting a reminder.
/// Returns a [DateTime] in local time, or null if cancelled.
class ReminderPickerDialog extends StatefulWidget {
  final DateTime? initialDateTime;
  const ReminderPickerDialog({super.key, this.initialDateTime});

  @override
  State<ReminderPickerDialog> createState() => _ReminderPickerDialogState();
}

class _ReminderPickerDialogState extends State<ReminderPickerDialog> {
  late DateTime _selectedDate;
  late final TextEditingController _hourCtrl;
  late final TextEditingController _minCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final initial = widget.initialDateTime ?? now;
    _selectedDate = initial.isBefore(now)
        ? DateTime(now.year, now.month, now.day)
        : DateTime(initial.year, initial.month, initial.day);
    _hourCtrl = TextEditingController(
        text: initial.hour.toString().padLeft(2, '0'));
    _minCtrl = TextEditingController(
        text: initial.minute.toString().padLeft(2, '0'));
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  int get _hour => int.tryParse(_hourCtrl.text) ?? -1;
  int get _minute => int.tryParse(_minCtrl.text) ?? -1;
  bool get _valid => _hour >= 0 && _hour <= 23 && _minute >= 0 && _minute <= 59;

  void _confirm() {
    if (!_valid) return;
    Navigator.pop(
      context,
      DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day,
          _hour, _minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return AlertDialog(
      title: const Text('Erinnerung setzen'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CalendarDatePicker(
              initialDate: _selectedDate,
              firstDate: DateTime(now.year, now.month, now.day),
              lastDate: DateTime(now.year + 5),
              onDateChanged: (d) => setState(() => _selectedDate = d),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Uhrzeit',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(width: 16),
                  _TimeField(
                      controller: _hourCtrl,
                      hint: 'hh',
                      max: 23,
                      onChanged: (_) => setState(() {})),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(':',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  _TimeField(
                      controller: _minCtrl,
                      hint: 'mm',
                      max: 59,
                      onChanged: (_) => setState(() {})),
                  const SizedBox(width: 8),
                  const Text('Uhr'),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _valid ? _confirm : null,
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int max;
  final ValueChanged<String> onChanged;

  const _TimeField({
    required this.controller,
    required this.hint,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 2,
        onChanged: onChanged,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
