import 'dart:io' show File;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart'
    show compute, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import '../models/models.dart';
import '../utils/attachment_upload.dart';
import '../services/api_service.dart';
import '../services/attachment_files.dart';
import '../services/auth_service.dart';
import '../services/notification_center.dart';
import '../services/task_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_format.dart';
import '../utils/field_limits.dart';
import 'attachment_widgets.dart';
import 'reminder_picker_dialog.dart';

/// Reusable sphere detail body – used as embedded panel (desktop) and
/// as the body of TaskDetailScreen (mobile).
class SphereDetailContent extends StatefulWidget {
  final String taskId;
  final VoidCallback? onDeleted;
  final VoidCallback? onClose;
  final VoidCallback? onChanged;
  final VoidCallback? onMarkedDone;
  final VoidCallback? onReopened;

  const SphereDetailContent({
    super.key,
    required this.taskId,
    this.onDeleted,
    this.onClose,
    this.onChanged,
    this.onMarkedDone,
    this.onReopened,
  });

  @override
  State<SphereDetailContent> createState() => _SphereDetailContentState();
}

class _SphereDetailContentState extends State<SphereDetailContent> {
  final TaskService _taskService = TaskService();
  final NotificationCenter _notifications = NotificationCenter();
  late Task? _task;
  final _logTextController = TextEditingController();
  late final TextEditingController _descriptionController;
  late final FocusNode _descriptionFocusNode;
  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;
  late final ScrollController _outerScrollController;
  String _lastSavedDescription = '';
  String _lastSavedTitle = '';
  bool _isBusy = false;

  /// Anhänge dieser Sphere. Bewusst im Widget statt im TaskService: Sie hängen
  /// nur an der geöffneten Detailansicht, und der Dienst hält den Zwischen-
  /// speicher für die Listenansichten – dort werden Anhänge nicht gebraucht.
  List<SphereAttachment> _attachments = [];
  bool _attachmentsLoaded = false;

