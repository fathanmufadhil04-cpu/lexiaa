-- LEXIAA ADMIN PANEL v1
-- Jalankan SEKALI di Supabase SQL Editor.
-- Setelah itu, ganti EMAIL_ADMIN di bagian bootstrap dengan email akun admin kamu lalu Run.

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;

drop policy if exists "admin own select" on public.admin_users;
create policy "admin own select" on public.admin_users
for select using (auth.uid() = user_id);

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(select 1 from public.admin_users where user_id = auth.uid());
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Admin dapat membaca data akun tanpa membuka data antar-user ke pengguna biasa.
drop policy if exists "admin read profiles" on public.profiles;
create policy "admin read profiles" on public.profiles for select using (public.is_admin());
drop policy if exists "admin read photos" on public.photos;
create policy "admin read photos" on public.photos for select using (public.is_admin());
drop policy if exists "admin read music" on public.music;
create policy "admin read music" on public.music for select using (public.is_admin());
drop policy if exists "admin read game profiles" on public.game_profiles;
create policy "admin read game profiles" on public.game_profiles for select using (public.is_admin());
drop policy if exists "admin read game unlocks" on public.game_avatar_unlocks;
create policy "admin read game unlocks" on public.game_avatar_unlocks for select using (public.is_admin());
drop policy if exists "admin read game scores" on public.game_scores;
create policy "admin read game scores" on public.game_scores for select using (public.is_admin());

-- Admin perlu bisa membuat signed URL untuk file private milik akun lain.
drop policy if exists "admin storage photos select" on storage.objects;
create policy "admin storage photos select" on storage.objects for select to authenticated using (bucket_id='photos' and public.is_admin());
drop policy if exists "admin storage music select" on storage.objects;
create policy "admin storage music select" on storage.objects for select to authenticated using (bucket_id='music' and public.is_admin());
drop policy if exists "admin storage avatars select" on storage.objects;
create policy "admin storage avatars select" on storage.objects for select to authenticated using (bucket_id='avatars' and public.is_admin());

create or replace function public.admin_list_users()
returns table(
  user_id uuid,
  email text,
  display_name text,
  username text,
  created_at timestamptz,
  coins integer,
  selected_avatar text,
  high_score integer
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  return query
  select u.id,
         u.email::text,
         coalesce(p.display_name,''),
         coalesce(p.username,''),
         u.created_at,
         coalesce(g.coins,0),
         coalesce(g.selected_avatar,'nova'),
         coalesce(gs.high_score,0)
  from auth.users u
  left join public.profiles p on p.id=u.id
  left join public.game_profiles g on g.user_id=u.id
  left join public.game_scores gs on gs.user_id=u.id and gs.game_key='runner'
  order by u.created_at desc;
end;
$$;
revoke all on function public.admin_list_users() from public;
grant execute on function public.admin_list_users() to authenticated;

create or replace function public.admin_add_game_coins(p_user_id uuid, p_amount integer)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  old_coins integer;
  new_coins integer;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  if p_amount is null or p_amount < 1 or p_amount > 1000000 then
    raise exception 'Jumlah koin harus 1 sampai 1.000.000';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'Akun tidak ditemukan';
  end if;

  select coins into old_coins
  from public.game_profiles
  where user_id = p_user_id
  for update;

  if old_coins is null then
    old_coins := 0;
    insert into public.game_profiles(user_id, coins, selected_avatar)
    values (p_user_id, p_amount, 'nova')
    on conflict (user_id) do update
      set coins = public.game_profiles.coins + excluded.coins, updated_at = now()
    returning coins into new_coins;
  else
    update public.game_profiles
      set coins = old_coins + p_amount, updated_at = now()
    where user_id = p_user_id
    returning coins into new_coins;
  end if;

  return jsonb_build_object(
    'user_id', p_user_id,
    'added', p_amount,
    'previous_coins', old_coins,
    'coins', new_coins
  );
end;
$$;
revoke all on function public.admin_add_game_coins(uuid,integer) from public;
grant execute on function public.admin_add_game_coins(uuid,integer) to authenticated;

-- BOOTSTRAP ADMIN:
-- 1. Ganti EMAIL_ADMIN dengan email akun Lexiaa milikmu.
-- 2. Jalankan baris INSERT ini sekali.
-- 3. Setelah itu buka admin.html.
insert into public.admin_users(user_id)
select id from auth.users where lower(email)=lower('fathanmufadhil04@gmail.com')
on conflict do nothing;
