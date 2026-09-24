-- LEXIAA - standalone Supabase schema
-- Create a NEW Supabase project for Lexiaa. Do not run this against Tann Album.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  username text unique,
  avatar_path text,
  theme text not null default 'obsidian' check (theme in ('obsidian','aurora','pearl','midnight','rosewood')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null,
  mime_type text,
  size_bytes bigint,
  created_at timestamptz not null default now()
);

create table if not exists public.music (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique,
  title text not null,
  mime_type text,
  size_bytes bigint,
  created_at timestamptz not null default now()
);

create table if not exists public.ai_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  tool text not null,
  input text not null,
  output text,
  created_at timestamptz not null default now()
);

create table if not exists public.game_scores (
  user_id uuid not null references auth.users(id) on delete cascade,
  game_key text not null,
  high_score integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, game_key)
);

create table if not exists public.activity (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.photos enable row level security;
alter table public.music enable row level security;
alter table public.ai_history enable row level security;
alter table public.game_scores enable row level security;
alter table public.activity enable row level security;

drop policy if exists "profiles own select" on public.profiles;
create policy "profiles own select" on public.profiles for select using (auth.uid() = id);
drop policy if exists "profiles own insert" on public.profiles;
create policy "profiles own insert" on public.profiles for insert with check (auth.uid() = id);
drop policy if exists "profiles own update" on public.profiles;
create policy "profiles own update" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "photos own" on public.photos;
create policy "photos own" on public.photos for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "music own" on public.music;
create policy "music own" on public.music for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "ai own" on public.ai_history;
create policy "ai own" on public.ai_history for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "scores own" on public.game_scores;
create policy "scores own" on public.game_scores for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "activity own" on public.activity;
create policy "activity own" on public.activity for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Automatically create a profile after signup.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$ begin
  insert into public.profiles(id, display_name) values (new.id, coalesce(new.raw_user_meta_data->>'display_name','')) on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- Private buckets. The frontend only receives signed URLs for the current user.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types) values
('photos','photos',false,15728640,array['image/jpeg','image/png','image/webp','image/gif']),
('music','music',false,52428800,array['audio/mpeg','audio/mp3','audio/wav','audio/ogg','audio/mp4','audio/aac','audio/webm']),
('avatars','avatars',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false;

-- Storage isolation: first path segment must be the authenticated user's UUID.
drop policy if exists "photos storage select own" on storage.objects;
create policy "photos storage select own" on storage.objects for select to authenticated using (bucket_id='photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "photos storage insert own" on storage.objects;
create policy "photos storage insert own" on storage.objects for insert to authenticated with check (bucket_id='photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "photos storage delete own" on storage.objects;
create policy "photos storage delete own" on storage.objects for delete to authenticated using (bucket_id='photos' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists "music storage select own" on storage.objects;
create policy "music storage select own" on storage.objects for select to authenticated using (bucket_id='music' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "music storage insert own" on storage.objects;
create policy "music storage insert own" on storage.objects for insert to authenticated with check (bucket_id='music' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "music storage delete own" on storage.objects;
create policy "music storage delete own" on storage.objects for delete to authenticated using (bucket_id='music' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists "avatar storage select own" on storage.objects;
create policy "avatar storage select own" on storage.objects for select to authenticated using (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "avatar storage insert own" on storage.objects;
create policy "avatar storage insert own" on storage.objects for insert to authenticated with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "avatar storage delete own" on storage.objects;
create policy "avatar storage delete own" on storage.objects for delete to authenticated using (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
