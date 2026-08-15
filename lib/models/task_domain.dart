import 'package:flutter/material.dart';

import '../utils/field_limits.dart';

class TaskDomain {
  final String id;
  final String name;
  final String description;
  final String colorHex;

  /// Einfache Liste im Stil einer Einkaufsliste. Positionen haben dann nur
  /// einen Titel – keine Beschreibung, Zuweisung, Wiederholung, Termine,
  /// Erinnerung oder Aktivitätsverlauf. Ein Klick setzt direkt auf „gelandet";
  /// gelandete Positionen löscht der Server nach 24 Stunden.
  ///
  /// Wird beim Anlegen des Orbits festgelegt und ist danach unveränderlich.
  final bool isShoppingList;

  /// Eigene Rolle in diesem Orbit: 'pilot' oder 'copilot'. Kommt aus
  /// GET /domains und steuert, welche Verwaltungsaktionen die App anbietet.
  ///
  /// Fallback 'pilot', falls das Feld fehlt (aelteres Backend): Dann sieht man
  /// wie bisher alle Aktionen. Das ist ungefaehrlich, denn die Rechte haengen
  /// nicht an diesem Feld – der Server lehnt unerlaubte Aufrufe ohnehin ab.
  final String myRole;

  /// Emoji, das in der Ansicht den farbigen Punkt ersetzt. `null` oder leer
  /// heißt: kein Symbol gesetzt, es bleibt beim Punkt.
  ///
  /// Die Farbe wird dadurch NICHT überflüssig – sie färbt auch die
  /// Sphere-Karten und bleibt deshalb in jedem Fall erhalten.
  final String? icon;

  /// Wie viele **gelandete** Ausgaben je Wiederholungsserie aufgehoben werden.
  /// Alles darüber hinaus löscht der Server, damit die Datenbank nicht
  /// unbegrenzt wächst.
  ///
  /// Anzahl statt Frist, weil eine Frist die Frequenzen ungleich trifft: Eine
  /// Sphere alle drei Tage sammelt in einem Jahr rund 120 Ausgaben an, eine
  /// jährliche hätte nie mehr als eine. Einmalige Spheres verschwinden
  /// stattdessen 365 Tage nach dem Erledigen.
  final int keepLandedCount;

  TaskDomain({
    required this.id,
    required this.name,
    required this.description,
    this.colorHex = '#F5F5F5',
    this.isShoppingList = false,
    this.myRole = 'pilot',
    this.icon,
    this.keepLandedCount = kDefaultKeepLandedCount,
  });

  /// Hat dieser Orbit ein Symbol? Leerer Text zählt wie keines.
  bool get hasIcon => icon != null && icon!.trim().isNotEmpty;

  /// Darf der angemeldete Nutzer diesen Orbit verwalten (umbenennen, loeschen,
  /// Co-Piloten einladen)?
  bool get isPilot => myRole == 'pilot';

  /// Kopie mit einzelnen geaenderten Feldern.
  ///
  /// Wichtig fuer die lokale Pflege nach einer Aenderung: Wird der Orbit von
  /// Hand neu zusammengesetzt, fallen leicht Felder unter den Tisch, die gerade
  /// nicht im Blick sind – [isShoppingList] etwa fiele auf `false` zurueck und
  /// ein Listen-Orbit verhielte sich bis zum naechsten Abgleich wie ein
  /// normaler.
  /// [clearIcon] löscht das Symbol – über `icon: null` ginge das nicht, weil
  /// null dort „unverändert" bedeutet.
  TaskDomain copyWith({
    String? name,
    String? description,
    String? colorHex,
    String? icon,
    bool clearIcon = false,
    int? keepLandedCount,
  }) {
    return TaskDomain(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      colorHex: colorHex ?? this.colorHex,
      isShoppingList: isShoppingList,
      myRole: myRole,
      icon: clearIcon ? null : (icon ?? this.icon),
      keepLandedCount: keepLandedCount ?? this.keepLandedCount,
    );
  }

  factory TaskDomain.fromJson(Map<String, dynamic> json) {
    // SQL Server liefert BIT je nach Treiber als bool oder als 0/1.
    final raw = json['isShoppingList'];
    return TaskDomain(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      colorHex: json['color'] as String? ?? '#F5F5F5',
      isShoppingList: raw == true || raw == 1,
      myRole: json['myRole'] as String? ?? 'pilot',
      icon: json['icon'] as String?,
      // Aelteres Backend liefert das Feld noch nicht – dann gilt die Vorgabe.
      keepLandedCount:
          (json['keepLandedCount'] as num?)?.toInt() ?? kDefaultKeepLandedCount,
    );
  }

  /// Fuer den lokalen Zwischenspeicher – Feldnamen wie in der Server-Antwort,
  /// damit [TaskDomain.fromJson] beide Quellen liest.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'color': colorHex,
        'isShoppingList': isShoppingList,
        'myRole': myRole,
        'icon': icon,
        'keepLandedCount': keepLandedCount,
      };

  Color get color {
    final hex = colorHex.replaceAll('#', '');
    return Color(int.parse('0xFF$hex'));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskDomain && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
