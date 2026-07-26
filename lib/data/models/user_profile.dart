class UserProfile {
  const UserProfile({
    required this.startedAt,
    required this.updatedAt,
    this.userId,
    this.email,
    this.displayName,
    this.lastWeekAvgProductivity,
    this.lastWeekOnTimeAverage,
    this.lastWeekResetAt,
  });

  final String? userId;
  final String? email;
  final String? displayName;
  final DateTime startedAt;

  /// Снимок средней продуктивности на начало текущей недели (= значение конца
  /// прошлой недели). База для расчёта недельной дельты.
  final double? lastWeekAvgProductivity;

  /// Снимок средней своевременности на начало текущей недели.
  final double? lastWeekOnTimeAverage;

  /// Понедельник недели, к началу которой относятся снимки выше.
  final DateTime? lastWeekResetAt;
  final DateTime updatedAt;

  UserProfile copyWith({
    String? userId,
    String? email,
    String? displayName,
    double? lastWeekAvgProductivity,
    double? lastWeekOnTimeAverage,
    DateTime? lastWeekResetAt,
    DateTime? updatedAt,
  }) =>
      UserProfile(
        userId: userId ?? this.userId,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        startedAt: startedAt,
        lastWeekAvgProductivity:
            lastWeekAvgProductivity ?? this.lastWeekAvgProductivity,
        lastWeekOnTimeAverage:
            lastWeekOnTimeAverage ?? this.lastWeekOnTimeAverage,
        lastWeekResetAt: lastWeekResetAt ?? this.lastWeekResetAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'email': email,
        'displayName': displayName,
        'startedAt': startedAt.toIso8601String(),
        'lastWeekAvgProductivity': lastWeekAvgProductivity,
        'lastWeekOnTimeAverage': lastWeekOnTimeAverage,
        'lastWeekResetAt': lastWeekResetAt?.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        userId: j['userId'] as String?,
        email: j['email'] as String?,
        displayName: j['displayName'] as String?,
        startedAt: DateTime.parse(j['startedAt'] as String),
        lastWeekAvgProductivity: j['lastWeekAvgProductivity'] as double?,
        lastWeekOnTimeAverage: j['lastWeekOnTimeAverage'] as double?,
        lastWeekResetAt: j['lastWeekResetAt'] == null
            ? null
            : DateTime.parse(j['lastWeekResetAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );
}
