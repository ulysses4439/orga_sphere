import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';

class TaskListItem extends StatelessWidget {
  final Task task;
  final String domainName;
  final Color? domainColor;
  final bool isSelected;
  final VoidCallback onTap;

  const TaskListItem({
    super.key,
    required this.task,
    required this.domainName,
    this.domainColor,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dueDate = task.dueDate;
    final now = DateTime.now();
    final daysUntilDue = dueDate.difference(now).inDays;

    final Color urgencyColor;
    if (task.status == TaskStatus.done) {
      urgencyColor = Colors.grey[400]!;
    } else if (dueDate.isBefore(now)) {
      urgencyColor = Colors.red;
    } else if (daysUntilDue <= 14) {
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
            Text('Orbit: $domainName', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              'Fällig: ${dueDate.day}. ${_monthName(dueDate.month)} ${dueDate.year}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              task.recurrence.germanLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
            ),
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

  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
      'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'
    ];
    return months[month - 1];
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
