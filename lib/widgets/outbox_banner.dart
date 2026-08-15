import 'package:flutter/material.dart';

import '../services/outbox.dart';
import '../services/sync_service.dart';

/// Zeigt an, dass Änderungen auf ihre Übertragung warten.
///
/// Der Grund für dieses Band ist eine Erfahrung aus dem Alltag: Wer im Laden
/// eine Position abhakt und nicht merkt, dass das Handy offline ist, weiß
/// sonst nicht, ob sein Tippen gezählt hat. Die Änderung ist zwar sicher
/// aufgehoben – aber das muss man auch sehen können.
///
/// Bewusst zurückhaltend: eine schmale Zeile, kein Dialog, keine Warnung. Es
/// ist ja nichts kaputt. Sobald die Schlange leer ist, verschwindet sie
/// wortlos.
class OutboxBanner extends StatefulWidget {
  const OutboxBanner({super.key});

  @override
  State<OutboxBanner> createState() => _OutboxBannerState();
}

class _OutboxBannerState extends State<OutboxBanner> {
  final Outbox _outbox = Outbox();

  @override
  void initState() {
    super.initState();
    _outbox.addListener(_onChanged);
    _outbox.laden();
  }

  @override
  void dispose() {
    _outbox.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final anzahl = _outbox.anzahl;
    if (anzahl == 0) return const SizedBox.shrink();

    // Hartnäckige Fälle bekommen einen anderen Ton: Wenn ein Auftrag seit
    // zwanzig Versuchen nicht durchgeht, liegt es nicht mehr am Funkloch.
    final haengt = _outbox.hatHartnaeckige;
    final farbe = haengt ? Colors.orange.shade800 : Colors.blueGrey.shade700;

    return Material(
      color: farbe,
      child: InkWell(
        onTap: () => SyncService().abgleichen(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(haengt ? Icons.error_outline : Icons.cloud_off,
                  size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  haengt
                      ? '$anzahl Änderung${anzahl == 1 ? '' : 'en'} lässt sich '
                          'nicht übertragen – zum erneuten Versuch tippen'
                      : 'Offline – $anzahl Änderung${anzahl == 1 ? '' : 'en'} '
                          'wartet auf die Übertragung',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const Icon(Icons.refresh, size: 16, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}
