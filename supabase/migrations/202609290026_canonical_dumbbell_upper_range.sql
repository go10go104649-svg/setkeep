-- Final coverage review: upper-bound-only ranges are still ordinary dumbbells.
-- Keep 025 immutable after its production application. No source/weight rewrite.
begin;
insert into public.canonical_equipment_matchers
 (canonical_id,name_key,category,load_type,manufacturer,model)
values ('dumbbell',public.canonical_equipment_key('ダンベル（〜50kg）'),'フリーウェイト','not_specified','',''),
 ('dumbbell',public.canonical_equipment_key('ダンベル（〜60kg）'),'フリーウェイト','not_specified','','')
on conflict do nothing;
insert into public.equipment_canonical_mapping(equipment_id,canonical_id,matcher_id,review_basis)
select equipment_id,canonical_id,matcher_id,'通常ダンベル。上限重量のみの表記で設備種別は明確。重量・原文は元データを維持。'
from public.equipment_canonical_matches
where canonical_id='dumbbell' and equipment_id in ('fit-easy:fp_eq_b9eb6340d4fc','fit-easy:fp_eq_9d8274bb322d')
on conflict do nothing;
commit;
