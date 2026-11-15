do $sim$
declare u1 uuid; u2 uuid; u3 uuid; c cups; m cup_matches; r jsonb; out jsonb := '{}'; rm rooms; mid uuid; err text; g record;
  procedure_dummy int;
begin
  select id into u1 from profiles order by created_at limit 1;
  select id into u2 from profiles where id <> u1 order by created_at limit 1;
  select id into u3 from profiles where id not in (u1,u2) order by created_at limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',u1,'role','authenticated')::text, true);
  c := cup_create_v3('Sim two-leg', 4, 'two_leg', 7, 3, 3, now() + interval '30 minutes', 0, '{60,30,10}', true, true, false, 'golden_goal', '', 0, '');
  out := out || jsonb_build_object('created', jsonb_build_object('mode', c.series_mode, 'games', c.games, 'target', c.target_wins, 'decider', c.decider, 'approval', c.require_approval));
  -- u2 requests, organizer approves; u3 requests, is rejected, re-request blocked
  perform set_config('request.jwt.claims', json_build_object('sub',u2,'role','authenticated')::text, true);
  perform cup_join(c.code);
  out := out || jsonb_build_object('u2_after_join', (select status from cup_players where cup_id=c.id and user_id=u2));
  perform set_config('request.jwt.claims', json_build_object('sub',u3,'role','authenticated')::text, true);
  perform cup_join(c.code);
  perform set_config('request.jwt.claims', json_build_object('sub',u1,'role','authenticated')::text, true);
  perform cup_approve(c.id, u2, true);
  perform cup_approve(c.id, u3, false);
  out := out || jsonb_build_object('u2_after_approve', (select status from cup_players where cup_id=c.id and user_id=u2));
  perform set_config('request.jwt.claims', json_build_object('sub',u3,'role','authenticated')::text, true);
  begin perform cup_join(c.code); err := 'NO ERROR'; exception when others then err := sqlerrm; end;
  out := out || jsonb_build_object('u3_rerequest', err);
  -- check-in window (10 min before start)
  update cups set starts_at = now() + interval '5 minutes' where id=c.id;
  perform set_config('request.jwt.claims', json_build_object('sub',u1,'role','authenticated')::text, true); perform cup_checkin(c.id);
  perform set_config('request.jwt.claims', json_build_object('sub',u2,'role','authenticated')::text, true); perform cup_checkin(c.id);
  out := out || jsonb_build_object('checked_in', (select count(*) from cup_players where cup_id=c.id and checked_in_at is not null));
  -- scheduled time reached: draw
  update cups set starts_at = now() - interval '1 second' where id=c.id;
  perform _cup_draw(c.id);
  select * into m from cup_matches where cup_id=c.id and kind='main' and round=1;
  out := out || jsonb_build_object('draw', jsonb_build_object('status', m.status, 'p1', m.p1 is not null, 'p2', m.p2 is not null),
     'draw_notified', (select count(*) from notifications where kind='cup_draw' and data->>'cup' = c.id::text),
     'ready_notified', (select count(*) from notifications where kind='cup_ready' and data->>'match' = m.id::text));
  -- both enter (app-wide auto-move calls cup_enter for each)
  perform set_config('request.jwt.claims', json_build_object('sub',m.p1,'role','authenticated')::text, true); perform cup_enter(m.id);
  perform set_config('request.jwt.claims', json_build_object('sub',m.p2,'role','authenticated')::text, true); perform cup_enter(m.id);
  -- game 1 (leg 1, home p1): both press Play + ready
  for g in select gs from generate_series(1,3) gs loop
    perform set_config('request.jwt.claims', json_build_object('sub',m.p1,'role','authenticated')::text, true);
    r := cup_ready(m.id, null, 2, 5, 9);
    perform set_config('request.jwt.claims', json_build_object('sub',m.p2,'role','authenticated')::text, true);
    r := cup_ready(m.id, null, 1, 7, 7);
    select * into m from cup_matches where id=m.id;
    select * into rm from rooms where id=m.room_id;
    out := out || jsonb_build_object('game'||g.gs, jsonb_build_object('cup_status', m.status, 'room_status', rm.status,
       'leg', rm.settings->'leg', 'home_is_p2', (rm.settings->>'home')::uuid = m.p2, 'goals', rm.settings->'goals', 'decider', rm.settings->'decider',
       'forms', rm.settings->'forms', 'field', rm.settings->'field', 'ball', rm.settings->'ball',
       'team0', (select user_id = m.p1 from room_players where room_id=rm.id and team=0 limit 1)));
    mid := rm.current_match;
    -- results (team_a = home): leg1 home p1 2:1, leg2 home p2 2:1 (3:3 agg), decider p1 1:0
    update matches set status='done', score_a = case g.gs when 1 then 2 when 2 then 2 else 1 end,
                                         score_b = case g.gs when 1 then 1 when 2 then 1 else 0 end, ended_at=now() where id=mid;
    update rooms set status='waiting', current_match=null where id=rm.id;
    select * into m from cup_matches where id=m.id;
    exit when m.status='done';
  end loop;
  out := out || jsonb_build_object('series', jsonb_build_object('status', m.status, 'winner_is_p1', m.winner = m.p1, 'played', m.games_played, 'g', array[m.goals1, m.goals2]),
     'games', (select jsonb_agg(jsonb_build_object('no',game_no,'g',array[g1,g2],'leg',leg,'home_p1',home_user=m.p1,'decider',decider) order by game_no) from cup_games where match_id=m.id),
     'cup_status', (select status from cups where id=c.id),
     'podium', cup_podium(c.id),
     'rank_rows', (select jsonb_agg(jsonb_build_object('titles',titles,'runner',runner_up,'pts',points,'sw',series_wins,'gf',goals_for,'ga',goals_against)) from cup_rankings where user_id in (m.p1,m.p2)),
     'ranking_rpc_len', jsonb_array_length(cup_ranking(10, 0)));
  raise exception 'SIMRESULT %', out;
end $sim$;
