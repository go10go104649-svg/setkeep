"""Import the reviewed Anytime workbook into the shared gym tables.

The workbook stays in Drive. This command reads it without modification and uses
the authenticated Supabase CLI; no credentials or generated SQL enter Git.
"""

import argparse
from collections import Counter, defaultdict
from datetime import date, datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unicodedata

ROOT = Path(__file__).resolve().parents[2]
CHAIN_ID = 'anytime-fitness'
CHAIN_NAME = 'エニタイムフィットネス'
MASTER_NAME = 'SETKEEP_エニタイムフィットネス_全国店舗設備マスター_v1.0.xlsx'
SHEETS = ('店舗', '設備マスター', '店舗設備')


def normalized(value):
    return ''.join(unicodedata.normalize('NFKC', str(value or '')).lower().split())


def serialized(value):
    return value.isoformat() if isinstance(value, (date, datetime)) else value


def read_workbook(path):
    from openpyxl import load_workbook

    book = load_workbook(path, read_only=True, data_only=True)
    result = {}
    try:
        for sheet in SHEETS:
            rows = iter(book[sheet].values)
            header = list(next(rows))
            while header and header[-1] is None:
                header.pop()
            if any(not isinstance(x, str) or not x for x in header):
                raise ValueError(f'Invalid column in {sheet}')
            if len(header) != len(set(header)):
                raise ValueError(f'Duplicate column in {sheet}')
            result[sheet] = [
                {key: serialized(value) for key, value in zip(header, row)}
                for row in rows if any(value is not None for value in row[:len(header)])
            ]
    finally:
        book.close()
    return result


def validate(tables, expected_stores=1327, expected_prefectures=47):
    stores, equipment, relations = (tables[name] for name in SHEETS)
    if len(stores) != expected_stores:
        raise ValueError(f'Expected {expected_stores} stores, found {len(stores)}')
    if len({r.get('prefecture') for r in stores}) != expected_prefectures:
        raise ValueError(f'Expected {expected_prefectures} prefectures')
    for sheet, rows, key_fields in (
        ('店舗', stores, ('gym_id',)),
        ('設備マスター', equipment, ('equipment_id',)),
        ('店舗設備', relations, ('gym_id', 'equipment_id')),
    ):
        seen = set()
        for row in rows:
            key = tuple(row.get(field) for field in key_fields)
            if any(not isinstance(value, str) or not value.strip() for value in key):
                raise ValueError(f'Missing ID in {sheet}')
            if key in seen:
                raise ValueError(f'Duplicate {sheet} key: {key}')
            seen.add(key)
    if len({(r['gym_name'], r['prefecture'], r['municipality'], r['address_raw'])
            for r in stores}) != len(stores):
        raise ValueError('Duplicate store identity in workbook')
    if any(r.get('gym_chain') != CHAIN_NAME or not r.get('gym_name') or
           not r.get('prefecture') for r in stores):
        raise ValueError('Incomplete or wrong-chain store')
    if any(r.get('machine_data_status') not in
           ('published', 'not_published', 'not_collected') for r in stores):
        raise ValueError('Unexpected equipment status')
    if any(r.get('page_status') not in ('preopening_text', 'no_preopening_text')
           for r in stores):
        raise ValueError('Unexpected page status')
    if any(not r.get('normalized_name') or not r.get('category') for r in equipment):
        raise ValueError('Incomplete equipment master')
    store_by_id = {r['gym_id']: r for r in stores}
    equipment_ids = {r['equipment_id'] for r in equipment}
    per_store = Counter()
    for row in relations:
        if row['gym_id'] not in store_by_id or row['equipment_id'] not in equipment_ids:
            raise ValueError('Orphan store-equipment relation')
        if store_by_id[row['gym_id']]['machine_data_status'] != 'published':
            raise ValueError('Equipment assigned to unpublished store')
        if not row.get('raw_name') or row.get('available') is not True:
            raise ValueError('Invalid source equipment row')
        quantity = row.get('quantity')
        if quantity is not None and (isinstance(quantity, bool) or
              not isinstance(quantity, (int, float)) or quantity <= 0 or
              int(quantity) != quantity):
            raise ValueError('Invalid explicit quantity')
        per_store[row['gym_id']] += 1
    if any(per_store[r['gym_id']] != r['equipment_rows'] for r in stores):
        raise ValueError('Store equipment_rows disagrees with relation sheet')
    if any((r['machine_data_status'] == 'published') !=
           (per_store[r['gym_id']] > 0) for r in stores):
        raise ValueError('Published status disagrees with equipment rows')


def cli_query(sql):
    result = subprocess.run(
        ['supabase', 'db', 'query', '--linked', sql, '--output', 'json'],
        cwd=ROOT, capture_output=True, text=True,
    )
    if result.returncode:
        raise RuntimeError('Supabase read failed: ' + result.stderr[:500])
    return json.loads(result.stdout)['rows']


