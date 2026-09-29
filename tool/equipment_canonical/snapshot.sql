-- Reference data only; no user records or secrets. Before/after audit snapshot.
select jsonb_build_object(
 'equipment',(select jsonb_agg(to_jsonb(e)) from public.equipment e),
 'mapping',(select jsonb_agg(to_jsonb(m)) from public.equipment_exercise_mapping m),
 'rules',(select jsonb_agg(to_jsonb(r)) from public.exercise_equipment_rules r),
 'items',(select jsonb_agg(to_jsonb(i)) from public.exercise_equipment_rule_items i),
 'chains',(select jsonb_agg(to_jsonb(c)) from public.gym_chains c),
 'memberships',(select jsonb_agg(to_jsonb(m)) from public.equipment_canonical_memberships m),
 'resolved',(select jsonb_agg(to_jsonb(m)) from public.equipment_resolved_exercise_mapping m),
 'canonical_items',(select jsonb_agg(to_jsonb(i)) from public.canonical_equipment_rule_items i),
 'concepts',(select jsonb_agg(to_jsonb(c)) from public.canonical_equipment c),
 'usage',(select jsonb_agg(to_jsonb(u)) from (
  select s.chain_id,g.equipment_id,count(*) store_count,array_agg(distinct g.raw_name) raw_names
  from public.gym_store_equipment g join public.gym_stores s on s.id=g.store_id
  group by s.chain_id,g.equipment_id) u)
) inventory;
