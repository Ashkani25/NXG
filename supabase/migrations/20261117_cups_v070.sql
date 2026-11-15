-- NEXORA v0.7.0 tournaments (cups v4). Applied on top of cups.sql + 20261116_cups_plus.sql.
-- ADDITIVE and rerunnable: only new tables/columns/functions, widened check constraints, replaced function bodies,
-- tightened read policies/grants. No table or column with data is dropped.
--
--  1. cup_cancel: signed-in + row lock + null-safe organizer check (3e3ea31), EXECUTE for authenticated only.
--  2. formats: series_mode 'two_leg' (home/away legs, aggregate goals, optional away-goals rule, then a decider),
--     decider = 'golden_goal' (first goal wins) | 'game' (a full game); deciders for every tied format.
--     cup_games.leg / home_user / decider; per-game home side + goals set by _cup_try_start.
--  3. cup_ready: the 30 s pre-match lineup (team, formation; room host also pitch + ball) saved server-side;
--     the window opens on the first Play press (or when both are seated), closes early when both are ready,
--     defaults (equipped team, formation 0, room pitch/ball) when it runs out.
--  4. approvals: a rejected player cannot re-request; pending requests expire when check-in opens (10 min).
--  5. rankings: cup_rankings table (refreshed when a cup finishes) + cup_ranking() / cup_podium() RPCs, read-only.
--  6. cash prizes: cup_payouts gets provider/provider_ref + pg_notify('cup_payout_pending') hook for an external
--     payout worker. Nothing here moves real money.
--  7. RLS: cup tables readable by signed-in users only (anon revoked), cup_ledger only own rows / organizer,
--     old cup_create revoked (cup_create_v3 validates everything).
--  8. pg_cron 'nexora-cups' every 10 seconds (pg_cron 1.6 interval syntax), cup_tick extended.

-- ------------------------------------------------------------------ 1. cancel (from 3e3ea31)
create or replace function public.cup_cancel(p_cup uuid) returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c cups; begin
  if uid is null then raise exception 'not signed in'; end if;
  select * into c from cups where id = p_cup for update;
  if c.id is null then raise exception 'tournament not found'; end if;
  if c.created_by is distinct from uid then raise exception 'organizer only'; end if;
  if c.status <> 'registration' then raise exception 'already started'; end if;
  perform _cup_refund(p_cup, 'برگزارکننده تورنمنت را لغو کرد');
end $$;
revoke execute on function public.cup_cancel(uuid) from public, anon;
grant execute on function public.cup_cancel(uuid) to authenticated;

-- ------------------------------------------------------------------ 2. formats
alter table public.cups
  add column if not exists away_goals boolean not null default false,
  add column if not exists decider text not null default 'golden_goal';
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.cups'::regclass and conname = 'cups_decider_check') then
    alter table public.cups add constraint cups_decider_check check (decider in ('golden_goal','game'));
  end if;
  -- widen (never narrow) the series mode list
  if exists (select 1 from pg_constraint where conrelid = 'public.cups'::regclass and conname = 'cups_series_mode_check'
             and pg_get_constraintdef(oid) not like '%two_leg%') then
    alter table public.cups drop constraint cups_series_mode_check;
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.cups'::regclass and conname = 'cups_series_mode_check') then
    alter table public.cups add constraint cups_series_mode_check check (series_mode in ('legacy','single','aggregate','first_to','two_leg'));
  end if;
end $$;
alter table public.cup_games
  add column if not exists leg int,
  add column if not exists home_user uuid,
  add column if not exists decider boolean not null default false;
alter table public.cup_matches add column if not exists decider boolean not null default false;

-- Series result (mirrored in lib/online/cup_logic.dart seriesWinnerV3): 1 / 2 = that side won, 0 = play another game.
--  regulation = the first n games. single (n 1): the game's winner. first_to: first to target wins (n = 2*target-1).
--  aggregate (n games) and two_leg (n 2): regulation goals rg1:rg2; two_leg + away_goals: then goals scored away
--  (a1 = p1's goals in leg 2, a2 = p2's goals in leg 1). Still level -> decider games (game_no > n), each won by
--  its winner (dw1 / dw2 = decider wins). After 3 deciders without a winner the higher seed (side 1) advances.
create or replace function public._cup_series_winner_v3(mode text, n int, target int, w1 int, w2 int, rg1 int, rg2 int,
  played int, a1 int, a2 int, use_away boolean, dw1 int, dw2 int)
