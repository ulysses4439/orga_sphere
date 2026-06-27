import 'package:flutter/material.dart';
import 'app_globals.dart';
import 'screens/screens.dart';
import 'services/auth_service.dart';
import 'services/event_poll_service.dart';
import 'services/notification_center.dart';
import 'services/push_service.dart';
import 'services/task_service.dart';
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
      navigatorKey: navigatorKey,
      theme: AppTheme.light,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/task-detail':
            final taskId = settings.arguments as String;
            return MaterialPageRoute(
                builder: (_) => TaskDetailScreen(taskId: taskId));
          case '/sphere-list':
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (_) => SphereListScreen(
                orbitId: args['orbitId'] as String?,
                orbitName: args['orbitName'] as String,
              ),
            );
          case '/create-domain':
            return MaterialPageRoute(
                builder: (_) => const CreateDomainScreen());
          case '/create-task':
            return MaterialPageRoute(
              builder: (_) =>
                  CreateTaskScreen(domainId: settings.arguments as String?),
            );
          default:
            return null;
        }
      },
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _loggedIn;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await AuthService.init();
    if (AuthService.isLoggedIn) _startNotifications();
    if (mounted) setState(() => _loggedIn = AuthService.isLoggedIn);
  }

  void _onLogin() {
    _startNotifications();
    setState(() => _loggedIn = true);
  }

  // Push-Registrierung (FCM) + ersten Event-Poll anstoßen.
  void _startNotifications() {
    PushService().init();
    EventPollService().poll();
  }

  Future<void> _onLogout() async {
    await PushService().unregister();
    EventPollService().reset();
    NotificationCenter().clear();
    TaskService.reset();
    if (mounted) setState(() => _loggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_loggedIn!) {
      return LoginScreen(onSuccess: _onLogin);
    }
    return TaskListScreen(onLogout: _onLogout);
  }
}
