import 'dart:async';
import 'package:flutter/material.dart';
import '../app_globals.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/task_service.dart';
import '../services/reminder_service.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../widgets/task_list_item.dart';
import '../widgets/sphere_detail_content.dart';
import '../widgets/reminder_picker_dialog.dart';
import 'settings_screen.dart';

class TaskListScreen extends StatefulWidget {
  final VoidCallback? onLogout;
  const TaskListScreen({super.key, this.onLogout});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final TaskService _taskService = TaskService();
  final ReminderService _reminderService = ReminderService();
  StreamSubscription<ReminderEvent>? _reminderSub;
  late final TabController _tabController;

  String? _selectedOrbitId;
  String? _selectedSphereId;

  static const double _desktopBreakpoint = 800;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    _tabController.dispose();
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.black, height: 1),
        ),
      ),
      body: FutureBuilder<void>(
        future: _taskService.ready,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _buildErrorView(snapshot.error);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    onMarkedDone: () => setState(() {
                      _tabController.animateTo(0);
                      _selectedSphereId = null;
                    }),
                    onReopened: () => setState(() {
                      _tabController.animateTo(0);
                    }),
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
            _UserHeader(onLogout: widget.onLogout),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                    child: ListView.separated(
                      itemCount: domains.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.grey[800],
                      ),
                      itemBuilder: (_, i) {
                        final d = domains[i];
                        return _buildOrbitTile(d);
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
      onTap: () {
        _reminderService.markShown(task.id);
        if (mounted) {
          setState(() {
            _selectedOrbitId = task.domainId;
            _selectedSphereId = task.id;
          });
        }
      },
    );
  }

  Widget _buildOrbitTile(TaskDomain domain) {
    final now = DateTime.now();
    final orbitTasks = _taskService
        .getTasks()
        .where((t) => t.domainId == domain.id && t.status != TaskStatus.done)
        .toList();
    return _OrbitTile(
      domain: domain,
      isSelected: _selectedOrbitId == domain.id,
      activeCount: orbitTasks.length,
      hasOverdue: orbitTasks.any((t) => t.dueDate != null && t.dueDate!.isBefore(now)),
      hasExpiredReminder: orbitTasks.any(
          (t) => t.reminderAt != null && t.reminderAt!.isBefore(now)),
      onSelect: () => setState(() {
        _selectedOrbitId = domain.id;
        _selectedSphereId = null;
        _tabController.animateTo(0);
      }),
      onDrop: (task) async {
        await _taskService.moveTask(task.id, domain.id);
        if (mounted) setState(() {});
      },
      onRename: () => _showRenameOrbitDialog(domain),
      onDelete: () => _showDeleteOrbitDialog(domain),
      onInviteCoPilot: () => _showInviteCoPilotDialog(domain),
    );
  }

  Future<void> _showRenameOrbitDialog(TaskDomain domain) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _OrbitRenameDialog(initialName: domain.name),
    );
    if (result == null || result.isEmpty || !mounted) return;
    try {
      await _taskService.renameDomain(domain.id, result);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _showInviteCoPilotDialog(TaskDomain domain) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Co-Pilot einladen – ${domain.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'E-Mail-Adresse',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person_add_outlined),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Einladen'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty || !mounted) return;
    try {
      final status = await ApiService.inviteCoPilot(domain.id, result);
      if (mounted) {
        final msg = status == 'invited'
            ? 'Einladung an $result gesendet'
            : '$result wurde als Co-Pilot hinzugefügt';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _showDeleteOrbitDialog(TaskDomain domain) async {
    final sphereCount =
        _taskService.getTasks().where((t) => t.domainId == domain.id).length;

    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Orbit "${domain.name}" löschen?'),
        content: Text(
          sphereCount > 0
              ? 'Dieser Orbit enthält $sphereCount Sphere${sphereCount == 1 ? '' : 's'}. '
                  'Alle Spheres werden unwiderruflich gelöscht.'
              : 'Der leere Orbit wird gelöscht.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wirklich endgültig löschen?'),
        content: const Text(
            'Diese Aktion kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Endgültig löschen'),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;

    try {
      await _taskService.deleteDomain(domain.id);
      if (mounted) {
        setState(() {
          if (_selectedOrbitId == domain.id) {
            final remaining = _taskService.getDomains();
            _selectedOrbitId =
                remaining.isNotEmpty ? remaining.first.id : null;
          }
          _selectedSphereId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
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

    final selectedOrbit = _taskService.getDomainById(_selectedOrbitId!);
    final selectedOrbitName = selectedOrbit?.name ?? 'Orbit';
    final selectedOrbitDescription = selectedOrbit?.description ?? '';

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
              if (selectedOrbitDescription.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    selectedOrbitDescription,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ColoredBox(
                color: const Color(0xFF2D2D2D),
                child: TabBar(controller: _tabController, tabs: const [Tab(text: 'Im Flug'), Tab(text: 'Gelandet')]),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
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
                        if (_selectedOrbitId != null)
                          _OrbitMembersBar(
                            key: ValueKey('members_$_selectedOrbitId'),
                            orbitId: _selectedOrbitId!,
                            onInvite: () => _showInviteCoPilotDialog(
                              _taskService.getDomainById(_selectedOrbitId!)!,
                            ),
                          ),
                        const Divider(height: 1),
                        _InlineSphereCreator(
                          orbitId: _selectedOrbitId,
                          orbitColor: _selectedOrbitId != null
                              ? _taskService.getDomainById(_selectedOrbitId!)?.color
                              : null,
                          onCreated: () => setState(() {}),
                        ),
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
        final card = TaskListItem(
          task: task,
          domainName: domain?.name ?? 'Allgemein',
          domainColor: domain?.color,
          isSelected: task.id == _selectedSphereId,
          onTap: () => setState(() => _selectedSphereId = task.id),
        );
        return Draggable<Task>(
          data: task,
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 220,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: domain?.color ?? Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                task.title,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: card),
          child: card,
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
              onTap: () {
                _reminderService.markShown(task.id);
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

// ─────────────────────────────────────────────────────────────────────────────

class _InlineSphereCreator extends StatefulWidget {
  final String? orbitId;
  final Color? orbitColor;
  final VoidCallback onCreated;

  const _InlineSphereCreator({
    required this.orbitId,
    required this.orbitColor,
    required this.onCreated,
  });

  @override
  State<_InlineSphereCreator> createState() => _InlineSphereCreatorState();
}

class _InlineSphereCreatorState extends State<_InlineSphereCreator> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _active = false;
  DateTime? _startDate;
  DateTime? _dueDate;
  DateTime? _reminderAt;
  RecurrenceFrequency _frequency = RecurrenceFrequency.none;

  final _taskService = TaskService();

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _active = v.trim().isNotEmpty);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickReminder() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => ReminderPickerDialog(initialDateTime: _reminderAt),
    );
    if (picked != null) setState(() => _reminderAt = picked);
  }

  Future<void> _pickRecurrence() async {
    final picked = await showDialog<RecurrenceFrequency>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Wiederholung'),
        children: RecurrenceFrequency.values.map((f) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, f),
            child: Text(_frequencyLabel(f)),
          );
        }).toList(),
      ),
    );
    if (picked != null) setState(() => _frequency = picked);
  }

  String _frequencyLabel(RecurrenceFrequency f) {
    switch (f) {
      case RecurrenceFrequency.none: return 'Einmalig';
      case RecurrenceFrequency.daily: return 'Täglich';
      case RecurrenceFrequency.weekly: return 'Wöchentlich';
      case RecurrenceFrequency.monthly: return 'Monatlich';
      case RecurrenceFrequency.yearly: return 'Jährlich';
    }
  }

  String _startDateLabel() {
    if (_startDate == null) return 'Startdatum';
    const months = ['Jan','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'];
    return '${_startDate!.day}. ${months[_startDate!.month - 1]}';
  }

  String _dueDateLabel() {
    if (_dueDate == null) return 'Fällig';
    const months = ['Jan','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'];
    return '${_dueDate!.day}. ${months[_dueDate!.month - 1]}';
  }

  Future<void> _submit() async {
    final title = _ctrl.text.trim();
    if (title.isEmpty || widget.orbitId == null) return;
    try {
      final task = await _taskService.createTask(
        domainId: widget.orbitId!,
        title: title,
        description: '',
        startDate: _startDate ?? DateTime.now(),
        dueDate: _dueDate,
        recurrence: RecurrencePattern(frequency: _frequency, interval: 1),
      );
      if (_reminderAt != null) {
        await _taskService.setReminder(task.id, _reminderAt);
      }
      _ctrl.clear();
      setState(() {
        _active = false;
        _startDate = null;
        _dueDate = null;
        _reminderAt = null;
        _frequency = RecurrenceFrequency.none;
      });
      widget.onCreated();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.orbitColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.add, size: 20, color: AppColors.teal),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              style: const TextStyle(color: Colors.black87, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Aufgabe hinzufügen',
                hintStyle: TextStyle(
                  color: Colors.black45,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: _onChanged,
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (_active) ...[
            const SizedBox(width: 8),
            _IconChip(
              icon: Icons.play_arrow_outlined,
              label: _startDateLabel(),
              active: _startDate != null,
              onTap: _pickStartDate,
            ),
            const SizedBox(width: 4),
            _IconChip(
              icon: Icons.calendar_today,
              label: _dueDateLabel(),
              active: _dueDate != null,
              onTap: _pickDueDate,
            ),
            const SizedBox(width: 4),
            _IconChip(
              icon: _reminderAt != null ? Icons.notifications_active : Icons.notifications_outlined,
              label: _reminderAt != null ? 'Erinnerung' : 'Erinnern',
              active: _reminderAt != null,
              onTap: _pickReminder,
            ),
            const SizedBox(width: 4),
            _IconChip(
              icon: Icons.repeat,
              label: _frequency == RecurrenceFrequency.none ? 'Einmalig' : _frequencyLabel(_frequency),
              active: _frequency != RecurrenceFrequency.none,
              onTap: _pickRecurrence,
            ),
          ],
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _IconChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.teal : const Color(0xFF424242);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _OrbitRenameDialog extends StatefulWidget {
  final String initialName;
  const _OrbitRenameDialog({required this.initialName});

  @override
  State<_OrbitRenameDialog> createState() => _OrbitRenameDialogState();
}

class _OrbitRenameDialogState extends State<_OrbitRenameDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isNotEmpty) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Orbit umbenennen'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen')),
        FilledButton(onPressed: _submit, child: const Text('Speichern')),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Orbit tile with reliable drag-hover detection via onMove / onLeave
// ─────────────────────────────────────────────────────────────────────────────

class _OrbitTile extends StatefulWidget {
  final TaskDomain domain;
  final bool isSelected;
  final int activeCount;
  final bool hasOverdue;
  final bool hasExpiredReminder;
  final VoidCallback onSelect;
  final Future<void> Function(Task) onDrop;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onInviteCoPilot;

  const _OrbitTile({
    required this.domain,
    required this.isSelected,
    required this.activeCount,
    required this.hasOverdue,
    required this.hasExpiredReminder,
    required this.onSelect,
    required this.onDrop,
    required this.onRename,
    required this.onDelete,
    required this.onInviteCoPilot,
  });

  @override
  State<_OrbitTile> createState() => _OrbitTileState();
}

class _OrbitTileState extends State<_OrbitTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => d.data.domainId != widget.domain.id,
      onAcceptWithDetails: (d) {
        setState(() => _hovering = false);
        widget.onDrop(d.data);
      },
      onMove: (_) { if (!_hovering) setState(() => _hovering = true); },
      onLeave: (_) { if (_hovering) setState(() => _hovering = false); },
      builder: (context, candidates, _) {
        final highlight = _hovering || candidates.isNotEmpty;
        return Container(
          color: highlight
              ? AppColors.teal.withValues(alpha: 0.55)
              : widget.isSelected
                  ? const Color(0xFF1C1C2E)
                  : Colors.transparent,
          child: ListTile(
            contentPadding: const EdgeInsets.only(left: 16, right: 4),
            leading: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: widget.domain.color, shape: BoxShape.circle),
            ),
            title: Text(
              widget.domain.name,
              style: TextStyle(
                color: Colors.white,
                fontWeight:
                    widget.isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.hasExpiredReminder)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.notifications_active,
                        color: Colors.red, size: 14),
                  ),
                if (widget.hasOverdue)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.error_outline,
                        color: Colors.red, size: 14),
                  ),
                if (widget.activeCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${widget.activeCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      color: Colors.white38, size: 18),
                  padding: EdgeInsets.zero,
                  color: const Color(0xFF1C1C2E),
                  onSelected: (action) {
                    if (action == 'rename') widget.onRename();
                    if (action == 'delete') widget.onDelete();
                    if (action == 'invite') widget.onInviteCoPilot();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'invite',
                      child: Row(children: [
                        Icon(Icons.person_add_outlined, color: Colors.white70, size: 18),
                        SizedBox(width: 8),
                        Text('Co-Pilot einladen', style: TextStyle(color: Colors.white)),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'rename',
                      child: Text('Umbenennen',
                          style: TextStyle(color: Colors.white)),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Löschen',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
            onTap: widget.onSelect,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Teilnehmerliste eines Orbits (Pilot + Co-Piloten)
// ─────────────────────────────────────────────────────────────────────────────

class _OrbitMembersBar extends StatefulWidget {
  final String orbitId;
  final VoidCallback onInvite;

  const _OrbitMembersBar({
    super.key,
    required this.orbitId,
    required this.onInvite,
  });

  @override
  State<_OrbitMembersBar> createState() => _OrbitMembersBarState();
}

class _OrbitMembersBarState extends State<_OrbitMembersBar> {
  late Future<List<OrbitMember>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getOrbitMembers(widget.orbitId);
  }

  void _reload() {
    setState(() {
      _future = ApiService.getOrbitMembers(widget.orbitId);
    });
  }

  bool _isPilot(List<OrbitMember> members) => members.any(
      (m) => m.email == AuthService.email && m.isPilot);

  Future<void> _manageMember(OrbitMember member) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(member.email),
        children: [
          if (!member.isSuspended)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'suspend'),
              child: const Row(children: [
                Icon(Icons.block, color: Colors.orange, size: 18),
                SizedBox(width: 8),
                Text('Sperren'),
              ]),
            ),
          if (member.isSuspended)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'reactivate'),
              child: const Row(children: [
                Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                SizedBox(width: 8),
                Text('Wieder aktivieren'),
              ]),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'remove'),
            child: const Row(children: [
              Icon(Icons.person_remove_outlined, color: Colors.red, size: 18),
              SizedBox(width: 8),
              Text('Entfernen', style: TextStyle(color: Colors.red)),
            ]),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'suspend') {
        await ApiService.suspendCoPilot(widget.orbitId, member.id);
      } else if (action == 'reactivate') {
        await ApiService.reactivateCoPilot(widget.orbitId, member.id);
      } else if (action == 'remove') {
        await ApiService.removeCoPilot(widget.orbitId, member.id);
      }
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OrbitMember>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 36,
            child: Center(child: SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final members = snapshot.data ?? [];
        final isPilot = _isPilot(members);

        return Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.group_outlined, size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: members.map((m) {
                      final initials = (m.displayName?.isNotEmpty == true
                              ? m.displayName!
                              : m.email)
                          .substring(0, 1)
                          .toUpperCase();
                      Color bg = m.isPilot
                          ? AppColors.teal
                          : m.isSuspended
                              ? Colors.red.shade800
                              : m.isPending
                                  ? Colors.orange.shade700
                                  : Colors.blueGrey.shade600;
                      final tooltipName = m.displayName?.isNotEmpty == true
                          ? '${m.displayName}\n${m.email}'
                          : m.email;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Tooltip(
                          message: '$tooltipName'
                              '${m.isPilot ? '\nPilot' : '\nCo-Pilot'}'
                              '${m.isSuspended ? ' – gesperrt' : ''}'
                              '${m.isPending ? ' – ausstehend' : ''}',
                          child: GestureDetector(
                            onTap: isPilot && !m.isPilot
                                ? () => _manageMember(m)
                                : null,
                            child: CircleAvatar(
                              radius: 13,
                              backgroundColor: bg,
                              child: Text(
                                initials,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (isPilot)
                IconButton(
                  icon: const Icon(Icons.person_add_outlined,
                      color: Colors.white54, size: 18),
                  tooltip: 'Co-Pilot einladen',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () async {
                    widget.onInvite();
                    await Future.delayed(const Duration(milliseconds: 800));
                    _reload();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// User-Header in der Sidebar
// ---------------------------------------------------------------------------

class _UserHeader extends StatelessWidget {
  final VoidCallback? onLogout;
  const _UserHeader({this.onLogout});

  String _initials() {
    final name = AuthService.displayName;
    if (name != null && name.isNotEmpty) {
      final parts = name.trim().split(' ');
      if (parts.length >= 2) {
        return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      }
      return name[0].toUpperCase();
    }
    return (AuthService.email ?? '?')[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      offset: const Offset(8, 0),
      color: const Color(0xFF1C1C2E),
      onSelected: (value) async {
        if (value == 'settings') {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SettingsScreen(onLogout: onLogout ?? () {}),
            ),
          );
        } else if (value == 'logout') {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Abmelden'),
              content: const Text('Möchtest du dich wirklich abmelden?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Abmelden'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await AuthService.logout();
            onLogout?.call();
          }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'settings',
          child: Row(children: [
            Icon(Icons.settings_outlined, color: Colors.white70, size: 20),
            SizedBox(width: 12),
            Text('Einstellungen', style: TextStyle(color: Colors.white)),
          ]),
        ),
        const PopupMenuItem(
          value: 'logout',
          child: Row(children: [
            Icon(Icons.logout, color: Colors.white70, size: 20),
            SizedBox(width: 12),
            Text('Ausloggen', style: TextStyle(color: Colors.white)),
          ]),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.teal,
              child: Text(
                _initials(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (AuthService.displayName != null)
                    Text(
                      AuthService.displayName!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    AuthService.email ?? '',
                    style: TextStyle(
                      color: AuthService.displayName != null
                          ? Colors.white54
                          : Colors.white,
                      fontSize: AuthService.displayName != null ? 11 : 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.expand_more, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }
}
