-- NEXORA online Mafia (6..12 real players). Mirrors lib/games/mafia/core/mafia_engine.dart:
-- roles godfather / mafia / doctor / detective / sniper (>= 7 players) / citizen; night actions resolved together;
-- day talk (voice + chat in the room) -> nomination vote -> defense -> final vote; roles revealed on death.
-- Secrets: every role and night action live in game_secret; each player's own role / mafia mates /
-- detective results live in their game_private row. Public state only has what the whole table may know.
-- Public state: day, alive[], shown[] (role of dead players), defendants[], voted[], ready[], ev[] (event log),
-- tally (last vote), team (winner). Phases: night, day, nominate, defense, final.

create or replace function public._gm_mf_roles(n int, sniper boolean) returns text[] language plpgsql immutable as $$
declare r text[] := array['godfather']; mc int := case when n >= 9 then 3 else 2 end; i int; begin
  for i in 2..mc loop r := r || 'mafia'::text; end loop;
  r := r || array['doctor', 'detective'];
  if sniper and n >= 7 then r := r || 'sniper'::text; end if;
  while coalesce(array_length(r, 1), 0) < n loop r := r || 'citizen'::text; end loop;
  return r; end $$;

create or replace function public._gm_mf_secret(gs game_state) returns jsonb language sql stable security definer set search_path to 'public' as $$
  select data from game_secret where match_id = gs.match_id $$;

create or replace function public._gm_mf_role(gs game_state, s int) returns text language sql stable security definer set search_path to 'public' as $$
  select data->'roles'->>s from game_secret where match_id = gs.match_id $$;

create or replace function public._gm_mf_alive(gs game_state, s int) returns boolean language sql immutable as $$
  select coalesce((gs.state->'alive'->>s)::boolean, false) $$;

create or replace function public._gm_mf_alive_seats(gs game_state) returns int[] language sql immutable as $$
  select coalesce(array_agg(i - 1 order by i), '{}') from generate_subscripts(gs.seats, 1) i where coalesce((gs.state->'alive'->>(i - 1))::boolean, false) $$;

-- seat holding a role and alive (null if none)
create or replace function public._gm_mf_holder(gs game_state, p_role text) returns int language sql stable security definer set search_path to 'public' as $$
  select min(i - 1) from game_secret x, generate_subscripts(gs.seats, 1) i
   where x.match_id = gs.match_id and x.data->'roles'->>(i - 1) = p_role and coalesce((gs.state->'alive'->>(i - 1))::boolean, false) $$;

create or replace function public._gm_mf_is_mafia(r text) returns boolean language sql immutable as $$ select r in ('godfather', 'mafia') $$;

create or replace function public._gm_mf_ev(gs game_state, ev jsonb) returns game_state language plpgsql immutable as $$
declare a jsonb := coalesce(gs.state->'ev', '[]'::jsonb) || jsonb_build_array(ev || jsonb_build_object('d', (gs.state->>'day')::int)); begin
  if jsonb_array_length(a) > 60 then a := a - 0; end if;
  gs.state := gs.state || jsonb_build_object('ev', a);
  return gs; end $$;

create or replace function public._gm_mf_priv(gs game_state, s int, patch jsonb) returns void
language sql security definer set search_path to 'public' as $$
  update game_private set data = data || patch, updated_at = now() where match_id = gs.match_id and seat = s $$;

-- winner: town when no mafia alive, mafia when mafia alive >= town alive
create or replace function public._gm_mf_check(gs game_state) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare roles jsonb := (_gm_mf_secret(gs))->'roles'; ma int := 0; ta int := 0; s int; team text; w int[]; begin
  for s in 0 .. array_length(gs.seats, 1) - 1 loop
    if _gm_mf_alive(gs, s) then
      if _gm_mf_is_mafia(roles->>s) then ma := ma + 1; else ta := ta + 1; end if;
    end if;
  end loop;
  if ma = 0 then team := 'town'; elsif ma >= ta then team := 'mafia'; else return gs; end if;
  select array_agg(i - 1 order by i) into w from generate_subscripts(gs.seats, 1) i
   where _gm_mf_is_mafia(roles->>(i - 1)) = (team = 'mafia');
  gs.state := gs.state || jsonb_build_object('team', team, 'shown', roles);
  for s in 0 .. array_length(gs.seats, 1) - 1 loop
    gs := _gm_set_score(gs, s, case when s = any(w) then 1 else 0 end);
  end loop;
  gs := _gm_mf_ev(gs, jsonb_build_object('k', 'win', 'team', team));
  return _gm_finish_with(gs, w, team); end $$;

