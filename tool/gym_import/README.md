# Gym reference data import

All chains share `gym_chains`, `gym_stores`, `equipment`, `gym_store_equipment`
and the many-to-many `equipment_exercise_mapping`. A namespace plus the source's
stable ID identifies each imported row; similar names are never merged automatically.
`user_gym_stores` and `gym_equipment_reports` are private owner-only RLS tables.
Unauthenticated device registrations stay in local preferences; they are not public
profiles, are not silently transferred to a signed-in account, and are not included
in the workout backup. Workout records/drafts retain an optional `gymStoreId` in
addition to their existing `gymName`.

## Import

Apply `supabase/migrations/202609230001_gym_equipment.sql` through the project's
migration workflow. The current linked project has this migration applied and
recorded. With Python + openpyxl and an authenticated, linked Supabase CLI:

```sh
python3 tool/gym_import/import_master.py --input /path/to/master.xlsx \
  --chain-id fit-place24 --chain-name 'FIT PLACE24' \
  --mapping tool/gym_import/fitplace_mappings.json \
  --requirements tool/gym_import/fitplace_requirement_rules.json
# Review counts and validation, then use the same command with --apply.
```

The workbook is opened read-only, hashed before/after, never saved. SQL is created
in a temporary directory and removed. No key, workbook or generated payload belongs
in Git. The importer validates before executing one transaction. Repeating an
import upserts by stable keys; it does not delete missing stores, equipment or
mappings. Closures/removals must be reviewed and marked `active=false` /
`available=false` by an administrator, not inferred from an absent source row.
Importing the same source again reapplies its explicit availability information.
Manufacturer, model, station and quantity stay null when absent. Raw source
metadata, raw equipment names, source URLs, dates and review notes are retained.
NFKC/whitespace normalization is only an additional equipment search name; it is
not an identity or fuzzy merge rule.

Mapping entries require an exact source ID, expected name, load type, reviewed
source and valid selectable catalog exercise IDs. Unknown/ambiguous equipment is
visible with “対応種目は現在準備中です”. Mappings can be added server-side without an
app update when the exercise ID already exists in the app's catalog. Older clients
ignore unknown exercise IDs safely. Another chain can use the same tables and UI;
normalize its source to the documented workbook columns or adapt the reader only,
then supply its own chain ID and reviewed mapping file.

## Anytime Fitness national master (2026-09-29)

The authoritative workbook is kept in Google Drive at
`SETKEEP/data/import/SETKEEP_エニタイムフィットネス_全国店舗設備マスター_v1.0.xlsx`.
It is not committed. Import with its local synchronized path:

```sh
python3 tool/gym_import/import_anytime_master.py --input /path/to/SETKEEP_エニタイムフィットネス_全国店舗設備マスター_v1.0.xlsx
# Review the dry-run counts, then repeat with --apply.
```

The importer validates 1,327 unique stores in 47 prefectures and the exact
store/equipment relationships. It checks the live database for legacy Anytime
IDs or matching store identities and stops for manual review rather than
creating a duplicate. A checked-in, name-verified reuse map links only clear
source equipment to existing shared equipment IDs; other source equipment gets
a stable `anytime-fitness:` ID and `needs_review=true`, without guessed exercise
mappings. The import is divided into idempotent batches for the Supabase query
API; rerunning it updates existing rows and does not delete missing rows. Do
not infer equipment absence from `not_collected` or `not_published`. Unknown
quantity remains null. `page_status=preopening_text` is kept in store source
metadata; those stores remain searchable but cannot be registered as a current
training place. Store and equipment contents from this workbook are never used
to update another chain.

## Current source audit (2026-09-23)

244 stores, 219 equipment IDs, 1,582 store-equipment pairs, no duplicate keys or
orphan references. Equipment coverage: 35 published, 3 not published, 206 not
collected. All 244 station fields and all 219 manufacturer/model fields are absent.
368 quantities are explicit; 1,214 remain null. 60 equipment IDs have 106 reviewed
exercise mappings; 159 are unmapped. This is partial equipment coverage, not a claim
that every listed store has a complete equipment inventory.

