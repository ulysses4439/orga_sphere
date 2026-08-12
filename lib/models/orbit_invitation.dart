import 'package:flutter/material.dart';

/// Eine offene Einladung in einen Orbit – also eine Mitgliedschaft, die noch
/// nicht angenommen wurde. Kommt von GET /invitations.
///
/// Solange die Einladung offen ist, hat man KEINEN Zugriff auf den Orbit: Er
/// taucht weder in der Orbit-Liste auf, noch kommen Erinnerungen oder
/// Team-Meldungen daraus an. Erst das Annehmen macht daraus eine
/// Mitgliedschaft.
class OrbitInvitation {
  final String id;
  final String orbitId;
  final String orbitName;
  final String orbitColorHex;

  /// Name des Piloten, der eingeladen hat – oder `null`, wenn er sich nicht
  /// ermitteln laesst.
  final String? pilotName;

  final DateTime? invitedAt;

  const OrbitInvitation({
    required this.id,
    required this.orbitId,
    required this.orbitName,
    this.orbitColorHex = '#F5F5F5',
    this.pilotName,
    this.invitedAt,
  });

  factory OrbitInvitation.fromJson(Map<String, dynamic> json) {
    return OrbitInvitation(
      id: json['id'] as String,
      orbitId: json['orbitId'] as String,
      orbitName: json['orbitName'] as String? ?? 'Orbit',
      orbitColorHex: json['orbitColor'] as String? ?? '#F5F5F5',
      pilotName: json['pilotName'] as String?,
      invitedAt: json['invitedAt'] != null
          ? DateTime.parse(json['invitedAt'] as String)
          : null,
    );
  }

  Color get orbitColor {
    final hex = orbitColorHex.replaceAll('#', '');
    return Color(int.parse('0xFF$hex'));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrbitInvitation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
