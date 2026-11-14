import 'package:flutter/material.dart';

import 'package:nexora/core/assets/app_assets.dart';

/// Shared widgets for the NEXORA game art pack v2 (assets/games/kit_v2/**).
/// Every image has a procedural fallback so a missing/corrupt asset never
/// breaks a game.

/// An asset image that draws [fallback] if the file cannot be decoded.
class KitImage extends StatelessWidget {
  const KitImage(
    this.asset, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.cacheWidth,
    this.fallback,
    this.opacity = 1,
  });

  final String asset;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget? fallback;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final Widget img = Image.asset(
      asset,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
          fallback ?? SizedBox(width: width, height: height),
    );
    if (opacity >= 1) return img;
    return Opacity(opacity: opacity, child: img);
  }
}

/// Full-screen game-room backdrop (bg_room) with a darkening veil so boards
/// and HUD stay readable. Falls back to a cosmic gradient.
class KitRoomBackground extends StatelessWidget {
  const KitRoomBackground({super.key, this.tint, this.veil = 0.35});

  /// Optional colour wash over the room (e.g. a game's accent).
  final Color? tint;

  /// 0..1 darkness of the readability veil.
  final double veil;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFF140A3A), Color(0xFF07051A), Color(0xFF02020A)],
            ),
          ),
        ),
        Image.asset(
          AppAssets.kitV2BackgroundsBgRoom,
          fit: BoxFit.cover,
          cacheWidth: 1024,
          filterQuality: FilterQuality.medium,
          errorBuilder: (BuildContext c, Object e, StackTrace? s) => const SizedBox.shrink(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: veil * 0.6),
                (tint ?? Colors.black).withValues(alpha: veil * 0.5),
                Colors.black.withValues(alpha: veil),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A round avatar inside the kit avatar ring (cyan/violet), with an
/// initial or a custom [child] in the middle.
class KitAvatar extends StatelessWidget {
  const KitAvatar({
    super.key,
    required this.label,
    this.size = 48,
    this.violet = false,
    this.color = const Color(0xFF2EE6D6),
    this.child,
  });

  final String label;
  final double size;
  final bool violet;
  final Color color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final String initial = label.trim().isEmpty ? '?' : label.trim().characters.first.toUpperCase();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: size * 0.62,
            height: size * 0.62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[color.withValues(alpha: 0.55), const Color(0xFF0A0B22)],
              ),
            ),
            child: child ??
                Text(
                  initial,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: size * 0.28,
                  ),
                ),
          ),
          IgnorePointer(
            child: KitImage(
              violet ? AppAssets.kitV2FramesAvatarRingViolet : AppAssets.kitV2FramesAvatarRingCyan,
              width: size,
              height: size,
              cacheWidth: 192,
              fallback: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Player HUD card following the kit mockups: avatar ring, name, one score
/// line, an active glow and an optional turn timer (0..1, null = hidden).
class KitPlayerHud extends StatelessWidget {
  const KitPlayerHud({
    super.key,
    required this.name,
    required this.subtitle,
    required this.active,
    this.accent = const Color(0xFF2EE6D6),
    this.violet = false,
    this.timer,
    this.leading,
    this.trailing,
    this.reducedMotion = false,
    this.compact = false,
  });

  final String name;
  final String subtitle;
  final bool active;
  final Color accent;
  final bool violet;
  final double? timer;
  final Widget? leading;
  final Widget? trailing;
  final bool reducedMotion;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double av = compact ? 38 : 48;
    final Duration dur = Duration(milliseconds: reducedMotion ? 0 : 260);
    return AnimatedContainer(
      duration: dur,
      padding: EdgeInsets.fromLTRB(6, compact ? 4 : 6, 10, compact ? 4 : 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: <Color>[
            const Color(0xCC0B0A2A),
            active ? accent.withValues(alpha: 0.22) : const Color(0xB3120D33),
          ],
        ),
        border: Border.all(
          color: active ? accent : const Color(0x557B5CFF),
          width: active ? 1.8 : 1.1,
        ),
        boxShadow: active && !reducedMotion
            ? <BoxShadow>[BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 16)]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              KitAvatar(label: name, size: av, violet: violet, color: accent, child: leading),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFFEAF6FF),
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 12 : 13,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? accent : const Color(0xB3EAF6FF),
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (timer != null) ...<Widget>[
            const SizedBox(height: 4),
            KitTimerBar(value: timer!, color: accent),
          ],
        ],
      ),
    );
  }
}

