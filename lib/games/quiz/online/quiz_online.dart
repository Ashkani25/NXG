/// Online Quiz (2–4 real players, 10 questions). The server picks the questions, keeps the answer
/// key (table gm_quiz_bank, no client access), times every answer on its own clock and scores
/// 100 + up to 50 speed bonus. Moves: {a:'answer', c: 0..3}.
///
/// Wire state: round, total, qid, category, answered[], scores[], correct[], started (server ms),
/// reveal = {qid, answer, choices[], points[], ms[]} during phase 'reveal'.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'package:nexora/games/core/online/gm_models.dart';
import 'package:nexora/games/core/online/gm_widgets.dart';

import '../core/question_bank.dart';
import '../core/question_model.dart';
import '../ui/quiz_widgets.dart';

final Map<String, QuizQuestion> _byId = <String, QuizQuestion>{for (final QuizQuestion q in kQuestionBank) q.id: q};

QuizQuestion? quizQuestionById(String id) => _byId[id];

class QuizOnlineBoard extends StatefulWidget {
  const QuizOnlineBoard({super.key, required this.c});
  final GmMatchController c;

  @override
  State<QuizOnlineBoard> createState() => _QuizOnlineBoardState();
}

class _QuizOnlineBoardState extends State<QuizOnlineBoard> {
  /// my pick for (round key) — the server keeps choices secret until the reveal
  String _pickKey = '';
  int? _pick;

  GmMatchController get c => widget.c;

  Future<void> _answer(GmView v, int i) async {
    final String key = '${v.state['round']}:${v.state['qid']}';
    if (_pickKey == key) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pickKey = key;
      _pick = i;
    });
    final bool ok = await c.move(GmMove('answer', <String, dynamic>{'c': i}));
    if (!ok && mounted && c.error != null && !c.error!.contains('قبلاً') && !c.error!.contains('Already')) {
      setState(() => _pickKey = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final GmView v = c.view!;
    final bool reveal = v.phase == 'reveal';
    final Map<String, dynamic> rv = gmMap(v.state['reveal']);
    final String qid = reveal ? '${rv['qid'] ?? v.state['qid']}' : '${v.state['qid'] ?? ''}';
    final QuizQuestion? q = quizQuestionById(qid);
    final int round = gmInt(v.state['round']);
    final int total = gmInt(v.state['total'], 10);
    final List<bool> answered = gmBools(v.state['answered']);
    final List<int> scores = v.scores;
    final String key = '$round:$qid';
    final int? myPick = _pickKey == key ? _pick : null;
    final int? me = v.mySeat;
    final bool iAnswered = me != null && me < answered.length && answered[me];
    final List<int?> choices = gmIntsOrNull(rv['choices']);
    final List<int> points = gmInts(rv['points']);
    final int? answer = gmIntOrNull(rv['answer']);
    final int secs = (c.remaining.inMilliseconds / 1000).ceil();
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints bc) {
      final bool compact = bc.maxHeight < 560;
      return ListView(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: <Widget>[
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: <Widget>[
          for (int s = 0; s < v.seatCount; s++)
            QuizScoreChip(
              name: v.nameOf(s) + (s == me ? context.tx(' (تو)', ' (you)') : ''),
              score: s < scores.length ? scores[s] : 0,
              color: gmSeatColor(s),
              icon: s == me ? Icons.person_rounded : Icons.public_rounded,
              active: !reveal && s < answered.length && answered[s],
              status: v.isOut(s)
                  ? context.tx('خارج شد', 'left')
                  : reveal
                      ? (s < points.length && points[s] > 0 ? '+${gmNum(context, points[s])}' : context.tx('۰', '0'))
                      : (s < answered.length && answered[s] ? context.tx('جواب داد ✓', 'answered ✓') : context.tx('فکر می‌کند…', 'thinking…')),
              statusColor: reveal && s < points.length && points[s] > 0 ? NxColors.success : NxColors.textDim,
            ),
        ]),
        const SizedBox(height: 10),
        Center(
          child: QuizTimerRing(
            fraction: c.remainingFraction(Duration(seconds: reveal ? 4 : 15)),
            seconds: secs,
            size: compact ? 56 : 70,
          ),
        ),
        const SizedBox(height: 10),
        if (q == null)
          Center(child: Text(context.tx('در حال دریافت سؤال…', 'Loading question…')))
        else ...<Widget>[
          QuizQuestionCard(
            category: q.category,
            categoryLabel: context.isFa ? quizCategoryNameFa(q.category) : quizCategoryNameEn(q.category),
            roundLabel: context.tx('سؤال ${gmNum(context, round + 1)} از ${gmNum(context, total)}', 'Question ${round + 1} of $total'),
            text: context.isFa ? q.fa : q.en,
            compact: compact,
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: QuizAnswerButton(
                index: i,
                text: context.isFa ? q.optionsFa[i] : q.optionsEn[i],
                compact: compact,
                reveal: reveal ? 1 : 0,
                state: _optionState(reveal, i, answer, myPick, me, choices),
                markerIcon: reveal && _othersPicked(choices, me, i) ? Icons.group_rounded : null,
                onTap: !reveal && v.live && me != null && !iAnswered && myPick == null && !v.isOut(me) ? () => _answer(v, i) : null,
              ),
            ),
        ],
        if (!reveal && iAnswered)
          Center(child: Text(context.tx('منتظر بقیه…', 'Waiting for the others…'), style: const TextStyle(color: NxColors.textDim))),
      ]);
    });
  }

  QuizOptionState _optionState(bool reveal, int i, int? answer, int? myPick, int? me, List<int?> choices) {
    if (!reveal) {
      if (myPick == null) return QuizOptionState.idle;
      return myPick == i ? QuizOptionState.picked : QuizOptionState.dimmed;
    }
    final int? mine = me != null && me < choices.length ? choices[me] : myPick;
    if (i == answer) return QuizOptionState.correct;
    if (mine == i) return QuizOptionState.wrong;
    return QuizOptionState.dimmed;
  }

  bool _othersPicked(List<int?> choices, int? me, int i) {
    for (int s = 0; s < choices.length; s++) {
      if (s != me && choices[s] == i) return true;
    }
    return false;
  }
}

String? quizResultDetail(BuildContext context, GmView v) {
  final List<int> s = v.resultScores;
  if (s.isEmpty) return null;
  return s.asMap().entries.map((MapEntry<int, int> e) => '${v.nameOf(e.key)}: ${gmNum(context, e.value)}').join(context.isFa ? ' • ' : ' • ');
}