returns int language plpgsql immutable as $$
begin
  if mode is null or mode = 'legacy' then return public._cup_series_winner(n, w1, w2, rg1, rg2, played); end if;
  if mode = 'first_to' then
    if w1 >= target then return 1; end if;
    if w2 >= target then return 2; end if;
    if played < n then return 0; end if;
    if w1 <> w2 then return case when w1 > w2 then 1 else 2 end; end if;
  elsif mode = 'single' then
    if played < 1 then return 0; end if;
    if rg1 <> rg2 then return case when rg1 > rg2 then 1 else 2 end; end if;
  elsif mode in ('aggregate', 'two_leg') then
    if played < n then return 0; end if;
    if rg1 <> rg2 then return case when rg1 > rg2 then 1 else 2 end; end if;
    if mode = 'two_leg' and coalesce(use_away, false) and a1 <> a2 then return case when a1 > a2 then 1 else 2 end; end if;
  else
    raise exception 'bad series mode';
  end if;
  -- level after regulation: deciders
  if dw1 > dw2 then return 1; end if;
  if dw2 > dw1 then return 2; end if;
  if played >= n + 3 then return 1; end if;
  return 0;
end $$;

-- the number of regulation games for a cup (decider games come after these)
create or replace function public._cup_reg_games(c public.cups) returns int language sql immutable as $$
  select case when c.series_mode = 'two_leg' then 2 when c.series_mode = 'single' then 1 else c.games end $$;

create or replace function public.cup_create_v3(
  p_name text, p_max int, p_mode text, p_games int, p_target_wins int, p_goals int, p_starts timestamptz,
  p_prize int, p_split int[], p_join boolean, p_require_approval boolean,
  p_away_goals boolean, p_decider text, p_prize_title text, p_cash_prize numeric, p_cash_currency text
) returns public.cups language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c cups; cd text; sp int[] := coalesce(p_split, '{60,30,10}'); mode text := coalesce(p_mode, '');
        games int := coalesce(p_games, 0); wins int := coalesce(p_target_wins, 1); dec text := coalesce(p_decider, 'golden_goal');
        cash numeric := round(coalesce(p_cash_prize, 0), 2); curr text := upper(trim(coalesce(p_cash_currency, '')));
begin
  if uid is null then raise exception 'not signed in'; end if;
  if char_length(trim(coalesce(p_name, ''))) < 3 or char_length(trim(coalesce(p_name, ''))) > 40 then raise exception 'title required'; end if;
  if p_max is null or p_max < 2 or p_max > public._cupc('max_players') then raise exception 'bad size'; end if;
  if p_goals is null or p_goals < 1 or p_goals > 10 then raise exception 'bad format'; end if;
  if p_starts is null or p_starts < now() + interval '2 minutes' or p_starts > now() + interval '60 days' then raise exception 'bad start time'; end if;
  if p_prize is null or p_prize < 0 or p_prize > public._cupc('max_prize') then raise exception 'bad prize'; end if;
  if coalesce(array_length(sp, 1), 0) <> 3 or sp[1] < sp[2] or sp[2] < sp[3] or sp[3] < 0 or sp[1] + sp[2] + sp[3] <> 100 then raise exception 'bad split'; end if;
  if dec not in ('golden_goal', 'game') then raise exception 'bad series'; end if;
  if mode = 'single' then games := 1; wins := 1;
  elsif mode = 'two_leg' then games := 2; wins := 1;
  elsif mode = 'aggregate' then
    if games < 2 or games > public._cupc('max_games') then raise exception 'bad series'; end if; wins := 1;
  elsif mode = 'first_to' then
    if wins < 1 or wins > 5 then raise exception 'bad series'; end if; games := 2 * wins - 1;
  else raise exception 'bad series'; end if;
  if cash < 0 or cash > 9999999999.99 then raise exception 'bad cash prize'; end if;
  if (cash > 0 and curr = '') or char_length(curr) > 12 then raise exception 'cash currency required'; end if;
  if char_length(coalesce(p_prize_title, '')) > 120 then raise exception 'prize title too long'; end if;
  if (select count(*) from cups where created_by = uid and status in ('registration', 'running')) >= 3 then raise exception 'too many open tournaments'; end if;
  if p_prize > 0 then
    update profiles set gems = gems - p_prize where id = uid and gems >= p_prize;
    if not found then raise exception 'not enough gems'; end if;
  end if;
  loop
    cd := (10000 + floor(random() * 90000))::int::text;
    exit when not exists (select 1 from cups where code = cd);
  end loop;
  insert into cups(code, name, created_by, max_players, games, goals, starts_at, prize, split, escrow,
                   require_approval, series_mode, target_wins, prize_title, cash_prize, cash_currency, away_goals, decider)
    values (cd, trim(p_name), uid, p_max, games, p_goals, date_trunc('minute', p_starts), p_prize, sp, p_prize,
            coalesce(p_require_approval, false), mode, wins, left(trim(coalesce(p_prize_title, '')), 120), cash, nullif(curr, ''),
            mode = 'two_leg' and coalesce(p_away_goals, false), dec) returning * into c;
  if p_prize > 0 then insert into cup_ledger(cup_id, user_id, kind, place, gems) values (c.id, uid, 'escrow', 0, -p_prize); end if;
  if coalesce(p_join, true) then insert into cup_players(cup_id, user_id, status) values (c.id, uid, 'main'); end if;
  return c;
