import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Действие «создать» для текущей активной вкладки: на «Сегодня» — новая
/// задача, на «Цели» — новая цель. Активный экран регистрирует своё действие
/// (в [State.initState] через post-frame), а глобальный Ctrl+N его вызывает.
///
/// Колбэк сам проверяет `mounted`, поэтому устаревшее действие неактивной
/// (уже размонтированной) вкладки — тихий no-op; чистить провайдер не нужно.
final createActionProvider = StateProvider<VoidCallback?>((ref) => null);
