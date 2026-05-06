import 'package:flutter/material.dart';
import '../services/task_service.dart';

const _kPaletteColors = [
  '#FFC0CB', // Rosa
  '#FFB6C1', // Hellrosa
  '#FFDAB9', // Pfirsich
  '#FFE4B5', // Maisgelb
  '#FFFACD', // Zitrone
  '#C1FFC1', // Hellgrün
  '#98FB98', // Blassgrün
  '#E0FFFF', // Hellcyan
  '#AFEEEE', // Türkis
  '#B0E0E6', // Puderblau
  '#E6E6FA', // Lavendel
  '#DDA0DD', // Pflaume
  '#F5F5DC', // Beige
  '#D3D3D3', // Hellgrau
  '#F5F5F5', // Weiß
];

class CreateDomainScreen extends StatefulWidget {
  const CreateDomainScreen({super.key});

  @override
  State<CreateDomainScreen> createState() => _CreateDomainScreenState();
}

class _CreateDomainScreenState extends State<CreateDomainScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _emailsController = TextEditingController();
  String _selectedColor = '#E6E6FA';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _emailsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await TaskService().createDomain(
        _nameController.text.trim(),
        _descController.text.trim(),
        _selectedColor,
        notificationEmails: _emailsController.text.trim(),
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

  Color _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    return Color(int.parse('0xFF$clean'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orbit anlegen')),
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
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailsController,
                    decoration: const InputDecoration(
                      labelText: 'Erinnerungs-E-Mails',
                      hintText: 'max@beispiel.de, anna@beispiel.de',
                      helperText: 'Kommagetrennt – erhalten E-Mail wenn ein Reminder fällig ist',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 16),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Farbe',
                      border: OutlineInputBorder(),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _kPaletteColors.map((hex) {
                            final isSelected = hex == _selectedColor;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedColor = hex),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _hexToColor(hex),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.grey.shade400,
                                    width: isSelected ? 3 : 1,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, size: 18, color: Colors.black54)
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: _hexToColor(_selectedColor),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey.shade400),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _selectedColor.toUpperCase(),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
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