end $$;

-- ------------------------------------------------------------------ 3. lineup / ready
create table if not exists public.cup_lineups (
  match_id uuid not null references public.cup_matches(id) on delete cascade,
  game_no int not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  team_id text, formation int not null default 0,
  field int, ball int,
  ready_at timestamptz not null default now(),
  primary key (match_id, game_no, user_id)
);
alter table public.cup_lineups enable row level security;
drop policy if exists "cup_lineups players read" on public.cup_lineups;
create policy "cup_lineups players read" on public.cup_lineups for select to authenticated using (
  exists (select 1 from public.cup_matches m where m.id = cup_lineups.match_id and auth.uid() in (m.p1, m.p2)));
grant select on public.cup_lineups to authenticated;
revoke all on public.cup_lineups from anon;
revoke insert, update, delete on public.cup_lineups from authenticated;
do $$ begin
  begin alter publication supabase_realtime add table public.cup_lineups; exception when others then null; end;
end $$;

-- start the next game of a pairing: both players seated and the lineup window over. Sets the home side
-- (two_leg: p2 is home in leg 2), the goal target (golden-goal decider = 1) and both formations from cup_lineups.
create or replace function public._cup_try_start(p_m uuid) returns void language plpgsql security definer set search_path = public as $$
declare m cup_matches; r rooms; c cups; gno int; home uuid; dec boolean; g int; f0 int; f1 int; begin
  select * into m from cup_matches where id = p_m for update;
  if m.status not in ('ready','live') or m.room_id is null then return; end if;
  select * into r from rooms where id = m.room_id;
  if r.id is null or r.status <> 'waiting' then return; end if;
  if not (_cup_present(r.id, m.p1) and _cup_present(r.id, m.p2)) then
    if m.lineup_until is not null and not exists (select 1 from cup_lineups where match_id = m.id and game_no = m.games_played + 1) then
      update cup_matches set lineup_until = null where id = p_m;
    end if;
    return;
  end if;
  if m.lineup_until is null then
    update cup_matches set lineup_until = now() + make_interval(secs => _cupc('lineup_s')) where id = p_m; return;
  end if;
  if now() < m.lineup_until then return; end if;
  select * into c from cups where id = m.cup_id;
  gno := m.games_played + 1;
  dec := gno > public._cup_reg_games(c) and coalesce(c.series_mode, 'legacy') <> 'legacy';
  home := case when c.series_mode = 'two_leg' and gno = 2 then m.p2 else m.p1 end;
  update room_players set team = case when user_id = home then 0 else 1 end, slot = 0, role = 'player'
    where room_id = r.id and user_id in (m.p1, m.p2);
  g := case when dec and c.decider = 'golden_goal' then 1 else c.goals end;
  select coalesce(max(formation) filter (where user_id = home), 0), coalesce(max(formation) filter (where user_id <> home), 0)
    into f0, f1 from cup_lineups where match_id = m.id and game_no = gno;
  update rooms set settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('goals', g, 'win', g, 'time', 0,
      'leg', gno, 'decider', dec, 'home', home, 'forms', jsonb_build_array(coalesce(f0, 0), coalesce(f1, 0))), updated_at = now()
    where id = r.id;
  update cup_matches set decider = dec where id = p_m;
  begin
    perform set_config('nexora.cup_start', '1', true);
    perform _start_match(r.id, false);
    perform set_config('nexora.cup_start', '', true);
  exception when others then
    perform set_config('nexora.cup_start', '', true);
    return;
  end;
  update cup_matches set status = 'live', lineup_until = null, wait_from = now() where id = p_m;
