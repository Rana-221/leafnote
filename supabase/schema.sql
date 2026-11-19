-- ============================================================================
-- 轻笺 LeafNote · Supabase schema, functions, Row Level Security (RLS)
-- ============================================================================
-- 在 Supabase Dashboard -> SQL Editor 中一次性执行本文件。
-- 设计原则：
--   1. 所有业务表开启 RLS；组外用户读不到任何组内数据。
--   2. 群组、成员、邀请、角色变更只能通过 SECURITY DEFINER 函数完成，
--      客户端没有直接写入这些表的策略，避免绕过角色检查。
--   3. 实名信息放在独立表，读取由 RLS + 组内可见性设置双重限制；
--      组员在界面中通过 ln_get_group_real_identities() 获取，严格限定当前群组。
--   4. 笔记仅作者能修改/删除；组员都能阅读；脚本执行权限由前端按作者判断，
--      并在 sandbox iframe 中运行（见 src/lib/markdown.js）。
-- ============================================================================

-- gen_random_uuid() is built into modern PostgreSQL / Supabase, so no
-- extension schema (e.g. pgcrypto in "extensions") is required.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_length check (char_length(btrim(username)) between 2 and 24)
);

create unique index if not exists profiles_username_lower_idx
  on public.profiles (lower(username));

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references auth.users (id) on delete cascade,
  real_name_visibility text not null default 'members'
    check (real_name_visibility in ('members', 'admins', 'off')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint groups_name_length check (char_length(btrim(name)) between 1 and 60)
);

create table if not exists public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index if not exists group_members_user_idx
  on public.group_members (user_id);

create table if not exists public.real_identities (
  user_id uuid primary key references auth.users (id) on delete cascade,
  real_name text not null,
  id_number text not null,
  updated_at timestamptz not null default now(),
  constraint real_name_length check (char_length(btrim(real_name)) between 1 and 80),
  constraint id_number_length check (char_length(btrim(id_number)) between 4 and 64)
);

create table if not exists public.invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  code text not null unique,
  created_by uuid not null references auth.users (id) on delete cascade,
  expires_at timestamptz,
  max_uses integer,
  uses integer not null default 0,
  revoked boolean not null default false,
  created_at timestamptz not null default now(),
  constraint invites_code_length check (char_length(code) between 6 and 32),
  constraint invites_max_uses_check check (max_uses is null or max_uses between 1 and 10000),
  constraint invites_uses_check check (uses >= 0)
);

create index if not exists invites_group_idx on public.invites (group_id);

create table if not exists public.folders (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  parent_id uuid references public.folders (id) on delete cascade,
  name text not null,
  created_by uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint folders_name_length check (char_length(btrim(name)) between 1 and 80)
);

create index if not exists folders_group_idx on public.folders (group_id);
create index if not exists folders_parent_idx on public.folders (parent_id);

create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  folder_id uuid references public.folders (id) on delete set null,
  title text not null default '未命名笔记',
  content text not null default '',
  created_by uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notes_title_length check (char_length(btrim(title)) between 1 and 200)
);

create index if not exists notes_group_idx on public.notes (group_id);
create index if not exists notes_folder_idx on public.notes (folder_id);
create index if not exists notes_updated_idx on public.notes (updated_at desc);

-- ---------------------------------------------------------------------------
-- Utility triggers
-- ---------------------------------------------------------------------------

create or replace function public.ln_touch_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.ln_touch_updated_at();

drop trigger if exists groups_touch_updated_at on public.groups;
create trigger groups_touch_updated_at
  before update on public.groups
  for each row execute function public.ln_touch_updated_at();

drop trigger if exists real_identities_touch_updated_at on public.real_identities;
create trigger real_identities_touch_updated_at
  before update on public.real_identities
  for each row execute function public.ln_touch_updated_at();

drop trigger if exists folders_touch_updated_at on public.folders;
create trigger folders_touch_updated_at
  before update on public.folders
  for each row execute function public.ln_touch_updated_at();

drop trigger if exists notes_touch_updated_at on public.notes;
create trigger notes_touch_updated_at
  before update on public.notes
  for each row execute function public.ln_touch_updated_at();

-- ---------------------------------------------------------------------------
-- Auth -> profile bootstrap
-- ---------------------------------------------------------------------------

create or replace function public.ln_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  base_name text;
  candidate text;
  suffix integer := 0;
