-- NEXORA online games: server rules for the turn-based arcade games (+ hooks for host-authoritative ones).
-- Each game <g> provides _gm_<g>_init(gs, settings), _gm_<g>_move(gs, seat, move), _gm_<g>_tick(gs),
-- _gm_<g>_resign(gs, seat). The server rolls every die and deals every card; clients only send intents.
-- Rules mirror the pure-Dart cores in lib/games/<g>/core (same board indices, card ids, scoring).

-- small helpers ---------------------------------------------------------------------------------
create or replace function public._gm_ints(j jsonb) returns int[] language sql immutable as $$
  select coalesce((select array_agg(x::int order by o) from jsonb_array_elements_text(coalesce(j, '[]'::jsonb)) with ordinality t(x, o)), '{}') $$;

-- remove the first occurrence of v
create or replace function public._gm_remove1(a int[], v int) returns int[] language plpgsql immutable as $$
declare i int; begin
  i := array_position(a, v);
  if i is null then return a; end if;
  return a[1:i - 1] || a[i + 1:array_length(a, 1)]; end $$;

-- ================================ BACKGAMMON ======================================================
-- Board b int[28]: b[i+1] = point i (0..23, + = seat 0, - = seat 1), b[25]/b[26] = bar of seat 0/1,
-- b[27]/b[28] = borne off of seat 0/1. Seat 0 moves 23 -> 0 (home 0..5), seat 1 moves 0 -> 23.
-- Moves use from = -1 for the bar and to = -2 for bearing off (kBgBar / kBgOff in backgammon_rules.dart).
create or replace function public._gm_bg_own(b int[], p int, i int) returns int language sql immutable as $$
  select case when p = 0 then greatest(b[i + 1], 0) else greatest(-b[i + 1], 0) end $$;

create or replace function public._gm_bg_rel(p int, i int) returns int language sql immutable as $$
  select case when p = 0 then i + 1 else 24 - i end $$;

create or replace function public._gm_bg_allhome(b int[], p int) returns boolean language sql immutable as $$
  select b[25 + p] = 0 and b[27 + p] + (select coalesce(sum(_gm_bg_own(b, p, i)), 0) from generate_series(0, 23) i
                                          where _gm_bg_rel(p, i) <= 6) = 15 $$;

create or replace function public._gm_bg_moves(b int[], p int, die int) returns table(fr int, t int)
language plpgsql immutable as $$
declare i int; pos int; tgt int; dest int; higher boolean; q int; begin
  if b[25 + p] > 0 then
    dest := case when p = 0 then 24 - die else die - 1 end;
    if _gm_bg_own(b, 1 - p, dest) < 2 then fr := -1; t := dest; return next; end if;
    return;
  end if;
  for i in 0..23 loop
    if _gm_bg_own(b, p, i) = 0 then continue; end if;
    pos := _gm_bg_rel(p, i);
    tgt := pos - die;
    if tgt >= 1 then
      dest := case when p = 0 then i - die else i + die end;
      if _gm_bg_own(b, 1 - p, dest) < 2 then fr := i; t := dest; return next; end if;
    elsif _gm_bg_allhome(b, p) then
      higher := false;
      for q in pos + 1 .. 6 loop
        if _gm_bg_own(b, p, case when p = 0 then q - 1 else 24 - q end) > 0 then higher := true; end if;
      end loop;
      if tgt = 0 or not higher then fr := i; t := -2; return next; end if;
    end if;
  end loop;
end $$;

create or replace function public._gm_bg_apply(b int[], p int, fr int, t int) returns int[]
language plpgsql immutable as $$
declare sg int := case when p = 0 then 1 else -1 end; begin
  if fr = -1 then b[25 + p] := b[25 + p] - 1; else b[fr + 1] := b[fr + 1] - sg; end if;
  if t = -2 then b[27 + p] := b[27 + p] + 1; return b; end if;
  if _gm_bg_own(b, 1 - p, t) = 1 then b[t + 1] := 0; b[26 - p] := b[26 - p] + 1; end if;
  b[t + 1] := b[t + 1] + sg;
  return b; end $$;

create or replace function public._gm_bg_expand(d int[]) returns int[] language sql immutable as $$
  select case when array_length(d, 1) = 2 and d[1] = d[2] then array[d[1], d[1], d[1], d[1]] else d end $$;

-- maximum number of dice from pool that can be played
create or replace function public._gm_bg_maxdepth(b int[], p int, pool int[]) returns int
language plpgsql immutable as $$
declare n int := coalesce(array_length(pool, 1), 0); best int := 0; k int; d int; tried int[] := '{}'; rest int[]; m record; v int; begin
  if n = 0 then return 0; end if;
  for k in 1..n loop
    d := pool[k];
    if d = any(tried) then continue; end if;
    tried := tried || d;
    rest := pool[1:k - 1] || pool[k + 1:n];
    for m in select * from _gm_bg_moves(b, p, d) loop
      v := 1 + _gm_bg_maxdepth(_gm_bg_apply(b, p, m.fr, m.t), p, rest);
      if v > best then best := v; end if;
      if best = n then return best; end if;
    end loop;
  end loop;
  return best; end $$;

create or replace function public._gm_bg_forced(b int[], p int, pool int[], total int) returns int
language plpgsql immutable as $$
declare hi int; begin
  if total <> 1 or coalesce(array_length(pool, 1), 0) <> 2 or pool[1] = pool[2] then return null; end if;
  hi := greatest(pool[1], pool[2]);
  if exists(select 1 from _gm_bg_moves(b, p, hi)) then return hi; end if;
  return least(pool[1], pool[2]); end $$;

