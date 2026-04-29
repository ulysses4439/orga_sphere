/// Enumeration for task instance status
enum TaskStatus {
  open,      // Not yet started
  inProgress, // In progress
  done;      // Completed

  /// Get a German label for this status
  String get germanLabel {
    switch (this) {
      case TaskStatus.open:
        return 'Offen';
      case TaskStatus.inProgress:
        return 'In Bearbeitung';
      case TaskStatus.done:
        return 'Abgeschlossen';
    }
  }

  /// Get a German label for this status (short version)
  String get germanLabelShort {
    switch (this) {
      case TaskStatus.open:
        return 'Offen';
      case TaskStatus.inProgress:
        return 'In Bearbeitung';
      case TaskStatus.done:
        return 'Fertig';
    }
  }
}