begin
  base_name := btrim(coalesce(new.raw_user_meta_data ->> 'username', ''));
  if char_length(base_name) < 2 then
    base_name := 'user_' || substr(new.id::text, 1, 8);
  end if;
  -- Keep room for a numeric suffix and respect the 24-char limit.
  base_name := left(base_name, 20);
  candidate := base_name;

  while exists (
    select 1 from public.profiles p where lower(p.username) = lower(candidate)
  ) loop
    suffix := suffix + 1;
    candidate := left(base_name, 20) || '_' || suffix::text;
  end loop;

  begin
    insert into public.profiles (id, username) values (new.id, candidate)
    on conflict (id) do nothing;
  exception when unique_violation then
    insert into public.profiles (id, username)
    values (new.id, 'user_' || substr(new.id::text, 1, 8))
    on conflict (id) do nothing;
  end;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.ln_handle_new_user();

-- If the schema is applied to a project that already has auth users, give
-- those users a placeholder profile. They can rename it in Profile settings.
insert into public.profiles (id, username)
select u.id, 'user_' || substr(u.id::text, 1, 8)
from auth.users u
where not exists (
  select 1 from public.profiles p where p.id = u.id
)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Membership / visibility helpers (SECURITY DEFINER avoids RLS recursion)
-- ---------------------------------------------------------------------------

create or replace function public.ln_is_group_member(
  p_group_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = p_user_id
  );
$$;

create or replace function public.ln_is_group_admin(
  p_group_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = p_user_id
      and gm.role = 'admin'
  );
$$;

