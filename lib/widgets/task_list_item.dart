import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_format.dart';

class TaskListItem extends StatelessWidget {
  final Task task;
  final Color? domainColor;
  final bool isSelected;
  final VoidCallback onTap;

  /// Schlanke Darstellung für Orbits im Einkaufslisten-Modus: nur Kreis und
  /// Name. Keine Ampel, keine Termine, kein Status-Chip – und ein Tippen auf
  /// den Kreis hakt die Position direkt ab, ohne Zwischenschritt.
  final bool simpleList;

  const TaskListItem({
    super.key,
    required this.task,
    this.domainColor,
    this.isSelected = false,
    required this.onTap,
    this.simpleList = false,
  });

  /// Hintergrund der Kachel – die Orbit-Farbe, bei Auswahl das helle Navy.
  Color get _bg =>
      isSelected ? AppColors.navyPale : (domainColor ?? AppColors.appWhite);

  /// Braucht dieser Hintergrund helle Schrift?
  ///
  /// Verglichen werden die Kontrastwerte nach WCAG gegen Weiß und gegen
  /// Schwarz; gewonnen hat, was besser lesbar ist. Ein fester
  /// Helligkeits-Schwellwert taugt dafür nicht – Orange (#FB8C00) etwa wirkt
  /// dunkel, erreicht mit weißer Schrift aber nur 2,4:1 und mit schwarzer
  /// 8,8:1. Umgekehrt braucht Violett (#8E24AA) eindeutig Weiß.
  bool get _darkBg {
    final l = _bg.computeLuminance();
    final withWhite = 1.05 / (l + 0.05);
    final withBlack = (l + 0.05) / 0.05;
    return withWhite > withBlack;
  }

  /// Haupttext (Titel).
  Color get _fg => _darkBg ? Colors.white : AppColors.textBlack;

  /// Nebentext (Datumsangaben, Wiederholung, Zuweisung). Auf hellem Grund
  /// abgeschwächtes Schwarz statt festem Grau – auf kräftigem Blau oder Grün
  /// hätte ein mittleres Grau zu wenig Kontrast.
  Color get _fgMuted => _darkBg
      ? Colors.white70
      : Colors.black.withValues(alpha: 0.72);

  /// Warnfarbe für Überfälliges. Auf dunklem Grund aufgehellt, auf hellem
  /// Grund kräftiger als Standardrot – damit es sich auch von einem orangen
  /// oder grünen Orbit noch abhebt.
  Color get _fgWarn =>
      _darkBg ? const Color(0xFFFFAB91) : const Color(0xFFB71C1C);

