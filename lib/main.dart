import 'package:flutter/material.dart';
import 'screens/screens.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const OrgaSphereApp());
}

/// Main OrgaSphere application
/// A Flutter app for managing recurring organizational tasks
class OrgaSphereApp extends StatelessWidget {
  const OrgaSphereApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OrgaSphere',
      theme: AppTheme.light,
      // Named routes for navigation
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(
              builder: (_) => const TaskListScreen(),
            );
          case '/task-detail':
            final taskId = settings.arguments as String;
            return MaterialPageRoute(
              builder: (_) => TaskDetailScreen(taskId: taskId),
            );
          case '/create-domain':
            return MaterialPageRoute(
              builder: (_) => const CreateDomainScreen(),
            );
          case '/create-template':
            return MaterialPageRoute(
              builder: (_) => const CreateTemplateScreen(),
            );
          case '/create-instance':
            return MaterialPageRoute(
              builder: (_) => const CreateInstanceScreen(),
            );
          default:
            return MaterialPageRoute(
              builder: (_) => const TaskListScreen(),
            );
        }
      },
      home: const TaskListScreen(),
    );
  }
}