def live_reference():
    stores = cli_query('select s.id,s.chain_id,s.source_id,s.name,s.prefecture,'
                       's.city,s.address,c.name as chain_name from public.gym_stores s '
                       'join public.gym_chains c on c.id=s.chain_id')
    equipment = cli_query('select id,name,normalized_name,display_name,aliases,'
                          'load_type,needs_review from public.equipment')
    return stores, equipment


def preflight_stores(stores, live_stores):
    by_id = {row['id']: row for row in live_stores}
    by_source = defaultdict(list)
    by_identity = defaultdict(list)
    for row in live_stores:
        if row['chain_id'] == CHAIN_ID or 'エニタイム' in row['chain_name']:
            by_source[row['source_id']].append(row)
            by_identity[(normalized(row['name']), row['prefecture'],
                         normalized(row['address']))].append(row)
    added = updated = 0
    for row in stores:
        target = f"{CHAIN_ID}:{row['gym_id']}"
        identity = (normalized(row['gym_name']), row['prefecture'],
                    normalized(row.get('address_raw')))
        conflicts = {r['id'] for r in by_source[row['gym_id']] +
                     by_identity[identity] if r['id'] != target}
        if conflicts:
            raise ValueError(f'Existing Anytime store needs manual ID review: {target}')
        existing = by_id.get(target)
        if existing and (existing['chain_id'] != CHAIN_ID or
                         existing['source_id'] != row['gym_id']):
            raise ValueError(f'Store ID collision: {target}')
        updated += existing is not None
        added += existing is None
    return added, updated


def reuse_map(source_equipment, live_equipment, approved):
    by_source = {r['equipment_id']: r for r in source_equipment}
    by_target = {r['id']: r for r in live_equipment}
    if set(approved) - set(by_source):
        raise ValueError('Reuse map references absent workbook equipment')
    mapping = {}
    for source_id, entry in approved.items():
        source = by_source[source_id]
        target = by_target.get(entry['target_id'])
        if (target is None or source['normalized_name'] != entry['source_name'] or
            normalized(target['name']) != normalized(entry['target_name']) or
            target['load_type'] != entry['target_load_type'] or
            target['needs_review']):
            raise ValueError(f'Reuse map requires review: {source_id}')
        mapping[source_id] = target['id']
    for source_id in by_source:
        mapping.setdefault(source_id, f'{CHAIN_ID}:{source_id}')
    return mapping


def checked_at(value):
    if not value:
        return None
    return date.fromisoformat(str(value)).isoformat() + 'T00:00:00+09:00'


def prepare(tables, live_stores, live_equipment, approved,
            expected_stores=1327, master_name=MASTER_NAME):
    validate(tables, expected_stores=expected_stores)
    stores, equipment, relations = (tables[name] for name in SHEETS)
    added, updated = preflight_stores(stores, live_stores)
    mapping = reuse_map(equipment, live_equipment, approved)
    prepared = {
        'gym_chains': [{'id': CHAIN_ID, 'name': CHAIN_NAME,
                        'search_aliases': ['Anytime', 'Anytime Fitness']}],
        'gym_stores': [dict(
            id=f"{CHAIN_ID}:{r['gym_id']}", chain_id=CHAIN_ID,
            source_id=r['gym_id'], name=r['gym_name'],
            prefecture=r['prefecture'], city=r.get('municipality'),
            address=r.get('address_raw'), official_url=r.get('official_url'),
            equipment_status=r['machine_data_status'], active=True,
            checked_at=checked_at(r.get('equipment_checked_at')),
            source=dict(r, master_file=master_name)) for r in stores],
        'equipment': [dict(
            id=mapping[r['equipment_id']], name=r['normalized_name'],
            normalized_name=normalized(r['normalized_name']),
            category=r['category'],
            load_type='cardio' if r['category'] == '有酸素' else 'not_specified',
            needs_review=True, source=dict(r, master_file=master_name))
            for r in equipment if mapping[r['equipment_id']].startswith(f'{CHAIN_ID}:')],
        'gym_store_equipment': [dict(
            store_id=f"{CHAIN_ID}:{r['gym_id']}",
            equipment_id=mapping[r['equipment_id']],
            quantity=int(r['quantity']) if r.get('quantity') is not None else None,
            available=True, raw_name=r['raw_name'],
            source_url=r.get('source_url'), checked_at=checked_at(r.get('checked_at')),
            source_kind='official', source=dict(r, master_file=master_name))
            for r in relations],
    }
    pairs = [(r['store_id'], r['equipment_id'])
             for r in prepared['gym_store_equipment']]
    if len(pairs) != len(set(pairs)):
        raise ValueError('Equipment reuse would collapse distinct source rows')
    report = {
        'source_stores': len(stores), 'source_equipment': len(equipment),
        'source_relations': len(relations),
        'store_insert': added, 'store_update': updated,
        'reuse_source_equipment_ids': len(approved),
        'reuse_distinct_existing_ids': len(set(mapping.values())) - len(prepared['equipment']),
        'new_equipment_ids': len(prepared['equipment']),
        'equipment_stores': len({r['gym_id'] for r in relations}),
        'equipment_status': dict(Counter(r['machine_data_status'] for r in stores)),
        'preopening_stores': sum(r['page_status'] == 'preopening_text' for r in stores),
        'null_quantities': sum(r['quantity'] is None for r in relations),
    }
    return prepared, report


