-- NEXORA (Flutter online port): host can change the room mode (1v1 / 2v2 / 3v3) from the lobby
-- settings with the same call the Godot lobby makes: update_room(p_room, p_settings, p_name, p_mode).
--
-- ADDITIVE ONLY: a NEW overload with 4 REQUIRED parameters. The existing
-- update_room(p_room uuid, p_settings jsonb, p_name text default null) is untouched; PostgREST keeps
-- routing 2/3-argument calls (Expo, old Godot) to it, 4-argument calls come here (no defaults on the
-- new overload, so no PGRST203 ambiguity). Settings / name are then applied by the existing function.
-- When the mode shrinks, players sitting in a slot that no longer exists become spectators.

create function public.update_room(p_room uuid, p_settings jsonb, p_name text, p_mode text)
returns void language plpgsql security definer set search_path = public as $$
declare
  r rooms;
  m text := nullif(trim(coalesce(p_mode, '')), '');
  n int;
begin
  select * into r from rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if r.host <> auth.uid() then raise exception 'host only'; end if;
  if m is not null and m <> r.mode then
    if r.status <> 'waiting' then raise exception 'match running'; end if;
    if r.kind not in ('casual', 'social') or r.tournament_match_id is not null then raise exception 'not allowed'; end if;
    if m not in ('1v1', '2v2', '3v3') then raise exception 'bad mode'; end if;
    n := room_size(m);
    update room_players set role = 'spectator', team = null, slot = null, ready = false
      where room_id = p_room and role = 'player' and slot is not null and slot >= n;
    update rooms set mode = m, updated_at = now() where id = p_room;
  end if;
  perform public.update_room(p_room, p_settings, p_name);
end $$;

revoke all on function public.update_room(uuid, jsonb, text, text) from public, anon;
grant execute on function public.update_room(uuid, jsonb, text, text) to authenticated;
