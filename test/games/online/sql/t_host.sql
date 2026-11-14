do $$
declare us uuid[] := array['cfc3a517-df48-4968-948e-464bb5cfc61b','2afacffd-b600-4492-b034-95d7d4960991']::uuid[];
        mid uuid; gs game_state; out jsonb := '{}'; err text := '';
begin
  mid := pg_temp.mk('carrom', us);
  select * into gs from game_state where match_id = mid;
  perform pg_temp.as_user(us[2]);
  begin perform gm_shot(mid, gs.version, '{"pucks":[]}', 1); exception when others then err := err || 'wrong_shooter:' || sqlerrm || ';'; end;
  perform pg_temp.as_user(us[1]);
  begin perform gm_move(mid, '{"a":"x"}'); exception when others then err := err || 'move_on_host:' || sqlerrm || ';'; end;
  perform gm_shot(mid, gs.version, '{"pucks":[1,2],"scores":[1,0]}', 0);   -- pocketed: shoots again
  select * into gs from game_state where match_id = mid;
  perform gm_shot(mid, gs.version, '{"pucks":[1],"scores":[1,0]}', 1);
  select * into gs from game_state where match_id = mid;
  out := out || jsonb_build_object('after2', jsonb_build_object('turn', gs.turn, 'v', gs.version, 'shots', gs.state->'shots', 'scores', gs.state->'scores'));
  update game_state set deadline = now() - interval '1 second' where match_id = mid;
  perform gm_sweep();
  select * into gs from game_state where match_id = mid;
  out := out || jsonb_build_object('timeout', jsonb_build_object('turn', gs.turn, 'strikes', gs.state->'strikes', 'foul', gs.state->'foul'));
  perform pg_temp.as_user(us[1]);
  perform gm_shot(mid, gs.version, '{"pucks":[],"scores":[9,1]}', 0, '{"winners":[0],"reason":"cleared"}');
  select * into gs from game_state where match_id = mid;
  out := out || jsonb_build_object('end', jsonb_build_object('status', gs.status, 'result', gs.result));
  raise exception 'RESULT %', out || jsonb_build_object('err', err);
end $$;
