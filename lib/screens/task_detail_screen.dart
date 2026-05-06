import 'package:flutter/material.dart';
import '../widgets/sphere_detail_content.dart';

class TaskDetailScreen extends StatelessWidget {
  final String taskId;

  const TaskDetailScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sphere')),
      body: SphereDetailContent(
        taskId: taskId,
        onDeleted: () => Navigator.of(context).pop(),
      ),
    );
  }
}
