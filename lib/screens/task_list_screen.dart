import 'dart:async';
import 'package:flutter/material.dart';
import '../app_globals.dart';
import '../models/models.dart';
import '../services/task_service.dart';
import '../services/reminder_service.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../widgets/task_list_item.dart';
import '../widgets/sphere_detail_content.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> with WidgetsBindingObserver {
  final TaskService _taskService = TaskService();
  final ReminderService _reminderService = ReminderService();
  StreamSubscription<ReminderEvent>? _reminderSub;

  String? _selectedOrbitId;
  String? _selectedSphereId;

  static const double _desktopBreakpoint = 800;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _taskService.ready.then((_) {
      if (!mounted) return;
      // Subscribe BEFORE start() so we don't miss the initial check event.
      _reminderSub = _reminderService.onReminderDue.listen(_onReminderDue);
      _reminderService.start();
      // Auto-select first orbit (no "Alle Spheres" anymore).
      final domains = _taskService.getDomains();
      if (domains.isNotEmpty) _selectedOrbitId = domains.first.id;
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminderSub?.cancel();
    _reminderService.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Feuert auf Mobile wenn App in Vordergrund kommt;
    // auf Web zusätzlich wenn Tab wieder fokussiert wird.
    if (state == AppLifecycleState.resumed) {
      _reminderService.checkNow();
      if (mounted) setState(() {});
    }
  }

  bool get _isDesktop => MediaQuery.of(context).size.width >= _desktopBreakpoint;

  List<Task> _filtered(List<Task> tasks) {
    if (_selectedOrbitId == null) return tasks;
    return tasks.where((t) => t.domainId == _selectedOrbitId).toList();
  }

  // ──────────────────────────────────────────────
  // REMINDER LOGIC
  // ──────────────────────────────────────────────

  void _onReminderDue(ReminderEvent event) {
    _reminderService.markShown(event.task.id);
    SoundService.playChime();
    _showReminderDialog(event.task); // navigatorKey – independent of mount state
    if (mounted) setState(() {}); // rebuild sidebar
  }

  void _showReminderDialog(Task task) {
    // navigatorKey.currentContext is the Navigator's OWN context – Navigator.of()
    // would look for a Navigator ABOVE it and find none → silent failure.
    // overlay.context is a descendant of the Navigator, so Navigator.of() works.
    final ctx = navigatorKey.currentState?.overlay?.context;
    if (ctx == null) return;

    final domain = _taskService.getDomainById(task.domainId);
    final reminderStr = task.reminderAt != null
        ? _formatDateTime(task.reminderAt!.toLocal())
        : '';

    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active, color: AppColors.teal, size: 32),
        title: const Text('Erinnerung'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (domain != null)
              Text('Orbit: ${domain.name}',
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(reminderStr,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[600])),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Schließen'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _taskService.setReminder(task.id, null);
              if (mounted) setState(() {});
            },
            child: const Text('Erinnerung löschen'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _taskService.setReminder(task.id, null);
              if (mounted) setState(() => _selectedSphereId = task.id);
            },
            child: const Text('Sphere öffnen'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime d) =>
      '${d.day}. ${_monthName(d.month)} ${d.year}, '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} Uhr';

  String _monthName(int m) => [
        'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
        'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'
      ][m - 1];

  // ──────────────────────────────────────────────
  // DESKTOP
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _isDesktop ? _buildDesktopLayout() : _buildMobileLayout();
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        centerTitle: true,
        title: Image.asset('assets/images/logo_full.png', height: 52, fit: BoxFit.contain),
      ),
      body: FutureBuilder<void>(
        future: _taskService.ready,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _buildErrorView(snapshot.error);
          return Row(
            children: [
              _buildOrbitSidebar(),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(child: _buildDesktopSpherePanel()),
              if (_selectedSphereId != null) ...[
                const VerticalDivider(width: 1, thickness: 1),
                SizedBox(
                  width: 420,
                  child: SphereDetailContent(
                    key: ValueKey(_selectedSphereId),
                    taskId: _selectedSphereId!,
                    onDeleted: () => setState(() => _selectedSphereId = null),
                    onClose: () => setState(() => _selectedSphereId = null),
                    onChanged: () => setState(() {}),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildOrbitSidebar() {
    final domains = _taskService.getDomains();
    final missed = _reminderService.getMissedReminders();

    return Container(
      width: 240,
      color: Colors.black,
      child: Theme(
        data: Theme.of(context).copyWith(
          listTileTheme: const ListTileThemeData(
            textColor: Colors.white,
            iconColor: Colors.white70,
            selectedColor: Colors.white,
            selectedTileColor: Color(0xFF1C1C2E),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                'Orbits',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: domains.length,
                      itemBuilder: (_, i) {
                        final d = domains[i];
                        return _buildOrbitTile(d.id, d.name, d.color);
                      },
                    ),
                  ),
                  if (missed.isNotEmpty) _buildMissedRemindersSection(missed),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Neuer Orbit'),
              onTap: () async {
                await Navigator.of(context).pushNamed('/create-domain');
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissedRemindersSection(List<Task> missed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.notifications_active, size: 16, color: Colors.orange),
              const SizedBox(width: 6),
              Text(
                'Verpasst (${missed.length})',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
        ...missed.map((task) => _buildMissedReminderTile(task)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildMissedReminderTile(Task task) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: const Icon(Icons.notifications_none, size: 18, color: Colors.orange),
      title: Text(
        task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white),
      ),
      subtitle: Text(
        _formatDateTime(task.reminderAt!.toLocal()),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        tooltip: 'Erinnerung löschen',
        onPressed: () async {
          _reminderService.markShown(task.id);
          await _taskService.setReminder(task.id, null);
          if (mounted) setState(() {});
        },
      ),
      onTap: () async {
        _reminderService.markShown(task.id);
        await _taskService.setReminder(task.id, null);
        if (mounted) {
          setState(() {
            _selectedOrbitId = task.domainId;
            _selectedSphereId = task.id;
          });
        }
      },
    );
  }

  Widget _buildOrbitTile(String? id, String name, Color? color) {
    final isSelected = _selectedOrbitId == id;
    return ListTile(
      selected: isSelected,
      selectedTileColor: const Color(0xFF1C1C2E),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: color != null
          ? Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            )
          : const SizedBox(width: 12),
      title: Text(
        name,
        style: TextStyle(
          color: Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: () => setState(() {
        _selectedOrbitId = id;
        _selectedSphereId = null;
      }),
    );
  }

  Widget _buildDesktopSpherePanel() {
    if (_selectedOrbitId == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey[700]),
              const SizedBox(height: 16),
              Text(
                'Orbit auswählen',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    final selectedOrbitName =
        _taskService.getDomainById(_selectedOrbitId!)?.name ?? 'Orbit';

    return Container(
      color: Colors.black,
      child: Theme(
        data: Theme.of(context).copyWith(
          tabBarTheme: const TabBarThemeData(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: AppColors.teal,
            dividerColor: Colors.transparent,
          ),
        ),
        child: DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  selectedOrbitName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: Colors.white),
                ),
              ),
              const TabBar(tabs: [Tab(text: 'Im Flug'), Tab(text: 'Gelandet')]),
              Expanded(
                child: TabBarView(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          child: _buildDesktopSphereList(
                            _filtered(_taskService.getActiveTasks()),
                            'Keine aktiven Spheres vorhanden',
                          ),
                        ),
                        const Divider(height: 1),
                        _buildNewSphereButton(),
                      ],
                    ),
                    _buildDesktopSphereList(
                      _filtered(_taskService.getArchivedTasks()),
                      'Keine gelandeten Spheres vorhanden',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewSphereButton() {
    final orbitColor = _selectedOrbitId != null
        ? _taskService.getDomainById(_selectedOrbitId!)?.color
        : null;
    return InkWell(
      onTap: () async {
        await Navigator.of(context).pushNamed(
          '/create-task',
          arguments: _selectedOrbitId,
        );
        if (mounted) setState(() {});
      },
      child: Container(
        color: orbitColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.add, size: 20, color: AppColors.teal),
            const SizedBox(width: 12),
            Text(
              'Neue Sphere hinzufügen',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.teal),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopSphereList(List<Task> tasks, String emptyMessage) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_alt, size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        final domain = _taskService.getDomainById(task.domainId);
        return TaskListItem(
          task: task,
          domainName: domain?.name ?? 'Allgemein',
          domainColor: domain?.color,
          isSelected: task.id == _selectedSphereId,
          onTap: () => setState(() => _selectedSphereId = task.id),
        );
      },
    );
  }

  // ──────────────────────────────────────────────
  // MOBILE
  // ──────────────────────────────────────────────

  Widget _buildMobileLayout() {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        centerTitle: true,
        title: Image.asset('assets/images/logo_full.png', height: 52, fit: BoxFit.contain),
      ),
      body: FutureBuilder<void>(
        future: _taskService.ready,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _buildErrorView(snapshot.error);
          return _buildMobileOrbitList();
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).pushNamed('/create-domain');
          if (mounted) setState(() {});
        },
        tooltip: 'Neuer Orbit',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMobileOrbitList() {
    final domains = _taskService.getDomains();
    final missed = _reminderService.getMissedReminders();

    return ListView(
      children: [
        if (missed.isNotEmpty) _buildMobileMissedBanner(missed),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            'Orbits',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
          ),
        ),
        ...domains.map(
          (d) => ListTile(
            leading: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(color: d.color, shape: BoxShape.circle),
            ),
            title: Text(d.name),
            subtitle: d.description.isNotEmpty ? Text(d.description) : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pushSphereList(d.id, d.name),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileMissedBanner(List<Task> missed) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        border: Border.all(color: Colors.orange),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Verpasste Erinnerungen (${missed.length})',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.orange[800],
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          ...missed.map(
            (task) => ListTile(
              dense: true,
              leading: const Icon(Icons.notifications_none, size: 18, color: Colors.orange),
              title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_formatDateTime(task.reminderAt!.toLocal())),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () async {
                  _reminderService.markShown(task.id);
                  await _taskService.setReminder(task.id, null);
                  if (mounted) setState(() {});
                },
              ),
              onTap: () async {
                _reminderService.markShown(task.id);
                await _taskService.setReminder(task.id, null);
                if (mounted) {
                  final domain = _taskService.getDomainById(task.domainId);
                  _pushSphereList(task.domainId, domain?.name ?? 'Orbit');
                }
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Future<void> _pushSphereList(String? orbitId, String orbitName) async {
    await Navigator.of(context).pushNamed(
      '/sphere-list',
      arguments: {'orbitId': orbitId, 'orbitName': orbitName},
    );
    if (mounted) setState(() {});
  }

  // ──────────────────────────────────────────────
  // SHARED
  // ──────────────────────────────────────────────

  Widget _buildErrorView(Object? error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('Verbindungsfehler', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('$error',
              style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }

}
