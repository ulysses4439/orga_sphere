import 'package:flutter/material.dart';
import '../models/models.dart';
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
    final daysUntilDue = dueDate?.difference(now).inDays;

    final Color urgencyColor;
    if (task.status == TaskStatus.done) {
      urgencyColor = Colors.grey[400]!;
    } else if (dueDate == null) {
      urgencyColor = Colors.grey;
    } else if (dueDate.isBefore(now)) {
      urgencyColor = Colors.red;
    } else if (daysUntilDue != null && daysUntilDue <= 14) {
      urgencyColor = Colors.amber;
    } else {
      urgencyColor = Colors.green;
    }

    final IconData statusIcon;
    final Color statusColor;
    switch (task.status) {
      case TaskStatus.open:
        statusIcon = Icons.radio_button_unchecked;
        statusColor = Colors.grey[600]!;
      case TaskStatus.inProgress:
        statusIcon = Icons.sync;
        statusColor = AppColors.teal;
      case TaskStatus.done:
        statusIcon = Icons.check_circle;
        statusColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: isSelected ? AppColors.navyPale : domainColor,
      shape: isSelected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.navy, width: 2),
            )
          : null,
      child: ListTile(
        onTap: onTap,
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.circle, color: urgencyColor, size: 14),
            const SizedBox(height: 6),
            Icon(statusIcon, color: statusColor, size: 22),
          ],
        ),
        title: Text(task.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Start: ${formatDate(task.startDate)}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            if (dueDate != null)
              Text(
                'Fällig: ${formatDate(dueDate)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: dueDate.isBefore(now) && task.status != TaskStatus.done
                          ? Colors.red
                          : null,
                    ),
              ),
            const SizedBox(height: 4),
            Text(
              task.recurrence.germanLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
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
              Builder(builder: (context) {
                final reminderExpired =
                    task.reminderAt!.isBefore(now) && task.status != TaskStatus.done;
                final reminderColor =
                    reminderExpired ? Colors.red : Colors.grey[600]!;
                return Row(
                  children: [
                    Icon(
                      reminderExpired
                          ? Icons.notifications_active
                          : Icons.notifications_outlined,
                      size: 13,
                      color: reminderColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formatDateTime(task.reminderAt!.toLocal()),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: reminderColor),
                    ),
                  ],
                );
              }),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Chip(
                  label: Text(
                    task.status.germanLabelShort,
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: _statusBackgroundColor(task.status),
                  labelStyle: const TextStyle(color: Colors.white),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
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
