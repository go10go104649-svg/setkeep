-- Verify the completed chain/store seed migrations.
do $$
declare
  rec record;
begin
  for rec in
    select * from (values
      ('auns-gym',19),
      ('fastgym24',91),
      ('fit-easy',322),
      ('fit24',122),
      ('golds-gym',114),
      ('hyper-fit24',46),
      ('joyfit24',195),
      ('joyfit24-lite',1),
      ('smart-fit100',57),
      ('world-plus-gym',160)
    ) as expected(chain_id,min_count)
  loop
    if (select count(*) from public.gym_stores where chain_id=rec.chain_id) < rec.min_count then
      raise exception 'Missing seeded stores for %', rec.chain_id;
    end if;
  end loop;

  if (select count(*) from public.gym_stores where chain_id='fastgym24' and not active) < 3 then
    raise exception 'Closed FASTGYM24 stores were not retained as inactive';
  end if;
end $$;

select 'completed gym chain/store catalog assertions passed' as result;