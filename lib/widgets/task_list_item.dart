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

  const TaskListItem({
    super.key,
    required this.task,
    this.domainColor,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dueDate = task.dueDate;
    final now = DateTime.now();
    final isDone = task.status == TaskStatus.done;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: isSelected ? AppColors.navyPale : domainColor,
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
                          child: Icon(Icons.sync, size: 22, color: Colors.grey[700]),
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
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Icon(Icons.chevron_right, color: Colors.grey[600]),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Start: ${formatDate(task.startDate)}',
                            style: Theme.of(context).textTheme.bodySmall),
                        if (dueDate != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Fällig: ${formatDate(dueDate)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: dueDate.isBefore(now) && !isDone
                                      ? Colors.red
                                      : null,
                                ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          task.recurrence.germanLabel,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[700]),
                        ),
                        if (task.assignedToLabel != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.person_outline, size: 13, color: Colors.grey[700]),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  task.assignedToLabel!,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey[700]),
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
                  if (task.logEntries.isNotEmpty)
                    Text(
                      '${task.logEntries.length} Einträge',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                ],
              ),
            ],
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
    final reminderColor = reminderExpired ? Colors.red : Colors.grey[600]!;
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
