-- Lexiaa: coarse city visibility + admin account bans
-- Run once in Supabase SQL Editor.

create table if not exists public.user_locations (
  user_id uuid primary key references auth.users(id) on delete cascade,
  city text not null,
  updated_at timestamptz not null default now()
);

alter table public.user_locations enable row level security;

drop policy if exists "user_locations_self_select" on public.user_locations;
drop policy if exists "user_locations_self_insert" on public.user_locations;
drop policy if exists "user_locations_self_update" on public.user_locations;
create policy "user_locations_self_select" on public.user_locations for select to authenticated using (user_id = auth.uid());
create policy "user_locations_self_insert" on public.user_locations for insert to authenticated with check (user_id = auth.uid());
create policy "user_locations_self_update" on public.user_locations for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create table if not exists public.user_bans (
  user_id uuid primary key references auth.users(id) on delete cascade,
  banned_until timestamptz null,
  reason text not null default 'Pelanggaran aturan Lexiaa',
  created_by uuid null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_bans enable row level security;
-- Tidak ada policy client untuk membaca daftar ban. Admin memakai SECURITY DEFINER RPC.

drop function if exists public.get_my_ban_status();
create or replace function public.get_my_ban_status()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object('banned', true, 'banned_until', banned_until, 'reason', reason)
     from public.user_bans b
     where b.user_id = auth.uid()
       and (b.banned_until is null or b.banned_until > now())
     limit 1),
    jsonb_build_object('banned', false)
  );
$$;
revoke all on function public.get_my_ban_status() from public;
grant execute on function public.get_my_ban_status() to authenticated;