end $$;

create or replace function public.cup_ready(p_match uuid, p_team text, p_formation int, p_field int default null, p_ball int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m cup_matches; r rooms; gno int; host boolean; n int; tm text := nullif(left(trim(coalesce(p_team, '')), 40), ''); begin
  if uid is null then raise exception 'not signed in'; end if;
  select * into m from cup_matches where id = p_match for update;
  if m.id is null or uid not in (m.p1, m.p2) then raise exception 'not in this match'; end if;
  if m.status not in ('ready', 'live') or m.room_id is null then raise exception 'match not ready'; end if;
  select * into r from rooms where id = m.room_id for update;
  if r.status <> 'waiting' then raise exception 'match not ready'; end if;
  if m.lineup_until is not null and now() >= m.lineup_until then raise exception 'lineup closed'; end if;
  gno := m.games_played + 1;
  host := r.host = uid;
  if p_field is not null and (p_field < 0 or p_field > 39) then raise exception 'bad room assets'; end if;
  if p_ball is not null and (p_ball < 0 or p_ball > 35) then raise exception 'bad room assets'; end if;
  insert into cup_lineups(match_id, game_no, user_id, team_id, formation, field, ball, ready_at)
    values (m.id, gno, uid, tm, greatest(0, least(coalesce(p_formation, 0), 9)), case when host then p_field end, case when host then p_ball end, now())
    on conflict (match_id, game_no, user_id) do update set team_id = excluded.team_id, formation = excluded.formation,
      field = excluded.field, ball = excluded.ball, ready_at = now();
  update room_players set disc_id = coalesce(tm, disc_id), last_seen = now() where room_id = r.id and user_id = uid;
  if host and (p_field is not null or p_ball is not null) then
    update rooms set settings = coalesce(settings, '{}'::jsonb)
      || case when p_field is not null then jsonb_build_object('field', p_field) else '{}'::jsonb end
      || case when p_ball is not null then jsonb_build_object('ball', p_ball) else '{}'::jsonb end,
      updated_at = now() where id = r.id;
  end if;
  -- the first press opens the 30 s window; both ready -> start now
  select count(*) into n from cup_lineups where match_id = m.id and game_no = gno and user_id in (m.p1, m.p2);
  if n >= 2 then
    update cup_matches set lineup_until = now() where id = m.id;
  elsif m.lineup_until is null then
    update cup_matches set lineup_until = now() + make_interval(secs => _cupc('lineup_s')) where id = m.id;
  end if;
  update rooms set updated_at = now() where id = r.id;
  perform _cup_try_start(m.id);
  select * into m from cup_matches where id = m.id;
  return jsonb_build_object('now', now(), 'lineup_until', m.lineup_until, 'status', m.status, 'game_no', gno, 'ready', n,
                            'host', host, 'games_played', m.games_played);
end $$;

-- ------------------------------------------------------------------ results: per-leg bookkeeping + v3 winner
create or replace function public._cup_on_match() returns trigger language plpgsql security definer set search_path = public as $$
declare mid uuid; m cup_matches; c cups; flip boolean; g1 int; g2 int; w int; n int; gno int; rs jsonb;
        rg1 int; rg2 int; a1 int; a2 int; dw1 int; dw2 int; begin
  if new.status = old.status or new.status = 'live' then return new; end if;
  select cup_match_id, settings into mid, rs from rooms where id = new.room_id;
  if mid is null then return new; end if;
  if new.bots then return new; end if;
  if new.status = 'abandoned' then
    update cup_matches set wait_from = now(), lineup_until = null where id = mid and status in ('ready','live');
    return new;
  end if;
  select * into m from cup_matches where id = mid for update;
  if m.status not in ('ready','live') then return new; end if;
  select * into c from cups where id = m.cup_id;
  n := public._cup_reg_games(c);
  gno := m.games_played + 1;
  flip := coalesce(new.team_a[1] = m.p2, false);
  g1 := coalesce(case when flip then new.score_b else new.score_a end, 0);
  g2 := coalesce(case when flip then new.score_a else new.score_b end, 0);
  insert into cup_games(match_id, game_no, match_ref, g1, g2, winner, leg, home_user, decider)
    values (mid, gno, new.id, g1, g2, case when g1 > g2 then m.p1 when g2 > g1 then m.p2 end,
            case when gno <= n then gno end, case when flip then m.p2 else m.p1 end, gno > n and coalesce(c.series_mode, 'legacy') <> 'legacy')
    on conflict do nothing;
  if not found then return new; end if;
  update cup_matches set games_played = games_played + 1, wins1 = wins1 + (g1 > g2)::int, wins2 = wins2 + (g2 > g1)::int,
    goals1 = goals1 + g1, goals2 = goals2 + g2, wait_from = now(),
    lineup_until = now() + make_interval(secs => _cupc('gap_s') + _cupc('lineup_s')) where id = mid returning * into m;
  select coalesce(sum(cg.g1) filter (where cg.game_no <= n), 0), coalesce(sum(cg.g2) filter (where cg.game_no <= n), 0),
         coalesce(sum(cg.g1) filter (where cg.game_no <= n and cg.home_user = m.p2), 0),
         coalesce(sum(cg.g2) filter (where cg.game_no <= n and cg.home_user = m.p1), 0),
         count(*) filter (where cg.game_no > n and cg.g1 > cg.g2), count(*) filter (where cg.game_no > n and cg.g2 > cg.g1)
    into rg1, rg2, a1, a2, dw1, dw2 from cup_games cg where cg.match_id = mid;
  w := public._cup_series_winner_v3(c.series_mode, n, c.target_wins, m.wins1, m.wins2, rg1, rg2, m.games_played, a1, a2, c.away_goals, dw1, dw2);
  if w = 1 then perform _cup_advance(mid, m.p1, m.p2, false);
  elsif w = 2 then perform _cup_advance(mid, m.p2, m.p1, false); end if;
  return new;
end $$;

-- ------------------------------------------------------------------ 4. approvals
create or replace function public.cup_join(p_code text) returns public.cups language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c cups; st text; n int; begin
  if uid is null then raise exception 'not signed in'; end if;
  select * into c from cups where code = trim(p_code) for update;
  if c.id is null then raise exception 'tournament not found'; end if;
  if exists (select 1 from cup_players where cup_id = c.id and user_id = uid and status in ('pending','main','wait')) then return c; end if;
  if exists (select 1 from cup_players where cup_id = c.id and user_id = uid and note = 'rejected') then raise exception 'request rejected'; end if;
  if c.status <> 'registration' or now() >= c.starts_at then raise exception 'registration closed'; end if;
  if c.require_approval and now() >= c.starts_at - make_interval(mins => _cupc('checkin_min')) then raise exception 'registration closed'; end if;
  select count(*) into n from cup_players where cup_id = c.id and status = 'main';
  st := case when c.require_approval then 'pending' when n < c.max_players then 'main' else 'wait' end;
  insert into cup_players(cup_id, user_id, status) values (c.id, uid, st)
    on conflict (cup_id, user_id) do update set status = excluded.status, joined_at = clock_timestamp(), checked_in_at = null, note = null;
  if st = 'pending' then
    perform public._notify(c.created_by, 'cup_join_request', 'درخواست عضویت در «' || c.name || '»', 'یک بازیکن منتظر تأیید توست', jsonb_build_object('cup', c.id, 'user', uid));
  end if;
  return c;
end $$;

create or replace function public._cup_expire_pending(p_cup uuid) returns void language plpgsql security definer set search_path = public as $$
declare c cups; begin
  select * into c from cups where id = p_cup;
  insert into notifications(user_id, kind, title, body, data)
    select user_id, 'cup_rejected', 'درخواست «' || c.name || '» منقضی شد', 'برگزارکننده پیش از زمان اعلام حضور تأیید نکرد', jsonb_build_object('cup', c.id)
    from cup_players where cup_id = p_cup and status = 'pending';
  update cup_players set status = 'out', note = 'approval expired' where cup_id = p_cup and status = 'pending';
end $$;

-- ------------------------------------------------------------------ 5. rankings
create table if not exists public.cup_rankings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  cups_played int not null default 0,
  titles int not null default 0, runner_up int not null default 0, third int not null default 0, fourth int not null default 0,
  series_wins int not null default 0, series_losses int not null default 0,
  goals_for int not null default 0, goals_against int not null default 0,
  points int not null default 0,
  last_cup_at timestamptz,
  updated_at timestamptz not null default now()
);
create index if not exists cup_rankings_points_idx on public.cup_rankings(points desc, titles desc);
alter table public.cup_rankings enable row level security;
drop policy if exists "cup_rankings read" on public.cup_rankings;
create policy "cup_rankings read" on public.cup_rankings for select to authenticated using (true);
grant select on public.cup_rankings to authenticated;
revoke all on public.cup_rankings from anon;
revoke insert, update, delete on public.cup_rankings from authenticated;

