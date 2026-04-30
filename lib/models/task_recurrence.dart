/// Supported recurrence frequencies for tasks.
enum RecurrenceFrequency {
  none,
  daily,
  weekly,
  monthly,
  yearly,
}

/// Pattern representing a task recurrence interval.
class RecurrencePattern {
  final RecurrenceFrequency frequency;
  final int interval;

  const RecurrencePattern({
    required this.frequency,
    this.interval = 1,
  }) : assert(interval >= 1, 'Interval must be at least 1');

  bool get isRecurring => frequency != RecurrenceFrequency.none;

  String get germanLabel {
    switch (frequency) {
      case RecurrenceFrequency.none:
        return 'Einmalig';
      case RecurrenceFrequency.daily:
        return interval == 1 ? 'Täglich' : 'Alle $interval Tage';
      case RecurrenceFrequency.weekly:
        return interval == 1 ? 'Wöchentlich' : 'Alle $interval Wochen';
      case RecurrenceFrequency.monthly:
        return interval == 1 ? 'Monatlich' : 'Alle $interval Monate';
      case RecurrenceFrequency.yearly:
        return interval == 1 ? 'Jährlich' : 'Alle $interval Jahre';
    }
  }

  /// Compute the next DateTime based on this recurrence pattern.
  DateTime nextDate(DateTime current) {
    switch (frequency) {
      case RecurrenceFrequency.none:
        return current;
      case RecurrenceFrequency.daily:
        return current.add(Duration(days: interval));
      case RecurrenceFrequency.weekly:
        return current.add(Duration(days: 7 * interval));
      case RecurrenceFrequency.monthly:
        return DateTime(current.year, current.month + interval, current.day);
      case RecurrenceFrequency.yearly:
        return DateTime(current.year + interval, current.month, current.day);
    }
  }
}
