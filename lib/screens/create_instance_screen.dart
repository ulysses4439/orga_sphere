import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';

class CreateInstanceScreen extends StatefulWidget {
  const CreateInstanceScreen({super.key});

  @override
  State<CreateInstanceScreen> createState() => _CreateInstanceScreenState();
}

class _CreateInstanceScreenState extends State<CreateInstanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  TaskTemplate? _selectedTemplate;
  DateTime _startDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  bool _saving = false;

  final TaskService _taskService = TaskService();

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _onTemplateSelected(TaskTemplate? template) {
    if (template == null) return;
    setState(() {
      _selectedTemplate = template;
      _titleController.text = template.title;
      _descController.text = template.description;
      _startDate = template.startDate;
      _dueDate = template.dueDate;
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _startDate : _dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_dueDate.isBefore(_startDate)) _dueDate = _startDate;
      } else {
        _dueDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _taskService.createInstance(
        templateId: _selectedTemplate!.id,
        domainId: _selectedTemplate!.domainId,
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        startDate: _startDate,
        dueDate: _dueDate,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = _taskService.getTemplates();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aufgabe anlegen'),
      ),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<TaskTemplate>(
                    initialValue: _selectedTemplate,
                    decoration: const InputDecoration(
                      labelText: 'Vorlage *',
                      border: OutlineInputBorder(),
                    ),
                    items: templates.map((t) {
                      final domain = _taskService.getDomainById(t.domainId);
                      return DropdownMenuItem(
                        value: t,
                        child: Text('${t.title} (${domain?.name ?? '?'})'),
                      );
                    }).toList(),
                    onChanged: _onTemplateSelected,
                    validator: (v) => v == null ? 'Vorlage ist erforderlich' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Titel *',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Titel ist erforderlich' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  _DateTile(
                    label: 'Startdatum',
                    date: _startDate,
                    onTap: () => _pickDate(true),
                  ),
                  const SizedBox(height: 16),
                  _DateTile(
                    label: 'Fälligkeitsdatum *',
                    date: _dueDate,
                    onTap: () => _pickDate(false),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Speichern'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DateTile({required this.label, required this.date, required this.onTap});

  String get _formatted =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(_formatted),
      ),
    );
  }
}
