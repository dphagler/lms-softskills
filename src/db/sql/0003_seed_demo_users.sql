begin;

do $$
begin
  if exists (select 1 from public.schema_migrations where version = '0003_seed_demo_users') then
    raise notice 'Migration 0003_seed_demo_users already applied';
    return;
  end if;
end $$;

-- Replace these with the real auth user ids:
--   TEACHER_UID_HERE
--   STUDENT_UID_HERE

-- Memberships
insert into public.memberships (org_id, user_id, role)
values
('11111111-1111-1111-1111-111111111111', 'TEACHER_UID_HERE', 'teacher'),
('11111111-1111-1111-1111-111111111111', 'STUDENT_UID_HERE', 'student')
on conflict do nothing;

-- Class
insert into public.classes (org_id, name, created_by)
values
('11111111-1111-1111-1111-111111111111', 'Soft Skills 101', 'TEACHER_UID_HERE')
on conflict do nothing;

-- Enrollment
insert into public.enrollments (org_id, class_id, student_id)
select
  c.org_id,
  c.id,
  'STUDENT_UID_HERE'
from public.classes c
where c.org_id = '11111111-1111-1111-1111-111111111111'
  and c.name = 'Soft Skills 101'
on conflict do nothing;

-- Backfill created_by on seeded content/assessments now that teacher exists
update public.content_modules
set created_by = 'TEACHER_UID_HERE'
where org_id = '11111111-1111-1111-1111-111111111111'
  and created_by is null;

update public.assessments
set created_by = 'TEACHER_UID_HERE'
where org_id = '11111111-1111-1111-1111-111111111111'
  and created_by is null;

-- Re-tighten schema: make created_by required again
alter table public.content_modules alter column created_by set not null;
alter table public.assessments alter column created_by set not null;

insert into public.schema_migrations(version)
values ('0003_seed_demo_users');

commit;
