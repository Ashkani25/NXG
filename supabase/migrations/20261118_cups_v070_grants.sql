-- NEXORA v0.7.0: tighten EXECUTE on the remaining cup RPCs (they defaulted to PUBLIC, i.e. also anon).
-- Additive/security only: signed-in users (incl. anonymous guests, who are 'authenticated') keep access.
revoke execute on function public.cup_checkin(uuid), public.cup_enter(uuid), public.cup_kick(uuid), public.cup_leave(uuid),
  public.cup_now(), public.cup_cfg() from public, anon;
grant execute on function public.cup_checkin(uuid), public.cup_enter(uuid), public.cup_kick(uuid), public.cup_leave(uuid),
  public.cup_now(), public.cup_cfg() to authenticated;
notify pgrst, 'reload schema';
