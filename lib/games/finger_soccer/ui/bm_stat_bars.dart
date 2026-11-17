// Power / Accuracy display for a disc: label, 10-segment bar and the number.
import 'package:flutter/material.dart';

import '../core/bm_stats.dart';

class BmStatBar extends StatelessWidget {
  const BmStatBar({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.track,
    required this.textColor,
    this.compact = false,
  });

  final String label;
  final int value;
  final Color color, track, textColor;

  /// Card size (tiny bar, no label column width).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final int v = value.clamp(kBmStatMin, kBmStatMax);
    final double seg = compact ? 2.8 : 9, gap = compact ? .8 : 2, h = compact ? 3 : 6;
    return Semantics(
      label: '$label $v/10',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: compact ? 18 : 58,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(color: textColor, fontSize: compact ? 6.5 : 10.5, fontWeight: FontWeight.w800)),
          ),
          for (int i = 0; i < 10; i++)
            Container(
              width: seg,
              height: h,
              margin: EdgeInsets.only(right: i == 9 ? 0 : gap),
              decoration: BoxDecoration(
                color: i < v ? color : track,
                borderRadius: BorderRadius.circular(compact ? 1 : 2),
              ),
            ),
          SizedBox(width: compact ? 2 : 6),
          Text('$v',
              style: TextStyle(color: textColor, fontSize: compact ? 7 : 11.5, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

/// Both stats of a disc, stacked.
class BmDiscStatBars extends StatelessWidget {
  const BmDiscStatBars({
    super.key,
    required this.discId,
    required this.powerLabel,
    required this.accuracyLabel,
    required this.powerColor,
    required this.accuracyColor,
    required this.track,
    required this.textColor,
    this.compact = false,
  });

  final String discId, powerLabel, accuracyLabel;
  final Color powerColor, accuracyColor, track, textColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final BmDiscStats s = bmDiscStats(discId);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        BmStatBar(
            label: powerLabel, value: s.power, color: powerColor, track: track, textColor: textColor, compact: compact),
        SizedBox(height: compact ? 1.5 : 4),
        BmStatBar(
            label: accuracyLabel,
            value: s.accuracy,
            color: accuracyColor,
            track: track,
            textColor: textColor,
            compact: compact),
      ],
    );
  }
}
