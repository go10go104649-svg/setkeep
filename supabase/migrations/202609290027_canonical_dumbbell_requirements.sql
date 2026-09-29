-- Preserve legacy mapping rows, but do not let a broad historical dumbbell
-- direct mapping bypass the explicit bench requirements in the current catalog.
begin;
create or replace view public.equipment_resolved_exercise_mapping with (security_invoker = true) as
 select d.equipment_id,d.exercise_id from public.equipment_exercise_mapping d
 where not exists (
   select 1 from public.equipment_canonical_memberships m
   join public.canonical_equipment_rule_items i on i.canonical_id=m.canonical_id
   join public.canonical_equipment_rules r on r.id=i.rule_id and r.exercise_id=d.exercise_id
   where m.equipment_id=d.equipment_id and m.canonical_id='dumbbell'
 )
 union
 select m.equipment_id,x.exercise_id from public.equipment_canonical_memberships m
 join public.canonical_equipment_exercise_mapping x on x.canonical_id=m.canonical_id;
commit;