/// Thin glowing timer/progress bar (value 0..1).
class KitTimerBar extends StatelessWidget {
  const KitTimerBar({super.key, required this.value, this.color = const Color(0xFF2EE6D6)});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double v = value.clamp(0.0, 1.0);
    final Color c = v < 0.25 ? const Color(0xFFFF4D6D) : color;
    return Container(
      height: 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: const Color(0x66000000),
        border: Border.all(color: const Color(0x407B5CFF), width: 0.8),
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: v,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(colors: <Color>[c.withValues(alpha: 0.7), c]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A kit orb button (gem frame + icon). Only built for actions that exist.
class KitOrbButton extends StatelessWidget {
  const KitOrbButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.orb = AppAssets.kitV2ButtonsOrbCyan,
    this.size = 52,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final String orb;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              KitImage(
                orb,
                width: size,
                height: size,
                cacheWidth: 160,
                fallback: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF14123A),
                    border: Border.fromBorderSide(BorderSide(color: Color(0xFF2EE6D6), width: 2)),
                  ),
                ),
              ),
              Container(
                width: size * 0.5,
                height: size * 0.5,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x88000000)),
                child: Icon(icon, color: Colors.white, size: size * 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom action bar from the mockups (chat / surrender / mic). A button is
/// shown only when its callback is non-null; with none it collapses to zero
/// size, so games pass only actions that really exist.
class KitBottomBar extends StatelessWidget {
  const KitBottomBar({
    super.key,
    required this.isFa,
    this.onChat,
    this.onSurrender,
    this.onMic,
    this.micOn = false,
    this.center,
  });

  final bool isFa;
  final VoidCallback? onChat;
  final VoidCallback? onSurrender;
  final VoidCallback? onMic;
  final bool micOn;

  /// Optional central widget (e.g. a ROLL button).
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final List<Widget> kids = <Widget>[];
    if (onChat != null) {
      kids.add(KitOrbButton(
          icon: Icons.chat_bubble_rounded, onTap: onChat!, tooltip: isFa ? 'گفتگو' : 'Chat'));
    }
    if (onSurrender != null) {
      kids.add(KitOrbButton(
          icon: Icons.flag_rounded,
          onTap: onSurrender!,
          tooltip: isFa ? 'تسلیم' : 'Surrender',
          orb: AppAssets.kitV2ButtonsOrbOrange));
    }
    if (center != null) kids.add(center!);
    if (onMic != null) {
      kids.add(KitOrbButton(
          icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
          onTap: onMic!,
          tooltip: isFa ? 'میکروفون' : 'Mic',
          orb: micOn ? AppAssets.kitV2ButtonsOrbGreen : AppAssets.kitV2ButtonsOrbGray));
    }
    if (kids.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: kids),
    );
  }
}

/// Pill call-to-action (e.g. ROLL) on the kit pill art.
class KitPillButton extends StatelessWidget {
  const KitPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.violet = false,
    this.width = 170,
    this.height = 52,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final bool violet;
  final double width;
  final double height;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Positioned.fill(
                child: KitImage(
                  violet ? AppAssets.kitV2ButtonsPillViolet : AppAssets.kitV2ButtonsPillPink,
                  fit: BoxFit.fill,
                  cacheWidth: 400,
                  fallback: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(height / 2),
                      gradient: LinearGradient(
                        colors: violet
                            ? const <Color>[Color(0xFF6B3BFF), Color(0xFF9B5CFF)]
                            : const <Color>[Color(0xFFE0379A), Color(0xFFFF5CC8)],
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: height * 0.36,
                  letterSpacing: 1,
                  shadows: const <Shadow>[Shadow(color: Color(0xAA000000), blurRadius: 6)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Die face from the kit (blue glass set by default, slate set with [slate]).
/// Falls back to [fallback] (typically the game's procedural face).
class KitDieFace extends StatelessWidget {
  const KitDieFace({
    super.key,
    required this.value,
    required this.size,
    this.slate = false,
    this.fallback,
  });

  final int value;
  final double size;
  final bool slate;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return KitImage(
      slate ? AppAssets.kitV2DieSlate(value) : AppAssets.kitV2DieBlue(value),
      width: size,
      height: size,
      cacheWidth: 192,
      fallback: fallback,
    );
  }
}
