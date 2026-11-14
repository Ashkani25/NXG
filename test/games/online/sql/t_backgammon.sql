do $$
declare u1 uuid := 'cfc3a517-df48-4968-948e-464bb5cfc61b'; u2 uuid := '2afacffd-b600-4492-b034-95d7d4960991';
        r rooms; mid uuid; v jsonb; gs game_state; i int; who uuid; err text := ''; log jsonb := '[]'; t0 timestamptz := clock_timestamp();
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  r := gm_create_room('backgammon', 2, 'test bg');
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  r := gm_join_room(r.code);
  perform set_ready(r.id, true);
  -- not host -> must fail
  begin perform gm_start(r.id); exception when others then err := err || 'nonhost:' || sqlerrm || ';'; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  mid := gm_start(r.id);
  v := gm_view(mid);
  log := log || jsonb_build_array(jsonb_build_object('start', v->'state'->'opening', 'turn', v->'turn', 'phase', v->'phase'));
  -- wrong player move
  select * into gs from game_state where match_id = mid;
  who := gs.seats[2 - gs.turn];  -- the other one
  perform set_config('request.jwt.claims', json_build_object('sub', who, 'role', 'authenticated')::text, true);
  begin perform gm_move(mid, '{"a":"roll"}'); exception when others then err := err || 'wrongturn:' || sqlerrm || ';'; end;
  -- illegal move by right player
  who := gs.seats[gs.turn + 1];
  perform set_config('request.jwt.claims', json_build_object('sub', who, 'role', 'authenticated')::text, true);
  begin perform gm_move(mid, '{"a":"play","moves":[[0,5,5],[0,5,5]]}'); exception when others then err := err || 'illegal:' || sqlerrm || ';'; end;
  for i in 1..600 loop
    select * into gs from game_state where match_id = mid;
    exit when gs.status <> 'live';
    who := gs.seats[gs.turn + 1];
    perform set_config('request.jwt.claims', json_build_object('sub', who, 'role', 'authenticated')::text, true);
    if gs.phase = 'roll' then perform gm_move(mid, '{"a":"roll"}', gs.version);
    else perform gm_move(mid, jsonb_build_object('a', 'play', 'moves', _gm_bg_auto(gs)), gs.version); end if;
  end loop;
  select * into gs from game_state where match_id = mid;
  raise exception 'RESULT %', jsonb_build_object('iters', i, 'status', gs.status, 'result', gs.result, 'board', gs.state->'b',
     'err', err, 'log', log, 'ms', extract(epoch from clock_timestamp() - t0) * 1000,
     'ratings', (select jsonb_agg(to_jsonb(g)) from game_ratings g where game = 'backgammon' and user_id in (u1, u2)),
     'room', (select jsonb_build_object('status', status, 'cm', current_match) from rooms where id = r.id),
     'moves', (select count(*) from game_moves where match_id = mid));
end $$;