  @override
  Widget build(BuildContext context) {
    if (simpleList) return _buildSimpleTile(context);

    final dueDate = task.dueDate;
    final now = DateTime.now();
    final isDone = task.status == TaskStatus.done;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: _bg,
      shape: isSelected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.navy, width: 2),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Oberer Teil: Ampel/Wiederholung links, Inhalt rechts daneben.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Linke Spalte: Ampel (Fälligkeit) oben, darunter Wiederholungs-Icon.
                  Column(
                    children: [
                      _buildAmpel(),
                      if (task.isRecurring) ...[
                        const SizedBox(height: 8),
                        Tooltip(
                          message: 'Wiederholung: ${task.recurrence.germanLabel}',
                          child: Icon(Icons.sync, size: 22, color: _fgMuted),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                task.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: _fg),
                              ),
                            ),
                            Icon(Icons.chevron_right, color: _fgMuted),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Start: ${formatDate(task.startDate)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: _fgMuted)),
                        if (dueDate != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Fällig: ${formatDate(dueDate)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: dueDate.isBefore(now) && !isDone
                                      ? _fgWarn
                                      : _fgMuted,
                                ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          task.recurrence.germanLabel,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: _fgMuted),
                        ),
                        if (task.assignedToLabel != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.person_outline, size: 13, color: _fgMuted),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  task.assignedToLabel!,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: _fgMuted),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (task.reminderAt != null) ...[
                          const SizedBox(height: 4),
                          _buildReminder(context, now),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Status-Zeile: linksbündig unter der Ampel – klickbares Status-Symbol
              // direkt neben dem Status-Chip.
              Row(
                children: [
                  _buildStatusControl(context),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      task.status.germanLabelShort,
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: _statusBackgroundColor(task.status),
                    labelStyle: const TextStyle(color: Colors.white),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  // Anzahl statt geladener Eintraege: Die Liste kennt die
                  // Eintraege selbst nicht mehr – sie kommen erst beim Oeffnen
                  // der Sphere. Der Server liefert die Zahl beim Abgleich mit.
                  if (task.logCount > 0)
                    Text(
                      '${task.logCount} Einträge',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: _fgMuted),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // EINFACHE LISTE (Einkaufslisten-Modus)
  // ──────────────────────────────────────────────

  /// Eine Zeile: Kreis links, Name daneben. Der Kreis steht bewusst oben in
  /// derselben Zeile wie der Name – nicht wie sonst unter dem Inhalt.
  Widget _buildSimpleTile(BuildContext context) {
    final isDone = task.status == TaskStatus.done;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      color: _bg,
      shape: isSelected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.navy, width: 2),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          child: Row(
            children: [
              _buildSimpleStatusControl(context, isDone),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? _fgMuted : _fg,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ein Tippen genügt: offen → erledigt. Erledigte Positionen lassen sich
  /// zurückholen, solange der Server sie nicht nach 24 Stunden entfernt hat.
  Widget _buildSimpleStatusControl(BuildContext context, bool isDone) {
    return Tooltip(
      message: isDone
          ? 'Erledigt – tippen, um die Position zurückzuholen'
          : 'Tippen, um abzuhaken',
      child: InkWell(
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            if (isDone) {
              await TaskService().reopenTask(task.id);
            } else {
              await TaskService().markAsDone(task.id);
            }
          } catch (e) {
            messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
          }
        },
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isDone
                ? (_darkBg ? const Color(0xFFA5D6A7) : Colors.green)
                : _fgMuted,
            size: 26,
          ),
        ),
      ),
    );
  }

  // Ampel = Fälligkeits-Indikator. Gleiche Breite wie die übrigen Symbole (22).
  Widget _buildAmpel() {
    final dueDate = task.dueDate;
    final now = DateTime.now();
    final daysUntilDue = dueDate?.difference(now).inDays;

    final Color color;
    final String tip;
    if (task.status == TaskStatus.done) {
      color = Colors.grey[400]!;
      tip = 'Erledigt';
    } else if (dueDate == null) {
      color = Colors.grey;
      tip = 'Kein Fälligkeitsdatum gesetzt';
    } else if (dueDate.isBefore(now)) {
      color = Colors.red;
      tip = 'Überfällig';
    } else if (daysUntilDue != null && daysUntilDue <= 14) {
      color = Colors.amber;
      tip = 'Bald fällig (innerhalb von 14 Tagen)';
    } else {
      color = Colors.green;
      tip = 'Fällig in mehr als 14 Tagen';
    }

    return Tooltip(
      message: tip,
      child: Icon(Icons.circle, color: color, size: 22),
    );
  }

  // Klickbares Status-Symbol: offen → in Bearbeitung → erledigt.
  Widget _buildStatusControl(BuildContext context) {
    final IconData icon;
    final Color color;
    final String tip;
    final Future<void> Function()? action;

    switch (task.status) {
      case TaskStatus.open:
        icon = Icons.radio_button_unchecked;
        color = Colors.grey[600]!;
        tip = 'Offen – tippen, um auf „In Bearbeitung“ zu setzen';
        action = () => TaskService().startTask(task.id);
      case TaskStatus.inProgress:
        icon = Icons.timelapse;
        color = AppColors.teal;
        tip = 'In Bearbeitung – tippen, um auf „Erledigt“ zu setzen';
        action = () => TaskService().markAsDone(task.id);
      case TaskStatus.done:
        icon = Icons.check_circle;
        color = Colors.green;
        tip = 'Erledigt';
        action = null;
    }

    final iconWidget = Icon(icon, color: color, size: 24);
    if (action == null) {
      return Tooltip(message: tip, child: iconWidget);
    }
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await action!();
          } catch (e) {
            messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: iconWidget,
        ),
      ),
    );
  }

  Widget _buildReminder(BuildContext context, DateTime now) {
    final reminderExpired =
        task.reminderAt!.isBefore(now) && task.status != TaskStatus.done;
    final reminderColor = reminderExpired ? _fgWarn : _fgMuted;
    return Row(
      children: [
        Icon(
          reminderExpired ? Icons.notifications_active : Icons.notifications_outlined,
          size: 13,
          color: reminderColor,
        ),
        const SizedBox(width: 4),
        Text(
          formatDateTime(task.reminderAt!.toLocal()),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: reminderColor),
        ),
      ],
    );
  }

  Color _statusBackgroundColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.open:
        return Colors.grey;
      case TaskStatus.inProgress:
        return AppColors.teal;
      case TaskStatus.done:
        return Colors.green;
    }
  }
}
