-- LEXIAA GAME UPDATE v3
-- Includes the purchase fix: use p_avatar_id instead of ambiguous avatar_id.

-- Lexiaa Runner Game Update v2
-- Jalankan SEKALI di Supabase > SQL Editor setelah update aplikasi.

create table if not exists public.game_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  coins integer not null default 0 check (coins >= 0),
  selected_avatar text not null default 'nova',
  updated_at timestamptz not null default now()
);

create table if not exists public.game_avatar_unlocks (
  user_id uuid not null references auth.users(id) on delete cascade,
  avatar_id text not null,
  unlocked_at timestamptz not null default now(),
  primary key (user_id, avatar_id)
);

alter table public.game_profiles enable row level security;
alter table public.game_avatar_unlocks enable row level security;

drop policy if exists "game profile own" on public.game_profiles;
create policy "game profile own" on public.game_profiles
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "game unlocks own" on public.game_avatar_unlocks;
create policy "game unlocks own" on public.game_avatar_unlocks
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Koin dari perjalanan. Satu request dibatasi 1000 agar tetap masuk akal.
create or replace function public.add_game_coins(p_amount integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare new_coins integer;
begin
  if auth.uid() is null then raise exception 'Login diperlukan'; end if;
  if p_amount < 1 or p_amount > 1000 then raise exception 'Jumlah koin tidak valid'; end if;
  insert into public.game_profiles(user_id, coins)
  values (auth.uid(), p_amount)
  on conflict (user_id) do update set coins = public.game_profiles.coins + excluded.coins, updated_at = now()
  returning coins into new_coins;
  return jsonb_build_object('coins', new_coins);
end;
$$;

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

-- Simpan rekor waktu bertahan. Hanya rekor yang lebih tinggi yang boleh mengganti skor lama.
create or replace function public.save_runner_score(p_score integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare old_score integer := 0; new_score integer := 0; changed boolean := false;
begin
  if auth.uid() is null then raise exception 'Login diperlukan'; end if;
  if p_score < 0 or p_score > 86400 then raise exception 'Skor tidak valid'; end if;
  select high_score into old_score from public.game_scores where user_id=auth.uid() and game_key='runner';
  if old_score is null then old_score := 0; end if;
  if p_score > old_score then
    insert into public.game_scores(user_id,game_key,high_score,updated_at)
    values(auth.uid(),'runner',p_score,now())
    on conflict(user_id,game_key) do update set high_score=excluded.high_score,updated_at=now();
    new_score := p_score; changed := true;
  else
    new_score := old_score;
  end if;
  return jsonb_build_object('high_score',new_score,'new_record',changed);
end;
$$;

-- Leaderboard publik di dalam aplikasi (data profil dasar + rekor runner).
create or replace function public.get_runner_leaderboard()
returns table(user_id uuid, display_name text, username text, high_score integer)
language sql
security definer
set search_path = public
as $$
  select gs.user_id,
         coalesce(nullif(p.display_name,''), nullif(p.username,''), 'Pemain') as display_name,
         p.username,
         gs.high_score
  from public.game_scores gs
  left join public.profiles p on p.id=gs.user_id
  where gs.game_key='runner'
  order by gs.high_score desc, gs.updated_at asc
  limit 20;
$$;

revoke all on function public.add_game_coins(integer) from public;
grant execute on function public.add_game_coins(integer) to authenticated;
revoke all on function public.purchase_game_avatar(text,integer) from public;
grant execute on function public.purchase_game_avatar(text,integer) to authenticated;
revoke all on function public.save_runner_score(integer) from public;
grant execute on function public.save_runner_score(integer) to authenticated;
revoke all on function public.get_runner_leaderboard() from public;
grant execute on function public.get_runner_leaderboard() to authenticated;
