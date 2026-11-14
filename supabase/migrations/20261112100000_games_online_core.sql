-- NEXORA online games: core (rooms carry a game, generic server-authoritative state, results).
-- ADDITIVE ONLY: one new column with a default on rooms, new tables, new functions, guard triggers.
-- Football (Expo + Godot) keeps working unchanged:
--   * rooms.game defaults to 'football'; rooms_mode_check is NOT touched (arcade rooms use 1v1/2v2/3v3 too).
--   * arcade matches live in public.game_state, never in public.matches, so football's monthly_ranking,
--     _sweep_rooms, report_match and abandon_match never see them.
--   * room_list (the football hub list) only shows football rooms; arcade rooms are in game_room_list.
--   * guard triggers stop a football RPC from starting/finishing a football match inside an arcade room.

-- 1. rooms carry the game ---------------------------------------------------------------------
alter table public.rooms add column if not exists game text not null default 'football';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'rooms_game_check') then
    alter table public.rooms add constraint rooms_game_check check (game in
      ('football','uno','backgammon','ludo','billiards','carrom','snakes_ladders','mafia','quiz'));
  end if;
end $$;
create index if not exists rooms_game_idx on public.rooms(game, status);

-- Football clients (Expo + Godot hubs) list room_list: keep it football-only. Same columns, same order.
create or replace view public.room_list as
 SELECT r.id, r.code, r.name, r.mode, r.kind, r.tier, r.status, r.is_private, r.ranked, r.voice, r.settings,
    r.created_at, r.host, h.username AS host_name, h.avatar AS host_avatar, h.avatar_url AS host_avatar_url,
    h.level AS host_level, h.league AS host_league,
    (( SELECT count(*) FROM room_players p WHERE p.room_id = r.id AND p.role = 'player'::text))::integer AS players,
    (( SELECT count(*) FROM room_players p WHERE p.room_id = r.id AND p.role = 'spectator'::text))::integer AS spectators,
    room_size(r.mode) * 2 AS capacity
   FROM rooms r JOIN profiles h ON h.id = r.host
  WHERE NOT r.is_private AND r.updated_at > (now() - '02:00:00'::interval) AND r.game = 'football';

-- Rooms of the eight arcade games with their real capacity.
create or replace view public.game_room_list as
 SELECT r.id, r.code, r.name, r.game, r.mode, r.kind, r.status, r.is_private, r.ranked, r.voice, r.settings,
    r.created_at, r.host, h.username AS host_name, h.avatar AS host_avatar, h.avatar_url AS host_avatar_url, h.level AS host_level,
    (( SELECT count(*) FROM room_players p WHERE p.room_id = r.id AND p.role = 'player'))::integer AS players,
    (( SELECT count(*) FROM room_players p WHERE p.room_id = r.id AND p.role = 'spectator'))::integer AS spectators,
    coalesce((r.settings->>'seats')::int, room_size(r.mode) * 2) AS capacity
   FROM rooms r JOIN profiles h ON h.id = r.host
  WHERE NOT r.is_private AND r.game <> 'football' AND r.updated_at > (now() - '02:00:00'::interval);
grant select on public.game_room_list to anon, authenticated;

-- 2. generic game state (one row per arcade match) -------------------------------------------
create table if not exists public.game_state (
  match_id   uuid primary key default gen_random_uuid(),
  room_id    uuid references public.rooms(id) on delete set null,
  game       text not null,
  seats      uuid[] not null,              -- seat index (0-based) -> user id
  ranked     boolean not null default true,
  status     text not null default 'live' check (status in ('live','finished','abandoned')),
  phase      text not null default '',
  turn       int  not null default 0,      -- seat to act (turn games)
  version    int  not null default 0,      -- bumps on every change
  state      jsonb not null default '{}'::jsonb,   -- PUBLIC state (no secrets)
  deadline   timestamptz,                  -- when the server may act for an idle player / end a phase
  result     jsonb,                        -- {winners:[seat], scores:[..], reason}
  authority  text not null default 'server' check (authority in ('server','host')),
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  ended_at   timestamptz
);
create index if not exists game_state_room_idx on public.game_state(room_id, started_at desc);
create index if not exists game_state_live_idx on public.game_state(deadline) where status = 'live';
alter table public.game_state enable row level security;
drop policy if exists "game_state read" on public.game_state;
create policy "game_state read" on public.game_state for select to authenticated using (true);

-- private per-player data (cards in hand, secret role, detective results): only the owner can read it
create table if not exists public.game_private (
  match_id uuid not null references public.game_state(match_id) on delete cascade,
  user_id  uuid not null references public.profiles(id) on delete cascade,
  seat     int  not null,
  data     jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (match_id, user_id)
);
alter table public.game_private enable row level security;
drop policy if exists "game_private own" on public.game_private;
create policy "game_private own" on public.game_private for select to authenticated using (user_id = auth.uid());

