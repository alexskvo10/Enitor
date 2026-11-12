import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import 'lan_section.dart';
import 'section_parts.dart';
import 'server_section.dart';

/// Настройки → Синхронизация: «мои задачи на всех моих устройствах». Сверху
/// — напрямую по сети (нужно почти всем), ниже — свой сервер (через
/// интернет, для тех, у кого он есть).
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncTitle)),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: [
          SectionNote(l10n.syncIntro),
          const LanSection(),
          const ServerSection(),
        ],
      ),
    );
  }
}
