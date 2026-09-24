-- LEXIAA NEW DATABASE — run on the NEW Supabase project.
create extension if not exists "pgcrypto";
create table if not exists public.profiles(id uuid primary key references auth.users(id) on delete cascade,display_name text not null default 'Lexiaa User',avatar_path text,theme text not null default 'obsidian',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.photos(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,storage_path text not null unique,file_name text not null,created_at timestamptz not null default now());
create table if not exists public.music(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,storage_path text not null unique,title text not null,created_at timestamptz not null default now());
create table if not exists public.ai_history(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,tool text not null,prompt text,result text,created_at timestamptz not null default now());
alter table public.ai_history add column if not exists result text;
create table if not exists public.game_scores(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,game text not null,score integer not null default 0,played_at timestamptz not null default now());

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
