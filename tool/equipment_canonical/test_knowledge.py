import unittest
from knowledge import CONCEPTS, RULES, concepts_for
from build_seed import seed


def equipment(name='ダンベル', category='フリーウェイト', load='not_specified', **extra):
    return dict(id='future-chain:unknown', name=name, normalized_name=name,
                category=category, load_type=load, needs_review=True,
                manufacturer=None, model=None, **extra)


class KnowledgeTest(unittest.TestCase):
    def test_dumbbell_variants_preserve_metadata(self):
        for name in ['ダンベル', 'ダンベル 1～40kg', 'IVANKOダンベル', 'ダンベル最大50kg', 'ダンベル（〜50kg）']:
            e=equipment(name);before=dict(e)
            self.assertEqual(concepts_for(e),['dumbbell'])
            self.assertEqual(e,before)

    def test_mixed_area_rack_and_loading_are_not_dumbbells(self):
        for name in ['ダンベルラック','ダンベルエリア','ダンベル＋ベンチ','ダンベル不明']:
            self.assertEqual(concepts_for(equipment(name)),[])
        self.assertEqual(concepts_for(equipment(category='有酸素')),[])
        self.assertEqual(concepts_for(equipment(load='plate_loaded_explicit')),[])

    def test_ambiguous_and_loading_sensitive(self):
        self.assertEqual(concepts_for(equipment('プルダウン', '筋トレ')),[])
        self.assertEqual(concepts_for(equipment('ショルダープレス','筋トレ')),[])
        self.assertEqual(concepts_for(equipment('ショルダープレス','筋トレ'),['shoulder_press']),['shoulder_press_stack'])
        self.assertEqual(concepts_for(equipment('ショルダープレス（プレートロード）','フリーウェイト','plate_loaded_explicit')),['plate_shoulder_press'])

    def test_bench_and_cable_capabilities_distinct(self):
        self.assertEqual(set(concepts_for(equipment('アジャスタブルベンチ'))),{'flat_bench','incline_bench'})
        self.assertEqual(concepts_for(equipment('フラットベンチ')),['flat_bench'])
        self.assertEqual(concepts_for(equipment('ケーブルマシン','筋トレ')),[])
        self.assertNotIn('face_pull',CONCEPTS['cable_crossover']['exercises'])

    def test_required_capabilities_not_implied(self):
        self.assertNotIn('flat_dumbbell_press',CONCEPTS['dumbbell']['exercises'])
        self.assertNotIn('dumbbell_shoulder_press',CONCEPTS['dumbbell']['exercises'])
        for rule in RULES:
            if rule['exercise_id']=='bench_press':
                self.assertEqual(set(rule['requires']),{'barbell','rack','flat_bench'})

    def test_unmatched_import_has_no_invalid_empty_insert(self):
        sql,rows=seed(dict(equipment=[equipment('不明な装置')],mapping=[]))
        self.assertEqual(rows,[])
        self.assertNotIn('insert into public.equipment_canonical_mapping',sql)
        self.assertNotIn('values\n\non conflict',sql)

    def test_seed_valid_catalog_and_no_legacy_mutation(self):
        sql,rows=seed(dict(equipment=[equipment()],mapping=[]))
        self.assertEqual(len(rows),1)
        self.assertNotIn('update public.equipment ',sql)
        self.assertNotIn('delete ',sql)
        self.assertNotIn('insert into public.equipment_exercise_mapping ',sql)
        self.assertIn('future-chain:unknown',sql)
        self.assertEqual(seed(dict(equipment=[equipment()],mapping=[]))[0],sql)


if __name__=='__main__': unittest.main()
