#!/usr/bin/env python3
"""Export repeatable coverage / unresolved CSVs from reference-data snapshots.
Counts are distinct equipment IDs installed per chain, not store-equipment rows.
Direct and multi columns overlap. Source needs_review is never rewritten.
"""
import argparse
import csv
import json
from pathlib import Path
from knowledge import concepts_for


def unpack(path):
    data = json.loads(path.read_text())
    return data['rows'][0]['inventory'] if 'rows' in data else data


def audit(data):
    eq = {e['id']: e for e in data['equipment']}
    direct = {}
    for row in data['mapping']:
        direct.setdefault(row['equipment_id'], set()).add(row['exercise_id'])
    resolved = {m['equipment_id'] for m in data.get('resolved', data['mapping'])}
    legacy = {m['equipment_id'] for m in data['items']}
    rule_concepts = {m['canonical_id'] for m in data.get('canonical_items', [])}
    memberships = {}
    for m in data.get('memberships', []):
        memberships.setdefault(m['equipment_id'], set()).add(m['canonical_id'])
    multi = legacy | {id for id, cs in memberships.items() if cs & rule_concepts}
    absent = {c['id'] for c in data.get('concepts', []) if c['catalog_status']=='exercise_not_in_catalog'}
    coverage, review = [], []
    for chain in data['chains']:
        usage = [u for u in data['usage'] if u['chain_id']==chain['id']]
        ids = {u['equipment_id'] for u in usage}
        no_mapping = ids - resolved - multi
        safe = {id for id in ids if concepts_for(eq[id], direct.get(id, ()))}
        coverage.append(dict(chain=chain['name'], equipment=len(ids), direct=len(ids & direct.keys()),
          legacy_multi=len(ids & legacy), canonical=len(ids & memberships.keys()),
          resolved_single=len(ids & resolved), resolved_multi=len(ids & multi),
          no_mapping=len(no_mapping), source_needs_review=sum(eq[id]['needs_review'] for id in ids),
          safe_canonical=len(safe), ambiguous_unmapped=sum(eq[id]['needs_review'] and id not in safe for id in no_mapping)))
        for u in usage:
            id=u['equipment_id']; e=eq[id]
            if id in resolved: continue
            reason = ('requires_other_equipment' if id in multi else
                      'exercise_not_in_catalog' if memberships.get(id,set()) & absent else
                      'equipment_ambiguous' if e['needs_review'] else 'equipment_mapping_missing')
            review.append(dict(chain=chain['name'],equipment_id=id,name=e['name'],category=e['category'],
              load_type=e['load_type'],manufacturer=e['manufacturer'],model=e['model'],
              store_count=u['store_count'],reason=reason,source_needs_review=e['needs_review'],
              raw_names=' | '.join(x or '' for x in u['raw_names'])))
    # Include unattached master rows too; never invent a chain from an ID prefix.
    installed = {u['equipment_id'] for u in data['usage']}
    for id in sorted(set(eq) - installed - resolved):
        e = eq[id]
        reason = ('requires_other_equipment' if id in multi else
                  'exercise_not_in_catalog' if memberships.get(id,set()) & absent else
                  'equipment_ambiguous' if e['needs_review'] else 'equipment_mapping_missing')
        review.append(dict(chain='店舗への設置なし',equipment_id=id,name=e['name'],category=e['category'],
          load_type=e['load_type'],manufacturer=e['manufacturer'],model=e['model'],
          store_count=0,reason=reason,source_needs_review=e['needs_review'],raw_names=''))
    return coverage, review


def write(path, rows):
    if not rows:
        path.write_text('')
        return
    with path.open('w') as f:
        w=csv.DictWriter(f, lineterminator='\n', fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--snapshot',type=Path,required=True)
    p.add_argument('--usage',type=Path,help='Optional legacy before-snapshot usage JSON')
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();data=unpack(a.snapshot)
    if a.usage: data['usage']=json.loads(a.usage.read_text())['rows'][0]['usage']
    coverage,review=audit(data);a.output.mkdir(parents=True,exist_ok=True)
    write(a.output/'coverage.csv',coverage);write(a.output/'unresolved.csv',review)
    print(json.dumps(coverage,ensure_ascii=False,indent=2))


if __name__=='__main__': main()
