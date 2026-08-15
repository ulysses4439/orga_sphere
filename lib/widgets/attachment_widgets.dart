import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

/// Anhänge unter einem Verlaufseintrag.
///
/// Bewusst als eigene Reihe unter dem Text und nicht mitten hinein: Bilder im
/// Fließtext bräuchten einen Rich-Text-Editor samt Speicherformat, und in einem
/// Fehlerbericht ist der Screenshot ohnehin fast immer der Beleg zur ganzen
/// Meldung – nicht eine Abbildung mitten im Satz. Gleich große Kacheln halten
/// den Verlauf außerdem überschaubar, egal wie breit die Detailansicht gerade
/// gezogen ist.
class AttachmentStrip extends StatelessWidget {
  final List<SphereAttachment> attachments;
  final void Function(SphereAttachment) onOpen;

  /// Wird gesetzt, sobald es etwas zu löschen gibt (Formular, eigene Dateien).
  /// Ohne diesen Rückruf erscheint kein Löschen-Knopf.
  final void Function(SphereAttachment)? onDelete;

  const AttachmentStrip({
    super.key,
    required this.attachments,
    required this.onOpen,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments
          .map((a) => AttachmentTile(
                attachment: a,
                onOpen: () => onOpen(a),
                onDelete: onDelete == null ? null : () => onDelete!(a),
              ))
          .toList(),
    );
  }
}

/// Eine einzelne Kachel: Vorschaubild bei Bildern, sonst ein Dateisymbol.
class AttachmentTile extends StatelessWidget {
  final SphereAttachment attachment;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.onOpen,
    this.onDelete,
  });

  static const double _thumbSize = 96;

  @override
  Widget build(BuildContext context) {
    final inhalt = attachment.isExpired
        ? _buildExpired(context)
        : attachment.isImage
            ? _buildImage(context)
            : _buildFile(context);

    if (onDelete == null) return inhalt;

    // Der Löschen-Knopf sitzt als kleine Ecke auf der Kachel statt daneben –
    // sonst bräuchte jede Kachel doppelt so viel Breite.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        inhalt,
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: Colors.black87,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImage(BuildContext context) {
    return Tooltip(
      message: '${attachment.fileName}\n${attachment.readableSize}',
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: _thumbSize,
            height: _thumbSize,
            color: AppColors.lightGrey,
            child: Image.network(
              ApiService.attachmentContentUrl(attachment.id),
              headers: ApiService.attachmentHeaders,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
              // Ein kaputtes Vorschaubild darf den Verlauf nicht sprengen –
              // lieber ein sichtbarer Platzhalter als eine rote Fehlerfläche.
              errorBuilder: (context, error, stack) => const Center(
                child: Icon(Icons.broken_image_outlined, color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFile(BuildContext context) {
    return Tooltip(
      message: '${attachment.fileName}\n${attachment.readableSize}\n'
          'Klicken zum Speichern',
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 190,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.lightGrey,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(attachment.fileName), size: 24, color: AppColors.navy),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      attachment.readableSize,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[600], fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Abgelaufener Anhang: Die Datei ist weg, der Vermerk bleibt. Sonst entstünde
  /// im Verlauf eine Lücke, bei der niemand mehr weiß, ob dort je etwas war.
  Widget _buildExpired(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 20, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[600]),
                ),
                Text(
                  'nach einem Jahr entfernt',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
      case 'odt':
      case 'rtf':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_outlined;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_outlined;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_outlined;
      case 'txt':
      case 'log':
      case 'md':
        return Icons.notes_outlined;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.movie_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}

/// Vollbildansicht eines Bildes – mit Zoom, denn genau dafür schickt man einen
/// Screenshot: um die kleine Schrift darauf lesen zu können.
Future<void> showAttachmentViewer(
  BuildContext context,
  SphereAttachment attachment, {
  VoidCallback? onSave,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${attachment.readableSize}'
                      '${attachment.uploadedByName != null ? ' · ${attachment.uploadedByName}' : ''}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Auch ein Bild will man manchmal behalten – etwa um es an einen
              // Fehlerbericht ausserhalb von OrgaSphere zu hängen.
              if (onSave != null)
                IconButton(
                  icon: const Icon(Icons.download_outlined, color: Colors.white),
                  tooltip: 'Speichern',
                  onPressed: onSave,
                ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Schließen',
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.network(
                ApiService.attachmentContentUrl(attachment.id),
                headers: ApiService.attachmentHeaders,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stack) => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Text(
                    'Das Bild konnte nicht geladen werden.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
