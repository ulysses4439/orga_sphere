import 'package:flutter/material.dart';

/// Domain or area for task grouping.
/// Examples: Verein, Arbeit, Privat.
class TaskDomain {
  final String id;
  final String name;
  final String description;
  final String colorHex;
  final String notificationEmails;

  TaskDomain({
    required this.id,
    required this.name,
    required this.description,
    this.colorHex = '#F5F5F5',
    this.notificationEmails = '',
  });

  factory TaskDomain.fromJson(Map<String, dynamic> json) {
    return TaskDomain(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      colorHex: json['color'] as String? ?? '#F5F5F5',
      notificationEmails: json['notificationEmails'] as String? ?? '',
    );
  }

  Color get color {
    final hex = colorHex.replaceAll('#', '');
    return Color(int.parse('0xFF$hex'));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskDomain &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
