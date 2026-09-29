-- 松戸馬橋店の公式マシン一覧で種別まで確認できる設備だけを紐付ける。
-- https://www.anytimefitness.co.jp/matsudomabashi/facility/
-- 同じ名称でもマシン／フリーウェイト区分が異なる設備は混同しない。
with reviewed(equipment_id, equipment_name, category, exercise_id) as (
  values
    ('anytime-fitness:anytime_eq_06bcb74c6e47', 'ライイング・レッグカール', 'マシン', 'lying_leg_curl'),
    ('anytime-fitness:anytime_eq_268ccd441a23', 'シーテッド・レッグカール', 'マシン', 'seated_leg_curl'),
    ('anytime-fitness:anytime_eq_34611d6e1005', 'シーテッド・ロー', 'マシン', 'seated_row'),
    ('anytime-fitness:anytime_eq_575ef0dacdf6', 'ショルダープレス', 'マシン', 'shoulder_press'),
    ('anytime-fitness:anytime_eq_629a8e48c638', 'バックエクステンション', 'マシン', 'back_extension_machine'),
    ('anytime-fitness:anytime_eq_2fca080e6712', 'ヒップアダクション/アブダクション', 'マシン', 'hip_adduction'),
    ('anytime-fitness:anytime_eq_2fca080e6712', 'ヒップアダクション/アブダクション', 'マシン', 'hip_abduction'),
    ('anytime-fitness:anytime_eq_671a7f3c8d9c', 'フライ/リアデルト', 'マシン', 'pec_fly'),
    ('anytime-fitness:anytime_eq_671a7f3c8d9c', 'フライ/リアデルト', 'マシン', 'rear_delt'),
    ('anytime-fitness:anytime_eq_7ceb3119ab57', 'ラテラルレイズ', 'マシン', 'machine_lateral_raise'),
    ('anytime-fitness:anytime_eq_05eb63eb1b2c', 'トレッドミル', '有酸素', 'treadmill'),
    ('anytime-fitness:anytime_eq_87295b2752ac', 'クロストレーナー', '有酸素', 'cross_trainer')
)
insert into public.equipment_exercise_mapping (equipment_id, exercise_id, rationale)
select r.equipment_id, r.exercise_id,
  'エニタイム松戸馬橋店の公式設備一覧に掲載。設備名と区分を照合し、同一器具・同一動作の既存種目に紐付け。'
from reviewed r
join public.equipment e on e.id = r.equipment_id
  and e.name = r.equipment_name and e.category = r.category
where exists (
  select 1 from public.gym_store_equipment g
  where g.store_id = 'anytime-fitness:anytime_jp_1d4bdbb1432e'
    and g.equipment_id = r.equipment_id
)
on conflict (equipment_id, exercise_id) do nothing;
