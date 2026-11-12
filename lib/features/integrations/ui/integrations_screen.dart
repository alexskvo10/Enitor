import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import 'calendar_section.dart';
import 'permissions_section.dart';
import 'section_parts.dart';
import 'tasker_section.dart';
import 'webhooks_section.dart';
import 'windows_section.dart';

/// Настройки → Интеграции. Всё на этом экране работает только на этом
/// устройстве: никаких аккаунтов и нашего сервера — его нет.
class IntegrationsScreen extends StatelessWidget {
  const IntegrationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.integrationsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: [
          SectionNote(l10n.integrationsIntro),
          // Сверху — то, что нужно почти всем: календари. Синхронизация —
          // отдельный экран в Настройках: это не связь с другими программами.
          // Права стоят прямо над входами, которыми управляют (Tasker,
          // консоль, ассистенты); вебхуки — для тех, кто строит своё, внизу.
          const CalendarSection(),
          const PermissionsSection(),
          if (defaultTargetPlatform == TargetPlatform.android)
            const TaskerSection(),
          if (defaultTargetPlatform == TargetPlatform.windows) ...[
            const WindowsSection(),
            const AssistantsSection(),
          ],
          const WebhooksSection(),
        ],
      ),
    );
  }
}
