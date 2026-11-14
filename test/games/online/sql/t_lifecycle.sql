do $$
declare us uuid[] := array['cfc3a517-df48-4968-948e-464bb5cfc61b','2afacffd-b600-4492-b034-95d7d4960991',
                           'c3e0b131-5950-413c-97ba-4fa627904cf9','160181e4-0d9c-4e78-9649-bc3f885ac73a']::uuid[];
        mid uuid; gs game_state; i int; out jsonb := '{}'; err text := ''; r rooms; r2 rooms; fm uuid; c int; rep jsonb;
begin
  -- quick match: two users -> same room, auto start
  perform pg_temp.as_user(us[1]); r := gm_quick('snakes_ladders', 2);
  perform pg_temp.as_user(us[2]); r2 := gm_quick('snakes_ladders', 2);
  out := out || jsonb_build_object('quick', jsonb_build_object('same', r.id = r2.id, 'status', r2.status, 'match', r2.current_match is not null));
  -- idle strikes: 3 timeouts in a row => out => other wins (uno)
  mid := pg_temp.mk('uno', us[1:2]);
  for i in 1..6 loop
    select * into gs from game_state where match_id = mid; exit when gs.status <> 'live';
    update game_state set deadline = now() - interval '1 second' where match_id = mid;
    perform pg_temp.as_user(us[1]); perform gm_tick(mid);
  end loop;
  select * into gs from game_state where match_id = mid;
  out := out || jsonb_build_object('uno_idle', jsonb_build_object('i', i, 'status', gs.status, 'result', gs.result, 'strikes', gs.state->'strikes'));
  -- backgammon idle tick plays for the idle player
  mid := pg_temp.mk('backgammon', us[1:2]);
  update game_state set deadline = now() - interval '1 second' where match_id = mid;
  perform gm_sweep();
  select * into gs from game_state where match_id = mid;
  out := out || jsonb_build_object('bg_sweep', jsonb_build_object('phase', gs.phase, 'last', gs.state->'last', 'strikes', gs.state->'strikes', 'version', gs.version));
  -- a player leaving the room mid-game is out at once (ludo 3p continues, then 2nd leave ends it)
  mid := pg_temp.mk('ludo', us[1:3]);
  perform pg_temp.as_user(us[2]); perform leave_room((select room_id from game_state where match_id = mid));
  perform gm_sweep();
  select * into gs from game_state where match_id = mid;
  out := out || jsonb_build_object('ludo_leave1', jsonb_build_object('status', gs.status, 'out', gs.state->'out', 'turn', gs.turn));
  perform pg_temp.as_user(us[3]); perform gm_resign(mid);
  select * into gs from game_state where match_id = mid;
  out := out || jsonb_build_object('ludo_resign', jsonb_build_object('status', gs.status, 'result', gs.result));
  -- football guards: start_match (football RPC) in an arcade room must fail; update_room keeps seats
  perform pg_temp.as_user(us[1]); r := gm_create_room('uno', 4, 'guard');
  perform pg_temp.as_user(us[2]); r2 := gm_join_room(r.code); perform set_ready(r.id, true);
  perform pg_temp.as_user(us[1]);
  begin perform start_match(r.id); exception when others then err := err || 'football_start_in_arcade:' || sqlerrm || ';'; end;
  perform update_room(r.id, '{"goals":5}'::jsonb);
  out := out || jsonb_build_object('guard_settings', (select settings from rooms where id = r.id));
  out := out || jsonb_build_object('room_list_has_arcade', exists(select 1 from room_list where id = r.id),
                                   'game_room_list_has_it', exists(select 1 from game_room_list where id = r.id));
  r := gm_update_room(r.id, 3);
  out := out || jsonb_build_object('gm_update_room', jsonb_build_object('seats', r.settings->'seats', 'mode', r.mode));
  -- football flow untouched: create_room -> join_room -> start_match -> report_match; abandon_match; update_room
  perform pg_temp.as_user(us[3]); r := create_room('1v1', 'fb test', false, true, true, null, 'casual');
  perform update_room(r.id, '{"goals":5,"time":0,"field":6,"turn":15}'::jsonb);
  perform pg_temp.as_user(us[4]); r2 := join_room(r.code); perform set_ready(r.id, true);
  perform pg_temp.as_user(us[3]); fm := start_match(r.id);
  rep := report_match(fm, 3, 1, 120);
  out := out || jsonb_build_object('football', jsonb_build_object('game', (select game from rooms where id = r.id),
      'settings', (select settings from rooms where id = r.id), 'report', rep,
      'match_status', (select status from matches where id = fm), 'in_room_list', exists(select 1 from room_list where id = r.id)));
  perform pg_temp.as_user(us[4]); perform set_ready(r.id, true);
  perform pg_temp.as_user(us[3]); fm := start_match(r.id);
  perform abandon_match(fm);
  out := out || jsonb_build_object('football_abandon', (select status from matches where id = fm), 'room_after', (select status from rooms where id = r.id));
  perform pg_temp.as_user(us[4]); r := quick_match('1v1', 'quick');
  out := out || jsonb_build_object('football_quick', jsonb_build_object('kind', r.kind, 'game', r.game));
  raise exception 'RESULT %', out || jsonb_build_object('err', err);
end $$;
