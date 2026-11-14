// Loadout pickers — port of the Godot build's src/game/formation_picker.gd (9 formations drawn as
// mini pitches with the player's disc art, «انتخاب» / «انتخاب شده») plus the NxLoadout disc / ball /
// field choices used by the setup panel and the in-match loadout sheet. Only items that are free in
// the Godot catalogue are offered (club + national discs, balls 0-5, fields 0-4): no fake shop.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/data.dart';
import 'df_images.dart';

typedef DfTx = String Function(String fa, String en);

/// Mini pitch of one formation: own half (own goal at the bottom, halfway line at the top), stripes,
/// markings and the discs (same mapping as the engine).
class DfFormationThumb extends StatelessWidget {
  const DfFormationThumb({super.key, required this.formation, required this.selected, this.discAsset});
  final int formation;
  final bool selected;
  final String? discAsset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final double w = c.maxWidth;
      final double h = c.maxHeight;
      const double m = 6.0;
      final double dr = w * 0.085;
      final List<Widget> discs = <Widget>[];
      for (final List<double> pt in kForms[formation].pts) {
        final double x = m + dr + pt[1] * (w - 2 * (m + dr));
        double y = (h - m) - (0.045 + pt[0] * 0.40) * 2.0 * (h - 2 * m);
        y = y.clamp(m + dr, h - m - dr).toDouble();
        discs.add(Positioned(
          left: x - dr - 2,
          top: y - dr - 2,
          width: 2 * dr + 4,
          height: 2 * dr + 4,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? const Color(0xFF66EBFF) : const Color(0xE6D9E6FF),
              boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x59000000), offset: Offset(0, 2), blurRadius: 2)],
            ),
            padding: const EdgeInsets.all(2),
            child: ClipOval(
              child: discAsset == null
                  ? const ColoredBox(color: Color(0xFF0D1A3A))
                  : Image.asset(discAsset!, fit: BoxFit.cover, cacheWidth: 96, errorBuilder: _err),
            ),
          ),
        ));
      }
      return Stack(children: <Widget>[
        Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
        ...discs,
      ]);
    });
  }

  static Widget _err(BuildContext c, Object e, StackTrace? s) => const ColoredBox(color: Color(0xFF0D1A3A));
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size size) {
    final double w = size.width, h = size.height;
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)), Paint()..color = const Color(0xFF1F7A34));
    const int n = 6;
    for (int k = 1; k < n; k += 2) {
      c.drawRect(Rect.fromLTWH(4, h * k / n, w - 8, h / n), Paint()..color = const Color(0x0FFFFFFF));
    }
    final Paint lc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xBFFFFFFF);
    const double m = 6.0;
    c.drawRect(Rect.fromLTWH(m, m, w - 2 * m, h - 2 * m), lc);
    c.drawArc(Rect.fromCircle(center: Offset(w * 0.5, m), radius: w * 0.16), 0, math.pi, false, lc);
    final double bw = w * 0.56, bh = h * 0.2;
    c.drawRect(Rect.fromLTWH((w - bw) * 0.5, h - m - bh, bw, bh), lc);
    c.drawRect(Rect.fromLTWH((w - w * 0.28) * 0.5, h - m - bh * 0.42, w * 0.28, bh * 0.42), lc);
    c.drawRect(Rect.fromLTWH((w - w * 0.3) * 0.5, h - m + 1, w * 0.3, m - 2), Paint()..color = const Color(0xE6FFFFFF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Card extends StatelessWidget {
  const _Card({required this.selected, required this.child, required this.onTap});
  final bool selected;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected ? const Color(0x2438D6FF) : const Color(0xD9080C22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? const Color(0xFF66EBFF) : const Color(0x1FFFFFFF), width: selected ? 2 : 1),
          boxShadow: <BoxShadow>[
            BoxShadow(color: selected ? const Color(0x7338D6FF) : const Color(0x59000000), blurRadius: selected ? 14 : 6),
          ],
        ),
        child: child,
      ),
    );
  }
}

Widget _selButton(bool on, DfTx tx, VoidCallback onTap) {
  return GestureDetector(
    onTap: on ? null : onTap,
    child: Container(
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? const Color(0xFF1FB85A) : const Color(0xFF2A6CFF),
        borderRadius: BorderRadius.circular(15),
        border: Border(top: BorderSide(color: on ? const Color(0xFF7DFFB0) : const Color(0x59FFFFFF), width: 1.5)),
      ),
      child: Text(on ? tx('انتخاب شده', 'Selected') : tx('انتخاب', 'Select'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
    ),
  );
}

/// 3-column grid of the 9 formations.
class DfFormationGrid extends StatelessWidget {
  const DfFormationGrid({super.key, required this.selected, required this.onPick, required this.tx, this.discAsset});
  final int selected;
  final ValueChanged<int> onPick;
  final DfTx tx;
  final String? discAsset;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.62),
      itemCount: kForms.length,
      itemBuilder: (BuildContext context, int i) {
        final bool on = i == selected;
        return _Card(
          selected: on,
          onTap: () => onPick(i),
          child: Column(children: <Widget>[
            Expanded(child: DfFormationThumb(formation: i, selected: on, discAsset: discAsset)),
            const SizedBox(height: 6),
            Text(tx(kForms[i].nameFa, kForms[i].nameEn),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            _selButton(on, tx, () => onPick(i)),
          ]),
        );
      },
    );
  }
}

/// Free discs (club + national) as round art.
class DfDiscGrid extends StatelessWidget {
  const DfDiscGrid({super.key, required this.selected, required this.onPick});
  final String selected;
  final ValueChanged<String> onPick;

