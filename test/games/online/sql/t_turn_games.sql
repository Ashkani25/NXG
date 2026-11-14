create or replace function pg_temp.as_user(u uuid) returns void language sql as $f$
  select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true) $f$;
-- creates a room of game g with the given users seated, returns match id
create or replace function pg_temp.mk(g text, us uuid[], settings jsonb default '{}') returns uuid language plpgsql as $f$
declare r rooms; i int; begin
  perform pg_temp.as_user(us[1]);
  r := gm_create_room(g, array_length(us, 1), 'test', false, settings);
  for i in 2..array_length(us, 1) loop
    perform pg_temp.as_user(us[i]); r := gm_join_room(r.code); perform set_ready(r.id, true);
  end loop;
  perform pg_temp.as_user(us[1]);
  return gm_start(r.id); end $f$;
do $$
declare us uuid[] := array['cfc3a517-df48-4968-948e-464bb5cfc61b','2afacffd-b600-4492-b034-95d7d4960991',
                           'c3e0b131-5950-413c-97ba-4fa627904cf9','160181e4-0d9c-4e78-9649-bc3f885ac73a']::uuid[];
        mid uuid; gs game_state; i int; v jsonb; out jsonb := '{}'; err text := ''; t int; s int; hand int[]; card int; c int; played boolean;
begin
  -- LUDO 4 players --------------------------------------------------------------------------
  mid := pg_temp.mk('ludo', us);
  for i in 1..3000 loop
    select * into gs from game_state where match_id = mid; exit when gs.status <> 'live';
    perform pg_temp.as_user(gs.seats[gs.turn + 1]);
    if gs.phase = 'roll' then perform gm_move(mid, '{"a":"roll"}', gs.version);
    else perform gm_move(mid, jsonb_build_object('a', 'move', 't', (gs.state->'legal'->>0)::int), gs.version); end if;
  end loop;
  select * into gs from game_state where match_id = mid;
  out := out || jsonb_build_object('ludo', jsonb_build_object('iters', i, 'status', gs.status, 'result', gs.result, 'tk', gs.state->'tk'));
  -- SNAKES & LADDERS 3 players --------------------------------------------------------------
  mid := pg_temp.mk('snakes_ladders', us[1:3]);
  for i in 1..2000 loop
    select * into gs from game_state where match_id = mid; exit when gs.status <> 'live';
    perform pg_temp.as_user(gs.seats[gs.turn + 1]);
    perform gm_move(mid, '{"a":"roll"}', gs.version);
  end loop;
  select * into gs from game_state where match_id = mid;
  out := out || jsonb_build_object('snl', jsonb_build_object('iters', i, 'status', gs.status, 'result', gs.result, 'pos', gs.state->'pos'));
  -- UNO 4 players: play first legal card, else draw (+ play drawn or pass) ------------------
  mid := pg_temp.mk('uno', us);
  for i in 1..3000 loop
    select * into gs from game_state where match_id = mid; exit when gs.status <> 'live';
    s := gs.turn;
    perform pg_temp.as_user(gs.seats[s + 1]);
    hand := _gm_uno_hand(gs, s);
    if array_length(hand, 1) = 2 and not coalesce((gs.state->'nx'->>s)::boolean, false) and i % 2 = 0 then
      perform gm_move(mid, '{"a":"nx"}'); continue;
    end if;
    select x into card from unnest(hand) x where _gm_uno_legal(gs, hand, x)
      and (_gm_uno_drawn(gs, s) is null or x = _gm_uno_drawn(gs, s)) limit 1;
    if card is not null then
      perform gm_move(mid, jsonb_build_object('a', 'play', 'card', card, 'color', 2));
    elsif _gm_uno_drawn(gs, s) is not null then perform gm_move(mid, '{"a":"pass"}');
    else perform gm_move(mid, '{"a":"draw"}'); end if;
    -- somebody catches a vulnerable player
    select * into gs from game_state where match_id = mid;
    if gs.status = 'live' and gs.state->>'vul' is not null then
      perform pg_temp.as_user(gs.seats[((gs.state->>'vul')::int + 1) % 4 + 1]);
      perform gm_move(mid, '{"a":"catch"}');
    end if;
  end loop;
  select * into gs from game_state where match_id = mid;
  out := out || jsonb_build_object('uno', jsonb_build_object('iters', i, 'status', gs.status, 'result', gs.result, 'counts', gs.state->'counts',
     'cards_total', (select sum(coalesce(jsonb_array_length(data->'hand'), 0)) from game_private where match_id = mid)
        + (select jsonb_array_length(data->'pile') + jsonb_array_length(data->'disc') from game_secret where match_id = mid) + 1,
     'reshuffled', gs.state->'reshuffled'));
  -- security: a player cannot read another player's hand
  perform pg_temp.as_user(us[1]);
  set local role authenticated;
  select count(*) into c from game_private where match_id = mid;
  out := out || jsonb_build_object('rls_private_rows_visible', c);
  select count(*) into c from game_secret;
  out := out || jsonb_build_object('rls_secret_rows_visible', c);
  select count(*) into c from gm_quiz_bank;
  out := out || jsonb_build_object('rls_bank_rows_visible', c);
  begin perform _gm_uno_hand(gs, 1); exception when others then err := err || 'internal_fn:' || sqlerrm || ';'; end;
  reset role;
  -- QUIZ 2 players: u1 answers right, u2 wrong; last rounds by timeout -----------------------
  mid := pg_temp.mk('quiz', us[1:2], '{"category":"space"}');
  for i in 1..60 loop
    select * into gs from game_state where match_id = mid; exit when gs.status <> 'live';
    if gs.phase = 'question' and (gs.state->>'round')::int < 8 then
      select correct into c from gm_quiz_bank where id = gs.state->>'qid';
      perform pg_temp.as_user(us[1]); perform gm_move(mid, jsonb_build_object('a', 'answer', 'c', c));
      begin perform gm_move(mid, jsonb_build_object('a', 'answer', 'c', c)); exception when others then err := err || 'dup:' || sqlerrm || ';'; end;
      perform pg_temp.as_user(us[2]); perform gm_move(mid, jsonb_build_object('a', 'answer', 'c', (c + 1) % 4));
    else
      update game_state set deadline = now() - interval '1 second' where match_id = mid;
      perform pg_temp.as_user(us[2]); perform gm_tick(mid);
    end if;
  end loop;
  select * into gs from game_state where match_id = mid;
  out := out || jsonb_build_object('quiz', jsonb_build_object('iters', i, 'status', gs.status, 'result', gs.result, 'correct', gs.state->'correct',
     'cat', (select jsonb_agg(b.cat) from game_secret x, jsonb_array_elements_text(x.data->'qids') q join gm_quiz_bank b on b.id = q where x.match_id = mid)));
  raise exception 'RESULT %', out || jsonb_build_object('err', err);
end $$;
