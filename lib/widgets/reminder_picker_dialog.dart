import 'package:flutter/material.dart';

/// Auswahl des Erinnerungszeitpunkts über die eingebauten Material-Dialoge.
///
/// Bewusst zwei getrennte Schritte statt eines eigenen Kombi-Dialogs: Der
/// selbstgebaute Dialog war auf Handys zu hoch (Schaltflächen lagen über dem
/// Kalender) und erzwang für die Uhrzeit die Zifferntastatur, die den halben
/// Dialog verdeckte. Die Standard-Dialoge bringen für kleine Bildschirme eine
/// eigene Darstellung mit und lassen die Uhrzeit per Zifferblatt wählen.
///
/// Die Beschriftungen sind deutsch, weil die App fest auf `de_DE` läuft
/// (siehe `localizationsDelegates` in lib/main.dart).

/// Startpunkt für den Kalender – nie vor heute, sonst verweigert
/// [showDatePicker] den Dienst (initialDate muss >= firstDate sein).
DateTime _notBeforeToday(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(value.year, value.month, value.day);
  return day.isBefore(today) ? today : day;
}

/// Fragt Datum und danach Uhrzeit ab. Gibt `null` zurück, sobald einer der
/// beiden Schritte abgebrochen wird.
Future<DateTime?> pickReminderDateTime(
  BuildContext context, {
  DateTime? initial,
}) async {
  final start = initial ?? DateTime.now().add(const Duration(hours: 1));

  final date = await _askDate(context, start);
  if (date == null || !context.mounted) return null;

  final time = await _askTime(context, start);
  if (time == null) return null;

  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Ändert nur den Tag und behält die eingestellte Uhrzeit bei.
Future<DateTime?> pickReminderDate(
  BuildContext context,
  DateTime current,
) async {
  final date = await _askDate(context, current);
  if (date == null) return null;
  return DateTime(
      date.year, date.month, date.day, current.hour, current.minute);
}

/// Ändert nur die Uhrzeit und behält den eingestellten Tag bei.
Future<DateTime?> pickReminderTime(
  BuildContext context,
  DateTime current,
) async {
  final time = await _askTime(context, current);
  if (time == null) return null;
  return DateTime(
      current.year, current.month, current.day, time.hour, time.minute);
}

Future<DateTime?> _askDate(BuildContext context, DateTime start) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: _notBeforeToday(start),
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 5),
    helpText: 'Datum der Erinnerung',
    cancelText: 'Abbrechen',
    confirmText: 'Weiter',
  );
}

Future<TimeOfDay?> _askTime(BuildContext context, DateTime start) {
  return showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: start.hour, minute: start.minute),
    helpText: 'Uhrzeit der Erinnerung',
    cancelText: 'Abbrechen',
    confirmText: 'Speichern',
  );
}
