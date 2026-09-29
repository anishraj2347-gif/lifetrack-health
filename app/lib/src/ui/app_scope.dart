import 'package:flutter/widgets.dart';

import '../app/app_services.dart';

/// Makes [AppServices] available to screens and lets any screen tell the
/// others that state changed (a grant revoked on Share must disappear from
/// Me's counts without a restart).
class AppScope extends InheritedNotifier<ValueNotifier<int>> {
  AppScope({super.key, required this.services, required super.child}) : super(notifier: ValueNotifier(0));

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  static void changed(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!.value++;
}
