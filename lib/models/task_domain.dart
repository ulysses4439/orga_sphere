import 'package:flutter/material.dart';

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

  TaskDomain({
    required this.id,
    required this.name,
    required this.description,
    this.colorHex = '#F5F5F5',
    this.isShoppingList = false,
    this.myRole = 'pilot',
  });

  /// Darf der angemeldete Nutzer diesen Orbit verwalten (umbenennen, loeschen,
  /// Co-Piloten einladen)?
  bool get isPilot => myRole == 'pilot';

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
    );
  }

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
