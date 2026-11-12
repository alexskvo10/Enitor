// Чистый Dart: группа «моих» устройств для синхронизации по сети.

/// Устройство группы. Знают его все устройства группы: список расходится
/// при каждом обмене, поэтому телефон, добавленный к ноутбуку, узнаёт и
/// планшет.
class LanMember {
  const LanMember({
    required this.id,
    required this.name,
    required this.fingerprint,
    required this.tokenHash,
    required this.updatedAt,
    this.revoked = false,
  });

  factory LanMember.fromJson(Map<String, dynamic> j) => LanMember(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        fingerprint: j['fp'] as String,
        tokenHash: j['th'] as String,
        updatedAt: DateTime.tryParse(j['at'] as String? ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        revoked: j['revoked'] == true,
      );

  final String id;
  final String name;

  /// Отпечаток TLS-сертификата: по нему соседи узнают это устройство.
  final String fingerprint;

  /// Хэш секрета, которым устройство подтверждает себя (сам секрет — только
  /// у него).
  final String tokenHash;
  final DateTime updatedAt;

  /// Отключено (потеряно). Насовсем: вернуться можно только новым
  /// знакомством с новыми ключами.
  final bool revoked;

  LanMember copyWith({String? name, bool? revoked, DateTime? updatedAt}) =>
      LanMember(
        id: id,
        name: name ?? this.name,
        fingerprint: fingerprint,
        tokenHash: tokenHash,
        updatedAt: updatedAt ?? this.updatedAt,
        revoked: revoked ?? this.revoked,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fp': fingerprint,
        'th': tokenHash,
        'at': updatedAt.toIso8601String(),
        if (revoked) 'revoked': true,
      };
}

/// Объединить два списка группы. Отключение побеждает всегда — иначе
/// украденное устройство вернуло бы себя своим старым списком. Устройство,
/// пришедшее с другими ключами под тем же id, не принимается: ключи меняет
/// только новое знакомство, а оно даёт новый id.
Map<String, LanMember> mergeLanGroups(
  Map<String, LanMember> a,
  Iterable<LanMember> b,
) {
  final out = Map<String, LanMember>.of(a);
  for (final m in b) {
    final cur = out[m.id];
    if (cur == null) {
      out[m.id] = m;
      continue;
    }
    if (cur.fingerprint != m.fingerprint || cur.tokenHash != m.tokenHash) {
      continue;
    }
    final newer = m.updatedAt.isAfter(cur.updatedAt) ? m : cur;
    out[m.id] = newer.copyWith(revoked: cur.revoked || m.revoked);
  }
  return out;
}

/// Чтение списка из сообщения соседа: битые записи пропускаем.
List<LanMember> lanMembersFromWire(Object? raw) => [
      for (final m in raw is List ? raw : const [])
        if (m is Map &&
            m['id'] is String &&
            m['fp'] is String &&
            m['th'] is String)
          LanMember.fromJson(m.cast<String, dynamic>()),
    ];
