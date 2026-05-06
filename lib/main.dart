import 'package:flutter/material.dart';
import 'screens/screens.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const OrgaSphereApp());
}

class OrgaSphereApp extends StatelessWidget {
  const OrgaSphereApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OrgaSphere',
      theme: AppTheme.light,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => const TaskListScreen());
          case '/task-detail':
            final taskId = settings.arguments as String;
            return MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: taskId));
          case '/sphere-list':
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (_) => SphereListScreen(
                orbitId: args['orbitId'] as String?,
                orbitName: args['orbitName'] as String,
              ),
            );
          case '/create-domain':
            return MaterialPageRoute(builder: (_) => const CreateDomainScreen());
          case '/create-task':
            return MaterialPageRoute(builder: (_) => const CreateTaskScreen());
          default:
            return MaterialPageRoute(builder: (_) => const TaskListScreen());
        }
      },
      home: const TaskListScreen(),
    );
  }
}
