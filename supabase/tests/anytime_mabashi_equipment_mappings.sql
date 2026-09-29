-- All assertions must be true. Run with: supabase db query --linked --file <this file>
with expected(equipment_id, exercise_id) as (
  values
    ('anytime-fitness:anytime_eq_06bcb74c6e47', 'lying_leg_curl'),
    ('anytime-fitness:anytime_eq_268ccd441a23', 'seated_leg_curl'),
    ('anytime-fitness:anytime_eq_34611d6e1005', 'seated_row'),
    ('anytime-fitness:anytime_eq_575ef0dacdf6', 'shoulder_press'),
    ('anytime-fitness:anytime_eq_629a8e48c638', 'back_extension_machine'),
    ('anytime-fitness:anytime_eq_2fca080e6712', 'hip_adduction'),
    ('anytime-fitness:anytime_eq_2fca080e6712', 'hip_abduction'),
    ('anytime-fitness:anytime_eq_671a7f3c8d9c', 'pec_fly'),
    ('anytime-fitness:anytime_eq_671a7f3c8d9c', 'rear_delt'),
    ('anytime-fitness:anytime_eq_7ceb3119ab57', 'machine_lateral_raise'),
    ('anytime-fitness:anytime_eq_05eb63eb1b2c', 'treadmill'),
    ('anytime-fitness:anytime_eq_87295b2752ac', 'cross_trainer')
), observed as (
  select m.equipment_id, m.exercise_id
  from public.equipment_exercise_mapping m
  join expected x on x.equipment_id = m.equipment_id and x.exercise_id = m.exercise_id
), visible as (
  select e.exercise_id, e.equipment_ids[1] as equipment_id
  from public.gym_store_exercise_evidence('anytime-fitness:anytime_jp_1d4bdbb1432e') e
)
select
  (select count(*) from observed) = 12 as all_reviewed_mappings_exist,
  (select count(*) from visible v join expected x using (equipment_id, exercise_id)) = 12
    as all_reviewed_exercises_visible,
  not exists (
    select 1 from public.equipment_exercise_mapping
    where equipment_id in (
      'anytime-fitness:anytime_eq_821f39b9c595', -- 別区分のショルダープレス
      'anytime-fitness:anytime_eq_f90fabed6c45'  -- 種類未特定のプルダウン
    )
  ) as ambiguous_machines_remain_unmapped;