  static List<Team> freeDiscs() => <Team>[
        for (final Team t in kTeams)
          if (teamPrice(t) == 0 && (t.cat == 'club' || t.cat == 'nat')) t,
      ];

  @override
  Widget build(BuildContext context) {
    final List<Team> list = freeDiscs();
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.78),
      itemCount: list.length,
      itemBuilder: (BuildContext context, int i) {
        final Team t = list[i];
        final bool on = t.id == selected;
        return _Card(
          selected: on,
          onTap: () => onPick(t.id),
          child: Column(children: <Widget>[
            Expanded(
              child: ClipOval(
                child: Image.asset(DfArt.team(t.id), fit: BoxFit.cover, cacheWidth: 128, errorBuilder: DfFormationThumb._err),
              ),
            ),
            const SizedBox(height: 4),
            Text(t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ]),
        );
      },
    );
  }
}

/// Free balls (price 0 in the Godot shop).
class DfBallGrid extends StatelessWidget {
  const DfBallGrid({super.key, required this.selected, required this.onPick});
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final List<int> list = <int>[
      for (int i = 0; i < kBallCount; i++)
        if (ballPrice(i) == 0) i,
    ];
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.85),
      itemCount: list.length,
      itemBuilder: (BuildContext context, int k) {
        final int i = list[k];
        return _Card(
          selected: i == selected,
          onTap: () => onPick(i),
          child: Column(children: <Widget>[
            Expanded(child: Image.asset(DfArt.ball(i), cacheWidth: 160, errorBuilder: DfFormationThumb._err)),
            const SizedBox(height: 4),
            Text(kBallNames[i], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        );
      },
    );
  }
}

/// Free pitches (price 0 in the Godot shop).
class DfFieldGrid extends StatelessWidget {
  const DfFieldGrid({super.key, required this.selected, required this.onPick});
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final List<int> list = <int>[
      for (int i = 0; i < kFields.length; i++)
        if (fieldPrice(i) == 0) i,
    ];
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.62),
      itemCount: list.length,
      itemBuilder: (BuildContext context, int k) {
        final int i = list[k];
        return _Card(
          selected: i == selected,
          onTap: () => onPick(i),
          child: Column(children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(DfArt.fieldThumb(i), fit: BoxFit.cover, cacheWidth: 220, errorBuilder: DfFormationThumb._err),
              ),
            ),
            const SizedBox(height: 4),
            Text(kFields[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        );
      },
    );
  }
}

/// What a loadout sheet may change.
class DfLoadout {
  DfLoadout({required this.form, required this.team, required this.ball, required this.field});
  int form;
  String team;
  int ball;
  int field;
}

/// Bottom sheet with tabs: formation · disc · ball (· pitch when [withField]). Calls [onChange] on every
/// pick (the in-match sheet swaps skins right away; the formation applies at the next kickoff).
Future<void> showDfLoadout(
  BuildContext context, {
  required DfLoadout value,
  required DfTx tx,
  required VoidCallback onChange,
  bool withField = false,
  String? note,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => _LoadoutSheet(value: value, tx: tx, onChange: onChange, withField: withField, note: note),
  );
}

class _LoadoutSheet extends StatefulWidget {
  const _LoadoutSheet({required this.value, required this.tx, required this.onChange, required this.withField, this.note});
  final DfLoadout value;
  final DfTx tx;
  final VoidCallback onChange;
  final bool withField;
  final String? note;

  @override
  State<_LoadoutSheet> createState() => _LoadoutSheetState();
}

class _LoadoutSheetState extends State<_LoadoutSheet> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final DfTx tx = widget.tx;
    final DfLoadout v = widget.value;
    final List<String> tabs = <String>[
      tx('ترکیب', 'Formation'),
      tx('مهره', 'Disc'),
      tx('توپ', 'Ball'),
      if (widget.withField) tx('زمین', 'Pitch'),
    ];
    Widget body;
    switch (_tab) {
      case 1:
        body = DfDiscGrid(selected: v.team, onPick: (String id) => _set(() => v.team = id));
        break;
      case 2:
        body = DfBallGrid(selected: v.ball, onPick: (int i) => _set(() => v.ball = i));
        break;
      case 3:
        body = DfFieldGrid(selected: v.field, onPick: (int i) => _set(() => v.field = i));
        break;
      default:
        body = DfFormationGrid(selected: v.form, tx: tx, discAsset: DfArt.team(v.team), onPick: (int i) => _set(() => v.form = i));
    }
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Color(0xF2070B1F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: Color(0x6639D5FF), width: 1.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(children: <Widget>[
          const SizedBox(height: 10),
          Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0x55FFFFFF), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 10),
          Text(tx('ترکیب، توپ و مهره', 'Formation, ball & disc'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          if (widget.note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: Text(widget.note!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF8EA3D6), fontSize: 12)),
            ),
          const SizedBox(height: 10),
          DfSegmented(labels: tabs, index: _tab, onChanged: (int i) => setState(() => _tab = i)),
          const SizedBox(height: 6),
          Expanded(child: body),
        ]),
      ),
    );
  }

  void _set(VoidCallback f) {
    setState(f);
    widget.onChange();
  }
}

/// Segmented tab row (Kit.tabs look: glass track, glowing selected pill).
class DfSegmented extends StatelessWidget {
  const DfSegmented({super.key, required this.labels, required this.index, required this.onChanged, this.color = const Color(0xFF39D5FF)});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xB3050816),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(children: <Widget>[
        for (int i = 0; i < labels.length; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == index ? color.withValues(alpha: 0.85) : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: i == index ? <BoxShadow>[BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 12)] : null,
                ),
                child: Text(labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: i == index ? Colors.white : const Color(0xFF8EA3D6), fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ),
      ]),
    );
  }
}
