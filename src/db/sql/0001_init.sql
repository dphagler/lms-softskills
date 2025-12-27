-- ==========================================
-- 0001_init.sql — Multi-tenant LMS schema + RLS
-- ==========================================
begin;

create extension if not exists pgcrypto;

do $$ begin
  create type public.app_role as enum ('student','teacher','admin','district_admin','employer');
exception when duplicate_object then null;
end $$;

create table public.orgs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

create table public.memberships (
  org_id uuid not null references public.orgs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null,
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);

create table public.classes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  name text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.enrollments (
  class_id uuid not null references public.classes(id) on delete cascade,
  org_id uuid not null references public.orgs(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (class_id, student_id)
);

create table public.content_modules (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  title text not null,
  description text,
  youtube_url text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.assessments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  module_id uuid not null references public.content_modules(id) on delete cascade,
  title text not null,
  rubric jsonb not null default '{}'::jsonb,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.mastery (
  org_id uuid not null references public.orgs(id) on delete cascade,
  assessment_id uuid not null references public.assessments(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  score numeric(5,2) not null default 0,
  last_attempt_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (assessment_id, student_id)
);

create table public.score_deltas (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  assessment_id uuid not null references public.assessments(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  prev_score numeric(5,2) not null,
  new_score numeric(5,2) not null,
  delta numeric(5,2) not null generated always as (new_score - prev_score) stored,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id)
);

create table public.certificates (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  issued_at timestamptz not null default now(),
  issued_by uuid not null references auth.users(id)
);

-- Helper functions used by RLS
create or replace function public.is_member(target_org uuid)
returns boolean
language sql stable
as $$
  select exists (
    select 1 from public.memberships m
    where m.org_id = target_org and m.user_id = auth.uid()
  );
$$;

create or replace function public.has_role(target_org uuid, allowed public.app_role[])
returns boolean
language sql stable
as $$
  select exists (
    select 1 from public.memberships m
    where m.org_id = target_org and m.user_id = auth.uid() and m.role = any(allowed)
  );
$$;

-- Create profile row on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', new.email))
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Enable RLS
alter table public.orgs enable row level security;
alter table public.profiles enable row level security;
alter table public.memberships enable row level security;
alter table public.classes enable row level security;
alter table public.enrollments enable row level security;
alter table public.content_modules enable row level security;
alter table public.assessments enable row level security;
alter table public.mastery enable row level security;
alter table public.score_deltas enable row level security;
alter table public.certificates enable row level security;

-- ORGS
create policy orgs_select on public.orgs
for select to authenticated
using (public.is_member(id));

create policy orgs_insert on public.orgs
for insert to authenticated
with check (true);

create policy orgs_update on public.orgs
for update to authenticated
using (public.has_role(id, array['admin','district_admin']::public.app_role[]))
with check (public.has_role(id, array['admin','district_admin']::public.app_role[]));

-- PROFILES
create policy profiles_select on public.profiles
for select to authenticated
using (user_id = auth.uid());

create policy profiles_update on public.profiles
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- MEMBERSHIPS
create policy memberships_select on public.memberships
for select to authenticated
using (public.is_member(org_id));

create policy memberships_insert on public.memberships
for insert to authenticated
with check (public.has_role(org_id, array['admin','district_admin']::public.app_role[]));

create policy memberships_update on public.memberships
for update to authenticated
using (public.has_role(org_id, array['admin','district_admin']::public.app_role[]))
with check (public.has_role(org_id, array['admin','district_admin']::public.app_role[]));

create policy memberships_delete on public.memberships
for delete to authenticated
using (public.has_role(org_id, array['admin','district_admin']::public.app_role[]));

-- CLASSES
create policy classes_select on public.classes
for select to authenticated
using (public.is_member(org_id));

create policy classes_insert on public.classes
for insert to authenticated
with check (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

create policy classes_update on public.classes
for update to authenticated
using (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]))
with check (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

create policy classes_delete on public.classes
for delete to authenticated
using (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

-- ENROLLMENTS
create policy enrollments_select on public.enrollments
for select to authenticated
using (
  public.is_member(org_id) and
  (
    public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[])
    or student_id = auth.uid()
  )
);

create policy enrollments_insert on public.enrollments
for insert to authenticated
with check (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

create policy enrollments_update on public.enrollments
for update to authenticated
using (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]))
with check (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

create policy enrollments_delete on public.enrollments
for delete to authenticated
using (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

-- CONTENT MODULES
create policy content_select on public.content_modules
for select to authenticated
using (public.is_member(org_id));

create policy content_insert on public.content_modules
for insert to authenticated
with check (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

create policy content_update on public.content_modules
for update to authenticated
using (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]))
with check (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

create policy content_delete on public.content_modules
for delete to authenticated
using (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

-- ASSESSMENTS
create policy assessments_select on public.assessments
for select to authenticated
using (public.is_member(org_id));

create policy assessments_insert on public.assessments
for insert to authenticated
with check (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

create policy assessments_update on public.assessments
for update to authenticated
using (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]))
with check (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

create policy assessments_delete on public.assessments
for delete to authenticated
using (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

-- MASTERY
create policy mastery_select on public.mastery
for select to authenticated
using (
  public.is_member(org_id) and
  (
    public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[])
    or student_id = auth.uid()
  )
);

create policy mastery_insert_student on public.mastery
for insert to authenticated
with check (public.is_member(org_id) and student_id = auth.uid());

create policy mastery_update_student on public.mastery
for update to authenticated
using (public.is_member(org_id) and student_id = auth.uid())
with check (public.is_member(org_id) and student_id = auth.uid());

-- SCORE DELTAS
create policy score_deltas_select on public.score_deltas
for select to authenticated
using (
  public.is_member(org_id) and
  (
    public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[])
    or student_id = auth.uid()
  )
);

create policy score_deltas_insert on public.score_deltas
for insert to authenticated
with check (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

-- CERTIFICATES
create policy certificates_select on public.certificates
for select to authenticated
using (
  public.is_member(org_id) and
  (
    public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[])
    or student_id = auth.uid()
  )
);

create policy certificates_insert on public.certificates
for insert to authenticated
with check (public.has_role(org_id, array['teacher','admin','district_admin']::public.app_role[]));

commit;
