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
