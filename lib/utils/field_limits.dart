/// Zeichen-Obergrenzen aller Texteingaben der App.
///
/// Die Werte spiegeln exakt die Spaltenbreiten in `backend/db/schema.sql`.
/// Wird eine Spalte dort verbreitert, muss der Wert hier mitwandern – sonst
/// laeuft man wieder in die Falle, die zu diesen Konstanten gefuehrt hat: Ein
/// zu langer Text wurde ohne Vorwarnung abgeschickt, SQL Server antwortete mit
/// "String or binary data would be truncated", und der Nutzer sah nur, dass
/// Speichern nicht funktioniert.
///
/// Regel: Jedes Eingabefeld, das in eine dieser Spalten schreibt, bekommt
/// `maxLength` mit der passenden Konstante. Damit ist die Grenze schon beim
/// Tippen sichtbar (Zaehler) und ueberlanger Text kann gar nicht erst
/// abgeschickt werden. Das Backend prueft dieselben Grenzen noch einmal.
library;

import 'package:flutter/material.dart';

/// Task.title – Titel einer Sphere bzw. Name einer Listenposition.
const int kSphereTitleMaxLength = 200;

/// Task.description
const int kSphereDescriptionMaxLength = 1000;

/// TaskDomain.name – Name eines Orbits.
const int kOrbitNameMaxLength = 100;

/// TaskDomain.description
const int kOrbitDescriptionMaxLength = 500;

/// TaskLogEntry.text – Eintrag im Aktivitaetsverlauf.
const int kLogEntryMaxLength = 1000;

/// AppUser.displayName
const int kDisplayNameMaxLength = 200;

/// Anhaenge je Verlaufseintrag. Spiegelt ATTACHMENT_MAX_PER_ENTRY im Backend –
/// dort wird die Grenze noch einmal geprueft.
const int kMaxAttachmentsPerEntry = 5;

/// Groesse einer einzelnen Datei. Spiegelt ATTACHMENT_MAX_BYTES im Backend.
const int kMaxAttachmentBytes = 10 * 1024 * 1024;

/// Vorgabe fuer TaskDomain.keepLandedCount – so viele gelandete Ausgaben je
/// Wiederholungsserie bleiben erhalten. Spiegelt DEFAULT_KEEP_LANDED_COUNT im
/// Backend.
const int kDefaultKeepLandedCount = 20;

/// Grenzen fuer die Eingabe. Untergrenze 1, nicht 0: Bei 0 verschwaende auch
/// die zuletzt erledigte Ausgabe und damit die Antwort auf "wie haben wir das
/// letzte Mal gemacht?".
const int kMinKeepLandedCount = 1;
const int kMaxKeepLandedCount = 500;

/// Ab welchem Fuellstand [nearLimitCounter] den Zaehler einblendet.
const double _kCounterThreshold = 0.8;

/// Zaehler fuer schlanke Inline-Felder (Detailtitel, Schnell-Eingabe,
/// Dialoge): bleibt unsichtbar, solange reichlich Platz ist, und blendet
/// „180/200" erst ein, wenn es eng wird. So stoert er das Layout nicht,
/// warnt aber rechtzeitig.
///
/// Als `buildCounter` an ein [TextField] uebergeben. Gibt der Builder `null`
/// zurueck, zeigt Flutter gar keinen Zaehler an.
Widget? nearLimitCounter(
  BuildContext context, {
  required int currentLength,
  required int? maxLength,
  required bool isFocused,
}) {
  if (maxLength == null || currentLength < maxLength * _kCounterThreshold) {
    return null;
  }
  final isFull = currentLength >= maxLength;
  return Text(
    '$currentLength/$maxLength',
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: isFull ? Colors.red[700] : Colors.grey[700],
        ),
  );
}
