begin;
do $$ begin if exists (
    select 1
    from public.schema_migrations
    where version = '0004_indexes'
) then raise notice 'Migration 0004_indexes already applied';
return;
end if;
end $$;
-- Fast membership lookup by user
create index if not exists memberships_user_id_idx on public.memberships (user_id);
-- Fast lookups for tenant filtering
create index if not exists classes_org_id_idx on public.classes (org_id);
create index if not exists content_modules_org_id_idx on public.content_modules (org_id);
create index if not exists assessments_org_id_idx on public.assessments (org_id);
-- Teacher dashboard likely queries deltas by org + assessment + student + time
create index if not exists score_deltas_org_created_idx on public.score_deltas (org_id, created_at desc);
create index if not exists score_deltas_assessment_student_idx on public.score_deltas (assessment_id, student_id);
insert into public.schema_migrations(version)
values ('0004_indexes');
commit;