-- legal next single moves given remaining dice and how many dice still must be played
create or replace function public._gm_bg_legal(b int[], p int, rem int[], needed int, force int)
returns table(fr int, t int, die int) language plpgsql immutable as $$
declare n int := coalesce(array_length(rem, 1), 0); k int; d int; tried int[] := '{}'; rest int[]; m record; begin
  if needed <= 0 then return; end if;
  for k in 1..n loop
    d := rem[k];
    if d = any(tried) then continue; end if;
    tried := tried || d;
    if force is not null and d <> force then continue; end if;
    rest := rem[1:k - 1] || rem[k + 1:n];
    for m in select * from _gm_bg_moves(b, p, d) loop
      if 1 + _gm_bg_maxdepth(_gm_bg_apply(b, p, m.fr, m.t), p, rest) >= needed then
        fr := m.fr; t := m.t; die := d; return next;
      end if;
    end loop;
  end loop;
end $$;

-- 1 single, 2 gammon, 3 backgammon (same as BgRules.resultMultiplier)
create or replace function public._gm_bg_mult(b int[], w int) returns int language plpgsql immutable as $$
declare l int := 1 - w; i int; begin
  if b[27 + l] > 0 then return 1; end if;
  if b[25 + l] > 0 then return 3; end if;
  for i in 0..23 loop
    if _gm_bg_rel(w, i) <= 6 and _gm_bg_own(b, l, i) > 0 then return 3; end if;
  end loop;
  return 2; end $$;

-- start the turn of gs.turn with gs.state.dice; passes at once when nothing can be played
create or replace function public._gm_bg_begin(gs game_state) returns game_state
language plpgsql as $$
declare b int[] := _gm_ints(gs.state->'b'); p int := gs.turn; dice int[] := _gm_ints(gs.state->'dice'); total int; begin
  total := _gm_bg_maxdepth(b, p, _gm_bg_expand(dice));
  if total = 0 then
    gs.state := gs.state || jsonb_build_object('last', jsonb_build_object('seat', p, 'dice', to_jsonb(dice), 'moves', '[]'::jsonb, 'pass', true),
                                               'dice', '[]'::jsonb);
    gs.turn := 1 - p;
    gs.phase := 'roll';
  else
    gs.phase := 'move';
  end if;
  gs.deadline := now() + make_interval(secs => _gm_secs(gs, 60));
  return gs; end $$;

create or replace function public._gm_backgammon_init(gs game_state, settings jsonb) returns game_state
language plpgsql as $$
declare a int; c int; b int[] := array_fill(0, array[28]); begin
  b[24] := 2; b[13] := 5; b[8] := 3; b[6] := 5; b[1] := -2; b[12] := -5; b[17] := -3; b[19] := -5;
  loop a := _gm_die(); c := _gm_die(); exit when a <> c; end loop;
  gs.turn := case when a > c then 0 else 1 end;
  gs.state := gs.state || jsonb_build_object('b', to_jsonb(b), 'dice', jsonb_build_array(a, c), 'opening', jsonb_build_array(a, c), 'last', null);
  return _gm_bg_begin(gs); end $$;

-- apply a full play (array of [from, to, die]); validates every step like BgTurnTracker
create or replace function public._gm_bg_play(gs game_state, p int, moves jsonb) returns game_state
language plpgsql as $$
declare b int[] := _gm_ints(gs.state->'b'); dice int[] := _gm_ints(gs.state->'dice'); pool int[]; total int; force int;
        k int; mf int; mt int; md int; mult int; begin
  pool := _gm_bg_expand(dice);
  total := _gm_bg_maxdepth(b, p, pool);
  force := _gm_bg_forced(b, p, pool, total);
  if jsonb_typeof(moves) <> 'array' or jsonb_array_length(moves) <> total then raise exception 'must play % dice', total; end if;
  for k in 0 .. total - 1 loop
    mf := (moves->k->>0)::int; mt := (moves->k->>1)::int; md := (moves->k->>2)::int;
    if not exists(select 1 from _gm_bg_legal(b, p, pool, total - k, case when k = 0 then force end) l
                  where l.fr = mf and l.t = mt and l.die = md) then
      raise exception 'illegal move';
    end if;
    b := _gm_bg_apply(b, p, mf, mt);
    pool := _gm_remove1(pool, md);
  end loop;
  gs.state := gs.state || jsonb_build_object('b', to_jsonb(b), 'dice', '[]'::jsonb,
                 'last', jsonb_build_object('seat', p, 'dice', to_jsonb(dice), 'moves', moves));
  if b[27 + p] >= 15 then
    mult := _gm_bg_mult(b, p);
    gs := _gm_set_score(gs, p, mult);
    gs.state := gs.state || jsonb_build_object('mult', mult);
    return _gm_finish_with(gs, array[p], case mult when 3 then 'backgammon' when 2 then 'gammon' else 'win' end);
  end if;
  gs.turn := 1 - p;
  gs.phase := 'roll';
  gs.deadline := now() + make_interval(secs => _gm_secs(gs, 60));
  return gs; end $$;

-- greedy legal play for an idle player
create or replace function public._gm_bg_auto(gs game_state) returns jsonb
language plpgsql as $$
declare b int[] := _gm_ints(gs.state->'b'); p int := gs.turn; pool int[]; total int; force int; k int; m record; out jsonb := '[]'::jsonb; begin
  pool := _gm_bg_expand(_gm_ints(gs.state->'dice'));
  total := _gm_bg_maxdepth(b, p, pool);
  force := _gm_bg_forced(b, p, pool, total);
  for k in 0 .. total - 1 loop
    select * into m from _gm_bg_legal(b, p, pool, total - k, case when k = 0 then force end) l
      order by (l.t = -2) desc, l.die desc, l.fr desc limit 1;
    out := out || jsonb_build_array(jsonb_build_array(m.fr, m.t, m.die));
    b := _gm_bg_apply(b, p, m.fr, m.t);
    pool := _gm_remove1(pool, m.die);
  end loop;
  return out; end $$;

create or replace function public._gm_backgammon_move(gs game_state, seat int, mv jsonb) returns game_state
language plpgsql as $$
begin
  if seat <> gs.turn then raise exception 'not your turn'; end if;
  case mv->>'a'
    when 'roll' then
      if gs.phase <> 'roll' then raise exception 'not now'; end if;
      gs.state := gs.state || jsonb_build_object('dice', jsonb_build_array(_gm_die(), _gm_die()));
      return _gm_bg_begin(gs);
    when 'play' then
      if gs.phase <> 'move' then raise exception 'roll first'; end if;
      return _gm_bg_play(gs, seat, mv->'moves');
    else raise exception 'bad move';
  end case; end $$;

