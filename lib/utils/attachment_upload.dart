import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'field_limits.dart';

/// Hilfen fuers Hochladen von Dateien an eine Sphere.

const Map<String, String> _mimeNachEndung = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'log': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'json': 'application/json',
  'xml': 'application/xml',
  'zip': 'application/zip',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'mp4': 'video/mp4',
};

/// Dateityp anhand der Endung. Nur ein Hinweis fuer den Server – ob etwas
/// wirklich ein Bild ist, entscheidet dort der Blick in die Datei selbst.
String mimeFuerDateiname(String fileName) {
  final punkt = fileName.lastIndexOf('.');
  if (punkt < 0) return 'application/octet-stream';
  final endung = fileName.substring(punkt + 1).toLowerCase();
  return _mimeNachEndung[endung] ?? 'application/octet-stream';
}

bool istBildDateiname(String fileName) =>
    mimeFuerDateiname(fileName).startsWith('image/');

/// Ergebnis von [verkleinereWennNoetig].
class VerkleinertesBild {
  final Uint8List bytes;

  /// Wurde tatsaechlich gerechnet? Sonst sind es die Originalbytes.
  final bool verkleinert;

  const VerkleinertesBild(this.bytes, this.verkleinert);
}

/// Verkleinert ein Bild **nur dann**, wenn es sonst an der Groessengrenze
/// scheitern wuerde.
///
/// Bewusst kein generelles Herunterrechnen: Anhaenge sind hier meist
/// Screenshots, und die schickt man, damit jemand die kleine Schrift darauf
/// lesen kann. Ein 4K-Bild auf 1600 Pixel zu stauchen wuerde genau das
/// zerstoeren – man haette Bandbreite gespart und den Zweck verfehlt. Ein
/// gewoehnlicher Screenshot bleibt deshalb unangetastet; gerechnet wird erst,
/// wenn die Datei ueber [kMaxAttachmentBytes] liegt und der Upload andernfalls
/// abgewiesen wuerde. Dann ist ein kleineres Bild besser als gar keines.
///
/// Laeuft ueber `compute` in einem eigenen Isolate – das Dekodieren eines
/// grossen Bildes braucht spuerbar Zeit und wuerde sonst die Oberflaeche
/// einfrieren.
VerkleinertesBild verkleinereWennNoetig(Uint8List bytes) {
  if (bytes.length <= kMaxAttachmentBytes) {
    return VerkleinertesBild(bytes, false);
  }

  final bild = img.decodeImage(bytes);
  if (bild == null) return VerkleinertesBild(bytes, false);

  // Schrittweise halbieren, bis es passt. Beim ersten Versuch bleibt die
  // Aufloesung oft schon erhalten, weil allein das Neukodieren als JPEG
  // genuegt.
  var breite = bild.width;
  var hoehe = bild.height;

  for (var versuch = 0; versuch < 6; versuch++) {
    final skaliert = (versuch == 0)
        ? bild
        : img.copyResize(bild, width: breite, height: hoehe);
    final kodiert = Uint8List.fromList(img.encodeJpg(skaliert, quality: 90));
    if (kodiert.length <= kMaxAttachmentBytes) {
      return VerkleinertesBild(kodiert, true);
    }
    breite = (breite * 0.75).round();
    hoehe = (hoehe * 0.75).round();
    if (breite < 640 || hoehe < 640) {
      return VerkleinertesBild(kodiert, true);
    }
  }

  return VerkleinertesBild(bytes, false);
}