-- points (mirrored in lib/online/cup_logic.dart cupRankPoints): 1st 25, 2nd 15, 3rd 10, 4th 6, +2 per finished cup
-- played (drawn into the bracket), +3 per series won.
create or replace function public._cup_rank_points(t int, r2 int, r3 int, r4 int, cups int, sw int) returns int language sql immutable as $$
  select 25 * t + 15 * r2 + 10 * r3 + 6 * r4 + 2 * cups + 3 * sw $$;

create or replace function public._cup_rank_refresh(p_users uuid[]) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into cup_rankings as k (user_id, cups_played, titles, runner_up, third, fourth, series_wins, series_losses, goals_for, goals_against, points, last_cup_at, updated_at)
  select u, s.cp, s.t, s.r2, s.r3, s.r4, s.sw, s.sl, s.gf, s.ga, _cup_rank_points(s.t, s.r2, s.r3, s.r4, s.cp, s.sw), s.last_at, now()
  from unnest(p_users) u
  cross join lateral (
    select count(*)::int cp,
           count(*) filter (where p.final_place = 1)::int t, count(*) filter (where p.final_place = 2)::int r2,
           count(*) filter (where p.final_place = 3)::int r3, count(*) filter (where p.final_place = 4)::int r4,
           max(c.finished_at) last_at
    from cup_players p join cups c on c.id = p.cup_id
    where p.user_id = u and c.status = 'finished' and p.seed is not null) a
  cross join lateral (
    select a.cp, a.t, a.r2, a.r3, a.r4, a.last_at,
           count(*) filter (where m.winner = u and m.loser is not null)::int sw,
           count(*) filter (where m.loser = u)::int sl,
           coalesce(sum(case when m.p1 = u then m.goals1 when m.p2 = u then m.goals2 else 0 end), 0)::int gf,
           coalesce(sum(case when m.p1 = u then m.goals2 when m.p2 = u then m.goals1 else 0 end), 0)::int ga
    from cup_matches m join cups c on c.id = m.cup_id
    where c.status = 'finished' and u in (m.p1, m.p2)) s
  on conflict (user_id) do update set cups_played = excluded.cups_played, titles = excluded.titles, runner_up = excluded.runner_up,
    third = excluded.third, fourth = excluded.fourth, series_wins = excluded.series_wins, series_losses = excluded.series_losses,
    goals_for = excluded.goals_for, goals_against = excluded.goals_against, points = excluded.points,
    last_cup_at = excluded.last_cup_at, updated_at = now();