## Mapping updates (2026-09-24)

Direct equipment mappings cover 205 of 219 equipment IDs with 349
equipment-exercise rows. In addition, 163 multi-equipment rules / 326 rule items
model combinations such as rack + bench and dumbbell + adjustable bench.

Generic racks are direct sources for barbell movements that do not require a bench.
Bench-press variants are only considered available when a compatible rack and bench
are both present. Dumbbell press/fly variants likewise require dumbbells plus the
appropriate bench angle. Generic curl benches no longer imply preacher curls by
themselves; they require dumbbells or a rack/barbell source.

14 equipment IDs still have no direct mapping. Explicit manual review can resolve a source row
that is still marked `needs_review` by setting `reviewed_source_override: true`
on that exact mapping entry; the importer rejects implicit overrides and rejects
using the flag on clean source rows. Some are intentionally represented
only through combination rules (generic benches), while others remain source rows
marked `needs_review` or are too ambiguous to infer safely. The store filter uses
the server-side `gym_store_exercise_ids` function to union direct mappings with
satisfied combination rules.

Apply migrations through
`202609240006_fitplace_spine_bench_mapping.sql` (or rerun the importer with both
`--mapping` and `--requirements`) before treating these counts as live
linked-project data.
## Search and reports

Public search is server-paged (30). It matches **store/chain names only**,
including explicit chain aliases and width/spacing normalization, ranked exact,
prefix, then substring. City is displayed for disambiguation, not searched.
The optional chain filter uses the same generic endpoint for every chain.

Migration 202609240008 is additive. `gym_store_detail` returns one store's metadata,
equipment and the same satisfied evidence used by `gym_store_exercise_ids`.
No mapping/rule IDs were replaced. Public equipment snapshots are cached locally
for 24 hours; stale snapshots render immediately while a refresh runs. Failed
refreshes retain the last snapshot; Pull-to-Refresh forces a fetch. Reports and
private registrations are not included in this cache. Unknown confirmation dates,
manufacturers, models and quantities remain unknown. Import time is not an
equipment confirmation date.

Reports require login and never mutate the master. Statuses are pending,
reviewing, resolved/rejected (legacy approved remains readable as awaiting
resolution). A per-user advisory lock coalesces identical open reports without
creating another row. Resolved/rejected reports allow a later new report; the
five-new-reports-per-five-minutes rate cap remains. RLS and column grants prevent
self-approval and cross-user access.

Administrators manage availability using `available` and, only for a known
quantity, `unavailable_quantity`. The evidence RPC excludes wholly unavailable
equipment but accepts remaining working units. To remove equipment from a store,
delete only its `gym_store_equipment` relation, never the shared equipment master.
Insert/update/delete snapshots are recorded in private `gym_equipment_changes`.
Source priority is admin > official > confirmed_report > unconfirmed_report;
lower-priority updates cannot replace a reviewed row. Imports explicitly identify
their source as official. Unknown or missing workbook rows do not imply removal.
Display names/aliases are separate from original names/categories and stable IDs.
No weekly crawler or equipment-photo feature is installed.

Utilization places use the existing registration repository plus an account-scoped
local default. Preferred store comes first, then home, then other stores; home is
never duplicated or removable. A workout-specific choice does not change the
default. Store removal does not touch workout history. Legacy names without IDs
are preserved, never matched heuristically to a store.

## Verification

```sh
python3 -m unittest discover -s tool/gym_import -p 'test_*.py'
supabase db query --linked --file supabase/tests/gym_equipment.sql
supabase db query --linked --file supabase/tests/gym_multi_equipment_rules.sql
supabase db query --linked --file supabase/tests/gym_places_details.sql
flutter test --no-pub test/gym_integration_test.dart test/fitplace_catalog_test.dart test/workout_gym_test.dart
flutter analyze --no-pub
```

DB tests use temporary fixtures inside a rolled-back transaction. Native smoke QA
is `integration_test/gym_store_flow_test.dart` with the existing screenshot driver
and local ignored `supabase.json` build configuration. It reads real public master
data; it does not create real accounts, post reports or modify the master.
