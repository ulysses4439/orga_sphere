import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';

/// Die Marke eines Orbits in Listen und Menüs: das Emoji, wenn eines gesetzt
/// ist – sonst der farbige Punkt wie bisher.
///
/// Eine einzige Stelle für alle Ansichten, damit die Regel nicht an fünf Orten
/// getrennt gepflegt werden muss und dann irgendwo abweicht.
class OrbitMarker extends StatelessWidget {
  /// Durchmesser des Punkts. Das Emoji wird passend dazu gesetzt.
  final double size;

  final String? icon;
  final Color color;

  const OrbitMarker({
    super.key,
    required this.color,
    this.icon,
    this.size = 12,
  });

  OrbitMarker.forDomain(TaskDomain domain, {super.key, this.size = 12})
      : icon = domain.hasIcon ? domain.icon : null,
        color = domain.color;

  @override
  Widget build(BuildContext context) {
    if (icon != null) {
      // Etwas größer als der Punkt: Ein Emoji auf Punktgröße wäre nicht mehr
      // zu erkennen. Die Breite bleibt an der Punktgröße ausgerichtet, damit
      // die Namen daneben in einer Flucht stehen.
      return SizedBox(
        width: size + 4,
        child: Text(
          icon!,
          style: TextStyle(fontSize: size + 4),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Auswahl eines Symbols für einen Orbit.
///
/// Bewusst eine **kuratierte** Liste statt der vollen Emoji-Palette. Zwei
/// Gründe: Sehr neue Emojis fehlen auf älteren Android-Versionen und erscheinen
/// dort als leeres Kästchen – hier stehen nur lange etablierte Zeichen. Und
/// eine überschaubare Auswahl ist schneller zu treffen als ein Raster mit
/// tausend Feldern, in dem man sich verliert.
///
/// Wer trotzdem ein bestimmtes Zeichen will, kann es unten in das Feld tippen
/// oder einfügen (Windows: Windows-Taste + Punkt öffnet die Emoji-Tastatur).
class OrbitIconPicker extends StatefulWidget {
  final String? initial;

  const OrbitIconPicker({super.key, this.initial});

  @override
  State<OrbitIconPicker> createState() => _OrbitIconPickerState();
}

/// Nach Zweck gruppiert, nicht alphabetisch – man sucht ein Symbol für „das,
/// worum es geht", nicht nach einem Namen.
const Map<String, List<String>> _gruppen = {
  'Arbeit': ['💼', '📁', '📅', '📌', '📊', '📝', '💻', '📞', '✉️', '🗓️'],
  'Zuhause': ['🏠', '🛋️', '🧹', '🧺', '🍽️', '🛒', '🔑', '🪴', '🐾', '🧾'],
  'Werkstatt': ['🔧', '🔨', '⚙️', '🧰', '🔩', '🪛', '⚡', '🚗', '🚲', '⛽'],
  'Freizeit': ['🎬', '🎵', '📚', '🎮', '⚽', '🏋️', '✈️', '🏖️', '🎯', '🎁'],
  'Zeichen': ['⭐', '❤️', '🔥', '💡', '⚠️', '✅', '🚀', '🎓', '💰', '🌍'],
};

class _OrbitIconPickerState extends State<OrbitIconPicker> {
  late String? _gewaehlt = widget.initial?.trim().isEmpty == true
      ? null
      : widget.initial;
  late final TextEditingController _eigenes =
      TextEditingController(text: _gewaehlt ?? '');

  @override
  void dispose() {
    _eigenes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Symbol wählen'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Das Symbol ersetzt den farbigen Punkt in der Orbit-Liste. '
                'Ohne Symbol bleibt es beim Punkt.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              for (final gruppe in _gruppen.entries) ...[
                Text(gruppe.key,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: gruppe.value
                      .map((zeichen) => _Feld(
                            zeichen: zeichen,
                            gewaehlt: _gewaehlt == zeichen,
                            onTap: () => setState(() {
                              _gewaehlt = zeichen;
                              _eigenes.text = zeichen;
                            }),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
              ],
              const Divider(),
              Text('Eigenes Zeichen',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              TextField(
                controller: _eigenes,
                // Nicht auf ein Zeichen begrenzen: Zusammengesetzte Emojis
                // (Familien, Flaggen, Hautton) bestehen aus mehreren Einheiten
                // und wuerden sonst mitten entzwei geschnitten.
                maxLength: 50,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'Einfügen oder tippen – Windows-Taste + Punkt',
                  counterText: '',
                ),
                onChanged: (wert) =>
                    setState(() => _gewaehlt = wert.trim().isEmpty ? null : wert.trim()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Vorschau:',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(width: 12),
                  _Vorschau(zeichen: _gewaehlt),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const OrbitIconAuswahl.abbruch()),
          child: const Text('Abbrechen'),
        ),
        // Entfernen ist kein Sonderweg, sondern eine gleichwertige Wahl: Wer
        // ein Symbol wieder loswerden will, soll es nicht ueber das leere Feld
        // erraten muessen.
        TextButton(
          onPressed: () =>
              Navigator.pop(context, const OrbitIconAuswahl.entfernen()),
          child: const Text('Kein Symbol'),
        ),
        FilledButton(
          onPressed: _gewaehlt == null
              ? null
              : () => Navigator.pop(context, OrbitIconAuswahl.setzen(_gewaehlt!)),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

/// Ergebnis der Auswahl. Trennt sauber zwischen „abgebrochen" und „bewusst
/// kein Symbol" – beides ergäbe sonst denselben Nullwert und der Aufrufer
/// könnte das eine nicht vom anderen unterscheiden.
class OrbitIconAuswahl {
  final String? zeichen;
  final bool abgebrochen;

  const OrbitIconAuswahl.abbruch()
      : zeichen = null,
        abgebrochen = true;

  const OrbitIconAuswahl.entfernen()
      : zeichen = null,
        abgebrochen = false;

  const OrbitIconAuswahl.setzen(String this.zeichen) : abgebrochen = false;
}

class _Feld extends StatelessWidget {
  final String zeichen;
  final bool gewaehlt;
  final VoidCallback onTap;

  const _Feld({required this.zeichen, required this.gewaehlt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: gewaehlt ? AppColors.tealPale : null,
          border: Border.all(
            color: gewaehlt ? AppColors.teal : Colors.grey.shade300,
            width: gewaehlt ? 2 : 1,
          ),
        ),
        child: Text(zeichen, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}

class _Vorschau extends StatelessWidget {
  final String? zeichen;

  const _Vorschau({this.zeichen});

  @override
  Widget build(BuildContext context) {
    if (zeichen == null) {
      return Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              color: AppColors.teal,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text('Punkt in der Orbit-Farbe',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }
    return Text(zeichen!, style: const TextStyle(fontSize: 22));
  }
}

/// Öffnet die Auswahl. Gibt `null` zurück, wenn abgebrochen wurde.
Future<OrbitIconAuswahl?> showOrbitIconPicker(
  BuildContext context, {
  String? initial,
}) async {
  final ergebnis = await showDialog<OrbitIconAuswahl>(
    context: context,
    builder: (ctx) => OrbitIconPicker(initial: initial),
  );
  if (ergebnis == null || ergebnis.abgebrochen) return null;
  return ergebnis;
}
