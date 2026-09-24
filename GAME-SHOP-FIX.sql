-- LEXIAA SHOP FIX v1
-- Jalankan SEKALI di Supabase > SQL Editor. Ini memperbaiki fungsi pembelian avatar.
create or replace function public.purchase_game_avatar(p_avatar_id text, p_price integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare new_coins integer;
begin
  if auth.uid() is null then raise exception 'Login diperlukan'; end if;
  if p_price < 1 or p_price > 5000 then raise exception 'Harga tidak valid'; end if;
  insert into public.game_profiles(user_id, coins) values (auth.uid(), 0) on conflict (user_id) do nothing;
  update public.game_profiles
    set coins = coins - p_price, updated_at = now()
    where user_id = auth.uid() and coins >= p_price
    returning coins into new_coins;
  if new_coins is null then raise exception 'Koin tidak cukup'; end if;
  insert into public.game_avatar_unlocks(user_id, avatar_id) values (auth.uid(), p_avatar_id) on conflict do nothing;
  return jsonb_build_object('coins', new_coins);
end;
$$;
revoke all on function public.purchase_game_avatar(text,integer) from public;
grant execute on function public.purchase_game_avatar(text,integer) to authenticated;
