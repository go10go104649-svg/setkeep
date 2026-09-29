#!/usr/bin/env python3
"""Generate reviewable SQL; never connects to or mutates a database.

Input: a Supabase db query JSON inventory snapshot (equipment + mapping).
Re-run for a new chain, review the CSV, then apply via a NEW migration.
"""
import argparse
import csv
import json
from pathlib import Path
from knowledge import CONCEPTS, RULES, concepts_for, key

ROOT = Path(__file__).resolve().parents[2]


def sql(value):
    return "'" + str(value).replace("'", "''") + "'"


def seed(inventory):
    known = {x['exerciseId'] for x in json.loads((ROOT / 'tool/exercise_forms/catalog.json').read_text())['exercises']}
    used = {x for c in CONCEPTS.values() for x in c['exercises']} | {r['exercise_id'] for r in RULES}
    if used - known:
        raise ValueError(f'Unknown exercise IDs: {used - known}')
    direct = {}
    for m in inventory['mapping']:
        direct.setdefault(m['equipment_id'], set()).add(m['exercise_id'])
    approvals, signatures = [], set()
    for e in inventory['equipment']:
        for c in concepts_for(e, direct.get(e['id'], ())):
            approvals.append(dict(equipment_id=e['id'], name=e['name'], category=e['category'],
                                  load_type=e['load_type'], canonical_id=c,
                                  source_needs_review=e['needs_review'],
                                  manufacturer=e['manufacturer'], model=e['model']))
            signatures.add((c, key(e['name']), e['category'], e['load_type'],
                            e['manufacturer'] or '', e['model'] or ''))
    out = []
    def insert(table, fields, rows):
        if not rows:
            return
        out.append(f'insert into public.{table} ({fields}) values\n' + ',\n'.join(rows) + '\non conflict do nothing;\n')
    insert('canonical_equipment', 'id,name,catalog_status,review_basis', [
        '(' + ','.join(map(sql, [id, c['name'], c['catalog_status'],
          '既存種目仕様・レビュー済み設備定義を照合。名称/カテゴリ/負荷方式/メーカー/型番の完全一致署名で所属を審査。'])) + ')'
        for id,c in CONCEPTS.items()])
    insert('canonical_equipment_exercise_mapping', 'canonical_id,exercise_id,rationale', [
        '(' + ','.join(map(sql, [id,x,'既存SETKEEP種目とFIT PLACEレビュー済み知識を照合。追加設備が必要な種目は複数設備条件へ分離。'])) + ')'
        for id,c in CONCEPTS.items() for x in c['exercises']])
    insert('canonical_equipment_rules', 'id,exercise_id,rationale', [
        '(' + ','.join(map(sql, [r['id'],r['exercise_id'],'既存複数設備ルールと種目仕様を再利用。必要能力をすべて実在設備で満たす場合のみ表示。'])) + ')'
        for r in RULES])
    insert('canonical_equipment_rule_items', 'rule_id,canonical_id', [
        f"({sql(r['id'])},{sql(c)})" for r in RULES for c in r['requires']])
    insert('canonical_equipment_matchers', 'canonical_id,name_key,category,load_type,manufacturer,model,required_direct_ids', [
        '(' + ','.join(map(sql,s)) + ',array[' + ','.join(map(sql, CONCEPTS[s[0]]['exercises'] if CONCEPTS[s[0]]['require_direct'] else [])) + ']::text[])'
        for s in sorted(signatures)])
    # Only IDs present in the reviewed snapshot are approved. Future imports are
    # suggestions in equipment_canonical_candidates until explicitly reviewed.
    if approvals:
        out.append('insert into public.equipment_canonical_mapping (equipment_id,canonical_id,matcher_id,review_basis)\n'
                   "select m.equipment_id,m.canonical_id,m.matcher_id,'2026-09-29 全チェーン設備定義レビュー'\n"
                   'from public.equipment_canonical_matches m join (values\n' + ',\n'.join(
                       f"({sql(a['equipment_id'])},{sql(a['canonical_id'])})" for a in approvals) +
                   ') reviewed(equipment_id,canonical_id) using(equipment_id,canonical_id)\non conflict do nothing;\n')
    return '\n'.join(out), approvals


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inventory', type=Path, required=True)
    p.add_argument('--sql', type=Path, required=True)
    p.add_argument('--review', type=Path, required=True)
    a=p.parse_args()
    data=json.loads(a.inventory.read_text())
    inventory=data['rows'][0]['inventory'] if 'rows' in data else data
    output, rows=seed(inventory)
    a.sql.write_text(output)
    with a.review.open('w') as f:
        writer=csv.DictWriter(f,lineterminator='\n',fieldnames=['equipment_id','name','category','load_type','canonical_id','source_needs_review','manufacturer','model'])
        writer.writeheader();writer.writerows(rows)
    print(f'{len(rows)} reviewed memberships; {len(set(r["equipment_id"] for r in rows))} equipment IDs')


if __name__ == '__main__':
    main()
