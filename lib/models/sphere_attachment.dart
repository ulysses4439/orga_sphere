/// Ein Dateianhang an einer Sphere – Bild oder beliebige Datei.
///
/// Die Datei selbst liegt im Azure Blob Storage; hier stehen nur die Angaben
/// dazu. Abgerufen wird sie über `ApiService.attachmentContentUrl`.
class SphereAttachment {
  final String id;
  final String taskId;

  /// Der Verlaufseintrag, zu dem der Anhang gehört. `null` bedeutet: gerade
  /// hochgeladen, der Eintrag ist noch nicht abgeschickt.
  final String? logEntryId;

  final String fileName;
  final String contentType;
  final int sizeBytes;

  /// Vom Server am Dateiinhalt festgestellt, nicht an der Endung.
  final bool isImage;

  final String? uploadedBy;
  final String? uploadedByName;
  final DateTime createdAt;

  /// Gesetzt, wenn die Datei nach Ablauf der Aufbewahrungsfrist entfernt wurde.
  /// Der Eintrag bleibt trotzdem sichtbar – sonst entstünde im Verlauf eine
  /// Lücke, bei der niemand mehr weiß, ob dort je etwas war.
  final DateTime? blobDeletedAt;

  const SphereAttachment({
    required this.id,
    required this.taskId,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.isImage,
    required this.createdAt,
    this.logEntryId,
    this.uploadedBy,
    this.uploadedByName,
    this.blobDeletedAt,
    this.localPath,
  });

  /// Die Datei ist abgelaufen und nicht mehr abrufbar.
  bool get isExpired => blobDeletedAt != null;

  /// Noch keinem Verlaufseintrag zugeordnet – hängt am offenen Formular.
  bool get isPending => logEntryId == null;

  /// Pfad im Zwischenlager, solange die Datei noch nicht hochgeladen ist.
  ///
  /// Nur bei Anhängen gesetzt, die ohne Verbindung gewählt wurden. Die Kachel
  /// zeigt dann das Bild von der Platte – ein Abruf beim Server würde ohne Netz
  /// nur ein kaputtes Vorschaubild ergeben.
  final String? localPath;

  /// Wartet die Datei noch auf ihre Übertragung?
  bool get isLocalOnly => localPath != null;

  /// Größe in einer Form, die man vorlesen kann.
  String get readableSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// Zahl aus dem JSON, egal in welcher Gestalt sie ankommt.
  ///
  /// `sizeBytes` ist in der Datenbank ein BIGINT, und der SQL-Treiber liefert
  /// solche Werte als **Zeichenkette** aus – sie könnten größer werden, als
  /// JavaScript-Zahlen zuverlässig abbilden. Ein harter Cast auf `num` fliegt
  /// deshalb auf die Nase, und zwar erst in Dart: JavaScript rechnet mit "70"
  /// klaglos weiter, weshalb so etwas serverseitig nicht auffällt.
  static int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// Wahrheitswert aus dem JSON. Ein BIT kann je nach Weg als `true`, als `1`
  /// oder als `"1"` ankommen – aus demselben Grund wie oben lieber alles
  /// abfangen, als sich auf eine Gestalt zu verlassen.
  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  factory SphereAttachment.fromJson(Map<String, dynamic> json) {
    return SphereAttachment(
      id: json['id'] as String,
      taskId: json['taskId'] as String,
      logEntryId: json['logEntryId'] as String?,
      fileName: json['fileName'] as String? ?? 'Datei',
      contentType: json['contentType'] as String? ?? 'application/octet-stream',
      sizeBytes: _toInt(json['sizeBytes']),
      isImage: _toBool(json['isImage']),
      uploadedBy: json['uploadedBy'] as String?,
      uploadedByName: json['uploadedByName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      blobDeletedAt: json['blobDeletedAt'] != null
          ? DateTime.parse(json['blobDeletedAt'] as String)
          : null,
    );
  }

  /// Fuer den lokalen Zwischenspeicher – Feldnamen wie in der Server-Antwort,
  /// damit [SphereAttachment.fromJson] beide Quellen liest.
  ///
  /// `localPath` bleibt aussen vor: Ein Anhang, der noch im Zwischenlager
  /// wartet, gehoert der Warteschlange und nicht dem Datenbestand.
  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'logEntryId': logEntryId,
        'fileName': fileName,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
        'isImage': isImage,
        'uploadedBy': uploadedBy,
        'uploadedByName': uploadedByName,
        'createdAt': createdAt.toIso8601String(),
        'blobDeletedAt': blobDeletedAt?.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SphereAttachment && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