drop function if exists public.admin_list_account_controls();
create or replace function public.admin_list_account_controls()
returns table(
  user_id uuid,
  email text,
  display_name text,
  username text,
  coins integer,
  city text,
  location_updated_at timestamptz,
  banned_until timestamptz,
  ban_reason text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  return query
  select u.id,
         u.email::text,
         p.display_name,
         p.username,
         coalesce(g.coins,0)::integer,
         l.city,
         l.updated_at,
         case when b.user_id is not null and (b.banned_until is null or b.banned_until > now()) then b.banned_until else null end,
         case when b.user_id is not null and (b.banned_until is null or b.banned_until > now()) then b.reason else null end
  from auth.users u
  left join public.profiles p on p.id=u.id
  left join public.game_profiles g on g.user_id=u.id
  left join public.user_locations l on l.user_id=u.id
  left join public.user_bans b on b.user_id=u.id
  order by u.created_at desc;
end;
$$;
revoke all on function public.admin_list_account_controls() from public;
grant execute on function public.admin_list_account_controls() to authenticated;

drop function if exists public.admin_set_user_ban(uuid,integer,text);
create or replace function public.admin_set_user_ban(p_user_id uuid, p_duration_minutes integer, p_reason text default 'Pelanggaran aturan Lexiaa')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_until timestamptz;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if p_user_id = auth.uid() then raise exception 'Admin tidak dapat memban dirinya sendiri'; end if;
  if p_duration_minutes is null or p_duration_minutes <= 0 then v_until := null; else v_until := now() + make_interval(mins => p_duration_minutes); end if;
  insert into public.user_bans(user_id,banned_until,reason,created_by,updated_at)
  values(p_user_id,v_until,coalesce(nullif(trim(p_reason),''),'Pelanggaran aturan Lexiaa'),auth.uid(),now())
  on conflict(user_id) do update set banned_until=excluded.banned_until,reason=excluded.reason,created_by=excluded.created_by,updated_at=now();
  return jsonb_build_object('ok',true,'banned_until',v_until);
end;
$$;
revoke all on function public.admin_set_user_ban(uuid,integer,text) from public;
grant execute on function public.admin_set_user_ban(uuid,integer,text) to authenticated;

drop function if exists public.admin_unban_user(uuid);
create or replace function public.admin_unban_user(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  delete from public.user_bans where user_id=p_user_id;
  return true;
end;
$$;
revoke all on function public.admin_unban_user(uuid) from public;
grant execute on function public.admin_unban_user(uuid) to authenticated;
-- Lexiaa Music Requests + Music Storage
-- Member-requested songs are visible ONLY to the member who requested them.
-- Admin-added songs are global and visible to every authenticated member.

create table if not exists public.music_catalog (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  audio_url text not null,
  storage_path text null,
  owner_user_id uuid null references auth.users(id) on delete cascade,
  active boolean not null default true,
  created_by uuid null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.music_catalog enable row level security;
alter table public.music_catalog add column if not exists storage_path text;
alter table public.music_catalog add column if not exists owner_user_id uuid references auth.users(id) on delete cascade;

drop policy if exists "music_catalog_authenticated_read" on public.music_catalog;
create policy "music_catalog_authenticated_read" on public.music_catalog
for select to authenticated using (
  active = true and (owner_user_id is null or owner_user_id = auth.uid())
);

create table if not exists public.music_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  status text not null default 'pending' check (status in ('pending','processing','rejected','completed')),
  admin_note text null,
  catalog_music_id uuid null references public.music_catalog(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.music_requests enable row level security;
drop policy if exists "music_requests_self_select" on public.music_requests;
drop policy if exists "music_requests_self_insert" on public.music_requests;
create policy "music_requests_self_select" on public.music_requests for select to authenticated using (user_id = auth.uid());
create policy "music_requests_self_insert" on public.music_requests for insert to authenticated with check (user_id = auth.uid());

drop function if exists public.submit_music_request(text);
create or replace function public.submit_music_request(p_title text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if length(trim(coalesce(p_title,''))) < 1 then raise exception 'Nama lagu wajib diisi'; end if;
  if length(trim(p_title)) > 160 then raise exception 'Nama lagu terlalu panjang'; end if;
  insert into public.music_requests(user_id,title) values(auth.uid(),trim(p_title)) returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id);
end; $$;
revoke all on function public.submit_music_request(text) from public;
grant execute on function public.submit_music_request(text) to authenticated;

drop function if exists public.admin_list_music_requests();
create or replace function public.admin_list_music_requests()
returns table(
  id uuid, user_id uuid, email text, display_name text, username text,
  title text, status text, admin_note text, catalog_music_id uuid,
  created_at timestamptz, updated_at timestamptz
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  return query
  select r.id,r.user_id,u.email::text,p.display_name,p.username,r.title,r.status,r.admin_note,
         r.catalog_music_id,r.created_at,r.updated_at
  from public.music_requests r
  join auth.users u on u.id=r.user_id
  left join public.profiles p on p.id=r.user_id
  order by r.created_at desc;
end; $$;
revoke all on function public.admin_list_music_requests() from public;
grant execute on function public.admin_list_music_requests() to authenticated;

drop function if exists public.admin_approve_music_request(uuid);
create or replace function public.admin_approve_music_request(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  update public.music_requests
  set status='processing', admin_note='Pengajuan diterima dan sedang diproses admin.', updated_at=now()
  where id=p_request_id and status='pending';
  if not found then raise exception 'Pengajuan tidak ditemukan atau sudah diproses'; end if;
  return jsonb_build_object('ok',true,'status','processing');
end; $$;
revoke all on function public.admin_approve_music_request(uuid) from public;
grant execute on function public.admin_approve_music_request(uuid) to authenticated;

drop function if exists public.admin_reject_music_request(uuid,text);
create or replace function public.admin_reject_music_request(p_request_id uuid,p_note text default 'Maaf, pengajuan anda ditolak.')
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  update public.music_requests
  set status='rejected',admin_note=coalesce(nullif(trim(p_note),''),'Maaf, pengajuan anda ditolak.'),updated_at=now()
  where id=p_request_id and status='pending';
  if not found then raise exception 'Pengajuan tidak ditemukan atau sudah diproses'; end if;
  return true;
end; $$;
revoke all on function public.admin_reject_music_request(uuid,text) from public;
grant execute on function public.admin_reject_music_request(uuid,text) to authenticated;

drop function if exists public.admin_publish_music_request(uuid,text,text);
drop function if exists public.admin_publish_music_request(uuid,text,text,text);
create or replace function public.admin_publish_music_request(
  p_request_id uuid, p_audio_url text, p_storage_path text, p_title text default null
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.music_requests; v_music_id uuid; v_title text;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if length(trim(coalesce(p_audio_url,''))) < 8 then raise exception 'Audio URL tidak valid'; end if;
  if length(trim(coalesce(p_storage_path,''))) < 1 then raise exception 'Storage path wajib diisi'; end if;
  select * into r from public.music_requests where id=p_request_id;
  if not found then raise exception 'Pengajuan tidak ditemukan'; end if;
  if r.status <> 'processing' then raise exception 'Pengajuan harus berstatus processing'; end if;
  v_title=coalesce(nullif(trim(p_title),''),r.title);
  insert into public.music_catalog(title,audio_url,storage_path,owner_user_id,created_by)
  values(v_title,trim(p_audio_url),trim(p_storage_path),r.user_id,auth.uid()) returning id into v_music_id;
  update public.music_requests
  set status='completed',catalog_music_id=v_music_id,
      admin_note='Sukses! Lagu sudah tersedia di Music Lexiaa untuk akun kamu.',updated_at=now()
  where id=p_request_id;
  return jsonb_build_object('ok',true,'music_id',v_music_id);
end; $$;
revoke all on function public.admin_publish_music_request(uuid,text,text,text) from public;
grant execute on function public.admin_publish_music_request(uuid,text,text,text) to authenticated;

drop function if exists public.admin_add_music(text,text);
drop function if exists public.admin_add_music(text,text,text);
create or replace function public.admin_add_music(p_title text,p_audio_url text,p_storage_path text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if length(trim(coalesce(p_title,''))) < 1 then raise exception 'Judul wajib diisi'; end if;
  if length(trim(coalesce(p_audio_url,''))) < 8 then raise exception 'Audio URL tidak valid'; end if;
  if length(trim(coalesce(p_storage_path,''))) < 1 then raise exception 'Storage path wajib diisi'; end if;
  insert into public.music_catalog(title,audio_url,storage_path,owner_user_id,created_by)
  values(trim(p_title),trim(p_audio_url),trim(p_storage_path),null,auth.uid()) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.admin_add_music(text,text,text) from public;
grant execute on function public.admin_add_music(text,text,text) to authenticated;

drop function if exists public.admin_list_music_catalog();
create or replace function public.admin_list_music_catalog()
returns table(id uuid,title text,audio_url text,storage_path text,active boolean,owner_user_id uuid,created_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  return query
  select m.id,m.title,m.audio_url,m.storage_path,m.active,m.owner_user_id,m.created_at
  from public.music_catalog m order by m.created_at desc;
end; $$;
revoke all on function public.admin_list_music_catalog() from public;
grant execute on function public.admin_list_music_catalog() to authenticated;

drop function if exists public.admin_delete_music(uuid);
create or replace function public.admin_delete_music(p_music_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m public.music_catalog;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  select * into m from public.music_catalog where id=p_music_id;
  if not found then raise exception 'Lagu tidak ditemukan'; end if;
  delete from public.music_catalog where id=p_music_id;
  return jsonb_build_object('ok',true,'storage_path',m.storage_path,'owner_user_id',m.owner_user_id);
end; $$;
revoke all on function public.admin_delete_music(uuid) from public;
grant execute on function public.admin_delete_music(uuid) to authenticated;

insert into storage.buckets (id,name,public)
values ('music','music',true)
on conflict (id) do update set public=true;

drop policy if exists "lexiaa_admin_music_upload" on storage.objects;
create policy "lexiaa_admin_music_upload" on storage.objects for insert to authenticated
with check (bucket_id='music' and public.is_admin());

drop policy if exists "lexiaa_admin_music_update" on storage.objects;
create policy "lexiaa_admin_music_update" on storage.objects for update to authenticated
using (bucket_id='music' and public.is_admin())
with check (bucket_id='music' and public.is_admin());

drop policy if exists "lexiaa_admin_music_delete" on storage.objects;
create policy "lexiaa_admin_music_delete" on storage.objects for delete to authenticated
using (bucket_id='music' and public.is_admin());

-- Admin may also read storage objects through the public bucket URL.
-- Existing old catalog rows are treated as global (owner_user_id NULL), so they remain visible to everyone
-- until the admin deletes them from the Admin Panel.