-- server-only secrets (draw pile, all roles, pending night actions, quiz answers): no policy = no client access
create table if not exists public.game_secret (
  match_id uuid primary key references public.game_state(match_id) on delete cascade,
  data jsonb not null default '{}'::jsonb
);
alter table public.game_secret enable row level security;

-- move log (replays / audit). Secret moves (mafia) are visible only to their author.
create table if not exists public.game_moves (
  id bigserial primary key,
  match_id uuid not null references public.game_state(match_id) on delete cascade,
  seq int not null,
  user_id uuid,
  seat int,
  move jsonb not null,
  secret boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists game_moves_match_idx on public.game_moves(match_id, seq);
alter table public.game_moves enable row level security;
drop policy if exists "game_moves read" on public.game_moves;
create policy "game_moves read" on public.game_moves for select to authenticated using (not secret or user_id = auth.uid());

-- per-game rating + record (football's profiles.rating / wins / losses are never touched)
create table if not exists public.game_ratings (
  user_id uuid not null references public.profiles(id) on delete cascade,
  game text not null,
  rating int not null default 1000,
  played int not null default 0,
  wins int not null default 0,
  losses int not null default 0,
  draws int not null default 0,
  streak int not null default 0,
  best_streak int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, game)
);
alter table public.game_ratings enable row level security;
drop policy if exists "game_ratings read" on public.game_ratings;
create policy "game_ratings read" on public.game_ratings for select using (true);

create or replace view public.game_leaderboard as
  select g.game, g.user_id, p.username, p.avatar, p.avatar_url, p.level, g.rating, g.played, g.wins, g.losses, g.draws,
         g.streak, g.best_streak, rank() over (partition by g.game order by g.rating desc, g.wins desc) as rank
  from public.game_ratings g join public.profiles p on p.id = g.user_id;
grant select on public.game_leaderboard to anon, authenticated;

do $$ begin
  begin alter publication supabase_realtime add table public.game_state; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.game_private; exception when duplicate_object then null; end;
end $$;

-- 3. helpers ---------------------------------------------------------------------------------
create or replace function public._gm_bounds(p_game text, out min_seats int, out max_seats int)
language sql immutable as $$
  select case p_game when 'mafia' then 6 else 2 end,
         case p_game when 'uno' then 6 when 'ludo' then 4 when 'snakes_ladders' then 4 when 'quiz' then 4
                     when 'mafia' then 12 else 2 end $$;

create or replace function public._gm_arcade(p_game text) returns boolean language sql immutable as $$
  select coalesce(p_game in ('uno','backgammon','ludo','billiards','carrom','snakes_ladders','mafia','quiz'), false) $$;

-- seat index <-> (team, slot): seat = slot*2 + team, the same order football's _autoseat fills
create or replace function public._gm_seat_of(p_team smallint, p_slot smallint) returns int language sql immutable as $$
  select p_slot::int * 2 + p_team::int $$;

create or replace function public._gm_rand(n int) returns int language sql volatile as $$
  select floor(random() * n)::int $$;   -- 0..n-1 (server RNG; clients never roll)

create or replace function public._gm_die() returns int language sql volatile as $$ select 1 + floor(random() * 6)::int $$;

-- shuffled 0..n-1
create or replace function public._gm_shuffle(n int) returns int[] language sql volatile as $$
  select coalesce(array_agg(i order by random()), '{}') from generate_series(0, n - 1) i $$;

create or replace function public._gm_seat_capacity(r rooms) returns int language sql stable as $$
  select coalesce((r.settings->>'seats')::int, room_size(r.mode) * 2) $$;

create or replace function public._gm_autoseat(r rooms, uid uuid) returns void
language plpgsql security definer set search_path to 'public' as $$
declare cap int := _gm_seat_capacity(r); s int; begin
  for s in 0..cap - 1 loop
    if not exists(select 1 from room_players where room_id = r.id and role = 'player' and _gm_seat_of(team, slot) = s) then
      update room_players set role = 'player', team = (s % 2)::smallint, slot = (s / 2)::smallint, ready = false
        where room_id = r.id and user_id = uid;
      return;
    end if;
  end loop;
  update room_players set role = 'spectator', team = null, slot = null, ready = false where room_id = r.id and user_id = uid;
end $$;

-- 4. lobby RPCs -------------------------------------------------------------------------------
create or replace function public.gm_create_room(p_game text, p_seats int default 2, p_name text default null,
  p_private boolean default false, p_settings jsonb default '{}'::jsonb, p_quick boolean default false)
returns rooms language plpgsql security definer set search_path to 'public' as $$
declare r rooms; b record; n int; begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not _gm_arcade(p_game) then raise exception 'bad game'; end if;
  select * into b from _gm_bounds(p_game);
  n := greatest(b.min_seats, least(b.max_seats, coalesce(p_seats, b.min_seats)));
  perform leave_all_rooms();
  insert into rooms(code, name, host, mode, is_private, ranked, voice, settings, kind, game)
  values (_gen_code(), coalesce(nullif(trim(p_name), ''), 'NEXORA ' || p_game), auth.uid(),
          case when n <= 2 then '1v1' when n <= 4 then '2v2' else '3v3' end,
          coalesce(p_private, false), not coalesce(p_private, false), true,
          coalesce(p_settings, '{}'::jsonb) || jsonb_build_object('seats', n, 'quick', coalesce(p_quick, false), 'game', p_game),
          'casual', p_game)
  returning * into r;
  insert into room_players(room_id, user_id, role, team, slot) values (r.id, auth.uid(), 'player', 0, 0);
  return r; end $$;

create or replace function public.gm_join_room(p_code text default null, p_room uuid default null, p_spectate boolean default false)
returns rooms language plpgsql security definer set search_path to 'public' as $$
declare r rooms; begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into r from rooms where (p_room is not null and id = p_room) or (p_code is not null and code = upper(trim(p_code))) limit 1;
  if r.id is null then raise exception 'room not found'; end if;
  if not _gm_arcade(r.game) then return join_room(p_code, p_room, p_spectate); end if;
  if r.status = 'finished' then raise exception 'room closed'; end if;
  if exists(select 1 from room_players where room_id = r.id and user_id = auth.uid()) then return r; end if;
  perform leave_all_rooms();
  insert into room_players(room_id, user_id, role) values (r.id, auth.uid(), 'spectator');
  if not p_spectate and r.status = 'waiting' then perform _gm_autoseat(r, auth.uid()); end if;
  update rooms set updated_at = now() where id = r.id;
  return r; end $$;

-- quick match: join a public quick room of this game with a free seat, or open one. Auto-starts when full.
create or replace function public.gm_quick(p_game text, p_seats int default 2)
returns rooms language plpgsql security definer set search_path to 'public' as $$
declare r rooms; rid uuid; b record; n int; cnt int; begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not _gm_arcade(p_game) then raise exception 'bad game'; end if;
  select * into b from _gm_bounds(p_game);
  n := greatest(b.min_seats, least(b.max_seats, coalesce(p_seats, b.min_seats)));
  perform pg_advisory_xact_lock(hashtext('nexora-gmq:' || p_game || ':' || n));
  select ro.* into r from rooms ro join room_players p on p.room_id = ro.id and p.user_id = auth.uid()
    where ro.game = p_game and ro.status in ('waiting','playing') and coalesce((ro.settings->>'quick')::boolean, false)
      and _gm_seat_capacity(ro) = n limit 1;
  if r.id is null then
    select ro.id into rid from rooms ro
     where ro.game = p_game and ro.status = 'waiting' and not ro.is_private and coalesce((ro.settings->>'quick')::boolean, false)
       and _gm_seat_capacity(ro) = n
       and (select count(*) from room_players p where p.room_id = ro.id and p.role = 'player') < n
       and exists(select 1 from room_players p where p.room_id = ro.id and p.last_seen > now() - interval '30 seconds')
     order by (select count(*) from room_players p where p.room_id = ro.id and p.role = 'player') desc, ro.created_at
     limit 1;
    if rid is null then
      r := gm_create_room(p_game, n, null, false, '{}'::jsonb, true);
    else
      r := gm_join_room(null, rid, false);
    end if;
  end if;
  update room_players set ready = true, last_seen = now() where room_id = r.id and user_id = auth.uid() and role = 'player';
  select count(*) into cnt from room_players where room_id = r.id and role = 'player' and ready;
  if cnt >= n and r.status = 'waiting' then perform _gm_start(r.id); end if;
  select * into r from rooms where id = r.id;
  return r; end $$;

create or replace function public.gm_take_seat(p_room uuid, p_seat int)
returns void language plpgsql security definer set search_path to 'public' as $$
declare r rooms; begin
  select * into r from rooms where id = p_room;
  if r.id is null then raise exception 'room not found'; end if;
  if r.status <> 'waiting' then raise exception 'match running'; end if;
  if p_seat < 0 or p_seat >= _gm_seat_capacity(r) then raise exception 'bad slot'; end if;
  if not exists(select 1 from room_players where room_id = p_room and user_id = auth.uid()) then raise exception 'not in room'; end if;
  if exists(select 1 from room_players where room_id = p_room and role = 'player' and _gm_seat_of(team, slot) = p_seat and user_id <> auth.uid())
    then raise exception 'seat taken'; end if;
  update room_players set role = 'player', team = (p_seat % 2)::smallint, slot = (p_seat / 2)::smallint, ready = false
    where room_id = p_room and user_id = auth.uid();
  update rooms set updated_at = now() where id = p_room; end $$;

-- host changes seat count / game options while waiting (football's update_room is not used for arcade rooms)
create or replace function public.gm_update_room(p_room uuid, p_seats int default null, p_settings jsonb default null, p_name text default null)
returns rooms language plpgsql security definer set search_path to 'public' as $$
declare r rooms; b record; n int; s jsonb; begin
  select * into r from rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if r.host <> auth.uid() then raise exception 'host only'; end if;
  if r.status <> 'waiting' then raise exception 'match running'; end if;
  if not _gm_arcade(r.game) then raise exception 'bad game'; end if;
  select * into b from _gm_bounds(r.game);
  n := greatest(b.min_seats, least(b.max_seats, coalesce(p_seats, _gm_seat_capacity(r))));
  s := coalesce(r.settings, '{}'::jsonb) || coalesce(p_settings, '{}'::jsonb)
       || jsonb_build_object('seats', n, 'quick', coalesce((r.settings->>'quick')::boolean, false), 'game', r.game);
  perform set_config('nexora.gm_update', '1', true);
  update rooms set settings = s, name = coalesce(nullif(trim(p_name), ''), name),
         mode = case when n <= 2 then '1v1' when n <= 4 then '2v2' else '3v3' end, updated_at = now()
   where id = p_room returning * into r;
  perform set_config('nexora.gm_update', '', true);
  -- players beyond the new capacity become spectators
  update room_players set role = 'spectator', team = null, slot = null, ready = false
   where room_id = p_room and role = 'player' and _gm_seat_of(team, slot) >= n;
  return r; end $$;

-- 5. match start -------------------------------------------------------------------------------
create or replace function public._gm_start(p_room uuid) returns uuid
language plpgsql security definer set search_path to 'public' as $$
declare r rooms; seats uuid[]; b record; mid uuid; n int; gs game_state; begin
  select * into r from rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if r.status <> 'waiting' then return r.current_match; end if;
  if not _gm_arcade(r.game) then raise exception 'not an arcade room'; end if;
  select coalesce(array_agg(user_id order by _gm_seat_of(team, slot)), '{}') into seats from room_players
    where room_id = p_room and role = 'player';
  n := coalesce(array_length(seats, 1), 0);
  select * into b from _gm_bounds(r.game);
  if n < b.min_seats then raise exception 'need % players', b.min_seats; end if;
  if n > b.max_seats then raise exception 'too many players'; end if;
  insert into game_state(room_id, game, seats, ranked, authority)
    values (p_room, r.game, seats, r.ranked, case when r.game in ('billiards','carrom') then 'host' else 'server' end)
    returning * into gs;
  mid := gs.match_id;
  insert into game_private(match_id, user_id, seat, data)
    select mid, seats[i], i - 1, '{}'::jsonb from generate_subscripts(seats, 1) i;
  insert into game_secret(match_id, data) values (mid, '{}'::jsonb);
  gs.state := jsonb_build_object('out', (select jsonb_agg(false) from generate_subscripts(seats, 1)),
                                 'strikes', (select jsonb_agg(0) from generate_subscripts(seats, 1)),
                                 'scores', (select jsonb_agg(0) from generate_subscripts(seats, 1)));
  if r.settings ? 'turn_secs' then
    gs.state := gs.state || jsonb_build_object('turn_secs', greatest(10, least(120, (r.settings->>'turn_secs')::int)));
  end if;
  execute format('select * from public.%I($1, $2)', '_gm_' || r.game || '_init') into gs using gs, r.settings;
  update game_state set phase = gs.phase, turn = gs.turn, state = gs.state, deadline = gs.deadline,
         status = gs.status, result = gs.result, version = 1, updated_at = now() where match_id = mid;
  update rooms set status = 'playing', current_match = mid, updated_at = now() where id = p_room;
  update room_players set last_seen = now() where room_id = p_room;
  return mid; end $$;

create or replace function public.gm_start(p_room uuid) returns uuid
language plpgsql security definer set search_path to 'public' as $$
declare r rooms; begin
  select * into r from rooms where id = p_room;
  if r.id is null then raise exception 'room not found'; end if;
  if r.status <> 'waiting' then raise exception 'already started'; end if;
  if r.host <> auth.uid() then raise exception 'host only'; end if;
  if not exists(select 1 from room_players where room_id = p_room and user_id = auth.uid() and role = 'player') then raise exception 'take a seat'; end if;
  if exists(select 1 from room_players where room_id = p_room and role = 'player' and not ready and user_id <> r.host) then raise exception 'not all ready'; end if;
  return _gm_start(p_room); end $$;

-- 6. view / move / tick / resign -----------------------------------------------------------------
create or replace function public._gm_my_seat(gs game_state, uid uuid) returns int language sql immutable as $$
  select (select i - 1 from generate_subscripts(gs.seats, 1) i where gs.seats[i] = uid limit 1) $$;

create or replace function public.gm_view(p_match uuid) returns jsonb
language plpgsql security definer set search_path to 'public' stable as $$
declare gs game_state; pv jsonb; seat int; begin
  select * into gs from game_state where match_id = p_match;
  if gs.match_id is null then raise exception 'no such match'; end if;
  seat := _gm_my_seat(gs, auth.uid());
  select data into pv from game_private where match_id = p_match and user_id = auth.uid();
  return jsonb_build_object('match_id', gs.match_id, 'room_id', gs.room_id, 'game', gs.game, 'seats', to_jsonb(gs.seats),
    'names', (select jsonb_agg(coalesce(p.username, '…') order by i) from generate_subscripts(gs.seats, 1) i
                left join profiles p on p.id = gs.seats[i]),
    'status', gs.status, 'phase', gs.phase, 'turn', gs.turn, 'version', gs.version, 'state', gs.state,
    'deadline', gs.deadline, 'now', now(), 'result', gs.result, 'authority', gs.authority, 'ranked', gs.ranked,
    'my_seat', seat, 'private', coalesce(pv, '{}'::jsonb)); end $$;

-- latest match of a room (for reconnecting)
create or replace function public.gm_room_match(p_room uuid) returns uuid
language sql security definer set search_path to 'public' stable as $$
  select match_id from game_state where room_id = p_room order by started_at desc limit 1 $$;

create or replace function public._gm_save(gs game_state) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  update game_state set phase = gs.phase, turn = gs.turn, state = gs.state, deadline = gs.deadline, result = gs.result,
         status = gs.status, version = version + 1, updated_at = now(),
         ended_at = case when gs.status <> 'live' then coalesce(ended_at, now()) else null end
   where match_id = gs.match_id;
  if gs.status = 'finished' then perform _gm_finish(gs.match_id); end if;
end $$;

create or replace function public._gm_log(gs game_state, p_seat int, p_move jsonb, p_secret boolean default false) returns void
language sql security definer set search_path to 'public' as $$
  insert into game_moves(match_id, seq, user_id, seat, move, secret)
  values (gs.match_id, gs.version + 1, case when p_seat is null or p_seat < 0 then null else gs.seats[p_seat + 1] end, p_seat, p_move, p_secret) $$;

create or replace function public.gm_move(p_match uuid, p_move jsonb, p_version int default null) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare gs game_state; seat int; begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into gs from game_state where match_id = p_match for update;
  if gs.match_id is null then raise exception 'no such match'; end if;
  if gs.status <> 'live' then raise exception 'match over'; end if;
  if gs.authority <> 'server' then raise exception 'host-authoritative game'; end if;
  seat := _gm_my_seat(gs, auth.uid());
  if seat is null then raise exception 'not a player'; end if;
  if _gm_out(gs, seat) then raise exception 'you are out'; end if;
  if p_version is not null and p_version <> gs.version then raise exception 'stale version'; end if;
  if jsonb_typeof(p_move) <> 'object' or not (p_move ? 'a') then raise exception 'bad move'; end if;
  perform _gm_log(gs, seat, p_move, gs.game = 'mafia');
  execute format('select * from public.%I($1, $2, $3)', '_gm_' || gs.game || '_move') into gs using gs, seat, p_move;
  -- a real action clears this seat's idle strikes
  if gs.state ? 'strikes' then gs.state := jsonb_set(gs.state, array['strikes', seat::text], '0'); end if;
  perform _gm_save(gs);
  update room_players set last_seen = now() where room_id = gs.room_id and user_id = auth.uid();
  return gm_view(p_match); end $$;

-- the server acts for idle players / ends timed phases; also drops players who left the room
create or replace function public._gm_tick(p_match uuid) returns void
language plpgsql security definer set search_path to 'public' as $$
declare gs game_state; s int; changed boolean := false; begin
  select * into gs from game_state where match_id = p_match for update skip locked;
  if gs.match_id is null or gs.status <> 'live' then return; end if;
  for s in 0 .. array_length(gs.seats, 1) - 1 loop
    if not _gm_out(gs, s) and (gs.room_id is null
       or not exists(select 1 from room_players where room_id = gs.room_id and user_id = gs.seats[s + 1])) then
      perform _gm_log(gs, s, jsonb_build_object('a', 'left'));
      execute format('select * from public.%I($1, $2)', '_gm_' || gs.game || '_resign') into gs using gs, s;
      changed := true;
      exit when gs.status <> 'live';
    end if;
  end loop;
  if gs.status = 'live' and gs.deadline is not null and now() >= gs.deadline then
    perform _gm_log(gs, -1, jsonb_build_object('a', 'timeout', 'phase', gs.phase, 'turn', gs.turn));
    if gs.authority = 'server' then
      execute format('select * from public.%I($1)', '_gm_' || gs.game || '_tick') into gs using gs;
    else
      gs := _gm_host_tick(gs);
    end if;
    changed := true;
  end if;
  if changed then perform _gm_save(gs); end if;
end $$;

-- any client may poke the server when it sees the deadline pass (cron does it too, every 10 s)
create or replace function public.gm_tick(p_match uuid) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
begin
  perform _gm_tick(p_match);
  return gm_view(p_match); end $$;

create or replace function public.gm_resign(p_match uuid) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare gs game_state; seat int; begin
  select * into gs from game_state where match_id = p_match for update;
  if gs.match_id is null then raise exception 'no such match'; end if;
  seat := _gm_my_seat(gs, auth.uid());
  if seat is null then raise exception 'not a player'; end if;
  if gs.status = 'live' and not _gm_out(gs, seat) then
    perform _gm_log(gs, seat, jsonb_build_object('a', 'resign'));
    execute format('select * from public.%I($1, $2)', '_gm_' || gs.game || '_resign') into gs using gs, seat;
    perform _gm_save(gs);
  end if;
  return gm_view(p_match); end $$;

-- generic helpers used by the per-game modules
create or replace function public._gm_out(gs game_state, s int) returns boolean language sql immutable as $$
  select coalesce((gs.state->'out'->>s)::boolean, false) $$;

create or replace function public._gm_alive_seats(gs game_state) returns int[] language sql immutable as $$
  select coalesce(array_agg(i - 1 order by i), '{}') from generate_subscripts(gs.seats, 1) i
   where not coalesce((gs.state->'out'->>(i - 1))::boolean, false) $$;

create or replace function public._gm_alive_count(gs game_state) returns int language sql immutable as $$
  select coalesce(array_length(_gm_alive_seats(gs), 1), 0) $$;

-- next seat in direction dir that is not out
create or replace function public._gm_next(gs game_state, from_seat int, dir int default 1) returns int
language plpgsql immutable as $$
declare n int := array_length(gs.seats, 1); s int := from_seat; k int; begin
  for k in 1..n loop
    s := ((s + dir) % n + n) % n;
    if not _gm_out(gs, s) then return s; end if;
  end loop;
  return from_seat; end $$;

create or replace function public._gm_secs(gs game_state, dflt int) returns int language sql immutable as $$
  select greatest(10, least(120, coalesce((gs.state->>'turn_secs')::int, dflt))) $$;

create or replace function public._gm_finish_with(gs game_state, p_winners int[], p_reason text) returns game_state
language plpgsql immutable as $$
begin
  gs.status := 'finished';
  gs.deadline := null;
  gs.result := jsonb_build_object('winners', to_jsonb(coalesce(p_winners, '{}'::int[])),
                                  'scores', coalesce(gs.state->'scores', '[]'::jsonb), 'reason', p_reason);
  return gs; end $$;

-- mark seat out; if one player (or nobody) remains, they win
create or replace function public._gm_mark_out(gs game_state, s int, p_reason text default 'resign') returns game_state
language plpgsql immutable as $$
declare alive int[]; begin
  gs.state := jsonb_set(gs.state, array['out', s::text], 'true');
  alive := _gm_alive_seats(gs);
  if coalesce(array_length(alive, 1), 0) <= 1 then
    gs := _gm_finish_with(gs, alive, p_reason);
  end if;
  return gs; end $$;

-- idle strike for seat s; after 3 in a row the seat resigns. Returns gs (may be finished).
create or replace function public._gm_strike(gs game_state, s int) returns game_state
language plpgsql as $$
declare k int; begin
  k := coalesce((gs.state->'strikes'->>s)::int, 0) + 1;
  gs.state := jsonb_set(gs.state, array['strikes', s::text], to_jsonb(k));
  if k >= 3 then
    execute format('select * from public.%I($1, $2)', '_gm_' || gs.game || '_resign') into gs using gs, s;
  end if;
  return gs; end $$;

create or replace function public._gm_set_score(gs game_state, s int, v int) returns game_state
language plpgsql immutable as $$
begin gs.state := jsonb_set(gs.state, array['scores', s::text], to_jsonb(v)); return gs; end $$;

-- 7. host-authoritative games (billiards, carrom): the shooter simulates, the server checks turn order
-- p_turn = seat to shoot next (same seat or the next seat); p_finish = {winners:[seat], reason} ends the match
create or replace function public.gm_shot(p_match uuid, p_version int, p_state jsonb, p_turn int, p_finish jsonb default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare gs game_state; seat int; nxt int; w int[]; begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into gs from game_state where match_id = p_match for update;
  if gs.match_id is null then raise exception 'no such match'; end if;
  if gs.status <> 'live' then raise exception 'match over'; end if;
  if gs.authority <> 'host' then raise exception 'server-authoritative game'; end if;
  seat := _gm_my_seat(gs, auth.uid());
  if seat is null then raise exception 'not a player'; end if;
  if seat <> gs.turn then raise exception 'not your turn'; end if;
  if p_version is not null and p_version <> gs.version then raise exception 'stale version'; end if;
  if p_state is null or jsonb_typeof(p_state) <> 'object' or length(p_state::text) > 20000 then raise exception 'bad state'; end if;
  nxt := _gm_next(gs, seat);
  if p_turn is distinct from seat and p_turn is distinct from nxt then raise exception 'bad turn'; end if;
  perform _gm_log(gs, seat, jsonb_build_object('a', 'shot', 'turn', p_turn, 'finish', p_finish));
  gs.state := p_state || jsonb_build_object('out', gs.state->'out', 'strikes', jsonb_set(gs.state->'strikes', array[seat::text], '0'),
                                            'scores', coalesce(p_state->'scores', gs.state->'scores'),
                                            'shots', coalesce((gs.state->>'shots')::int, 0) + 1);
  gs.turn := p_turn;
  gs.deadline := now() + make_interval(secs => _gm_secs(gs, 45));
  if p_finish is not null then
    w := coalesce((select array_agg(x::int) from jsonb_array_elements_text(p_finish->'winners') x), '{}');
    if exists(select 1 from unnest(w) x where x < 0 or x >= array_length(gs.seats, 1)) then raise exception 'bad winners'; end if;
    gs := _gm_finish_with(gs, w, coalesce(p_finish->>'reason', 'win'));
  end if;
  perform _gm_save(gs);
  update room_players set last_seen = now() where room_id = gs.room_id and user_id = auth.uid();
  return gm_view(p_match); end $$;

-- idle shooter: strike + turn passes (3 strikes = out)
create or replace function public._gm_host_tick(gs game_state) returns game_state
language plpgsql as $$
declare s int := gs.turn; begin
  gs := _gm_strike(gs, s);
  if gs.status = 'live' then
    gs.turn := _gm_next(gs, s);
    gs.state := gs.state || jsonb_build_object('foul', jsonb_build_object('seat', s, 'reason', 'timeout'));
    gs.deadline := now() + make_interval(secs => _gm_secs(gs, 45));
  end if;
  return gs; end $$;

create or replace function public._gm_host_resign(gs game_state, s int) returns game_state
language plpgsql as $$
begin
  gs := _gm_mark_out(gs, s, 'resign');
  if gs.status = 'live' and gs.turn = s then
    gs.turn := _gm_next(gs, s);
    gs.deadline := now() + make_interval(secs => _gm_secs(gs, 45));
  end if;
  return gs; end $$;

-- 8. results: per-game rating (Elo for ranked rooms), xp + coins to the profile ------------------
-- Football stats on profiles (rating, wins, losses, draws, win_streak) are deliberately NOT touched:
-- _grant is called with p_rating 0 and a neutral p_result so only xp / coins / level move.
create or replace function public._gm_finish(p_match uuid) returns void
language plpgsql security definer set search_path to 'public' as $$
declare gs game_state; winners int[]; n int; i int; u uuid; res int; draw boolean;
        wr numeric; lr numeric; d int; my_r int; deltas jsonb := '[]'::jsonb; begin
  select * into gs from game_state where match_id = p_match for update;
  if gs.match_id is null or gs.status <> 'finished' or coalesce((gs.result->>'rewarded')::boolean, false) then return; end if;
  n := array_length(gs.seats, 1);
  winners := coalesce((select array_agg(x::int) from jsonb_array_elements_text(coalesce(gs.result->'winners', '[]')) x), '{}');
  draw := coalesce(array_length(winners, 1), 0) = 0 or coalesce(array_length(winners, 1), 0) = n;
  select avg(coalesce(gr.rating, 1000)) into wr from generate_subscripts(gs.seats, 1) k
    left join game_ratings gr on gr.user_id = gs.seats[k] and gr.game = gs.game where (k - 1) = any(winners);
  select avg(coalesce(gr.rating, 1000)) into lr from generate_subscripts(gs.seats, 1) k
    left join game_ratings gr on gr.user_id = gs.seats[k] and gr.game = gs.game where not ((k - 1) = any(winners));
  for i in 1..n loop
    u := gs.seats[i];
    res := case when draw then 0 when (i - 1) = any(winners) then 1 else -1 end;
    insert into game_ratings(user_id, game) values (u, gs.game) on conflict do nothing;
    select rating into my_r from game_ratings where user_id = u and game = gs.game;
    d := 0;
    if gs.ranked and not draw and gs.authority = 'server' then
      if res = 1 then d := round(32 * (1 - 1 / (1 + power(10, (coalesce(lr, 1000) - my_r) / 400.0))));
      else d := -round(32 * (1 / (1 + power(10, (coalesce(wr, 1000) - my_r) / 400.0)))); end if;
    end if;
    update game_ratings set rating = greatest(100, rating + d), played = played + 1, wins = wins + (res = 1)::int,
      losses = losses + (res = -1)::int, draws = draws + (res = 0)::int,
      streak = case when res = 1 then streak + 1 else 0 end,
      best_streak = greatest(best_streak, case when res = 1 then streak + 1 else 0 end), updated_at = now()
      where user_id = u and game = gs.game;
    deltas := deltas || to_jsonb(d);
    perform _grant(u, 40 + res * 30 + 10, 50 + (res = 1)::int * 100, 0, 9, 0, 'game_' || gs.game, p_match);
    perform _progress(u, 'play_online', 1);
    if res = 1 then perform _progress(u, 'win_online', 1); end if;
  end loop;
  update game_state set result = coalesce(result, '{}'::jsonb) || jsonb_build_object('rewarded', true, 'rating_delta', deltas)
   where match_id = p_match;
  update rooms set status = 'waiting', current_match = null, updated_at = now() where id = gs.room_id and current_match = p_match;
  update room_players set ready = false where room_id = gs.room_id;
end $$;

-- 9. sweep: overdue deadlines, rooms nobody heartbeats any more (cron every 10 s) -----------------
create or replace function public.gm_sweep() returns void
language plpgsql security definer set search_path to 'public' as $$
declare m record; begin
  for m in select match_id, room_id from game_state where status = 'live' and (
            started_at < now() - interval '3 hours'
            or room_id is null
            or not exists(select 1 from room_players p where p.room_id = game_state.room_id and p.last_seen > now() - interval '90 seconds')) loop
    update game_state set status = 'abandoned', deadline = null, version = version + 1, updated_at = now(), ended_at = now(),
           result = jsonb_build_object('winners', '[]'::jsonb, 'reason', 'abandoned')
     where match_id = m.match_id and status = 'live';
    update rooms set status = 'waiting', current_match = null, updated_at = now() where id = m.room_id and current_match = m.match_id;
    update room_players set ready = false where room_id = m.room_id;
  end loop;
  for m in select match_id from game_state where status = 'live' and (
            (deadline is not null and deadline <= now())
            or exists(select 1 from generate_subscripts(seats, 1) i where not coalesce((state->'out'->>(i - 1))::boolean, false)
                        and not exists(select 1 from room_players p where p.room_id = game_state.room_id and p.user_id = seats[i]))) loop
    begin
      perform _gm_tick(m.match_id);
    exception when others then
      raise warning 'gm_sweep %: %', m.match_id, sqlerrm;
    end;
  end loop;
end $$;

-- 10. guards so football RPCs never act on an arcade room ----------------------------------------
create or replace function public._gm_guard_match_insert() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if new.room_id is not null and exists(select 1 from rooms where id = new.room_id and game <> 'football') then
    raise exception 'not allowed';
  end if;
  return new; end $$;
drop trigger if exists trg_gm_guard_match_insert on public.matches;
create trigger trg_gm_guard_match_insert before insert on public.matches
  for each row execute function public._gm_guard_match_insert();

-- update_room (football) may rewrite an arcade room's settings: keep the seat count / game / quick flags
create or replace function public._gm_guard_room_update() returns trigger
language plpgsql as $$
begin
  new.game := old.game;   -- a room never changes its game
  if old.game <> 'football' and new.settings is distinct from old.settings
     and new.settings->'seats' is distinct from old.settings->'seats'
     and coalesce(current_setting('nexora.gm_update', true), '') <> '1' then
    new.settings := coalesce(new.settings, '{}'::jsonb) || jsonb_build_object(
      'seats', old.settings->'seats', 'quick', coalesce(old.settings->'quick', 'false'::jsonb), 'game', old.game);
  end if;
  return new; end $$;
drop trigger if exists trg_gm_guard_room_update on public.rooms;
create trigger trg_gm_guard_room_update before update on public.rooms
  for each row execute function public._gm_guard_room_update();

-- RPC grants: only the public gm_* entry points are callable by clients
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like '\_gm\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'gm\_%' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  revoke all on function public.gm_sweep() from authenticated;
end $$;