create or replace function public.ln_shares_group_with(
  p_target_user_id uuid,
  p_viewer_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_viewer_id is not null
    and p_target_user_id is not null
    and (
      p_viewer_id = p_target_user_id
      or exists (
        select 1
        from public.group_members me
        join public.group_members them on them.group_id = me.group_id
        where me.user_id = p_viewer_id
          and them.user_id = p_target_user_id
      )
    );
$$;

-- Membership in at least one group whose owner has enabled real-name sharing.
create or replace function public.ln_can_view_real_identity(
  p_target_user_id uuid,
  p_viewer_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_viewer_id is not null
    and p_target_user_id is not null
    and (
      p_viewer_id = p_target_user_id
      or exists (
        select 1
        from public.group_members me
        join public.group_members target on target.group_id = me.group_id
        join public.groups g on g.id = me.group_id
        where me.user_id = p_viewer_id
          and target.user_id = p_target_user_id
          and (
            g.real_name_visibility = 'members'
            or (g.real_name_visibility = 'admins' and me.role = 'admin')
          )
      )
    );
$$;

-- ---------------------------------------------------------------------------
-- Integrity triggers
-- ---------------------------------------------------------------------------

create or replace function public.ln_validate_folder()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  parent_group uuid;
  makes_cycle boolean;
begin
  if new.parent_id is not null then
    if new.parent_id = new.id then
      raise exception 'FOLDER_CYCLE' using errcode = '23514';
    end if;

    select f.group_id into parent_group
    from public.folders f
    where f.id = new.parent_id;

    if parent_group is null or parent_group <> new.group_id then
      raise exception 'PARENT_FOLDER_INVALID' using errcode = '23514';
    end if;

    with recursive ancestors as (
      select f.id, f.parent_id
      from public.folders f
      where f.id = new.parent_id
      union all
      select f.id, f.parent_id
      from public.folders f
      join ancestors a on f.id = a.parent_id
    )
    select exists (select 1 from ancestors a where a.id = new.id)
    into makes_cycle;

    if makes_cycle then
      raise exception 'FOLDER_CYCLE' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists folders_validate on public.folders;
create trigger folders_validate
  before insert or update of parent_id, group_id on public.folders
  for each row execute function public.ln_validate_folder();

create or replace function public.ln_validate_note_folder()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  folder_group uuid;
begin
  if new.folder_id is not null then
    select f.group_id into folder_group
    from public.folders f
    where f.id = new.folder_id;

    if folder_group is null or folder_group <> new.group_id then
      raise exception 'NOTE_FOLDER_INVALID' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists notes_validate_folder on public.notes;
create trigger notes_validate_folder
  before insert or update of folder_id, group_id on public.notes
  for each row execute function public.ln_validate_note_folder();

-- ---------------------------------------------------------------------------
-- Group RPCs
-- ---------------------------------------------------------------------------

create or replace function public.ln_create_group(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_group_id uuid;
  v_name text := btrim(coalesce(p_name, ''));
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if char_length(v_name) < 1 or char_length(v_name) > 60 then
    raise exception 'INVALID_GROUP_NAME' using errcode = '22023';
  end if;

  insert into public.groups (name, owner_id)
  values (v_name, v_uid)
  returning id into v_group_id;

  insert into public.group_members (group_id, user_id, role)
  values (v_group_id, v_uid, 'admin');

  return v_group_id;
end;
$$;

create or replace function public.ln_update_group_settings(
  p_group_id uuid,
  p_name text,
  p_real_name_visibility text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
begin
  if v_uid is null or not public.ln_is_group_admin(p_group_id, v_uid) then
    raise exception 'ADMIN_REQUIRED' using errcode = '42501';
  end if;
  if char_length(v_name) < 1 or char_length(v_name) > 60 then
    raise exception 'INVALID_GROUP_NAME' using errcode = '22023';
  end if;
  if p_real_name_visibility is null
     or p_real_name_visibility not in ('members', 'admins', 'off') then
    raise exception 'INVALID_VISIBILITY' using errcode = '22023';
  end if;

  update public.groups
  set name = v_name,
      real_name_visibility = p_real_name_visibility
  where id = p_group_id;
end;
$$;

create or replace function public.ln_set_member_role(
  p_group_id uuid,
  p_user_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select owner_id into v_owner from public.groups where id = p_group_id;
  if v_owner is null then
    raise exception 'GROUP_NOT_FOUND' using errcode = '22023';
  end if;
  if v_owner <> v_uid then
    raise exception 'OWNER_REQUIRED' using errcode = '42501';
  end if;
  if p_user_id = v_owner then
    raise exception 'CANNOT_CHANGE_OWNER_ROLE' using errcode = '22023';
  end if;
  if p_role is null or p_role not in ('admin', 'member') then
    raise exception 'INVALID_ROLE' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = p_user_id
  ) then
    raise exception 'MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  update public.group_members
  set role = p_role
  where group_id = p_group_id and user_id = p_user_id;
end;
$$;

create or replace function public.ln_transfer_group(
  p_group_id uuid,
  p_new_owner_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_old_owner uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select owner_id into v_old_owner
  from public.groups
  where id = p_group_id
  for update;

  if v_old_owner is null then
    raise exception 'GROUP_NOT_FOUND' using errcode = '22023';
  end if;
  if v_old_owner <> v_uid then
    raise exception 'OWNER_REQUIRED' using errcode = '42501';
  end if;
  if p_new_owner_id = v_old_owner then
    raise exception 'ALREADY_OWNER' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = p_new_owner_id
  ) then
    raise exception 'MEMBER_NOT_FOUND' using errcode = '22023';
  end if;

  update public.groups set owner_id = p_new_owner_id where id = p_group_id;
  update public.group_members
    set role = 'admin'
    where group_id = p_group_id and user_id = p_new_owner_id;
  update public.group_members
    set role = 'member'
    where group_id = p_group_id and user_id = v_old_owner;
end;
$$;

create or replace function public.ln_remove_group_member(
  p_group_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_caller_role text;
  v_target_role text;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select owner_id into v_owner from public.groups where id = p_group_id;
  select role into v_caller_role
    from public.group_members where group_id = p_group_id and user_id = v_uid;
  select role into v_target_role
    from public.group_members where group_id = p_group_id and user_id = p_user_id;

  if v_caller_role is distinct from 'admin' then
    raise exception 'ADMIN_REQUIRED' using errcode = '42501';
  end if;
  if p_user_id = v_owner then
    raise exception 'CANNOT_REMOVE_OWNER' using errcode = '22023';
  end if;
  if v_target_role is null then
    raise exception 'MEMBER_NOT_FOUND' using errcode = '22023';
  end if;
  if v_target_role = 'admin' and v_uid <> v_owner then
    raise exception 'OWNER_REQUIRED' using errcode = '42501';
  end if;

  delete from public.group_members
  where group_id = p_group_id and user_id = p_user_id;
end;
$$;

create or replace function public.ln_leave_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select owner_id into v_owner from public.groups where id = p_group_id;
  if v_owner = v_uid then
    raise exception 'OWNER_MUST_TRANSFER' using errcode = '22023';
  end if;
  delete from public.group_members
  where group_id = p_group_id and user_id = v_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Invite RPCs
-- ---------------------------------------------------------------------------

create or replace function public.ln_create_invite(
  p_group_id uuid,
  p_expires_hours integer default 168,
  p_max_uses integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_invite public.invites;
  v_hours integer := coalesce(p_expires_hours, 168);
begin
  if v_uid is null or not public.ln_is_group_member(p_group_id, v_uid) then
    raise exception 'GROUP_MEMBER_REQUIRED' using errcode = '42501';
  end if;
  if v_hours < 1 or v_hours > 8760 then
    raise exception 'INVALID_EXPIRY' using errcode = '22023';
  end if;
  if p_max_uses is not null and (p_max_uses < 1 or p_max_uses > 10000) then
    raise exception 'INVALID_MAX_USES' using errcode = '22023';
  end if;

  loop
    -- 40 bits of randomness from a v4 UUID; enough for a short-lived invite.
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    begin
      insert into public.invites (
        group_id, code, created_by, expires_at, max_uses
      ) values (
        p_group_id, v_code, v_uid, now() + make_interval(hours => v_hours), p_max_uses
      )
      returning * into v_invite;
      exit;
    exception when unique_violation then
      -- Extremely unlikely; generate another code.
    end;
  end loop;

  return to_jsonb(v_invite);
end;
$$;

create or replace function public.ln_revoke_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_invite public.invites;
begin
  select * into v_invite from public.invites where id = p_invite_id;
  if v_invite.id is null then
    raise exception 'INVITE_NOT_FOUND' using errcode = '22023';
  end if;
  if not public.ln_is_group_member(v_invite.group_id, v_uid) then
    raise exception 'GROUP_MEMBER_REQUIRED' using errcode = '42501';
  end if;
  if v_invite.created_by <> v_uid and not public.ln_is_group_admin(v_invite.group_id, v_uid) then
    raise exception 'NOT_ALLOWED' using errcode = '42501';
  end if;
  update public.invites set revoked = true where id = p_invite_id;
end;
$$;

create or replace function public.ln_get_invite_preview(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_row record;
  v_member_count integer;
  v_already_member boolean;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  select i.*, g.name as group_name, p.username as inviter_username
  into v_row
  from public.invites i
  join public.groups g on g.id = i.group_id
  left join public.profiles p on p.id = i.created_by
  where upper(i.code) = upper(btrim(coalesce(p_code, '')))
  limit 1;

  if v_row.id is null then
    return jsonb_build_object('valid', false, 'reason', '邀请码不存在');
  end if;
  if v_row.revoked then
    return jsonb_build_object('valid', false, 'reason', '邀请码已被撤销');
  end if;
  if v_row.expires_at is not null and v_row.expires_at <= now() then
    return jsonb_build_object('valid', false, 'reason', '邀请码已过期');
  end if;
  if v_row.max_uses is not null and v_row.uses >= v_row.max_uses then
    return jsonb_build_object('valid', false, 'reason', '邀请码使用次数已用完');
  end if;

  select count(*) into v_member_count
  from public.group_members where group_id = v_row.group_id;
  select exists(
    select 1 from public.group_members
    where group_id = v_row.group_id and user_id = v_uid
  ) into v_already_member;

  return jsonb_build_object(
    'valid', true,
    'group_name', v_row.group_name,
    'inviter_username', v_row.inviter_username,
    'member_count', v_member_count,
    'already_member', v_already_member
  );
end;
$$;

create or replace function public.ln_join_group_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_invite public.invites;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  select * into v_invite
  from public.invites
  where upper(code) = upper(btrim(coalesce(p_code, '')))
  for update;

  if v_invite.id is null then
    raise exception 'INVITE_NOT_FOUND' using errcode = '22023';
  end if;
  if v_invite.revoked then
    raise exception 'INVITE_REVOKED' using errcode = '22023';
  end if;
  if v_invite.expires_at is not null and v_invite.expires_at <= now() then
    raise exception 'INVITE_EXPIRED' using errcode = '22023';
  end if;
  if v_invite.max_uses is not null and v_invite.uses >= v_invite.max_uses then
    raise exception 'INVITE_EXHAUSTED' using errcode = '22023';
  end if;

  insert into public.group_members (group_id, user_id, role)
  values (v_invite.group_id, v_uid, 'member')
  on conflict (group_id, user_id) do nothing;

  if not found then
    return v_invite.group_id;
  end if;

  update public.invites set uses = uses + 1 where id = v_invite.id;
  return v_invite.group_id;
end;
$$;

-- Group-scoped real-name lookup. This is deliberately an RPC rather than a
-- direct table read: the active group's visibility setting is enforced here,
-- so a name visible in group A never leaks while viewing group B.
create or replace function public.ln_get_group_real_identities(p_group_id uuid)
returns table (user_id uuid, real_name text, id_number text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_visibility text;
begin
  if v_uid is null or not public.ln_is_group_member(p_group_id, v_uid) then
    raise exception 'GROUP_MEMBER_REQUIRED' using errcode = '42501';
  end if;

  select g.real_name_visibility into v_visibility
  from public.groups g where g.id = p_group_id;

  if v_visibility is null or v_visibility = 'off' then
    return;
  end if;
  if v_visibility = 'admins' and not public.ln_is_group_admin(p_group_id, v_uid) then
    return;
  end if;

  return query
  select gm.user_id, ri.real_name, ri.id_number
  from public.group_members gm
  join public.real_identities ri on ri.user_id = gm.user_id
  where gm.group_id = p_group_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.real_identities enable row level security;
alter table public.invites enable row level security;
alter table public.folders enable row level security;
alter table public.notes enable row level security;

-- profiles ------------------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.ln_shares_group_with(id));

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- groups --------------------------------------------------------------------
drop policy if exists groups_select_member on public.groups;
create policy groups_select_member on public.groups
  for select to authenticated
  using (public.ln_is_group_member(id));

-- No client INSERT/UPDATE/DELETE policies: only RPCs may change groups.

-- group_members -------------------------------------------------------------
drop policy if exists group_members_select_member on public.group_members;
create policy group_members_select_member on public.group_members
  for select to authenticated
  using (public.ln_is_group_member(group_id));

-- No client INSERT/UPDATE/DELETE policies: only RPCs may change membership.

-- real_identities -----------------------------------------------------------
drop policy if exists real_identities_select on public.real_identities;
create policy real_identities_select on public.real_identities
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.ln_can_view_real_identity(user_id)
  );

drop policy if exists real_identities_insert_own on public.real_identities;
create policy real_identities_insert_own on public.real_identities
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists real_identities_update_own on public.real_identities;
create policy real_identities_update_own on public.real_identities
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists real_identities_delete_own on public.real_identities;
create policy real_identities_delete_own on public.real_identities
  for delete to authenticated
  using (user_id = auth.uid());

-- invites -------------------------------------------------------------------
drop policy if exists invites_select_member on public.invites;
create policy invites_select_member on public.invites
  for select to authenticated
  using (public.ln_is_group_member(group_id));

-- No client write policies: create/revoke use RPCs.

-- folders -------------------------------------------------------------------
drop policy if exists folders_select_member on public.folders;
create policy folders_select_member on public.folders
  for select to authenticated
  using (public.ln_is_group_member(group_id));

drop policy if exists folders_insert_member on public.folders;
create policy folders_insert_member on public.folders
  for insert to authenticated
  with check (
    public.ln_is_group_member(group_id)
    and created_by = auth.uid()
  );

drop policy if exists folders_update_owner_admin on public.folders;
create policy folders_update_owner_admin on public.folders
  for update to authenticated
  using (
    public.ln_is_group_member(group_id)
    and (created_by = auth.uid() or public.ln_is_group_admin(group_id))
  )
  with check (public.ln_is_group_member(group_id));

drop policy if exists folders_delete_owner_admin on public.folders;
create policy folders_delete_owner_admin on public.folders
  for delete to authenticated
  using (
    public.ln_is_group_member(group_id)
    and (created_by = auth.uid() or public.ln_is_group_admin(group_id))
  );

-- notes ---------------------------------------------------------------------
drop policy if exists notes_select_member on public.notes;
create policy notes_select_member on public.notes
  for select to authenticated
  using (public.ln_is_group_member(group_id));

drop policy if exists notes_insert_author on public.notes;
create policy notes_insert_author on public.notes
  for insert to authenticated
  with check (
    public.ln_is_group_member(group_id)
    and created_by = auth.uid()
  );

-- Only the author can change a note. This protects script provenance:
-- nobody can inject a script into another member's note.
drop policy if exists notes_update_author on public.notes;
create policy notes_update_author on public.notes
  for update to authenticated
  using (created_by = auth.uid() and public.ln_is_group_member(group_id))
  with check (created_by = auth.uid() and public.ln_is_group_member(group_id));

drop policy if exists notes_delete_author on public.notes;
create policy notes_delete_author on public.notes
  for delete to authenticated
  using (created_by = auth.uid() and public.ln_is_group_member(group_id));

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

-- Remove Supabase's permissive default table grants first, then grant only the
-- operations each client role actually needs. This prevents changing immutable
-- columns (group_id, created_by, roles, etc.) even if a write RLS policy allows
-- the row.
revoke all on table public.profiles from anon, authenticated;
revoke all on table public.groups from anon, authenticated;
revoke all on table public.group_members from anon, authenticated;
revoke all on table public.real_identities from anon, authenticated;
revoke all on table public.invites from anon, authenticated;
revoke all on table public.folders from anon, authenticated;
revoke all on table public.notes from anon, authenticated;

grant select on table public.profiles to authenticated;
grant update (username, avatar_path) on table public.profiles to authenticated;

grant select on table public.groups to authenticated;
grant select on table public.group_members to authenticated;
grant select, insert, update, delete on table public.real_identities to authenticated;
grant select on table public.invites to authenticated;

grant select, insert, delete on table public.folders to authenticated;
grant update (name, parent_id) on table public.folders to authenticated;

grant select, insert, delete on table public.notes to authenticated;
grant update (title, content, folder_id) on table public.notes to authenticated;

revoke all on function public.ln_is_group_member(uuid, uuid) from public, anon;
revoke all on function public.ln_is_group_admin(uuid, uuid) from public, anon;
revoke all on function public.ln_shares_group_with(uuid, uuid) from public, anon;
revoke all on function public.ln_can_view_real_identity(uuid, uuid) from public, anon;
revoke all on function public.ln_get_group_real_identities(uuid) from public, anon;
revoke all on function public.ln_create_group(text) from public, anon;
revoke all on function public.ln_update_group_settings(uuid, text, text) from public, anon;
revoke all on function public.ln_set_member_role(uuid, uuid, text) from public, anon;
revoke all on function public.ln_transfer_group(uuid, uuid) from public, anon;
revoke all on function public.ln_remove_group_member(uuid, uuid) from public, anon;
revoke all on function public.ln_leave_group(uuid) from public, anon;
revoke all on function public.ln_create_invite(uuid, integer, integer) from public, anon;
revoke all on function public.ln_revoke_invite(uuid) from public, anon;
revoke all on function public.ln_get_invite_preview(text) from public, anon;
revoke all on function public.ln_join_group_by_code(text) from public, anon;

grant execute on function public.ln_is_group_member(uuid, uuid) to authenticated;
grant execute on function public.ln_is_group_admin(uuid, uuid) to authenticated;
grant execute on function public.ln_shares_group_with(uuid, uuid) to authenticated;
grant execute on function public.ln_can_view_real_identity(uuid, uuid) to authenticated;
grant execute on function public.ln_get_group_real_identities(uuid) to authenticated;
grant execute on function public.ln_create_group(text) to authenticated;
grant execute on function public.ln_update_group_settings(uuid, text, text) to authenticated;
grant execute on function public.ln_set_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.ln_transfer_group(uuid, uuid) to authenticated;
grant execute on function public.ln_remove_group_member(uuid, uuid) to authenticated;
grant execute on function public.ln_leave_group(uuid) to authenticated;
grant execute on function public.ln_create_invite(uuid, integer, integer) to authenticated;
grant execute on function public.ln_revoke_invite(uuid) to authenticated;
grant execute on function public.ln_get_invite_preview(text) to authenticated;
grant execute on function public.ln_join_group_by_code(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage: private avatar bucket (signed URLs only)
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  false,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = 2097152,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists leafnote_avatars_select on storage.objects;
create policy leafnote_avatars_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'avatars'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or (
        name ~ '^[0-9a-fA-F-]{36}/'
        and public.ln_shares_group_with(((storage.foldername(name))[1])::uuid)
      )
    )
  );

drop policy if exists leafnote_avatars_insert on storage.objects;
create policy leafnote_avatars_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists leafnote_avatars_update on storage.objects;
create policy leafnote_avatars_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists leafnote_avatars_delete on storage.objects;
create policy leafnote_avatars_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- Done.
--
-- 首次配置还需要在 Dashboard 操作（无法用 SQL 代替）：
--   Authentication -> Providers -> Email: 开启 Confirm email
--   Authentication -> URL Configuration:
--     Site URL = https://<你的域名>/<仓库名>/
--     Redirect URLs += https://<你的域名>/<仓库名>/  (本地再加 http://localhost:5173/)
--   手机号绑定为可选：如需使用，配置 Authentication -> Providers -> Phone
-- ---------------------------------------------------------------------------
