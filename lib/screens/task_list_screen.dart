import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';
import '../services/reminder_service.dart';
import '../theme/app_colors.dart';
import '../widgets/task_list_item.dart';
import '../widgets/sphere_detail_content.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final TaskService _taskService = TaskService();
  final ReminderService _reminderService = ReminderService();
  StreamSubscription<ReminderEvent>? _reminderSub;

  String? _selectedOrbitId;
  String? _selectedSphereId;

  static const double _desktopBreakpoint = 800;

  @override
  void initState() {
    super.initState();
    _taskService.ready.then((_) {
      if (!mounted) return;
      _reminderService.start();
      _reminderSub = _reminderService.onReminderDue.listen(_onReminderDue);
      // Show missed reminders after short delay so UI is fully built
      Future.delayed(const Duration(seconds: 2), _checkMissedReminders);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _reminderSub?.cancel();
    _reminderService.stop();
    super.dispose();
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
    if (mounted) _showReminderDialog(event.task);
  }

  void _checkMissedReminders() {
    final missed = _reminderService.getMissedReminders();
    if (missed.isNotEmpty && mounted) setState(() {});
  }

  void _showReminderDialog(Task task) {
    final domain = _taskService.getDomainById(task.domainId);
    final reminderStr = task.reminderAt != null
        ? _formatDateTime(task.reminderAt!.toLocal())
        : '';

    showDialog<void>(
      context: context,
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
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _selectedSphereId = task.id);
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
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Neu erstellen',
            onPressed: _showCreateMenu,
          ),
        ],
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

    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          _buildOrbitTile(null, 'Alle Spheres', null),
          const Divider(height: 8, indent: 16, endIndent: 16),
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
        style: Theme.of(context).textTheme.bodySmall,
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
      onTap: () {
        _reminderService.markShown(task.id);
        setState(() => _selectedSphereId = task.id);
      },
    );
  }

  Widget _buildOrbitTile(String? id, String name, Color? color) {
    final isSelected = _selectedOrbitId == id;
    return ListTile(
      selected: isSelected,
      selectedTileColor: AppColors.navyPale,
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
        style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
      ),
      onTap: () => setState(() {
        _selectedOrbitId = id;
        _selectedSphereId = null;
      }),
    );
  }

  Widget _buildDesktopSpherePanel() {
    final selectedOrbitName = _selectedOrbitId != null
        ? (_taskService.getDomainById(_selectedOrbitId!)?.name ?? 'Orbit')
        : 'Alle Spheres';

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(selectedOrbitName, style: Theme.of(context).textTheme.titleLarge),
          ),
          const TabBar(tabs: [Tab(text: 'Aktiv'), Tab(text: 'Archiv')]),
          Expanded(
            child: TabBarView(
              children: [
                _buildDesktopSphereList(
                  _filtered(_taskService.getActiveTasks()),
                  'Keine aktiven Spheres vorhanden',
                ),
                _buildDesktopSphereList(
                  _filtered(_taskService.getArchivedTasks()),
                  'Keine archivierten Spheres vorhanden',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSphereList(List<Task> tasks, String emptyMessage) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_alt, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(emptyMessage, style: Theme.of(context).textTheme.titleLarge),
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
        onPressed: _showCreateMenu,
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
        ListTile(
          leading: const Icon(Icons.all_inclusive),
          title: const Text('Alle Spheres'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pushSphereList(null, 'Alle Spheres'),
        ),
        const Divider(indent: 16, endIndent: 16),
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
              onTap: () {
                _reminderService.markShown(task.id);
                final domain = _taskService.getDomainById(task.domainId);
                _pushSphereList(task.domainId, domain?.name ?? 'Orbit');
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

  void _showCreateMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Orbit anlegen'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await Navigator.of(context).pushNamed('/create-domain');
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_task),
              title: const Text('Sphere anlegen'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await Navigator.of(context).pushNamed('/create-task');
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}