create or replace function public._gm_backgammon_tick(gs game_state) returns game_state
language plpgsql as $$
begin
  gs := _gm_strike(gs, gs.turn);
  if gs.status <> 'live' then return gs; end if;
  if gs.phase = 'roll' then
    gs.state := gs.state || jsonb_build_object('dice', jsonb_build_array(_gm_die(), _gm_die()));
    gs := _gm_bg_begin(gs);
    if gs.phase = 'move' then gs.deadline := now() + make_interval(secs => _gm_secs(gs, 60)); end if;
    return gs;
  end if;
  return _gm_bg_play(gs, gs.turn, _gm_bg_auto(gs)); end $$;

create or replace function public._gm_backgammon_resign(gs game_state, seat int) returns game_state
language plpgsql as $$
begin
  gs := _gm_set_score(gs, 1 - seat, 1);
  return _gm_mark_out(gs, seat, 'resign'); end $$;

-- ================================ LUDO ============================================================
-- tk[seat][token]: -1 base, 0..50 main track (relative), 51..55 home column, 56 home (ludo_rules.dart)
create or replace function public._gm_ludo_corners(n int) returns int[] language sql immutable as $$
  select case when n <= 2 then array[3, 1] when n = 3 then array[3, 0, 1] else array[3, 0, 1, 2] end $$;

create or replace function public._gm_ludo_global(gs game_state, seat int, prog int) returns int language sql immutable as $$
  select (13 * (gs.state->'corners'->>seat)::int + prog) % 52 $$;

create or replace function public._gm_ludo_tok(gs game_state, seat int, t int) returns int language sql immutable as $$
  select (gs.state->'tk'->seat->>t)::int $$;

create or replace function public._gm_ludo_to(gs game_state, seat int, t int, r int) returns int language plpgsql immutable as $$
declare p int := _gm_ludo_tok(gs, seat, t); begin
  if p = 56 then return null; end if;
  if p = -1 then return case when r = 6 then 0 else null end; end if;
  if p + r > 56 then return null; end if;
  return p + r; end $$;

create or replace function public._gm_ludo_legal(gs game_state, seat int, r int) returns int[] language sql immutable as $$
  select coalesce(array_agg(t order by t), '{}') from generate_series(0, 3) t where _gm_ludo_to(gs, seat, t, r) is not null $$;

-- tokens captured by seat landing on relative square `to`: rows of (seat, token, from)
create or replace function public._gm_ludo_caps(gs game_state, seat int, dest int) returns jsonb
language plpgsql immutable as $$
declare g int; o int; u int; q int; caps jsonb := '[]'::jsonb; n int := array_length(gs.seats, 1); begin
  if dest < 0 or dest > 50 then return caps; end if;
  g := _gm_ludo_global(gs, seat, dest);
  if g % 13 = 0 or g % 13 = 8 then return caps; end if;
  for o in 0 .. n - 1 loop
    if o = seat then continue; end if;
    for u in 0..3 loop
      q := _gm_ludo_tok(gs, o, u);
      if q between 0 and 50 and _gm_ludo_global(gs, o, q) = g then caps := caps || jsonb_build_array(jsonb_build_array(o, u, q)); end if;
    end loop;
  end loop;
  return caps; end $$;

create or replace function public._gm_ludo_advance(gs game_state) returns game_state
language plpgsql as $$
begin
  gs.turn := _gm_next(gs, gs.turn);
  gs.phase := 'roll';
  gs.state := gs.state || jsonb_build_object('six', 0, 'roll', null, 'legal', '[]'::jsonb);
  gs.deadline := now() + make_interval(secs => _gm_secs(gs, 25));
  return gs; end $$;

create or replace function public._gm_ludo_init(gs game_state, settings jsonb) returns game_state
language plpgsql as $$
declare n int := array_length(gs.seats, 1); begin
  gs.state := gs.state || jsonb_build_object('n', n, 'corners', to_jsonb(_gm_ludo_corners(n)),
                 'tk', (select jsonb_agg('[-1,-1,-1,-1]'::jsonb) from generate_series(1, n)),
                 'six', 0, 'roll', null, 'legal', '[]'::jsonb, 'last', null);
  gs.turn := 0;
  gs.phase := 'roll';
  gs.deadline := now() + make_interval(secs => _gm_secs(gs, 25));
  return gs; end $$;

create or replace function public._gm_ludo_roll(gs game_state) returns game_state
language plpgsql as $$
declare r int := _gm_die(); seat int := gs.turn; six int := coalesce((gs.state->>'six')::int, 0); legal int[]; begin
  if r = 6 and six >= 2 then
    gs.state := gs.state || jsonb_build_object('last', jsonb_build_object('seat', seat, 'roll', r, 'forfeit', true));
    return _gm_ludo_advance(gs);
  end if;
  legal := _gm_ludo_legal(gs, seat, r);
  if coalesce(array_length(legal, 1), 0) = 0 then
    if r = 6 then
      gs.state := gs.state || jsonb_build_object('six', six + 1, 'last', jsonb_build_object('seat', seat, 'roll', r, 'again', true));
      gs.deadline := now() + make_interval(secs => _gm_secs(gs, 25));
      return gs;
    end if;
    gs.state := gs.state || jsonb_build_object('last', jsonb_build_object('seat', seat, 'roll', r, 'pass', true));
    return _gm_ludo_advance(gs);
  end if;
  gs.phase := 'move';
  gs.state := gs.state || jsonb_build_object('roll', r, 'legal', to_jsonb(legal), 'last', jsonb_build_object('seat', seat, 'roll', r));
  gs.deadline := now() + make_interval(secs => _gm_secs(gs, 25));
  return gs; end $$;

