-- Read-only live smoke checks using the actual client-facing functions.
select jsonb_build_object(
 'counts',jsonb_build_object(
  'concepts',(select count(*) from public.canonical_equipment),
  'memberships',(select count(*) from public.equipment_canonical_memberships),
  'equipment',(select count(distinct equipment_id) from public.equipment_canonical_memberships),
  'canonical_singles',(select count(*) from public.canonical_equipment_exercise_mapping),
  'canonical_rules',(select count(*) from public.canonical_equipment_rules),
  'canonical_items',(select count(*) from public.canonical_equipment_rule_items)),
 'dumbbell_chains',(select jsonb_agg(to_jsonb(x)) from (
  select c.name,count(distinct e.id) equipment_count,
   min((select count(*) from public.equipment_resolved_exercise_mapping r
     join public.canonical_equipment_exercise_mapping k on k.exercise_id=r.exercise_id and k.canonical_id='dumbbell'
     where r.equipment_id=e.id)) basic_exercises
  from public.gym_chains c join public.gym_stores s on s.chain_id=c.id
  join public.gym_store_equipment g on g.store_id=s.id
  join public.equipment e on e.id=g.equipment_id
  join public.equipment_canonical_memberships m on m.equipment_id=e.id and m.canonical_id='dumbbell'
  group by c.id,c.name order by c.name) x),
 'mabashi_exercises',(select jsonb_agg(x.exercise_id order by x.exercise_id)
   from public.gym_store_exercise_ids('anytime-fitness:anytime_jp_1d4bdbb1432e') x),
 'mabashi_dumbbell',(select jsonb_agg(v) from jsonb_array_elements(
   public.gym_store_detail('anytime-fitness:anytime_jp_1d4bdbb1432e')->'equipment') v
   where v->'equipment'->>'id'='golds-gym:fp_eq_e2f3c2ba7ec7'),
 'mabashi_combinations',(select jsonb_agg(to_jsonb(v))
   from public.gym_store_exercise_evidence('anytime-fitness:anytime_jp_1d4bdbb1432e') v
   where exercise_id in ('flat_dumbbell_press','incline_dumbbell_press','dumbbell_fly')
   and rule_id like 'canonical:%')
) result;