create or replace function public._gm_mf_kill(gs game_state, s int, cause text) returns game_state
language plpgsql security definer set search_path to 'public' as $$
begin
  if not _gm_mf_alive(gs, s) then return gs; end if;
  gs.state := jsonb_set(gs.state, array['alive', s::text], 'false');
  gs.state := jsonb_set(gs.state, array['shown', s::text], to_jsonb(_gm_mf_role(gs, s)));
  return _gm_mf_ev(gs, jsonb_build_object('k', cause, 's', s, 'r', _gm_mf_role(gs, s))); end $$;

create or replace function public._gm_mf_phase(gs game_state, ph text) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare n int := array_length(gs.seats, 1); secs int; begin
  gs.phase := ph;
  secs := case ph when 'night' then 40 when 'day' then 90 when 'nominate' then 30 when 'defense' then 30 else 20 end;
  gs.deadline := now() + make_interval(secs => secs);
  gs.state := gs.state || jsonb_build_object('voted', (select jsonb_agg(false) from generate_series(1, n)),
                                             'ready', (select jsonb_agg(false) from generate_series(1, n)));
  if ph = 'night' then
    update game_secret set data = data || jsonb_build_object('act', '{}'::jsonb, 'acted', '[]'::jsonb) where match_id = gs.match_id;
    perform _gm_mf_priv(gs, s, jsonb_build_object('team_pick', '{}'::jsonb, 'my_pick', null))
      from generate_series(0, n - 1) s;
  elsif ph in ('nominate', 'final') then
    update game_secret set data = data || jsonb_build_object('votes', '{}'::jsonb) where match_id = gs.match_id;
  end if;
  return gs; end $$;

create or replace function public._gm_mafia_init(gs game_state, settings jsonb) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare n int := array_length(gs.seats, 1); roles text[]; s int; mates jsonb; begin
  select array_agg(x order by random()) into roles from unnest(_gm_mf_roles(n, coalesce((settings->>'sniper')::boolean, true))) x;
  update game_secret set data = jsonb_build_object('roles', to_jsonb(roles), 'act', '{}'::jsonb, 'acted', '[]'::jsonb, 'votes', '{}'::jsonb,
                                                   'last_doc', null, 'doc_self', false, 'bullets', 1) where match_id = gs.match_id;
  select jsonb_agg(jsonb_build_object('seat', i - 1, 'role', roles[i]) order by i) into mates
    from generate_subscripts(roles, 1) i where _gm_mf_is_mafia(roles[i]);
  for s in 0 .. n - 1 loop
    perform _gm_mf_priv(gs, s, jsonb_build_object('role', roles[s + 1],
      'mates', case when _gm_mf_is_mafia(roles[s + 1]) then mates else '[]'::jsonb end, 'checks', '{}'::jsonb));
  end loop;
  gs.state := gs.state || jsonb_build_object('day', 1, 'n', n, 'alive', (select jsonb_agg(true) from generate_series(1, n)),
                 'shown', (select jsonb_agg(null::text) from generate_series(1, n)), 'defendants', '[]'::jsonb,
                 'tally', null, 'team', null, 'ev', '[]'::jsonb, 'sniper', n >= 7 and coalesce((settings->>'sniper')::boolean, true));
  gs.turn := 0;
  gs := _gm_mf_ev(gs, jsonb_build_object('k', 'night'));
  return _gm_mf_phase(gs, 'night'); end $$;

-- is target legal for this seat's night role?
create or replace function public._gm_mf_night_ok(gs game_state, s int, r text, t int) returns boolean
language plpgsql security definer set search_path to 'public' as $$
declare sec jsonb := _gm_mf_secret(gs); begin
  if t is null then return true; end if;
  if t < 0 or t >= array_length(gs.seats, 1) or not _gm_mf_alive(gs, t) then return false; end if;
  case r
    when 'godfather', 'mafia' then return not _gm_mf_is_mafia(sec->'roles'->>t);
    when 'doctor' then return t is distinct from (sec->>'last_doc')::int and not (t = s and coalesce((sec->>'doc_self')::boolean, false));
    when 'detective' then return t <> s;
    when 'sniper' then return t <> s and coalesce((sec->>'bullets')::int, 0) > 0;
    else return false;
  end case; end $$;

