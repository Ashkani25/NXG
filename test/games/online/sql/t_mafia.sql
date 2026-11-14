do $$
declare us uuid[]; mid uuid; gs game_state; i int; out jsonb := '{}'; err text := ''; s int; r text; sec jsonb; t int; tgt int; alive int[]; v jsonb;
begin
  select array_agg(id order by created_at) into us from (select id, created_at from profiles order by created_at limit 8) x;
  mid := pg_temp.mk('mafia', us);
  -- a citizen's view: own role only, no others
  for i in 1..200 loop
    select * into gs from game_state where match_id = mid; exit when gs.status <> 'live';
    sec := _gm_mf_secret(gs);
    alive := _gm_mf_alive_seats(gs);
    if gs.phase = 'night' then
      foreach s in array alive loop
        r := sec->'roles'->>s;
        continue when r = 'citizen';
        perform pg_temp.as_user(gs.seats[s + 1]);
        -- mafia shoot the first non-mafia; doctor saves seat 0 unless illegal; detective checks the next seat; sniper shoots the last alive
        if r in ('godfather', 'mafia') then select x into tgt from unnest(alive) x where not _gm_mf_is_mafia(sec->'roles'->>x) order by x limit 1;
        elsif r = 'doctor' then select x into tgt from unnest(alive) x where _gm_mf_night_ok(gs, s, r, x) order by x desc limit 1;
        elsif r = 'detective' then select x into tgt from unnest(alive) x where x <> s order by random() limit 1;
        else tgt := null; end if;
        begin perform gm_move(mid, jsonb_build_object('a', 'night', 't', tgt));
        exception when others then err := err || r || ':' || sqlerrm || ';'; end;
        select * into gs from game_state where match_id = mid; exit when gs.phase <> 'night';
      end loop;
    elsif gs.phase in ('day', 'defense') then
      foreach s in array alive loop
        perform pg_temp.as_user(gs.seats[s + 1]); perform gm_move(mid, '{"a":"ready"}');
      end loop;
    elsif gs.phase = 'nominate' then
      -- everybody votes the lowest alive seat that isn't themselves (town vs mafia mix)
      foreach s in array alive loop
        select x into tgt from unnest(alive) x where x <> s order by x limit 1;
        perform pg_temp.as_user(gs.seats[s + 1]); perform gm_move(mid, jsonb_build_object('a', 'vote', 't', tgt));
        select * into gs from game_state where match_id = mid; exit when gs.phase <> 'nominate';
      end loop;
    else
      foreach s in array alive loop
        select x into tgt from unnest(_gm_ints(gs.state->'defendants')) x where x <> s limit 1;
        perform pg_temp.as_user(gs.seats[s + 1]); perform gm_move(mid, jsonb_build_object('a', 'vote', 't', tgt));
        select * into gs from game_state where match_id = mid; exit when gs.phase <> 'final';
      end loop;
    end if;
  end loop;
  select * into gs from game_state where match_id = mid;
  perform pg_temp.as_user(us[3]);
  v := gm_view(mid);
  out := out || jsonb_build_object('iters', i, 'status', gs.status, 'result', gs.result, 'team', gs.state->'team', 'day', gs.state->'day',
     'roles', _gm_mf_secret(gs)->'roles', 'ev', gs.state->'ev', 'my_private', v->'private');
  -- timed flow: a second game driven only by deadlines must progress and never crash
  mid := pg_temp.mk('mafia', us[1:6]);
  for i in 1..40 loop
    select * into gs from game_state where match_id = mid; exit when gs.status <> 'live';
    update game_state set deadline = now() - interval '1 second' where match_id = mid;
    perform gm_sweep();
  end loop;
  select * into gs from game_state where match_id = mid;
  out := out || jsonb_build_object('timed', jsonb_build_object('status', gs.status, 'phase', gs.phase, 'day', gs.state->'day', 'n_ev', jsonb_array_length(gs.state->'ev')));
  -- public state must never contain living players' roles
  out := out || jsonb_build_object('public_shown', gs.state->'shown');
  raise exception 'RESULT %', out || jsonb_build_object('err', err);
end $$;
