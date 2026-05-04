import 'package:flutter/material.dart';
import '../services/task_service.dart';

class CreateDomainScreen extends StatefulWidget {
  const CreateDomainScreen({super.key});

  @override
  State<CreateDomainScreen> createState() => _CreateDomainScreenState();
}

class _CreateDomainScreenState extends State<CreateDomainScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await TaskService().createDomain(
        _nameController.text.trim(),
        _descController.text.trim(),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bereich anlegen'),
      ),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name *',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    autofocus: true,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Name ist erforderlich' : null,
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