create or replace function public._gm_mf_resolve_night(gs game_state) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare sec jsonb := _gm_mf_secret(gs); act jsonb := coalesce(sec->'act', '{}'::jsonb); roles jsonb := sec->'roles';
        gf int := _gm_mf_holder(gs, 'godfather'); doc int := _gm_mf_holder(gs, 'doctor'); det int := _gm_mf_holder(gs, 'detective');
        sn int := _gm_mf_holder(gs, 'sniper'); mt int; ds int; dc int; st int; deaths int[] := '{}'; causes text[] := '{}';
        saved boolean := false; i int; s int; begin
  -- the Godfather's pick decides; otherwise the lowest alive mafia seat that picked
  if gf is not null and act->'maf' ? gf::text then mt := (act->'maf'->>gf::text)::int;
  else
    select (act->'maf'->>k)::int into mt from jsonb_object_keys(coalesce(act->'maf', '{}'::jsonb)) k
     where _gm_mf_alive(gs, k::int) order by k::int limit 1;
  end if;
  if mt is not null and not _gm_mf_night_ok(gs, coalesce(gf, -1), 'mafia', mt) then mt := null; end if;
  if doc is not null then ds := (act->>'doc')::int; if not _gm_mf_night_ok(gs, doc, 'doctor', ds) then ds := null; end if; end if;
  if det is not null then dc := (act->>'det')::int; if not _gm_mf_night_ok(gs, det, 'detective', dc) then dc := null; end if; end if;
  if sn is not null then st := (act->>'sni')::int; if not _gm_mf_night_ok(gs, sn, 'sniper', st) then st := null; end if; end if;
  if mt is not null then
    if ds = mt then saved := true; else deaths := deaths || mt; causes := causes || 'night_kill'::text; end if;
  end if;
  if st is not null then
    update game_secret set data = data || jsonb_build_object('bullets', 0) where match_id = gs.match_id;
    if _gm_mf_is_mafia(roles->>st) then
      if ds = st then saved := true;
      elsif not (st = any(deaths)) then deaths := deaths || st; causes := causes || 'sniper'::text; end if;
    elsif not (sn = any(deaths)) then deaths := deaths || sn; causes := causes || 'backfire'::text; end if;
  end if;
  if dc is not null then
    update game_private set data = jsonb_set(data, array['checks', dc::text], to_jsonb(roles->>dc = 'mafia'))
     where match_id = gs.match_id and seat = det;
  end if;
  if doc is not null then
    update game_secret set data = data || jsonb_build_object('last_doc', ds,
       'doc_self', coalesce((data->>'doc_self')::boolean, false) or ds = doc) where match_id = gs.match_id;
    perform _gm_mf_priv(gs, doc, jsonb_build_object('last_save', ds, 'saved_ok', saved and ds is not null));
  end if;
  for i in 1 .. coalesce(array_length(deaths, 1), 0) loop
    gs := _gm_mf_kill(gs, deaths[i], causes[i]);
  end loop;
  if coalesce(array_length(deaths, 1), 0) = 0 then gs := _gm_mf_ev(gs, jsonb_build_object('k', 'no_victim')); end if;
  if saved then gs := _gm_mf_ev(gs, jsonb_build_object('k', 'saved')); end if;
  gs := _gm_mf_check(gs);
  if gs.status <> 'live' then return gs; end if;
  gs := _gm_mf_ev(gs, jsonb_build_object('k', 'day'));
  return _gm_mf_phase(gs, 'day'); end $$;

create or replace function public._gm_mf_start_night(gs game_state) returns game_state
language plpgsql as $$
begin
  gs.state := gs.state || jsonb_build_object('day', (gs.state->>'day')::int + 1, 'defendants', '[]'::jsonb);
  gs := _gm_mf_ev(gs, jsonb_build_object('k', 'night'));
  return _gm_mf_phase(gs, 'night'); end $$;

