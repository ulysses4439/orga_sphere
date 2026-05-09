class OrbitMember {
  final String id;
  final String orbitId;
  final String? userId;
  final String email;
  final String? displayName;
  final String role; // 'pilot' | 'copilot'
  final String status; // 'active' | 'suspended' | 'pending'
  final DateTime? invitedAt;
  final DateTime? joinedAt;

  const OrbitMember({
    required this.id,
    required this.orbitId,
    this.userId,
    required this.email,
    this.displayName,
    required this.role,
    required this.status,
    this.invitedAt,
    this.joinedAt,
  });

  String get displayLabel => displayName?.isNotEmpty == true ? displayName! : email;

  factory OrbitMember.fromJson(Map<String, dynamic> json) {
    return OrbitMember(
      id: json['id'] as String,
      orbitId: json['orbitId'] as String,
      userId: json['userId'] as String?,
      email: json['email'] as String,
      displayName: json['displayName'] as String?,
      role: json['role'] as String,
      status: json['status'] as String,
      invitedAt: json['invitedAt'] != null
          ? DateTime.parse(json['invitedAt'] as String)
          : null,
      joinedAt: json['joinedAt'] != null
          ? DateTime.parse(json['joinedAt'] as String)
          : null,
    );
  }

  bool get isPilot => role == 'pilot';
  bool get isPending => status == 'pending';
  bool get isSuspended => status == 'suspended';
}
