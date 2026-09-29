import unittest

from import_anytime_master import (
    CHAIN_ID,
    preflight_stores,
    reuse_map,
    sql_batches,
    sql_for,
    validate,
)


class AnytimeImportTest(unittest.TestCase):
    def setUp(self):
        self.store = dict(gym_id='anytime_jp_1', gym_chain='エニタイムフィットネス',
                          gym_name='試験店', prefecture='千葉県', municipality='松戸市',
                          address_raw='千葉県松戸市1', machine_data_status='published',
                          page_status='no_preopening_text', equipment_rows=1)
        self.equipment = dict(equipment_id='anytime_eq_1', normalized_name='パワーラック',
                              category='フリーウェイト')
        self.relation = dict(gym_id='anytime_jp_1', equipment_id='anytime_eq_1',
                             raw_name='パワーラック', quantity=None, available=True)
        self.tables = {'店舗': [self.store], '設備マスター': [self.equipment],
                       '店舗設備': [self.relation]}

    def test_validates_unknown_quantities_and_status(self):
        validate(self.tables, expected_stores=1, expected_prefectures=1)
        self.store['machine_data_status'] = 'not_collected'
        with self.assertRaisesRegex(ValueError, 'unpublished store'):
            validate(self.tables, expected_stores=1, expected_prefectures=1)
        self.store['machine_data_status'] = 'published'
        self.relation['quantity'] = 0
        with self.assertRaisesRegex(ValueError, 'quantity'):
            validate(self.tables, expected_stores=1, expected_prefectures=1)

    def test_reuse_requires_stable_reviewed_target(self):
        live = [dict(id='fit-place24:rack', name='パワーラック', load_type='not_specified',
                     needs_review=False)]
        approved = {'anytime_eq_1': dict(source_name='パワーラック',
                    target_id='fit-place24:rack', target_name='パワーラック',
                    target_load_type='not_specified')}
        self.assertEqual(reuse_map([self.equipment], live, approved),
                         {'anytime_eq_1': 'fit-place24:rack'})
        live[0]['needs_review'] = True
        with self.assertRaisesRegex(ValueError, 'requires review'):
            reuse_map([self.equipment], live, approved)

    def test_new_equipment_keeps_source_id_without_fuzzy_match(self):
        self.assertEqual(reuse_map([self.equipment], [], {}),
                         {'anytime_eq_1': f'{CHAIN_ID}:anytime_eq_1'})

    def test_store_identity_collision_stops_import(self):
        self.assertEqual(preflight_stores([self.store], []), (1, 0))
        existing = [dict(id='legacy:anytime', chain_id=CHAIN_ID,
                         source_id='other', name='試験店', prefecture='千葉県',
                         city='松戸市', address='千葉県松戸市1',
                         chain_name='エニタイムフィットネス')]
        with self.assertRaisesRegex(ValueError, 'manual ID review'):
            preflight_stores([self.store], existing)

    def test_sql_is_atomic_and_preserves_existing_store_active_flag(self):
        sql = sql_for({'gym_chains': [dict(id=CHAIN_ID, name='エニタイムフィットネス',
                                           search_aliases=['Anytime'])],
                       'gym_stores': [dict(id=f'{CHAIN_ID}:anytime_jp_1',
                                           chain_id=CHAIN_ID, source_id='anytime_jp_1',
                                           name='試験店', prefecture='千葉県', city='松戸市',
                                           address='千葉県松戸市1', official_url=None,
                                           equipment_status='not_collected', active=True,
                                           checked_at=None, source={})],
                       'equipment': [], 'gym_store_equipment': []})
        self.assertTrue(sql.startswith('begin;'))
        self.assertTrue(sql.endswith('commit;'))
        self.assertIn('on conflict (id) do update', sql)
        self.assertNotIn('active=excluded.active', sql)
        self.assertEqual([part[0] for part in sql_batches({
            'gym_chains': [dict(id=CHAIN_ID, name='エニタイムフィットネス',
                                search_aliases=['Anytime'])],
            'gym_stores': [], 'equipment': [], 'gym_store_equipment': [],
        })], ['gym_chains'])


if __name__ == '__main__':
    unittest.main()