end $$;

create or replace function public._cup_rank_on_finish() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'finished' and old.status is distinct from 'finished' then
    perform _cup_rank_refresh(array(select user_id from cup_players where cup_id = new.id and seed is not null));
  end if;
  return new;
end $$;
drop trigger if exists trg_cup_rank_on_finish on public.cups;
create trigger trg_cup_rank_on_finish after update of status on public.cups for each row execute function public._cup_rank_on_finish();

create or replace function public.cup_ranking(p_limit int default 100, p_offset int default 0) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x.rank), '[]'::jsonb) from (
    select row_number() over (order by k.points desc, k.titles desc, k.series_wins desc, (k.goals_for - k.goals_against) desc, k.user_id) as rank,
           k.user_id, p.username, p.avatar, p.avatar_url, k.points, k.cups_played, k.titles, k.runner_up, k.third, k.fourth,
           k.series_wins, k.series_losses, k.goals_for, k.goals_against
    from cup_rankings k join profiles p on p.id = k.user_id
    where k.cups_played > 0
    order by rank
    offset greatest(coalesce(p_offset, 0), 0) limit least(greatest(coalesce(p_limit, 100), 1), 200)) x $$;

create or replace function public.cup_podium(p_cup uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('place', p.final_place, 'user_id', p.user_id, 'username', pr.username,
                  'avatar', pr.avatar, 'avatar_url', pr.avatar_url) order by p.final_place), '[]'::jsonb)
  from cup_players p join profiles pr on pr.id = p.user_id
  where p.cup_id = p_cup and p.final_place between 1 and 4 $$;