create or replace function public._gm_ludo_play(gs game_state, t int) returns game_state
language plpgsql as $$
declare seat int := gs.turn; r int := (gs.state->>'roll')::int; six int := coalesce((gs.state->>'six')::int, 0);
        p int; dest int; caps jsonb; c jsonb; extra boolean; begin
  if not (t = any(_gm_ints(gs.state->'legal'))) then raise exception 'illegal move'; end if;
  p := _gm_ludo_tok(gs, seat, t);
  dest := _gm_ludo_to(gs, seat, t, r);
  caps := _gm_ludo_caps(gs, seat, dest);
  gs.state := jsonb_set(gs.state, array['tk', seat::text, t::text], to_jsonb(dest));
  for c in select * from jsonb_array_elements(caps) loop
    gs.state := jsonb_set(gs.state, array['tk', c->>0, c->>1], '-1');
  end loop;
  gs.state := gs.state || jsonb_build_object('last', jsonb_build_object('seat', seat, 'roll', r, 't', t, 'from', p, 'to', dest, 'caps', caps),
                                             'roll', null, 'legal', '[]'::jsonb);
  gs := _gm_set_score(gs, seat, (select count(*)::int from jsonb_array_elements_text(gs.state->'tk'->seat) x where x::int = 56));
  if (select bool_and(x::int = 56) from jsonb_array_elements_text(gs.state->'tk'->seat) x) then
    return _gm_finish_with(gs, array[seat], 'win');
  end if;
  extra := r = 6 or jsonb_array_length(caps) > 0 or dest = 56;
  if extra then
    gs.phase := 'roll';
    gs.state := gs.state || jsonb_build_object('six', case when r = 6 then six + 1 else 0 end);
    gs.deadline := now() + make_interval(secs => _gm_secs(gs, 25));
    return gs;
  end if;
  return _gm_ludo_advance(gs); end $$;

create or replace function public._gm_ludo_move(gs game_state, seat int, mv jsonb) returns game_state
language plpgsql as $$
begin
  if seat <> gs.turn then raise exception 'not your turn'; end if;
  case mv->>'a'
    when 'roll' then
      if gs.phase <> 'roll' then raise exception 'not now'; end if;
      return _gm_ludo_roll(gs);
    when 'move' then
      if gs.phase <> 'move' then raise exception 'roll first'; end if;
      return _gm_ludo_play(gs, (mv->>'t')::int);
    else raise exception 'bad move';
  end case; end $$;

create or replace function public._gm_ludo_tick(gs game_state) returns game_state
language plpgsql as $$
declare t int; r int; begin
  gs := _gm_strike(gs, gs.turn);
  if gs.status <> 'live' then return gs; end if;
  if gs.phase = 'roll' then return _gm_ludo_roll(gs); end if;
  r := (gs.state->>'roll')::int;
  select x into t from unnest(_gm_ints(gs.state->'legal')) x
    order by jsonb_array_length(_gm_ludo_caps(gs, gs.turn, _gm_ludo_to(gs, gs.turn, x, r))) desc, _gm_ludo_to(gs, gs.turn, x, r) desc limit 1;
  return _gm_ludo_play(gs, t); end $$;

create or replace function public._gm_ludo_resign(gs game_state, seat int) returns game_state
language plpgsql as $$
begin
  gs.state := jsonb_set(gs.state, array['tk', seat::text], '[-1,-1,-1,-1]');
  gs := _gm_mark_out(gs, seat, 'resign');
  if gs.status = 'live' and gs.turn = seat then gs := _gm_ludo_advance(gs); end if;
  return gs; end $$;

