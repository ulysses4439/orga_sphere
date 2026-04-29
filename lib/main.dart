import 'package:flutter/material.dart';
import 'screens/screens.dart';

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
      theme: ThemeData(
        // Use a clean purple theme
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
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
