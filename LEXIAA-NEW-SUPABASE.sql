-- LEXIAA NEW DATABASE — run on the NEW Supabase project.
create extension if not exists "pgcrypto";
create table if not exists public.profiles(id uuid primary key references auth.users(id) on delete cascade,display_name text not null default 'Lexiaa User',avatar_path text,theme text not null default 'obsidian',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.photos(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,storage_path text not null unique,file_name text not null,created_at timestamptz not null default now());
create table if not exists public.music(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,storage_path text not null unique,title text not null,created_at timestamptz not null default now());
create table if not exists public.ai_history(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,tool text not null,prompt text,result text,created_at timestamptz not null default now());
alter table public.ai_history add column if not exists result text;
create table if not exists public.game_scores(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,game text not null,score integer not null default 0,played_at timestamptz not null default now());
alter table public.profiles add column if not exists diamonds integer not null default 0;
alter table public.game_scores add column if not exists diamond_earned integer not null default 0;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,display_name)
  values(new.id,left(coalesce(nullif(new.raw_user_meta_data->>'display_name',''),nullif(split_part(coalesce(new.email,''),'@',1),''),'Lexiaa User'),80))
  on conflict(id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at=now(); return new; end; $$;
drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at before update on public.profiles for each row execute procedure public.touch_updated_at();

alter table public.profiles enable row level security;
alter table public.photos enable row level security;
alter table public.music enable row level security;
alter table public.ai_history enable row level security;
alter table public.game_scores enable row level security;

drop policy if exists profiles_own on public.profiles;
create policy profiles_own on public.profiles for all to authenticated using(id=auth.uid()) with check(id=auth.uid());
drop policy if exists photos_own on public.photos;
create policy photos_own on public.photos for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists music_own on public.music;
create policy music_own on public.music for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists ai_history_own on public.ai_history;
create policy ai_history_own on public.ai_history for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists game_scores_own on public.game_scores;
create policy game_scores_own on public.game_scores for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

insert into storage.buckets(id,name,public) values('photos','photos',false),('music','music',false),('avatars','avatars',false) on conflict(id) do update set public=false;
drop policy if exists photos_storage on storage.objects;
create policy photos_storage on storage.objects for all to authenticated using(bucket_id='photos' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists music_storage on storage.objects;
create policy music_storage on storage.objects for all to authenticated using(bucket_id='music' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='music' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatars_storage on storage.objects;
create policy avatars_storage on storage.objects for all to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
-- Logged-in users may view profile avatars used by the leaderboard; uploads/deletes remain owner-only.
drop policy if exists avatars_view_authenticated on storage.objects;
create policy avatars_view_authenticated on storage.objects for select to authenticated using(bucket_id='avatars');


-- Leaderboard: public-to-authenticated ranking without exposing email/profile secrets.
drop view if exists public.leaderboard;
drop function if exists public.get_leaderboard(text);
create function public.get_leaderboard(p_game text)
returns table(id uuid, game text, display_name text, avatar_path text, score integer, played_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select ranked.id, ranked.game, ranked.display_name, ranked.avatar_path, ranked.score, ranked.played_at
  from (
    select distinct on (gs.user_id)
           gs.id, gs.user_id, gs.game,
           coalesce(nullif(p.display_name,''),'Lexiaa User') as display_name,
           p.avatar_path, gs.score, gs.played_at
    from public.game_scores gs
    left join public.profiles p on p.id=gs.user_id
    where gs.game = p_game
    order by gs.user_id, gs.score desc, gs.played_at asc
  ) ranked
  order by ranked.score desc, ranked.played_at asc
  limit 50;
$$;
-- Atomic score save + Quick Tap diamond reward. Existing score/history behavior is preserved.
drop function if exists public.save_game_score(text, integer);
create function public.save_game_score(p_game text, p_score integer)
returns table(score_id uuid, diamonds_earned integer, diamond_balance integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_reward integer := 0;
  v_balance integer := 0;
  v_score integer := greatest(0, p_score);
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if p_game not in ('Quick Tap','Quiz') then
    raise exception 'Invalid game';
  end if;
  if p_game = 'Quick Tap' then
    v_reward := floor(v_score / 10.0)::integer;
  end if;

  insert into public.game_scores(user_id,game,score,diamond_earned)
  values(auth.uid(),p_game,v_score,v_reward)
  returning id into v_id;

  update public.profiles
     set diamonds = diamonds + v_reward, updated_at = now()
   where id = auth.uid()
   returning diamonds into v_balance;

  return query select v_id, v_reward, coalesce(v_balance,0);
end;
$$;

revoke all on function public.save_game_score(text,integer) from public;
grant execute on function public.save_game_score(text,integer) to authenticated;

revoke all on function public.get_leaderboard(text) from public;
grant execute on function public.get_leaderboard(text) to authenticated;