-- ------------------------------------------------------------------ 6. cash prize payout hook
alter table public.cup_payouts
  add column if not exists provider text,
  add column if not exists provider_ref text;
create or replace function public._cup_payout_hook() returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- HOOK: an external payout worker (edge function / backend with a payment provider) can LISTEN on this channel,
  -- pay the winner, then record provider + provider_ref and the organizer marks it paid. Nothing here moves money.
  perform pg_notify('cup_payout_pending', jsonb_build_object('cup', new.cup_id, 'place', new.place, 'user', new.user_id,
                    'amount', new.amount, 'currency', new.currency)::text);
  return new;
end $$;
drop trigger if exists trg_cup_payout_hook on public.cup_payouts;
create trigger trg_cup_payout_hook after insert on public.cup_payouts for each row execute function public._cup_payout_hook();

-- ------------------------------------------------------------------ 7. RLS / grants
do $$ begin
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'cup_ledger' and policyname = 'cup_ledger read') then
    drop policy "cup_ledger read" on public.cup_ledger;
  end if;
end $$;
drop policy if exists "cup_ledger own" on public.cup_ledger;
create policy "cup_ledger own" on public.cup_ledger for select to authenticated using (
  user_id = auth.uid() or exists (select 1 from public.cups c where c.id = cup_ledger.cup_id and c.created_by = auth.uid()));
revoke select on public.cups, public.cup_players, public.cup_matches, public.cup_games, public.cup_ledger from anon;
grant select on public.cups, public.cup_players, public.cup_matches, public.cup_games, public.cup_ledger to authenticated;
revoke execute on function public.cup_create(text, int, int, int, timestamptz, int, int[], boolean) from public, anon, authenticated;

revoke execute on function public._cup_series_winner_v3(text, int, int, int, int, int, int, int, int, int, boolean, int, int),
  public._cup_reg_games(public.cups), public._cup_expire_pending(uuid), public._cup_rank_points(int, int, int, int, int, int),
  public._cup_rank_refresh(uuid[]), public._cup_rank_on_finish(), public._cup_payout_hook(), public._cup_try_start(uuid),
  public._cup_on_match() from public, anon, authenticated;
revoke execute on function public.cup_create_v3(text, int, text, int, int, int, timestamptz, int, int[], boolean, boolean, boolean, text, text, numeric, text),
  public.cup_ready(uuid, text, int, int, int), public.cup_ranking(int, int), public.cup_podium(uuid), public.cup_join(text) from public, anon;