-- ================================ SNAKES & LADDERS ================================================
create or replace function public._gm_snl_resolve(sq int) returns int language sql immutable as $$
  select coalesce(
    (jsonb '{"1":38,"4":14,"9":31,"21":42,"28":84,"36":44,"51":67,"71":91,"80":100,
            "16":6,"47":26,"49":11,"56":53,"62":19,"64":60,"87":24,"93":73,"95":75,"98":78}'->>sq::text)::int, sq) $$;

create or replace function public._gm_snakes_ladders_init(gs game_state, settings jsonb) returns game_state
language plpgsql as $$
begin
  gs.state := gs.state || jsonb_build_object('pos', (select jsonb_agg(0) from generate_subscripts(gs.seats, 1)), 'last', null);
  gs.turn := 0;
  gs.phase := 'roll';
  gs.deadline := now() + make_interval(secs => _gm_secs(gs, 20));
  return gs; end $$;

create or replace function public._gm_snl_roll(gs game_state) returns game_state
language plpgsql as $$
declare seat int := gs.turn; r int := _gm_die(); pos int; dir int := 1; i int; steps jsonb := '[]'::jsonb; fr int; landed int; fin int; begin
  fr := (gs.state->'pos'->>seat)::int;
  pos := fr;
  for i in 1..r loop
    if pos = 100 then dir := -1; end if;
    pos := pos + dir;
    steps := steps || to_jsonb(pos);
  end loop;
  landed := pos;
  fin := _gm_snl_resolve(landed);
  gs.state := jsonb_set(gs.state, array['pos', seat::text], to_jsonb(fin));
  gs := _gm_set_score(gs, seat, fin);
  gs.state := gs.state || jsonb_build_object('last', jsonb_build_object('seat', seat, 'roll', r, 'from', fr, 'steps', steps,
                                             'landed', landed, 'final', fin, 'extra', fin <> 100 and r = 6));
  if fin = 100 then return _gm_finish_with(gs, array[seat], 'win'); end if;
  if r <> 6 then gs.turn := _gm_next(gs, seat); end if;
  gs.deadline := now() + make_interval(secs => _gm_secs(gs, 20));
  return gs; end $$;

create or replace function public._gm_snakes_ladders_move(gs game_state, seat int, mv jsonb) returns game_state
language plpgsql as $$
begin
  if seat <> gs.turn then raise exception 'not your turn'; end if;
  if mv->>'a' <> 'roll' then raise exception 'bad move'; end if;
  return _gm_snl_roll(gs); end $$;

create or replace function public._gm_snakes_ladders_tick(gs game_state) returns game_state
language plpgsql as $$
begin
  gs := _gm_strike(gs, gs.turn);
  if gs.status <> 'live' then return gs; end if;
  return _gm_snl_roll(gs); end $$;

create or replace function public._gm_snakes_ladders_resign(gs game_state, seat int) returns game_state
language plpgsql as $$
begin
  gs := _gm_mark_out(gs, seat, 'resign');
  if gs.status = 'live' and gs.turn = seat then
    gs.turn := _gm_next(gs, seat);
    gs.deadline := now() + make_interval(secs => _gm_secs(gs, 20));
  end if;
  return gs; end $$;

-- ================================ NX CARDS (UNO) ==================================================
-- Card ids 0..107 exactly as buildUnoDeck() in uno_models.dart: per colour c (turquoise, violet, gold, pink)
-- ids c*25 + 0 = number 0, +1..+18 = numbers 1..9 twice, +19..+24 = skip, reverse, drawTwo (twice);
-- 100..103 wild, 104..107 wild draw four.
create or replace function public._gm_uno_kind(id int) returns text language sql immutable as $$
  select case when id >= 104 then 'w4' when id >= 100 then 'w' when id % 25 <= 18 then 'n'
              else (array['skip','rev','d2'])[((id % 25) - 19) % 3 + 1] end $$;
create or replace function public._gm_uno_color(id int) returns int language sql immutable as $$
  select case when id < 100 then id / 25 else -1 end $$;
create or replace function public._gm_uno_num(id int) returns int language sql immutable as $$
  select case when id >= 100 or id % 25 > 18 then -1 when id % 25 = 0 then 0 else ((id % 25) - 1) / 2 + 1 end $$;
create or replace function public._gm_uno_points(id int) returns int language sql immutable as $$
  select case _gm_uno_kind(id) when 'n' then _gm_uno_num(id) when 'w' then 50 when 'w4' then 50 else 20 end $$;

create or replace function public._gm_uno_hand(gs game_state, seat int) returns int[] language sql stable security definer set search_path to 'public' as $$
  select _gm_ints(data->'hand') from game_private where match_id = gs.match_id and seat = $2 $$;

create or replace function public._gm_uno_drawn(gs game_state, seat int) returns int language sql stable security definer set search_path to 'public' as $$
  select (data->>'drawn')::int from game_private where match_id = gs.match_id and seat = $2 $$;

create or replace function public._gm_uno_put(gs game_state, seat int, hand int[], drawn int) returns game_state
language plpgsql security definer set search_path to 'public' as $$
begin
  update game_private set data = jsonb_build_object('hand', to_jsonb(hand), 'drawn', drawn), updated_at = now()
   where match_id = gs.match_id and game_private.seat = $2;
  gs.state := jsonb_set(gs.state, array['counts', seat::text], to_jsonb(coalesce(array_length(hand, 1), 0)));
  if gs.turn = seat then gs.state := gs.state || jsonb_build_object('drawn', drawn is not null); end if;
  return gs; end $$;

-- move up to k cards from the draw pile to seat's hand (reshuffling the discard when needed)
create or replace function public._gm_uno_give(gs game_state, seat int, k int) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare sec jsonb; pile int[]; disc int[]; hand int[]; i int; got int := 0; n int; begin
  select data into sec from game_secret where match_id = gs.match_id for update;
  pile := _gm_ints(sec->'pile'); disc := _gm_ints(sec->'disc');
  hand := _gm_uno_hand(gs, seat);
  for i in 1..k loop
    if coalesce(array_length(pile, 1), 0) = 0 then
      if coalesce(array_length(disc, 1), 0) = 0 then exit; end if;
      select array_agg(x order by random()) into pile from unnest(disc) x;
      disc := '{}';
      gs.state := gs.state || jsonb_build_object('reshuffled', coalesce((gs.state->>'reshuffled')::int, 0) + 1);
    end if;
    n := array_length(pile, 1);
    hand := hand || pile[n];
    pile := pile[1:n - 1];
    got := got + 1;
  end loop;
  update game_secret set data = data || jsonb_build_object('pile', to_jsonb(pile), 'disc', to_jsonb(disc)) where match_id = gs.match_id;
  gs.state := gs.state || jsonb_build_object('pile', coalesce(array_length(pile, 1), 0));
  gs := _gm_uno_put(gs, seat, hand, _gm_uno_drawn(gs, seat));
  if got > 0 and array_length(hand, 1) > 1 then
    gs.state := jsonb_set(gs.state, array['nx', seat::text], 'false');
    if (gs.state->>'vul')::int = seat then gs.state := gs.state || jsonb_build_object('vul', null); end if;
  end if;
  return gs; end $$;

create or replace function public._gm_uno_legal(gs game_state, hand int[], card int) returns boolean
language plpgsql immutable as $$
declare col int := (gs.state->>'color')::int; top int := (gs.state->>'top')::int; k text := _gm_uno_kind(card); begin
  if k in ('w', 'w4') then
    if k = 'w4' then
      return not exists(select 1 from unnest(hand) c where c <> card and c < 100 and _gm_uno_color(c) = col);
    end if;
    return true;
  end if;
  if _gm_uno_color(card) = col then return true; end if;
  if top >= 100 then return false; end if;
  return k = _gm_uno_kind(top) and (k <> 'n' or _gm_uno_num(card) = _gm_uno_num(top)); end $$;

create or replace function public._gm_uno_init(gs game_state, settings jsonb) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare deck int[] := _gm_shuffle(108); n int := array_length(gs.seats, 1); s int; hs int := 7; first int; guard int := 0; begin
  gs.state := gs.state || jsonb_build_object('counts', (select jsonb_agg(0) from generate_series(1, n)),
                 'nx', (select jsonb_agg(false) from generate_series(1, n)), 'dir', 1, 'vul', null, 'drawn', false, 'last', null);
  for s in 0 .. n - 1 loop
    gs := _gm_uno_put(gs, s, deck[s * hs + 1 : s * hs + hs], null);
  end loop;
  deck := deck[n * hs + 1 : 108];
  -- first discard must be a number card; others go back under the pile
  loop
    first := deck[array_length(deck, 1)];
    deck := deck[1:array_length(deck, 1) - 1];
    exit when _gm_uno_kind(first) = 'n' or guard > 200;
    deck := array[first] || deck;
    guard := guard + 1;
  end loop;
  update game_secret set data = jsonb_build_object('pile', to_jsonb(deck), 'disc', '[]'::jsonb) where match_id = gs.match_id;
  gs.state := gs.state || jsonb_build_object('top', first, 'color', _gm_uno_color(first), 'pile', array_length(deck, 1));
  gs.turn := _gm_rand(n);
  gs.phase := 'play';
  gs.deadline := now() + make_interval(secs => _gm_secs(gs, 30));
  return gs; end $$;

create or replace function public._gm_uno_after_turn(gs game_state, nxt int) returns game_state
language plpgsql as $$
begin
  gs.turn := nxt;
  gs.state := gs.state || jsonb_build_object('drawn', false);
  gs.deadline := now() + make_interval(secs => _gm_secs(gs, 30));
  return gs; end $$;

-- the catch window closes once another player starts acting
create or replace function public._gm_uno_acts(gs game_state, seat int) returns game_state
language plpgsql immutable as $$
begin
  if gs.state->>'vul' is not null and (gs.state->>'vul')::int <> seat then gs.state := gs.state || jsonb_build_object('vul', null); end if;
  return gs; end $$;

create or replace function public._gm_uno_play(gs game_state, seat int, card int, chosen int) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare hand int[] := _gm_uno_hand(gs, seat); drawn int := _gm_uno_drawn(gs, seat); k text; dir int := (gs.state->>'dir')::int;
        left_n int; nxt int; victim int; total int; s int; begin
  if seat <> gs.turn then raise exception 'not your turn'; end if;
  if card is null or not (card = any(hand)) then raise exception 'card not in hand'; end if;
  if drawn is not null and drawn <> card then raise exception 'play the drawn card or pass'; end if;
  if not _gm_uno_legal(gs, hand, card) then raise exception 'illegal card'; end if;
  k := _gm_uno_kind(card);
  if k in ('w', 'w4') and (chosen is null or chosen < 0 or chosen > 3) then raise exception 'choose a colour'; end if;
  gs := _gm_uno_acts(gs, seat);
  hand := _gm_remove1(hand, card);
  update game_secret set data = jsonb_set(data, '{disc}', coalesce(data->'disc', '[]'::jsonb) || to_jsonb((gs.state->>'top')::int))
   where match_id = gs.match_id;
  gs := _gm_uno_put(gs, seat, hand, null);
  gs.state := gs.state || jsonb_build_object('top', card, 'color', case when k in ('w', 'w4') then chosen else _gm_uno_color(card) end,
                 'last', jsonb_build_object('seat', seat, 'a', 'play', 'card', card, 'color', chosen));
  left_n := coalesce(array_length(hand, 1), 0);
  if left_n = 1 then
    if not coalesce((gs.state->'nx'->>seat)::boolean, false) then gs.state := gs.state || jsonb_build_object('vul', seat); end if;
  elsif left_n > 1 then
    gs.state := jsonb_set(gs.state, array['nx', seat::text], 'false');
  end if;
  if left_n = 0 then
    total := 0;
    for s in 0 .. array_length(gs.seats, 1) - 1 loop
      if s <> seat then total := total + (select coalesce(sum(_gm_uno_points(c)), 0) from unnest(_gm_uno_hand(gs, s)) c); end if;
    end loop;
    gs := _gm_set_score(gs, seat, total);
    gs.state := gs.state || jsonb_build_object('vul', null);
    -- the last card's draw penalty still lands (same as the offline engine)
    if k in ('d2', 'w4') then gs := _gm_uno_give(gs, _gm_next(gs, seat, dir), case when k = 'd2' then 2 else 4 end); end if;
    return _gm_finish_with(gs, array[seat], 'win');
  end if;
  nxt := _gm_next(gs, seat, dir);
  case k
    when 'skip' then nxt := _gm_next(gs, nxt, dir);
    when 'rev' then
      dir := -dir;
      gs.state := gs.state || jsonb_build_object('dir', dir);
      if _gm_alive_count(gs) = 2 then nxt := seat; else nxt := _gm_next(gs, seat, dir); end if;
    when 'd2' then victim := nxt; gs := _gm_uno_give(gs, victim, 2); nxt := _gm_next(gs, victim, dir);
    when 'w4' then victim := nxt; gs := _gm_uno_give(gs, victim, 4); nxt := _gm_next(gs, victim, dir);
    else null;
  end case;
  return _gm_uno_after_turn(gs, nxt); end $$;

create or replace function public._gm_uno_draw(gs game_state, seat int) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare before int[]; hand int[]; c int; begin
  if seat <> gs.turn then raise exception 'not your turn'; end if;
  if _gm_uno_drawn(gs, seat) is not null then raise exception 'already drew'; end if;
  gs := _gm_uno_acts(gs, seat);
  before := _gm_uno_hand(gs, seat);
  gs := _gm_uno_give(gs, seat, 1);
  hand := _gm_uno_hand(gs, seat);
  if coalesce(array_length(hand, 1), 0) = coalesce(array_length(before, 1), 0) then
    gs.state := gs.state || jsonb_build_object('last', jsonb_build_object('seat', seat, 'a', 'draw', 'n', 0, 'pass', true));
    return _gm_uno_after_turn(gs, _gm_next(gs, seat, (gs.state->>'dir')::int));
  end if;
  c := hand[array_length(hand, 1)];
  if _gm_uno_legal(gs, hand, c) then
    gs := _gm_uno_put(gs, seat, hand, c);
    gs.state := gs.state || jsonb_build_object('last', jsonb_build_object('seat', seat, 'a', 'draw', 'n', 1));
    gs.deadline := now() + make_interval(secs => _gm_secs(gs, 30));
    return gs;
  end if;
  gs.state := gs.state || jsonb_build_object('last', jsonb_build_object('seat', seat, 'a', 'draw', 'n', 1, 'pass', true));
  return _gm_uno_after_turn(gs, _gm_next(gs, seat, (gs.state->>'dir')::int)); end $$;

create or replace function public._gm_uno_pass(gs game_state, seat int) returns game_state
language plpgsql security definer set search_path to 'public' as $$
begin
  if seat <> gs.turn then raise exception 'not your turn'; end if;
  if _gm_uno_drawn(gs, seat) is null then raise exception 'draw first'; end if;
  gs := _gm_uno_put(gs, seat, _gm_uno_hand(gs, seat), null);
  gs.state := gs.state || jsonb_build_object('last', jsonb_build_object('seat', seat, 'a', 'pass'));
  return _gm_uno_after_turn(gs, _gm_next(gs, seat, (gs.state->>'dir')::int)); end $$;

create or replace function public._gm_uno_move(gs game_state, seat int, mv jsonb) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare n int; v int; begin
  case mv->>'a'
    when 'play' then return _gm_uno_play(gs, seat, (mv->>'card')::int, (mv->>'color')::int);
    when 'draw' then return _gm_uno_draw(gs, seat);
    when 'pass' then return _gm_uno_pass(gs, seat);
    when 'nx' then
      n := coalesce(array_length(_gm_uno_hand(gs, seat), 1), 0);
      if n = 1 and (gs.state->>'vul')::int = seat then
        gs.state := gs.state || jsonb_build_object('vul', null);
      elsif not (n = 2 and gs.turn = seat and not coalesce((gs.state->'nx'->>seat)::boolean, false)) then
        raise exception 'not now';
      end if;
      gs.state := jsonb_set(gs.state, array['nx', seat::text], 'true');
      gs.state := gs.state || jsonb_build_object('last', jsonb_build_object('seat', seat, 'a', 'nx'));
      return gs;
    when 'catch' then
      v := (gs.state->>'vul')::int;
      if v is null or v = seat then raise exception 'nothing to catch'; end if;
      gs.state := gs.state || jsonb_build_object('vul', null);
      gs := _gm_uno_give(gs, v, 2);
      gs.state := gs.state || jsonb_build_object('last', jsonb_build_object('seat', seat, 'a', 'catch', 'victim', v));
      return gs;
    else raise exception 'bad move';
  end case; end $$;

create or replace function public._gm_uno_tick(gs game_state) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare s int := gs.turn; begin
  gs := _gm_strike(gs, s);
  if gs.status <> 'live' or gs.turn <> s or _gm_out(gs, s) then return gs; end if;
  if _gm_uno_drawn(gs, s) is null then gs := _gm_uno_draw(gs, s); end if;
  if gs.turn = s and _gm_uno_drawn(gs, s) is not null then gs := _gm_uno_pass(gs, s); end if;
  return gs; end $$;

create or replace function public._gm_uno_resign(gs game_state, seat int) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare hand int[] := _gm_uno_hand(gs, seat); begin
  update game_secret set data = jsonb_set(data, '{pile}', to_jsonb(hand) || coalesce(data->'pile', '[]'::jsonb)) where match_id = gs.match_id;
  gs.state := gs.state || jsonb_build_object('pile', coalesce((gs.state->>'pile')::int, 0) + coalesce(array_length(hand, 1), 0));
  gs := _gm_uno_put(gs, seat, '{}'::int[], null);
  if (gs.state->>'vul')::int = seat then gs.state := gs.state || jsonb_build_object('vul', null); end if;
  gs := _gm_mark_out(gs, seat, 'resign');
  if gs.status = 'live' and gs.turn = seat then gs := _gm_uno_after_turn(gs, _gm_next(gs, seat, (gs.state->>'dir')::int)); end if;
  return gs; end $$;

-- ================================ QUIZ ============================================================
-- Answer key lives server-side (gm_quiz_bank, no client access). Timing is measured on the server.
create table if not exists public.gm_quiz_bank (
  id text primary key,
  cat text not null,
  diff int not null default 1,
  correct int not null check (correct between 0 and 3)
);
alter table public.gm_quiz_bank enable row level security;

create or replace function public._gm_ms() returns bigint language sql volatile as $$ select (extract(epoch from clock_timestamp()) * 1000)::bigint $$;

create or replace function public._gm_quiz_ask(gs game_state, r int) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare qids jsonb; begin
  select data->'qids' into qids from game_secret where match_id = gs.match_id;
  update game_secret set data = data || jsonb_build_object('ans', '{}'::jsonb) where match_id = gs.match_id;
  gs.phase := 'question';
  gs.state := gs.state || jsonb_build_object('round', r, 'qid', qids->>r, 'started', _gm_ms(),
                 'answered', (select jsonb_agg(false) from generate_subscripts(gs.seats, 1)));
  gs.deadline := now() + interval '15.5 seconds';
  return gs; end $$;

create or replace function public._gm_quiz_init(gs game_state, settings jsonb) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare v_cat text := nullif(settings->>'category', ''); qids jsonb; total int := 10; begin
  select coalesce(jsonb_agg(id order by ord), '[]'::jsonb) into qids from (
    select id, row_number() over (order by (v_cat is not null and b.cat = v_cat) desc, rn, random()) ord from (
      select q.id, q.cat, row_number() over (partition by q.cat order by random()) rn from gm_quiz_bank q) b
  ) x where ord <= total;
  total := jsonb_array_length(qids);
  if total = 0 then raise exception 'no questions'; end if;
  update game_secret set data = jsonb_build_object('qids', qids, 'ans', '{}'::jsonb) where match_id = gs.match_id;
  gs.state := gs.state || jsonb_build_object('total', total, 'category', v_cat,
                 'correct', (select jsonb_agg(0) from generate_subscripts(gs.seats, 1)), 'reveal', null);
  return _gm_quiz_ask(gs, 0); end $$;

create or replace function public._gm_quiz_reveal(gs game_state) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare ans jsonb; key int; s int; a jsonb; choices jsonb := '[]'; pts jsonb := '[]'; ms jsonb := '[]'; begin
  select data->'ans' into ans from game_secret where match_id = gs.match_id;
  select correct into key from gm_quiz_bank where id = gs.state->>'qid';
  for s in 0 .. array_length(gs.seats, 1) - 1 loop
    a := ans->(s::text);
    choices := choices || coalesce(a->'c', 'null'::jsonb);
    pts := pts || coalesce(a->'p', '0'::jsonb);
    ms := ms || coalesce(a->'e', 'null'::jsonb);
    if a is not null then
      gs := _gm_set_score(gs, s, (gs.state->'scores'->>s)::int + (a->>'p')::int);
      if (a->>'ok')::boolean then gs.state := jsonb_set(gs.state, array['correct', s::text], to_jsonb((gs.state->'correct'->>s)::int + 1)); end if;
    end if;
  end loop;
  gs.phase := 'reveal';
  gs.state := gs.state || jsonb_build_object('reveal', jsonb_build_object('qid', gs.state->>'qid', 'answer', key,
                 'choices', choices, 'points', pts, 'ms', ms));
  gs.deadline := now() + interval '4 seconds';
  return gs; end $$;

create or replace function public._gm_quiz_next(gs game_state) returns game_state
language plpgsql as $$
declare r int := (gs.state->>'round')::int + 1; best int; bestc int; w int[]; alive int[] := _gm_alive_seats(gs); begin
  if r < (gs.state->>'total')::int then return _gm_quiz_ask(gs, r); end if;
  select max((gs.state->'scores'->>s)::int) into best from unnest(alive) s;
  select max((gs.state->'correct'->>s)::int) into bestc from unnest(alive) s where (gs.state->'scores'->>s)::int = best;
  select array_agg(s order by s) into w from unnest(alive) s
   where (gs.state->'scores'->>s)::int = best and (gs.state->'correct'->>s)::int = bestc;
  return _gm_finish_with(gs, w, 'win'); end $$;

create or replace function public._gm_quiz_move(gs game_state, seat int, mv jsonb) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare c int := (mv->>'c')::int; e bigint; key int; ok boolean; p int; begin
  if mv->>'a' <> 'answer' then raise exception 'bad move'; end if;
  if gs.phase <> 'question' then raise exception 'not now'; end if;
  if coalesce((gs.state->'answered'->>seat)::boolean, false) then raise exception 'already answered'; end if;
  if c is null or c < 0 or c > 3 then raise exception 'bad answer'; end if;
  e := greatest(0, _gm_ms() - (gs.state->>'started')::bigint);
  select correct into key from gm_quiz_bank where id = gs.state->>'qid';
  ok := c = key and e < 15000;
  p := case when ok then 100 + round(50.0 * (15000 - e) / 15000)::int else 0 end;
  update game_secret set data = jsonb_set(data, array['ans', seat::text], jsonb_build_object('c', c, 'e', e, 'ok', ok, 'p', p))
   where match_id = gs.match_id;
  gs.state := jsonb_set(gs.state, array['answered', seat::text], 'true');
  if not exists(select 1 from unnest(_gm_alive_seats(gs)) s where not coalesce((gs.state->'answered'->>s)::boolean, false)) then
    gs := _gm_quiz_reveal(gs);
  end if;
  return gs; end $$;

-- quiz has no idle strikes: an unanswered question just scores 0
create or replace function public._gm_quiz_tick(gs game_state) returns game_state
language plpgsql as $$
begin
  if gs.phase = 'question' then return _gm_quiz_reveal(gs); end if;
  return _gm_quiz_next(gs); end $$;

create or replace function public._gm_quiz_resign(gs game_state, seat int) returns game_state
language plpgsql as $$
begin
  gs := _gm_mark_out(gs, seat, 'resign');
  if gs.status = 'live' and gs.phase = 'question'
     and not exists(select 1 from unnest(_gm_alive_seats(gs)) s where not coalesce((gs.state->'answered'->>s)::boolean, false)) then
    gs := _gm_quiz_reveal(gs);
  end if;
  return gs; end $$;

-- ================================ HOST-AUTHORITATIVE: CARROM, BILLIARDS ===========================
-- The shooter simulates the shot with the shared pure-Dart physics and submits the result via gm_shot;
-- the server checks seat / turn order / version and runs timeouts. No server-side physics.
create or replace function public._gm_carrom_init(gs game_state, settings jsonb) returns game_state
language plpgsql as $$
begin
  gs.turn := 0; gs.phase := 'shoot';
  gs.state := gs.state || jsonb_build_object('seed', _gm_rand(1000000000), 'shots', 0);
  gs.deadline := now() + make_interval(secs => _gm_secs(gs, 45));
  return gs; end $$;
create or replace function public._gm_carrom_resign(gs game_state, seat int) returns game_state
language plpgsql as $$ begin return _gm_host_resign(gs, seat); end $$;
create or replace function public._gm_carrom_tick(gs game_state) returns game_state
language plpgsql as $$ begin return _gm_host_tick(gs); end $$;
create or replace function public._gm_carrom_move(gs game_state, seat int, mv jsonb) returns game_state
language plpgsql as $$ begin raise exception 'host-authoritative game'; end $$;

create or replace function public._gm_billiards_init(gs game_state, settings jsonb) returns game_state
language plpgsql as $$
begin
  gs.turn := _gm_rand(2); gs.phase := 'shoot';
  gs.state := gs.state || jsonb_build_object('seed', _gm_rand(1000000000), 'shots', 0);
  gs.deadline := now() + make_interval(secs => _gm_secs(gs, 45));
  return gs; end $$;
create or replace function public._gm_billiards_resign(gs game_state, seat int) returns game_state
language plpgsql as $$ begin return _gm_host_resign(gs, seat); end $$;
create or replace function public._gm_billiards_tick(gs game_state) returns game_state
language plpgsql as $$ begin return _gm_host_tick(gs); end $$;
create or replace function public._gm_billiards_move(gs game_state, seat int, mv jsonb) returns game_state
language plpgsql as $$ begin raise exception 'host-authoritative game'; end $$;

-- grants: internal helpers are server-only
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like '\_gm\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