create or replace function public._gm_mf_resolve_nominate(gs game_state) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare votes jsonb := coalesce((_gm_mf_secret(gs))->'votes', '{}'::jsonb); alive int[] := _gm_mf_alive_seats(gs);
        thr int; tally jsonb := '{}'; top int := 0; defs int[]; s int; t int; skips int := 0; begin
  thr := case when array_length(alive, 1) <= 4 then 1 else 2 end;
  foreach s in array alive loop
    t := (votes->>s::text)::int;
    if t is null or t = s or not _gm_mf_alive(gs, t) then skips := skips + 1;
    else tally := tally || jsonb_build_object(t::text, coalesce((tally->>t::text)::int, 0) + 1); end if;
  end loop;
  select coalesce(max(v::int), 0) into top from jsonb_each_text(tally) x(k, v);
  if top >= thr then
    select array_agg(k::int order by k::int) into defs from jsonb_each_text(tally) x(k, v) where v::int = top;
    if array_length(defs, 1) > 3 then defs := null; end if;
  end if;
  gs.state := gs.state || jsonb_build_object('tally', tally, 'skips', skips, 'defendants', to_jsonb(coalesce(defs, '{}'::int[])));
  if defs is null then
    gs := _gm_mf_ev(gs, jsonb_build_object('k', 'no_trial'));
    return _gm_mf_start_night(gs);
  end if;
  gs := _gm_mf_ev(gs, jsonb_build_object('k', 'trial', 'ss', to_jsonb(defs)));
  return _gm_mf_phase(gs, 'defense'); end $$;

create or replace function public._gm_mf_resolve_final(gs game_state) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare votes jsonb := coalesce((_gm_mf_secret(gs))->'votes', '{}'::jsonb); alive int[] := _gm_mf_alive_seats(gs);
        defs int[] := _gm_ints(gs.state->'defendants'); tally jsonb := '{}'; spares int := 0; s int; t int; top int; leaders int[]; begin
  foreach s in array defs loop tally := tally || jsonb_build_object(s::text, 0); end loop;
  foreach s in array alive loop
    t := (votes->>s::text)::int;
    if t is null or t = s or not (t = any(defs)) or not _gm_mf_alive(gs, t) then spares := spares + 1;
    else tally := tally || jsonb_build_object(t::text, (tally->>t::text)::int + 1); end if;
  end loop;
  select max(v::int) into top from jsonb_each_text(tally) x(k, v);
  select array_agg(k::int) into leaders from jsonb_each_text(tally) x(k, v) where v::int = top;
  gs.state := gs.state || jsonb_build_object('tally', tally, 'skips', spares);
  if top > 0 and array_length(leaders, 1) = 1 and top > spares then
    gs := _gm_mf_kill(gs, leaders[1], 'vote_out');
    gs := _gm_mf_check(gs);
    if gs.status <> 'live' then return gs; end if;
  else
    gs := _gm_mf_ev(gs, jsonb_build_object('k', 'spared'));
  end if;
  return _gm_mf_start_night(gs); end $$;

-- everyone who must act tonight has acted?
create or replace function public._gm_mf_night_done(gs game_state) returns boolean
language plpgsql security definer set search_path to 'public' as $$
declare sec jsonb := _gm_mf_secret(gs); acted int[] := _gm_ints(sec->'acted'); s int; r text; begin
  foreach s in array _gm_mf_alive_seats(gs) loop
    r := sec->'roles'->>s;
    if r in ('godfather', 'mafia', 'doctor', 'detective') or (r = 'sniper' and coalesce((sec->>'bullets')::int, 0) > 0) then
      if not (s = any(acted)) then return false; end if;
    end if;
  end loop;
  return true; end $$;