grant execute on function public.cup_create_v3(text, int, text, int, int, int, timestamptz, int, int[], boolean, boolean, boolean, text, text, numeric, text),
  public.cup_ready(uuid, text, int, int, int), public.cup_ranking(int, int), public.cup_podium(uuid), public.cup_join(text) to authenticated;

-- ------------------------------------------------------------------ 8. the clock
create or replace function public.cup_tick() returns void language plpgsql security definer set search_path = public as $$
declare c record; m record; p1 boolean; p2 boolean; w uuid; l uuid; begin
  if not pg_try_advisory_xact_lock(hashtext('nexora-cup-tick')) then return; end if;
  -- 10 min before start: pending approvals expire, reminder + check-in opens
  for c in select * from cups where status = 'registration' and not reminded and now() >= starts_at - make_interval(mins => _cupc('remind_min')) loop
    update cups set reminded = true where id = c.id;
    begin perform _cup_expire_pending(c.id); exception when others then raise warning 'cup_expire %: %', c.id, sqlerrm; end;
    insert into notifications(user_id, kind, title, body, data)
      select user_id, 'cup_soon', '⏰ «' || c.name || '» ساعت ' || to_char(c.starts_at at time zone 'Asia/Tehran', 'HH24:MI') || ' شروع می‌شود',
             'اعلام حضور کن؛ بدون اعلام حضور از قرعه‌کشی حذف می‌شوی', jsonb_build_object('cup', c.id)
      from cup_players where cup_id = c.id and status in ('main','wait');
  end loop;
  for c in select id from cups where status = 'registration' and now() >= starts_at - make_interval(mins => _cupc('replace_min')) and now() < starts_at loop
    begin perform _cup_fill(c.id); exception when others then raise warning 'cup_fill %: %', c.id, sqlerrm; end;
  end loop;
  for c in select id from cups where status = 'registration' and now() >= starts_at order by starts_at loop
    begin perform _cup_draw(c.id); exception when others then raise warning 'cup_draw %: %', c.id, sqlerrm; end;
  end loop;
  for m in select cm.* from cup_matches cm join cups cc on cc.id = cm.cup_id where cc.status = 'running' and cm.status in ('pending','ready','live') loop
   begin
    if m.status = 'pending' then
      if not m.reminded and m.p1 is not null and m.p2 is not null and now() >= m.scheduled_at - make_interval(mins => _cupc('remind_min')) then
        update cup_matches set reminded = true where id = m.id;
        perform _notify(u, 'cup_match_soon', '⏰ مسابقه‌ی بعدی‌ات ساعت ' || to_char(greatest(m.scheduled_at, now()) at time zone 'Asia/Tehran', 'HH24:MI'),
                        'آماده باش؛ مسابقه خودکار شروع می‌شود', jsonb_build_object('cup', m.cup_id, 'match', m.id)) from unnest(array[m.p1, m.p2]) u;
      end if;
      perform _cup_check_ready(m.id);
      continue;
    end if;
    perform _cup_try_start(m.id);
    if exists (select 1 from rooms where id = m.room_id and status = 'playing') then continue; end if;
    if m.wait_from is null or now() < m.wait_from + make_interval(mins => _cupc('noshow_min')) then continue; end if;
    p1 := m.room_id is not null and _cup_present(m.room_id, m.p1);
    p2 := m.room_id is not null and _cup_present(m.room_id, m.p2);
    if p1 and p2 then continue; end if;
    if p1 then w := m.p1; l := m.p2;
    elsif p2 then w := m.p2; l := m.p1;
    elsif m.wins2 > m.wins1 or (m.wins2 = m.wins1 and m.goals2 > m.goals1) then w := m.p2; l := m.p1;
    else w := m.p1; l := m.p2; end if;
    perform _cup_advance(m.id, w, l, true);
   exception when others then raise warning 'cup match %: %', m.id, sqlerrm;
   end;
  end loop;
end $$;
revoke execute on function public.cup_tick() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('nexora-cups') where exists (select 1 from cron.job where jobname = 'nexora-cups');
  perform cron.schedule('nexora-cups', '10 seconds', 'select public.cup_tick()');
end $$;

notify pgrst, 'reload schema';
