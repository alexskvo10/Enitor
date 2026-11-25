class UserProfile {
  const UserProfile({
    required this.startedAt,
    required this.updatedAt,
    this.userId,
    this.email,
    this.displayName,
  });

  final String? userId;
  final String? email;
  final String? displayName;
  final DateTime startedAt;
  final DateTime updatedAt;

  UserProfile copyWith({
    String? userId,
    String? email,
    String? displayName,
    DateTime? updatedAt,
  }) =>
      UserProfile(
        userId: userId ?? this.userId,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        startedAt: startedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'email': email,
        'displayName': displayName,
        'startedAt': startedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        userId: j['userId'] as String?,
        email: j['email'] as String?,
        displayName: j['displayName'] as String?,
        startedAt: DateTime.parse(j['startedAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );
}