  /// Bereits hochgeladene Anhänge, die auf das Absenden dieses Eintrags warten.
  /// Sie liegen schon beim Server, gehören aber noch zu keinem Eintrag – der
  /// existiert ja noch nicht.
  List<SphereAttachment> _pendingUploads = [];
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _task = _taskService.getTaskById(widget.taskId);
    _lastSavedDescription = _task?.description ?? '';
    _lastSavedTitle = _task?.title ?? '';
    _descriptionController = TextEditingController(text: _lastSavedDescription);
    _descriptionFocusNode = FocusNode()
      ..addListener(_onDescriptionFocusChange);
    _titleController = TextEditingController(text: _lastSavedTitle);
    _titleFocusNode = FocusNode()..addListener(_onTitleFocusChange);
    _outerScrollController = ScrollController();
    _taskService.addListener(_onServiceChanged);
    // Wer diese Sphere ansieht, hat ihre Meldungen gesehen – das rote Badge an
    // der Glocke muss dafür nicht extra angetippt werden.
    _markNotificationsRead();
    _notifications.addListener(_markNotificationsRead);
    _taskService.loadLogs(widget.taskId);
    _loadAttachments();
  }

  Future<void> _loadAttachments() async {
    try {
      final attachments = await ApiService.getAttachments(widget.taskId);
      if (!mounted) return;
      setState(() {
        _attachments = attachments;
        _attachmentsLoaded = true;
      });
    } catch (e) {
      // Anhänge sind Beiwerk: Wer offline ist oder einen Aussetzer erwischt,
      // soll trotzdem Titel, Beschreibung und Verlauf sehen. Beim nächsten
      // Öffnen wird es erneut versucht. Der Grund gehört aber ins Protokoll –
      // ein stilles Verschlucken macht genau die Fehlersuche unmöglich, für
      // die man es später braucht.
      debugPrint('[Anhänge] konnten nicht geladen werden: $e');
      if (mounted) setState(() => _attachmentsLoaded = true);
    }
  }

  /// Anhänge eines bestimmten Verlaufseintrags. Solange die Liste noch lädt,
  /// bleibt sie leer – lieber kurz nichts anzeigen als Kacheln aufblitzen zu
  /// lassen, während man schon liest.
  List<SphereAttachment> _attachmentsOf(String logEntryId) => _attachmentsLoaded
      ? _attachments.where((a) => a.logEntryId == logEntryId).toList()
      : const [];

  /// Dateien auswählen und sofort hochladen.
  ///
  /// Hochgeladen wird gleich beim Auswählen, nicht erst beim Absenden: So sieht
  /// man sofort, ob die Datei durchgeht, statt es nach dem Verfassen eines
  /// langen Textes erst zu erfahren.
  Future<void> _pickAndUploadFiles() async {
    final frei = kMaxAttachmentsPerEntry - _pendingUploads.length;
    if (frei <= 0) {
      _zeigeHinweis('Mehr als $kMaxAttachmentsPerEntry Anhänge pro Eintrag '
          'sind nicht möglich.');
      return;
    }

    final List<XFile> auswahl;
    try {
      auswahl = await openFiles();
    } catch (e) {
      _zeigeHinweis('Dateiauswahl fehlgeschlagen: $e');
      return;
    }
    if (auswahl.isEmpty || !mounted) return;

    final zuViele = auswahl.length > frei;
    final dateien = auswahl.take(frei).toList();

    setState(() => _isUploading = true);
    var fehler = 0;
    for (final datei in dateien) {
      final ok = await _uploadOne(await datei.readAsBytes(), datei.name);
      if (!ok) fehler++;
      if (!mounted) return;
    }
    setState(() => _isUploading = false);

    if (zuViele && fehler == 0) {
      _zeigeHinweis('Es passen nur noch $frei Anhänge in diesen Eintrag – der '
          'Rest wurde nicht übernommen.');
    }
  }

  /// Ob die Zwischenablage Bilder liefern kann. Nur auf dem Rechner – auf dem
  /// Handy führt der Weg über die Galerie.
  static bool get _zwischenablageMoeglich =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  /// Bild oder Datei aus der Zwischenablage anhängen.
  ///
  /// Der eigentliche Grund für das ganze Vorhaben: Ein Tester macht einen
  /// Screenshot und hat ihn in der Zwischenablage. Müsste er ihn erst als Datei
  /// speichern und wieder heraussuchen, benutzt er nach zwei Wochen wieder
  /// WhatsApp.
  Future<void> _pasteFromClipboard() async {
    if (_isUploading) return;
    if (_pendingUploads.length >= kMaxAttachmentsPerEntry) {
      _zeigeHinweis('Mehr als $kMaxAttachmentsPerEntry Anhänge pro Eintrag '
          'sind nicht möglich.');
      return;
    }

    setState(() => _isUploading = true);
    try {
      final bild = await Pasteboard.image;
      if (bild != null && bild.isNotEmpty) {
        final stempel = DateTime.now();
        final name = 'Screenshot_${stempel.year}'
            '${stempel.month.toString().padLeft(2, '0')}'
            '${stempel.day.toString().padLeft(2, '0')}_'
            '${stempel.hour.toString().padLeft(2, '0')}'
            '${stempel.minute.toString().padLeft(2, '0')}'
            '${stempel.second.toString().padLeft(2, '0')}.png';
        await _uploadOne(bild, name);
        return;
      }

      // Kein Bild, aber vielleicht im Explorer kopierte Dateien.
      final pfade = await Pasteboard.files();
      if (pfade.isEmpty) {
        _zeigeHinweis('In der Zwischenablage ist kein Bild und keine Datei.');
        return;
      }
      final frei = kMaxAttachmentsPerEntry - _pendingUploads.length;
      for (final pfad in pfade.take(frei)) {
        final datei = File(pfad);
        if (!await datei.exists()) continue;
        await _uploadOne(await datei.readAsBytes(), pfad.split(RegExp(r'[\\/]')).last);
        if (!mounted) return;
      }
    } catch (e) {
      _zeigeHinweis('Einfügen fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  /// Eine Datei hochladen und in die Warteliste des Formulars legen.
  /// Gibt `false` zurück, wenn es nicht geklappt hat.
  Future<bool> _uploadOne(Uint8List bytes, String name) async {
    try {
      // Nur retten, was sonst abgewiesen würde – siehe verkleinereWennNoetig.
      if (bytes.length > kMaxAttachmentBytes && istBildDateiname(name)) {
        final ergebnis = await compute(verkleinereWennNoetig, bytes);
        bytes = ergebnis.bytes;
      }
      if (bytes.length > kMaxAttachmentBytes) {
        _zeigeHinweis('„$name" ist größer als 10 MB und lässt sich nicht anhängen.');
        return false;
      }

      final hochgeladen = await ApiService.uploadAttachment(
        widget.taskId,
        bytes: bytes,
        fileName: name,
        contentType: mimeFuerDateiname(name),
      );
      if (!mounted) return false;
      setState(() => _pendingUploads = [..._pendingUploads, hochgeladen]);
      return true;
    } catch (e) {
      _zeigeHinweis('Hochladen fehlgeschlagen: $e');
      return false;
    }
  }

  /// Einen noch nicht abgeschickten Anhang wieder wegnehmen. Er wird auch beim
  /// Server gelöscht – sonst bliebe eine Datei liegen, die niemand mehr sieht.
  Future<void> _removePendingUpload(SphereAttachment attachment) async {
    setState(() => _pendingUploads =
        _pendingUploads.where((a) => a.id != attachment.id).toList());
    try {
      await ApiService.deleteAttachment(attachment.id);
    } catch (e) {
      // Aus der Ansicht ist er weg, das war der Wunsch. Bleibt er beim Server
      // liegen, räumt ihn der tägliche Lauf nach 24 Stunden ab.
      debugPrint('[Anhänge] Verwerfen fehlgeschlagen: $e');
    }
  }

  void _zeigeHinweis(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openAttachment(SphereAttachment attachment) async {
    if (attachment.isExpired) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('„${attachment.fileName}" wurde nach einem Jahr entfernt.'),
      ));
      return;
    }
    // Ein Bild schaut man an, eine Datei will man haben. Deshalb zwei
    // verschiedene Hauptwege statt eines Zwischendialogs, den man erst
    // wegklicken muss.
    if (attachment.isImage) {
      await showAttachmentViewer(
        context,
        attachment,
        onSave: () => _saveAttachment(attachment),
      );
      return;
    }
    await _saveAttachment(attachment);
  }

  /// Datei speichern (Rechner) bzw. weiterreichen (Handy).
  Future<void> _saveAttachment(SphereAttachment attachment) async {
    final ergebnis = await AttachmentFiles.herausgeben(attachment);
    // null heißt: Dialog abgebrochen. Das ist keine Meldung wert.
    if (ergebnis == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ergebnis.meldung),
        action: ergebnis.pfad == null
            ? null
            : SnackBarAction(
                label: 'Ordner öffnen',
                onPressed: () => AttachmentFiles.imOrdnerZeigen(ergebnis.pfad!),
              ),
      ),
    );
  }

  @override
  void didUpdateWidget(SphereDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Desktop: das Panel wird beim Wechsel der Auswahl wiederverwendet.
    if (oldWidget.taskId != widget.taskId) {
      _markNotificationsRead();
      _taskService.loadLogs(widget.taskId);
    }
  }

  /// Läuft auch bei jedem Poll erneut: Ereignisse, die eintreffen während die
  /// Sphere offen ist, gelten ebenfalls als gesehen. Endet von selbst, sobald
  /// nichts Ungelesenes mehr übrig ist (dann kein notifyListeners mehr).
  void _markNotificationsRead() {
    _notifications.markSphereRead(widget.taskId);
  }

  @override
  void dispose() {
    _notifications.removeListener(_markNotificationsRead);
    _taskService.removeListener(_onServiceChanged);
    // Noch nicht gespeicherte Eingaben sichern, BEVOR die Controller weg sind:
    // Wer den Titel ändert und sofort auf „Zurück" tippt bzw. das Detailpanel
    // schließt, verlässt die Ansicht ohne dass das Feld den Fokus verliert –
    // der übliche Speicher-Auslöser greift dann nicht mehr.
    _flushPendingEdits();
    _logTextController.dispose();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    _titleController.dispose();
    _titleFocusNode.dispose();
    _outerScrollController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    final updated = _taskService.getTaskById(widget.taskId);
    if (updated == null) return;
    setState(() => _task = updated);
    // Ein Abgleich kann den Verlauf als veraltet markiert haben, weil jemand
    // anderes etwas ergaenzt hat. Dann hier nachladen – die Sphere ist ja
    // gerade offen, initState und didUpdateWidget laufen nicht mehr.
    if (!updated.logsLoaded) _taskService.loadLogs(widget.taskId);
    // Nur aktualisieren wenn das Feld gerade nicht bearbeitet wird
    if (!_titleFocusNode.hasFocus) {
      final newTitle = updated.title;
      if (newTitle != _lastSavedTitle) {
        _lastSavedTitle = newTitle;
        _titleController.text = newTitle;
      }
    }
    if (!_descriptionFocusNode.hasFocus) {
      final newDesc = updated.description;
      if (newDesc != _lastSavedDescription) {
        _lastSavedDescription = newDesc;
        _descriptionController.text = newDesc;
      }
    }
  }

  void _onTitleFocusChange() {
    if (!_titleFocusNode.hasFocus) _saveTitle();
  }

  Future<void> _saveTitle() async {
    final newTitle = _titleController.text.trim();
    if (newTitle.isEmpty || newTitle == _lastSavedTitle) return;
    _lastSavedTitle = newTitle;
    try {
      await _taskService.updateTaskTitle(widget.taskId, newTitle);
      if (mounted) {
        setState(() => _task = _taskService.getTaskById(widget.taskId));
        widget.onChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  void _onDescriptionFocusChange() {
    if (!_descriptionFocusNode.hasFocus) _saveDescription();
  }

  Future<void> _saveDescription() async {
    final newDesc = _descriptionController.text;
    if (newDesc == _lastSavedDescription) return;
    _lastSavedDescription = newDesc;
    try {
      await _taskService.updateTaskDescription(widget.taskId, newDesc);
      if (mounted) setState(() => _task = _taskService.getTaskById(widget.taskId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  /// Speichert offene Änderungen an Titel und Beschreibung beim Verlassen der
  /// Ansicht. Läuft aus [dispose] heraus und darf deshalb weder `setState` noch
  /// `context` verwenden. Fehler werden bewusst geschluckt – eine Meldung ließe
  /// sich nicht mehr anzeigen, und der nächste Abgleich mit dem Backend
  /// korrigiert die Anzeige ohnehin.
  void _flushPendingEdits() {
    final title = _titleController.text.trim();
    if (title.isNotEmpty && title != _lastSavedTitle) {
      _lastSavedTitle = title;
      _taskService
          .updateTaskTitle(widget.taskId, title)
          .catchError((Object _) {});
    }
    final description = _descriptionController.text;
    if (description != _lastSavedDescription) {
      _lastSavedDescription = description;
      _taskService
          .updateTaskDescription(widget.taskId, description)
          .catchError((Object _) {});
    }
  }

  Future<void> _addLogEntry() async {
    // Ein Bild allein ist eine vollwertige Meldung – Text ist nur dann Pflicht,
    // wenn gar nichts angehängt ist.
    if (_logTextController.text.trim().isEmpty && _pendingUploads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Text eingeben oder etwas anhängen')),
      );
      return;
    }

    setState(() => _isBusy = true);
    try {
      await _taskService.addLogEntry(
        widget.taskId,
        _logTextController.text.trim(),
        attachmentIds: _pendingUploads.map((a) => a.id).toList(),
      );
      _logTextController.clear();
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _pendingUploads = [];
        _isBusy = false;
      });
      // Die Anhänge gehören jetzt zum neuen Eintrag – frisch holen, damit sie
      // im Verlauf an der richtigen Stelle auftauchen.
      _loadAttachments();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eintrag hinzugefügt')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  /// Neue Erinnerung anlegen: Datum, dann Uhrzeit.
  Future<void> _pickReminder() async {
    // .toLocal() fixes UTC-stored reminderAt showing wrong time in the picker.
    final initial = _task?.reminderAt?.toLocal();
    final result = await pickReminderDateTime(context, initial: initial);
    await _applyReminder(result);
  }

  /// Nur den Tag ändern – die eingestellte Uhrzeit bleibt bestehen.
  Future<void> _editReminderDate() async {
    final current = _task?.reminderAt?.toLocal();
    if (current == null) return;
    final result = await pickReminderDate(context, current);
    await _applyReminder(result);
  }

  /// Nur die Uhrzeit ändern – der eingestellte Tag bleibt bestehen.
  Future<void> _editReminderTime() async {
    final current = _task?.reminderAt?.toLocal();
    if (current == null) return;
    final result = await pickReminderTime(context, current);
    await _applyReminder(result);
  }

  Future<void> _applyReminder(DateTime? value) async {
    if (value == null || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await _taskService.setReminder(widget.taskId, value);
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _clearReminder() async {
    setState(() => _isBusy = true);
    try {
      await _taskService.setReminder(widget.taskId, null);
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _pickAssignee(Task task) async {
    setState(() => _isBusy = true);
    List<OrbitMember> members;
    try {
      members = await ApiService.getOrbitMembers(task.domainId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      return;
    }
    if (!mounted) return;
    setState(() => _isBusy = false);

    // Zuweisung nur an aktive (Co-)Piloten dieses Orbits.
    final active = members.where((m) => m.status == 'active').toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Zuweisen an'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _assign(task, null);
            },
            child: Row(
              children: [
                Icon(Icons.person_off_outlined, size: 20, color: Colors.grey[600]),
                const SizedBox(width: 12),
                const Text('Niemand'),
              ],
            ),
          ),
          ...active.map(
            (m) => SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                _assign(task, m);
              },
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: m.isPilot ? AppColors.teal : Colors.blueGrey,
                    child: Text(
                      m.displayLabel.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.displayLabel, overflow: TextOverflow.ellipsis),
                        Text(
                          m.isPilot ? 'Pilot' : 'Co-Pilot',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  if (task.assignedToMemberId == m.id)
                    const Icon(Icons.check, size: 18, color: AppColors.teal),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _assign(Task task, OrbitMember? member) async {
    setState(() => _isBusy = true);
    try {
      await _taskService.assignTask(
        task.id,
        member?.id,
        displayName: member?.displayName,
        email: member?.email,
      );
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  void _startTask() {
    final logCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setSt) => AlertDialog(
          title: const Text('In Bearbeitung setzen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Was ist der aktuelle Stand oder nächste Schritt?'),
              const SizedBox(height: 12),
              TextField(
                controller: logCtrl,
                autofocus: true,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Ersten Eintrag eingeben…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setSt(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                logCtrl.dispose();
                Navigator.pop(dialogContext);
              },
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: logCtrl.text.trim().isEmpty
                  ? null
                  : () async {
                      final text = logCtrl.text.trim();
                      logCtrl.dispose();
                      Navigator.pop(dialogContext);
                      setState(() => _isBusy = true);
                      try {
                        await _taskService.startTask(widget.taskId);
                        await _taskService.addLogEntry(widget.taskId, text);
                        if (!mounted) return;
                        setState(() {
                          _task = _taskService.getTaskById(widget.taskId);
                          _isBusy = false;
                        });
                      } catch (e) {
                        if (!mounted) return;
                        setState(() => _isBusy = false);
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
                      }
                    },
              child: const Text('In Bearbeitung'),
            ),
          ],
        ),
      ),
    );
  }

  void _markAsDone() {
    final task = _task;
    if (task == null) return;

    final confirmationText = task.isRecurring
        ? 'Sphere wird als erledigt markiert. Die nächste Sphere wird automatisch angelegt.'
        : 'Die Sphere wird als erledigt markiert und ins Archiv verschoben.';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sphere erledigt?'),
        content: Text(confirmationText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              setState(() => _isBusy = true);
              try {
                await _taskService.markAsDone(widget.taskId);
                if (!mounted) return;
                setState(() => _isBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sphere erledigt')),
                );
                widget.onMarkedDone?.call();
              } catch (e) {
                if (!mounted) return;
                setState(() => _isBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
              }
            },
            child: const Text('Erledigt'),
          ),
        ],
      ),
    );
  }

  void _reopenTask() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abschluss rückgängig machen?'),
        content: const Text(
          'Die Sphere wird wieder als aktiv markiert. Eine bereits angelegte Folge-Sphere bleibt erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              setState(() => _isBusy = true);
              try {
                await _taskService.reopenTask(widget.taskId);
                if (!mounted) return;
                setState(() => _isBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sphere wieder geöffnet')),
                );
                widget.onReopened?.call();
              } catch (e) {
                if (!mounted) return;
                setState(() => _isBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
              }
            },
            child: const Text('Ja, wieder öffnen'),
          ),
        ],
      ),
    );
  }

  void _deleteTask() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sphere löschen?'),
        content: const Text(
          'Diese Sphere und alle zugehörigen Einträge werden dauerhaft gelöscht. Dies kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              setState(() => _isBusy = true);
              try {
                await _taskService.deleteTask(widget.taskId);
                if (!mounted) return;
                widget.onDeleted?.call();
              } catch (e) {
                if (!mounted) return;
                setState(() => _isBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_task == null) {
      return const Center(child: Text('Sphere nicht gefunden'));
    }

    final task = _task!;
    final dueDate = task.dueDate;
    final domain = _taskService.getDomainById(task.domainId);
    final isDone = task.status == TaskStatus.done;

    return Stack(
      children: [
        Scrollbar(
          controller: _outerScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _outerScrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Kasten 1: Sphere-Titel (variable Höhe, navyPale)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: AppColors.navyPale,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _titleController,
                              focusNode: _titleFocusNode,
                              style: Theme.of(context).textTheme.headlineSmall,
                              maxLines: null,
                              maxLength: kSphereTitleMaxLength,
                              buildCounter: nearLimitCounter,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onSubmitted: (_) => _saveTitle(),
                            ),
                          ),
                          if (widget.onClose != null)
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: widget.onClose,
                              tooltip: 'Schließen',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _periodLabel(task),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Chip(
                            label: Text(
                              task.status.germanLabel,
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor: _statusColor(task.status),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 1, color: Colors.black),

                // Kasten 2: Beschreibung + Metadaten + Aktionen (variable Höhe)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDescriptionField(),
                      const SizedBox(height: 16),
                      _buildInfoRow('Orbit', domain?.name ?? 'Allgemein'),
                      const SizedBox(height: 8),
                      _buildTappableInfoRow(
                        'Zugewiesen an',
                        task.assignedToLabel ?? 'Niemand',
                        valueColor: task.assignedToLabel == null ? Colors.grey[500] : null,
                        onTap: _isBusy ? null : () => _pickAssignee(task),
                        onClear: task.assignedToMemberId != null && !_isBusy
                            ? () => _assign(task, null)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _buildTappableInfoRow(
                        'Wiederholung',
                        task.recurrence.germanLabel,
                        onTap: _isBusy ? null : _pickRecurrence,
                      ),
                      const SizedBox(height: 8),
                      _buildTappableInfoRow(
                        'Startdatum',
                        formatDate(task.startDate),
                        onTap: _isBusy ? null : _pickStartDate,
                      ),
                      const SizedBox(height: 8),
                      _buildTappableInfoRow(
                        'Fällig am',
                        dueDate != null ? formatDate(dueDate) : 'Kein Datum',
                        valueColor: dueDate != null && dueDate.isBefore(DateTime.now()) && !isDone
                            ? Colors.red
                            : null,
                        onTap: _isBusy ? null : _pickDueDate,
                        onClear: dueDate != null && !_isBusy ? _clearDueDate : null,
                      ),
                      const SizedBox(height: 8),
                      _buildReminderRow(task),
                      if (task.completedAt != null) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          'Abgeschlossen am',
                          formatDate(task.completedAt!),
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (task.status == TaskStatus.open) ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isBusy ? null : _startTask,
                                icon: const Icon(Icons.timelapse),
                                label: const Text('In Bearbeitung'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _isBusy ? null : _markAsDone,
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Erledigt'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (task.status == TaskStatus.inProgress)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isBusy ? null : _markAsDone,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Erledigt'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      if (isDone)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isBusy ? null : _reopenTask,
                            icon: const Icon(Icons.undo),
                            label: const Text('Abschluss rückgängig'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isBusy ? null : _deleteTask,
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          label: const Text(
                            'Sphere löschen',
                            style: TextStyle(color: Colors.red),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 1, color: Colors.black),

                // Kasten 3: Neuer Eintrag (fixe Höhe, Textbox scrollt intern, navyPale)
                if (!isDone) ...[
                  _buildAddLogEntryForm(),
                  const Divider(height: 1, thickness: 1, color: Colors.black),
                ],

                // Kasten 4: Aktivitätsverlauf (variable Höhe, weißer Hintergrund)
                _buildActivityLog(task),
              ],
            ),
          ),
        ),
        if (_isBusy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color.fromRGBO(0, 0, 0, 0.15),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _buildActivityLog(Task task) {
    // Der Aktivitätsverlauf ist der unterste Block der Detailansicht. Ohne
    // Reserve für die Systemleiste (Samsung-Navigationstasten/Gestenbalken)
    // liegen diese auf dem letzten Eintrag. `viewPadding` statt `padding`,
    // damit der Wert auch bei geöffneter Tastatur stabil bleibt; auf Desktop
    // ist er 0, dort bleibt die Darstellung unverändert.
    final systemBottom = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      width: double.infinity,
      color: AppColors.appWhite,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + systemBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Aktivitätsverlauf', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          // Der Verlauf wird erst beim Öffnen der Sphere geholt. Bis die
          // Antwort da ist, darf hier nicht „Noch keine Einträge" stehen – das
          // wäre für Spheres mit Verlauf schlicht falsch. Solange die bekannte
          // Anzahl größer null ist, zeigen wir deshalb einen Ladehinweis.
          if (!task.logsLoaded && task.logCount > 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (task.logEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Noch keine Einträge',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                ),
              ),
            )
          else
            _buildTimeline(task.logEntries),
        ],
      ),
    );
  }

  Widget _buildReminderRow(Task task) {
    if (task.reminderAt == null) {
      return InkWell(
        onTap: _isBusy ? null : _pickReminder,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(Icons.notifications_none, color: Colors.grey[400], size: 20),
              const SizedBox(width: 8),
              Text(
                'Erinnerung hinzufügen',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.grey[400],
                    ),
              ),
            ],
          ),
        ),
      );
    }

    final local = task.reminderAt!.toLocal();
    final reminderExpired =
        task.reminderAt!.isBefore(DateTime.now()) && task.status != TaskStatus.done;
    final reminderColor = reminderExpired ? Colors.red : AppColors.teal;

    // Datum und Uhrzeit sind einzeln antippbar: ein Tipp öffnet genau den
    // passenden Dialog, statt den Zeitpunkt löschen und neu setzen zu müssen.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.notifications_active, color: reminderColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildReminderPart(
                  label: formatDate(local),
                  tooltip: 'Datum ändern',
                  color: reminderColor,
                  onTap: _editReminderDate,
                ),
                _buildReminderPart(
                  label: formatTime(local),
                  tooltip: 'Uhrzeit ändern',
                  color: reminderColor,
                  onTap: _editReminderTime,
                ),
              ],
            ),
          ),
          if (reminderExpired)
            TextButton.icon(
              onPressed: _isBusy ? null : _clearReminder,
              icon: const Icon(Icons.notifications_off_outlined, size: 16),
              label: const Text('Erinnerung löschen'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                textStyle: const TextStyle(fontSize: 12),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.close, size: 18, color: Colors.grey[500]),
              tooltip: 'Erinnerung löschen',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: _isBusy ? null : _clearReminder,
            ),
        ],
      ),
    );
  }

  /// Antippbarer Teil des Erinnerungszeitpunkts (Datum bzw. Uhrzeit).
  /// Die gestrichelte Unterstreichung signalisiert die Bearbeitbarkeit.
  Widget _buildReminderPart({
    required String label,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: _isBusy ? null : onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                  decorationColor: color.withValues(alpha: 0.6),
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Beschreibung',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey[700]),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionController,
          focusNode: _descriptionFocusNode,
          maxLines: null,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
          maxLength: kSphereDescriptionMaxLength,
          buildCounter: nearLimitCounter,
          decoration: InputDecoration(
            hintText: 'Beschreibung hinzufügen…',
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.lightGrey),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.teal, width: 2),
            ),
            filled: true,
            fillColor: AppColors.appWhite,
          ),
        ),
      ],
    );
  }

  String _periodLabel(Task task) {
    final d = task.startDate;
    final months = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
    ];
    switch (task.recurrence.frequency) {
      case RecurrenceFrequency.none:
        return 'Einmalig';
      case RecurrenceFrequency.daily:
        return 'Datum: ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
      case RecurrenceFrequency.weekly:
        final monday = d.subtract(Duration(days: d.weekday - 1));
        final sunday = monday.add(const Duration(days: 6));
        String fmt(DateTime x) =>
            '${x.day.toString().padLeft(2, '0')}.${x.month.toString().padLeft(2, '0')}.${x.year}';
        return 'Woche: ${fmt(monday)} – ${fmt(sunday)}';
      case RecurrenceFrequency.monthly:
        return 'Monat: ${months[d.month - 1]} ${d.year}';
      case RecurrenceFrequency.yearly:
        return 'Jahr: ${d.year}';
    }
  }

  Future<void> _pickStartDate() async {
    final task = _task;
    if (task == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: task.startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _isBusy = true);
    try {
      await _taskService.updateTaskSchedule(widget.taskId, startDate: picked);
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _pickDueDate() async {
    final task = _task;
    if (task == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: task.dueDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _isBusy = true);
    try {
      await _taskService.updateTaskSchedule(widget.taskId, dueDate: picked);
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _clearDueDate() async {
    setState(() => _isBusy = true);
    try {
      await _taskService.updateTaskSchedule(widget.taskId, clearDueDate: true);
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _pickRecurrence() async {
    final task = _task;
    if (task == null) return;
    String frequencyLabel(RecurrenceFrequency f) {
      switch (f) {
        case RecurrenceFrequency.none:    return 'Einmalig';
        case RecurrenceFrequency.daily:   return 'Täglich';
        case RecurrenceFrequency.weekly:  return 'Wöchentlich';
        case RecurrenceFrequency.monthly: return 'Monatlich';
        case RecurrenceFrequency.yearly:  return 'Jährlich';
      }
    }
    final picked = await showDialog<RecurrenceFrequency>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Wiederholung'),
        children: RecurrenceFrequency.values.map((f) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, f),
          child: Text(frequencyLabel(f)),
        )).toList(),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _isBusy = true);
    try {
      await _taskService.updateTaskSchedule(
        widget.taskId,
        recurrenceFrequency: picked.name,
        recurrenceInterval: picked == RecurrenceFrequency.none ? 1 : task.recurrence.interval,
      );
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Widget _buildTappableInfoRow(
    String label,
    String value, {
    Color? valueColor,
    VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(color: valueColor)),
                if (onClear != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onClear,
                    borderRadius: BorderRadius.circular(12),
                    child: Icon(Icons.close, size: 16, color: Colors.grey[500]),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(Icons.edit_outlined, size: 14, color: Colors.grey[400]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
        Text(value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: valueColor)),
      ],
    );
  }

  Widget _buildTimeline(List<TaskLogEntry> entries) {
    return Column(
      children: List.generate(entries.length, (index) {
        final entry = entries[index];
        final isLast = index == entries.length - 1;

        final attachments = _attachmentsOf(entry.id);

        return Column(
          children: [
            // IntrinsicHeight, damit die Verbindungslinie mitwaechst: Vorher
            // hatte sie feste 60 Pixel, was genau so lange passte, wie jeder
            // Eintrag aus zwei Zeilen Text bestand. Mit Bildern darunter waere
            // sie ins Leere gelaufen.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 12,
                    child: Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.teal,
                            border: Border.all(color: AppColors.appWhite, width: 2),
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(width: 2, color: AppColors.lightGrey),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              entry.user,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _formatDate(entry.timestamp),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        // Ein Eintrag darf inzwischen auch nur aus Anhaengen
                        // bestehen – dann entfaellt die Textzeile ganz, statt
                        // eine leere Luecke zu lassen.
                        if (entry.text.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(entry.text,
                              style: Theme.of(context).textTheme.bodyMedium),
                        ],
                        if (attachments.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          AttachmentStrip(
                            attachments: attachments,
                            onOpen: _openAttachment,
                          ),
                        ],
                        if (!isLast) const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildAddLogEntryForm() {
    // Keine feste Höhe mehr: Der Kasten wächst um die Anhänge, sobald welche
    // angehängt sind. Das Textfeld behält seine Höhe, damit das Formular nicht
    // bei jedem Tippen springt.
    return Material(
      elevation: 0,
      color: AppColors.navyPale,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Neuer Eintrag', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text(
                  AuthService.displayName ?? AuthService.email ?? '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              // Strg+V muss hier abgefangen werden, bevor das Textfeld es als
              // Einfügen von Text versteht. Die Taste wird bewusst NICHT als
              // erledigt gemeldet (KeyEventResult.ignored): Liegt Text in der
              // Zwischenablage, soll er ganz normal im Feld landen. Nur wenn
              // dort ein Bild oder eine Datei liegt, kommt zusätzlich ein
              // Anhang dazu.
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      HardwareKeyboard.instance.isControlPressed &&
                      event.logicalKey == LogicalKeyboardKey.keyV) {
                    _pasteFromClipboard();
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _logTextController,
                  expands: true,
                  maxLines: null,
                  maxLength: kLogEntryMaxLength,
                  buildCounter: nearLimitCounter,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: 'Beschreiben Sie den Fortschritt...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
            ),
            if (_pendingUploads.isNotEmpty) ...[
              const SizedBox(height: 8),
              AttachmentStrip(
                attachments: _pendingUploads,
                onOpen: _openAttachment,
                onDelete: _isBusy ? null : _removePendingUpload,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                // Anhängen sitzt links neben dem Absenden, nicht darüber: So
                // liest sich die Zeile als „erst dranhängen, dann abschicken".
                // Beide Knöpfe nur mit Symbol – in einer schmal gezogenen Pane
                // bliebe für den Absenden-Knopf sonst kaum Platz.
                Tooltip(
                  message: 'Datei anhängen (max. $kMaxAttachmentsPerEntry, je 10 MB)',
                  child: OutlinedButton(
                    onPressed: _isBusy || _isUploading ? null : _pickAndUploadFiles,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      minimumSize: const Size(0, 0),
                    ),
                    child: _isUploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file, size: 18),
                  ),
                ),
                const SizedBox(width: 6),
                // Der Knopf macht den Weg sichtbar. Strg+V allein wäre eine
                // versteckte Funktion, von der niemand erfährt.
                //
                // Auf dem Handy entfällt er: Dort gibt es keine Zwischenablage
                // für Bilder, die App käme nicht heran, und der Knopf würde
                // ausnahmslos „kein Bild in der Zwischenablage" melden – ein
                // Knopf, der nie etwas tut, ist schlimmer als keiner. Screenshots
                // holt man dort über die Büroklammer aus der Galerie.
                if (_zwischenablageMoeglich) ...[
                  Tooltip(
                    message: 'Bild oder Datei aus der Zwischenablage einfügen (Strg+V)',
                    child: OutlinedButton(
                      onPressed: _isBusy || _isUploading ? null : _pasteFromClipboard,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        minimumSize: const Size(0, 0),
                      ),
                      child: const Icon(Icons.content_paste, size: 18),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isBusy ? null : _addLogEntry,
                    icon: const Icon(Icons.add),
                    label: const Text('Eintrag hinzufügen'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.open:
        return Colors.grey;
      case TaskStatus.inProgress:
        return AppColors.teal;
      case TaskStatus.done:
        return Colors.green;
    }
  }

  String _formatDate(DateTime date) => formatDateTime(date);
}
