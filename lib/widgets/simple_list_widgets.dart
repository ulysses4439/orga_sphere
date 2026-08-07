import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';

/// Bausteine für Orbits im Einkaufslisten-Modus ([TaskDomain.isShoppingList]).
///
/// Bewusst als gemeinsame Widgets angelegt: Desktop-Panel und mobile
/// Orbitansicht verwenden dieselben Bausteine, damit beide Plattformen sich
/// nicht auseinanderentwickeln können.

/// Eingabefeld zum schnellen Erfassen mehrerer Positionen hintereinander.
/// Nach dem Absenden bleibt der Fokus im Feld – tippen, Enter, nächste Position.
class SimpleListQuickAdd extends StatefulWidget {
  final String orbitId;

  /// Wird nach dem Anlegen aufgerufen, damit die Liste sich aktualisiert.
  final VoidCallback? onAdded;

  const SimpleListQuickAdd({super.key, required this.orbitId, this.onAdded});

  @override
  State<SimpleListQuickAdd> createState() => _SimpleListQuickAddState();
}

class _SimpleListQuickAddState extends State<SimpleListQuickAdd> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _saving) return;

    setState(() => _saving = true);
    try {
      await TaskService().createTask(
        domainId: widget.orbitId,
        title: title,
        // Eine Listenposition hat nur einen Namen. Startdatum ist ein
        // Pflichtfeld des Datenmodells und wird still auf heute gesetzt –
        // angezeigt wird es in diesem Modus nirgends.
        description: '',
        startDate: DateTime.now(),
        recurrence: const RecurrencePattern(
          frequency: RecurrenceFrequency.none,
        ),
      );
      _controller.clear();
      widget.onAdded?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
      // Fokus zurück ins Feld, damit die nächste Position direkt getippt
      // werden kann, ohne erneut anzutippen.
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                hintText: 'Position hinzufügen…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            tooltip: 'Position hinzufügen',
          ),
        ],
      ),
    );
  }
}

/// Kleiner Dialog zum Korrigieren oder Löschen einer Position. Ersetzt in
/// Listen-Orbits die vollständige Sphere-Detailansicht.
///
/// Gibt `true` zurück, wenn sich etwas geändert hat.
Future<bool> showSimpleListItemDialog(BuildContext context, Task task) async {
  final controller = TextEditingController(text: task.title);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Position bearbeiten'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(ctx);
            Navigator.pop(ctx, true);
            try {
              await TaskService().deleteTask(task.id);
            } catch (e) {
              messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
            }
          },
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          label: const Text('Löschen', style: TextStyle(color: Colors.red)),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  if (result == true) {
    final newTitle = controller.text.trim();
    if (newTitle.isNotEmpty && newTitle != task.title) {
      try {
        await TaskService().updateTaskTitle(task.id, newTitle);
      } catch (_) {
        // Anzeige korrigiert sich beim nächsten Abgleich mit dem Backend.
      }
    }
  }
  controller.dispose();
  return result == true;
}