def sql_for(prepared):
    # One transaction protects every batch's rows and FK relationships.
    statements = ['begin;']
    tables = (
        ('gym_chains', 'id text,name text,search_aliases text[]',
         'name=excluded.name,search_aliases=excluded.search_aliases'),
        ('gym_stores', 'id text,chain_id text,source_id text,name text,'
         'prefecture text,city text,address text,official_url text,'
         'equipment_status text,active boolean,checked_at timestamptz,source jsonb',
         'name=excluded.name,prefecture=excluded.prefecture,city=excluded.city,'
         'address=excluded.address,official_url=excluded.official_url,'
         "equipment_status=case when excluded.equipment_status='not_collected' "
         "and gym_stores.equipment_status in ('published','partial') "
         'then gym_stores.equipment_status else excluded.equipment_status end,'
         'checked_at=coalesce(excluded.checked_at,gym_stores.checked_at),'
         'source=excluded.source,updated_at=now()'),
        ('equipment', 'id text,name text,normalized_name text,category text,'
         'load_type text,needs_review boolean,source jsonb', None),
        ('gym_store_equipment', 'store_id text,equipment_id text,quantity integer,'
         'available boolean,raw_name text,source_url text,checked_at timestamptz,'
         'source_kind text,source jsonb',
         'quantity=excluded.quantity,available=excluded.available,'
         'raw_name=excluded.raw_name,source_url=excluded.source_url,'
         'checked_at=excluded.checked_at,source_kind=excluded.source_kind,'
         'source=excluded.source'),
    )
    for table, definitions, updates in tables:
        rows = prepared.get(table, [])
        if not rows:
            continue
        columns = list(rows[0])
        data = json.dumps(rows, ensure_ascii=False, separators=(',', ':')).replace("'", "''")
        key = {'gym_chains': 'id', 'gym_stores': 'id', 'equipment': 'id',
               'gym_store_equipment': 'store_id,equipment_id'}[table]
        action = f'do update set {updates}' if updates else 'do nothing'
        statements.append(
            f"insert into public.{table} ({','.join(columns)}) "
            f"select {','.join(columns)} from jsonb_to_recordset('{data}'::jsonb) "
            f'as r({definitions}) on conflict ({key}) {action};')
    statements.append('commit;')
    return '\n'.join(statements)


def sql_batches(prepared, max_rows=200, max_bytes=500000):
    """Respect the Management API request limit; batches are idempotent.

    Chain, stores, new equipment, then relations must be submitted in that order.
    A failed run can be restarted without duplicate rows.
    """
    for table, rows in prepared.items():
        start = 0
        while start < len(rows):
            end = min(start + max_rows, len(rows))
            while end > start:
                statement = sql_for({table: rows[start:end]})
                if len(statement.encode()) <= max_bytes:
                    break
                end = start + (end - start) // 2
            if end <= start:
                raise ValueError(f'One {table} row exceeds the SQL request limit')
            yield table, start, end, statement
            start = end


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--reuse-map', type=Path,
                        default=ROOT / 'tool/gym_import/anytime_equipment_reuse.json')
    parser.add_argument('--expected-stores', type=int, default=1327)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    before = hashlib.sha256(args.input.read_bytes()).hexdigest()
    tables = read_workbook(args.input)
    approved = json.loads(args.reuse_map.read_text())
    live_stores, live_equipment = live_reference()
    prepared, report = prepare(tables, live_stores, live_equipment, approved,
                               expected_stores=args.expected_stores,
                               master_name=args.input.name)
    report['master_sha256'] = before
    if args.apply:
        with tempfile.TemporaryDirectory(prefix='setkeep-anytime-') as directory:
            sql_path = Path(directory) / 'import.sql'
            for table, start, end, statement in sql_batches(prepared):
                sql_path.write_text(statement)
                result = subprocess.run(
                    ['supabase', 'db', 'query', '--linked', '--file', str(sql_path),
                     '--output', 'json'], cwd=ROOT, capture_output=True, text=True,
                )
                if result.returncode:
                    raise RuntimeError(f'Supabase import failed at {table} '
                                       f'rows {start}:{end}: ' + result.stderr[:500])
                print(f'Applied {table} rows {start}:{end}', file=sys.stderr)
        report['applied'] = True
    if hashlib.sha256(args.input.read_bytes()).hexdigest() != before:
        raise ValueError('Workbook changed during import')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
