begin;

do $$
begin
  if exists (select 1 from public.schema_migrations where version = '0002_seed_demo_org_content') then
    raise notice 'Migration 0002_seed_demo_org_content already applied';
    return;
  end if;
end $$;

-- Fixed demo org id so your app can refer to it easily while prototyping
insert into public.orgs (id, name)
values ('11111111-1111-1111-1111-111111111111', 'Demo District')
on conflict (id) do nothing;

-- Seed content modules (use a placeholder created_by for now)
-- We can't insert without created_by, so we create a "system" profile-less user mapping strategy:
-- Easiest remote-only: temporarily allow NULL created_by for seed inserts, then set it once teacher exists.
-- We'll do it in a safe, reversible way.

alter table public.content_modules alter column created_by drop not null;
alter table public.assessments alter column created_by drop not null;

insert into public.content_modules (org_id, title, description, youtube_url, created_by)
values
('11111111-1111-1111-1111-111111111111',
 'Active Listening',
 'Basics of active listening for teams',
 'https://www.youtube.com/watch?v=1Evwgu369Jw',
 null),
('11111111-1111-1111-1111-111111111111',
 'Conflict Resolution',
 'De-escalation frameworks and collaborative solutions',
 'https://www.youtube.com/watch?v=8dP8mP7zK6g',
 null)
on conflict do nothing;

-- Create one assessment per module
insert into public.assessments (org_id, module_id, title, rubric, created_by)
select
  cm.org_id,
  cm.id,
  cm.title || ' - Check',
  jsonb_build_object(
    'criteria', jsonb_build_array('clarity','empathy','specificity'),
    'scale', 5
  ),
  null
from public.content_modules cm
where cm.org_id = '11111111-1111-1111-1111-111111111111'
on conflict do nothing;

insert into public.schema_migrations(version)
values ('0002_seed_demo_org_content');

commit;
