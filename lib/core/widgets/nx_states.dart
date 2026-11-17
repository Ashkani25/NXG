import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../theme/nx_theme.dart';

/// Shared empty / loading / error states for every list page (UI audit M1).
/// One look everywhere: centred icon, one short line, at most one action. Cheap: no blur, no per-frame work
/// except the platform progress indicator while loading.

class NxLoadingState extends StatelessWidget {
  const NxLoadingState({super.key, this.message});

  /// Optional short line under the spinner.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors v = NxThemeColors.of(context);
    return Semantics(
      liveRegion: true,
      label: message ?? context.tx('در حال بارگذاری', 'Loading'),
      child: Padding(
        padding: const EdgeInsets.all(NxSpace.xl),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3)),
            if (message != null) ...<Widget>[
              const SizedBox(height: NxSpace.sm),
              Text(message!, textAlign: TextAlign.center, style: TextStyle(color: v.muted, fontSize: 13)),
            ],
          ]),
        ),
      ),
    );
  }
}

class NxEmptyState extends StatelessWidget {
  const NxEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_rounded,
    this.title,
    this.action,
    this.onRetry,
    this.leading,
  });

  final String message;
  final IconData icon;
  final String? title;

  /// A custom action (e.g. "Create the first one"). Takes precedence over [onRetry].
  final Widget? action;

  /// Shows a "Refresh" text button when set and [action] is null.
  final Future<void> Function()? onRetry;

  /// Replaces the icon (e.g. ORACLE art in social pages).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return _NxStateBody(
      leading: leading ?? _StateIcon(icon: icon, color: NxThemeColors.of(context).accent),
      title: title,
      message: message,
      action: action ??
          (onRetry == null
              ? null
              : TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.tx('تازه‌سازی', 'Refresh')),
                )),
    );
  }
}

class NxErrorState extends StatelessWidget {
  const NxErrorState({super.key, required this.message, this.onRetry, this.icon = Icons.wifi_off_rounded});

  final String message;
  final Future<void> Function()? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: _NxStateBody(
        leading: _StateIcon(icon: icon, color: NxColors.danger),
        message: message,
        action: onRetry == null
            ? null
            : FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.tx('تلاش دوباره', 'Try again')),
              ),
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Icon(icon, size: 34, color: color),
    );
  }
}

class _NxStateBody extends StatelessWidget {
  const _NxStateBody({required this.leading, required this.message, this.title, this.action});
  final Widget leading;
  final String? title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors v = NxThemeColors.of(context);
    return Center(
      // No scrollable here: these states are also placed inside ListViews (unbounded height).
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NxSpace.lg, vertical: NxSpace.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            leading,
            const SizedBox(height: NxSpace.md),
            if (title != null) ...<Widget>[
              Text(title!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: v.text, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: NxSpace.xs),
            ],
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: v.muted, fontSize: 13.5, height: 1.5)),
            if (action != null) ...<Widget>[const SizedBox(height: NxSpace.md), action!],
          ]),
        ),
      ),
    );
  }
}