create or replace function public._gm_mafia_move(gs game_state, seat int, mv jsonb) returns game_state
language plpgsql security definer set search_path to 'public' as $$
declare r text := _gm_mf_role(gs, seat); t int := (mv->>'t')::int; sec jsonb := _gm_mf_secret(gs); defs int[]; m int; key text; begin
  if not _gm_mf_alive(gs, seat) then raise exception 'you are out'; end if;
  case mv->>'a'
    when 'night' then
      if gs.phase <> 'night' then raise exception 'not now'; end if;
      if r not in ('godfather', 'mafia', 'doctor', 'detective', 'sniper') then raise exception 'no night action'; end if;
      if not _gm_mf_night_ok(gs, seat, r, t) then raise exception 'bad target'; end if;
      if r in ('godfather', 'mafia') then
        update game_secret set data = jsonb_set(data, '{act}', coalesce(data->'act', '{}'::jsonb)
                 || jsonb_build_object('maf', coalesce(data->'act'->'maf', '{}'::jsonb) || jsonb_build_object(seat::text, t)))
         where match_id = gs.match_id;
        -- every mafia sees the team's picks
        for m in select i - 1 from generate_subscripts(gs.seats, 1) i where _gm_mf_is_mafia(sec->'roles'->>(i - 1)) loop
          update game_private gp set data = gp.data || jsonb_build_object('team_pick',
                   coalesce(gp.data->'team_pick', '{}'::jsonb) || jsonb_build_object($2::text, t))
           where gp.match_id = gs.match_id and gp.seat = m;
        end loop;
      else
        key := case r when 'doctor' then 'doc' when 'detective' then 'det' else 'sni' end;
        update game_secret set data = jsonb_set(data, '{act}', coalesce(data->'act', '{}'::jsonb) || jsonb_build_object(key, t))
         where match_id = gs.match_id;
      end if;
      update game_secret set data = data || jsonb_build_object('acted', (select to_jsonb(array(select distinct x from unnest(_gm_ints(data->'acted') || seat) x))))
       where match_id = gs.match_id;
      perform _gm_mf_priv(gs, seat, jsonb_build_object('my_pick', t));
      if _gm_mf_night_done(gs) then return _gm_mf_resolve_night(gs); end if;
      return gs;
    when 'vote' then
      if gs.phase not in ('nominate', 'final') then raise exception 'not now'; end if;
      if t is not null then
        if t = seat or not _gm_mf_alive(gs, t) then raise exception 'bad target'; end if;
        defs := _gm_ints(gs.state->'defendants');
        if gs.phase = 'final' and not (t = any(defs)) then raise exception 'bad target'; end if;
      end if;
      update game_secret set data = jsonb_set(data, '{votes}', coalesce(data->'votes', '{}'::jsonb) || jsonb_build_object(seat::text, t))
       where match_id = gs.match_id;
      perform _gm_mf_priv(gs, seat, jsonb_build_object('my_vote', t));
      gs.state := jsonb_set(gs.state, array['voted', seat::text], 'true');
      if not exists(select 1 from unnest(_gm_mf_alive_seats(gs)) s where not coalesce((gs.state->'voted'->>s)::boolean, false)) then
        if gs.phase = 'nominate' then return _gm_mf_resolve_nominate(gs); end if;
        return _gm_mf_resolve_final(gs);
      end if;
      return gs;
    when 'ready' then
      if gs.phase not in ('day', 'defense') then raise exception 'not now'; end if;
      gs.state := jsonb_set(gs.state, array['ready', seat::text], 'true');
      if not exists(select 1 from unnest(_gm_mf_alive_seats(gs)) s where not coalesce((gs.state->'ready'->>s)::boolean, false)) then
        return _gm_mafia_tick(gs);
      end if;
      return gs;
    else raise exception 'bad move';
  end case; end $$;

-- deadline: the phase ends (missing night actions = none, missing votes = skip)
create or replace function public._gm_mafia_tick(gs game_state) returns game_state
language plpgsql security definer set search_path to 'public' as $$
begin
  case gs.phase
    when 'night' then return _gm_mf_resolve_night(gs);
    when 'day' then gs := _gm_mf_ev(gs, jsonb_build_object('k', 'vote')); return _gm_mf_phase(gs, 'nominate');
    when 'nominate' then return _gm_mf_resolve_nominate(gs);
    when 'defense' then return _gm_mf_phase(gs, 'final');
    else return _gm_mf_resolve_final(gs);
  end case; end $$;

-- leaving / resigning = the player dies (role revealed) and is out
create or replace function public._gm_mafia_resign(gs game_state, seat int) returns game_state
language plpgsql security definer set search_path to 'public' as $$
begin
  gs := _gm_mf_kill(gs, seat, 'left');
  gs.state := jsonb_set(gs.state, array['out', seat::text], 'true');
  return _gm_mf_check(gs); end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like '\_gm\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

-- server-side clock for every arcade match: overdue deadlines + players who left (every 10 s)
do $$ begin
  if exists(select 1 from cron.job where jobname = 'nexora-games') then perform cron.unschedule('nexora-games'); end if;
  perform cron.schedule('nexora-games', '10 seconds', 'select public.gm_sweep()');
end $$;
