-- Verify the completed chain/store/equipment seed migrations.
do $$
declare
  rec record;
begin
  for rec in
    select * from (values
      ('auns-gym',19,90,79),
      ('fastgym24',91,1954,336),
      ('fit-easy',322,31,336),
      ('fit24',122,683,92),
      ('golds-gym',114,250,336),
      ('hyper-fit24',46,923,142),
      ('joyfit24',195,1116,336),
      ('joyfit24-lite',1,0,0),
      ('smart-fit100',57,73,56),
      ('world-plus-gym',160,385,336)
    ) as expected(chain_id,min_store_count,min_relation_count,min_mapping_count)
  loop
    if (select count(*) from public.gym_stores where chain_id=rec.chain_id) < rec.min_store_count then
      raise exception 'Missing seeded stores for %', rec.chain_id;
    end if;
    if (select count(*) from public.gym_store_equipment g
        join public.gym_stores s on s.id=g.store_id
        where s.chain_id=rec.chain_id) < rec.min_relation_count then
      raise exception 'Missing store-equipment rows for %', rec.chain_id;
    end if;
    if (select count(*) from public.equipment_exercise_mapping m
        join public.equipment e on e.id=m.equipment_id
        where e.id like rec.chain_id || ':%') < rec.min_mapping_count then
      raise exception 'Missing direct exercise mappings for %', rec.chain_id;
    end if;
  end loop;

  if (select count(*) from public.gym_stores where chain_id='fastgym24' and not active) < 3 then
    raise exception 'Closed FASTGYM24 stores were not retained as inactive';
  end if;

  if not exists (
    select 1 from public.exercise_equipment_rules
    where id like 'fastgym24:%'
  ) then
    raise exception 'FASTGYM24 composite equipment rules were not seeded';
  end if;

  if not exists (
    select 1 from public.exercise_equipment_rules
    where id like 'joyfit24:%'
  ) then
    raise exception 'JOYFIT24 composite equipment rules were not seeded';
  end if;
end $$;

select 'completed gym chain/store/equipment catalog assertions passed' as result;
