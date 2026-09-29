"""Reviewed equipment capabilities. No chain IDs or fuzzy matching.

Canonical IDs are capabilities: an adjustable bench can supply flat AND incline,
but a rack never supplies a barbell. Existing direct mappings remain untouched.
Sources: catalog.json; reviewed FIT PLACE mappings / multi-equipment rules;
202609290020's reviewed machine mappings. Only exact listed variants are reused.
"""
import re
import unicodedata


def key(value):
    return re.sub(r'[\s・]', '', unicodedata.normalize('NFKC', value or '').lower())


CONCEPTS = {}


def concept(id, name, aliases, categories, exercises=(), loads=('not_specified',),
            require_direct=False, status='supported'):
    CONCEPTS[id] = dict(name=name, aliases={key(a) for a in aliases},
                        categories=set(categories), exercises=list(exercises),
                        loads=set(loads), require_direct=require_direct,
                        catalog_status=status)


FREE = ['フリーウェイト']
MACHINE = ['筋トレ', 'マシン']
CABLE = [*MACHINE, 'フリーウェイト', 'ファンクショナル']
# Conservative subset of FIT PLACE's dumbbell knowledge. Seated/supported forms
# in the current catalog are below as bench combinations, never inherited alone.
concept('dumbbell', 'ダンベル', ['ダンベル', 'ダンベル()', 'ダンベル(1~)', 'カラーダンベル 1kg2kg', '可変式ダンベル', 'IVANKOダンベル',
        'QuickDraw アジャスタブルダンベル'], FREE + ['ファンクショナル'],
        ['dumbbell_curl', 'hammer_curl', 'lateral_raise', 'front_raise',
         'goblet_squat', 'rear_raise', 'dumbbell_shrug', 'zottman_curl',
         'lunge', 'reverse_lunge', 'walking_lunge', 'split_squat',
         'single_leg_rdl', 'weighted_crunch', 'russian_twist'])
concept('barbell', 'バーベル', ['バーベル', 'オリンピックバーベル'], FREE,
        ['bent_over_row', 'pendlay_row', 'deadlift', 'romanian_deadlift',
         'sumo_deadlift', 'barbell_curl', 'upright_row', 'barbell_shrug'])
concept('ez_bar', 'EZバー', ['EZバー', 'EZバー×2', 'IVANKOオリンピックアームカールバー'],
        FREE + ['ファンクショナル'])
concept('rack', 'スクワット対応ラック', ['パワーラック', 'ハーフラック', 'スクワットラック',
        'パワーラック()', 'ハーフラック()', 'パワーラック×2', 'ハーフラック×2',
        'HDエリートiDパワーラック', 'メガパワーラック'], FREE)
ADJUSTABLE = ['アジャスタブルベンチ', 'マルチアジャスタブルベンチ', 'アジャスタブルフラット/インクラインベンチ',
              'フラットインクラインベンチ', 'TORQUEフラットインクラインベンチ',
              'アジャスタブルベンチ()', 'アジャスタブルベンチ7台',
              'アジャスタブルベンチ×2', 'アジャスタブルベンチ×3',
              'アジャスタブルベンチ（デクライン可能）']
DECLINE = ['アジャスタブルマルチデクラインベンチ', 'マルチアジャスタブルデクラインベンチ',
           'デクラインフラットベンチ', 'アジャスタブルベンチ（デクライン可能）']
concept('flat_bench', 'フラット対応ベンチ', ['フラットベンチ', 'フラットベンチ()', *ADJUSTABLE, *DECLINE], FREE)
concept('incline_bench', 'インクライン対応ベンチ', ['インクラインベンチ', 'アジャスタブルインクラインベンチ', *ADJUSTABLE], FREE)
concept('decline_bench', 'デクライン対応ベンチ', [*DECLINE, 'アジャスタブルデクラインベンチ'], FREE)
concept('preacher_bench', 'プリーチャーベンチ', ['プリチャーカールベンチ', 'プリーチャーカールベンチ',
        'プリチャーカール台', 'プリーチャーカール台', 'プリーチャー台',
        'アームカールラック', 'アジャスタブル アームカールラック', 'カールベンチ'], FREE)
concept('back_extension_bench', 'バックエクステンションベンチ', ['バックエクステンションベンチ',
        'ローワーバックベンチ', '背筋台', '45°バックエクステンション'], FREE + MACHINE,
        ['back_extension'])
concept('smith', 'スミスマシン', ['スミスマシン', 'スミスマシン()', 'スミスマシン（垂直）',
        'スミスマシン(傾斜)', 'スミスマシン(斜め)', 'スミスマシン（垂直タイプ）',
        'バーティカルスミス', 'バーティカルスミスマシン', '垂直スミスマシン',
        'ヴァーティカルスミスマシン', 'ヴァーティカルスミスマシン（垂直タイプ）'], FREE,
        ['smith_squat'])
concept('dip_station', 'ディップス台', ['ディップス台', 'ディップススタンド', 'ディップスタンド',
        'ディップスバー', 'チン/ディップ', 'チン/ディップ/レッグレイズ'], FREE + MACHINE + ['ファンクショナル'], ['dips'])
concept('pullup_station', 'チンニング設備', ['チンニングバー', 'チンニングバー×2', 'チンニングラック',
        'チン/ディップ', 'チン/ディップ/レッグレイズ'], FREE + MACHINE + ['ファンクショナル'], ['chin_up'])
concept('dual_pulley', 'デュアルアジャスタブルプーリー', ['デュアルアジャスタブルプーリー',
        'デュアル・アジャスタブル・プーリー', 'アジャスタブルデュアルプーリー',
        'デュアルアジャスタブルケーブル', 'デュアルアジャスタブルプーリー(ケーブルマシン)',
        'ハンマーデュアルアジャスタブルプーリー', 'ファンクショナルトレーナー',
        'ファンクショナルトレーナー（ケーブルマシン）'], CABLE,
        ['cable_fly', 'cable_curl', 'rope_pushdown', 'straight_bar_pushdown',
         'face_pull', 'cable_lateral_raise'], loads=['not_specified', 'cable_named'])
# Fixed-height crossover does not inherit adjustable-pulley movements.
concept('cable_crossover', 'ケーブルクロスオーバー', ['ケーブルクロスオーバー', 'ケーブルクロス'], CABLE,
        ['cable_fly', 'single_arm_cable_fly'], loads=['not_specified', 'cable_named'])

for id, name, aliases, exercises in [
    ('seated_leg_curl', 'シーテッドレッグカール', ['シーテッドレッグカール', 'シーテッド・レッグカール', 'シーテッドレッグカール ROM'], ['seated_leg_curl']),
    ('lying_leg_curl', 'ライイングレッグカール', ['ライイングレッグカール', 'ライイング・レッグカール', 'プローンレッグカール', 'プロ―ンレッグカール'], ['lying_leg_curl']),
    ('standing_leg_curl', 'スタンディングレッグカール', ['スタンディングレッグカール'], ['standing_leg_curl']),
    ('leg_extension', 'レッグエクステンション', ['レッグエクステンション', 'シーテッドレッグエクステンション', 'レッグエクステンション ROM', 'レッグエクステンション（デュアルスタック）'], ['leg_extension']),
    ('leg_press', 'レッグプレス', ['レッグプレス', 'シーテッドレッグプレス', '45°レッグプレス', '45度レッグプレス', 'アングルドレッグプレス', 'リニアレッグプレス'], ['leg_press']),
    ('hip_adduction', 'ヒップアダクション', ['ヒップアダクション', 'ヒップアダクター', 'インナーサイ', 'アダクション', 'アダクター'], ['hip_adduction']),
    ('hip_abduction', 'ヒップアブダクション', ['ヒップアブダクション', 'ヒップアブダクター', 'アウターサイ', 'アブダクション', 'アブダクター'], ['hip_abduction']),
    ('hip_dual', 'ヒップアダクション／アブダクション', ['ヒップアダクション/アブダクション', 'ヒップアブダクション/アダクション', 'ヒップアダクター/アブダクター', 'ヒップアブダクター/アダクター', 'インナー/アウターサイ', 'インナーサイ/アウターサイ', 'インナーアウターサイ', 'インナーサイアウターサイ', 'アブダクター/アダクター', 'アブダクションアダクション', 'アブダクター&アダクター', 'ヒップアダクター&ヒップアブダクター', 'ヒップアダクター/アブダクター デュアル'], ['hip_adduction', 'hip_abduction']),
    ('pec_fly', 'ペックフライ', ['ペックフライ', 'ペクトラルフライ', 'ペックデック', 'バタフライ'], ['pec_fly']),
    ('rear_delt', 'リアデルト', ['リアデルト', 'リアデルトフライ', 'リアデルトイド'], ['rear_delt']),
    ('fly_rear_delt', 'フライ／リアデルト', ['ペックフライ/リアデルト', 'フライ/リアデルト', 'フライ/リアデルトイド', 'ペクトラル/リバースフライ', 'バタフライ/リアデルト', 'リアデルト/ペックフライ', 'リアデルト/ペクトラルフライ', 'リアデルトペックフライ', 'ペクトラルフライ/リアデルトイド', 'ペクトラルフライ、リアデルトイド'], ['pec_fly', 'rear_delt']),
    ('lateral_raise', 'ラテラルレイズマシン', ['ラテラルレイズ', 'シーテッドラテラルレイズ', 'スタンディングラテラルレイズ'], ['machine_lateral_raise']),
    ('back_extension_machine', 'バックエクステンションマシン', ['バックエクステンション', 'バックエクステンションマシン', 'ローワーバック'], ['back_extension_machine']),
    ('abdominal', 'アブドミナルマシン', ['アブドミナル', 'アブドミナルクランチ', 'アブドミナルトレーナー', 'トータルアブドミナル', 'アジャスタブルアブドミナルクランチ', 'MTSアブドミナルクランチ'], ['abdominal_crunch']),
    ('standing_calf', 'スタンディングカーフ', ['スタンディングカーフ', 'スタンディングカーフレイズ'], ['standing_calf_raise']),
    ('arm_curl', 'アームカールマシン', ['バイセップスカール', 'バイセップカール', 'バイセプスカール', 'アームカール'], ['machine_arm_curl']),
    ('glute_extension', 'グルートエクステンションマシン', ['グルートエクステンション', 'グルートマシン'], ['glute_kickback_machine']),
    ('rotary_torso', 'ロータリートルソー', ['ロータリートルソー', 'トルソーローテーション', 'トーソローテーション', 'トーソーローテーション'], ['rotary_torso']),
    ('assisted_chin', 'アシストチンニング', ['アシストチン', 'アシストチンニング', 'チンアシスト'], ['assisted_chin_up']),
    ('assisted_dips', 'アシストディップス', ['アシストディップ', 'ディップスアシスト'], ['assisted_dips']),
    ('assisted_chin_dips', 'アシストチン／ディップ', ['アシストチン/ディップ', 'アシストチンディップ', 'アシストチン/アシストディップ', 'アシストディップ/チン', 'アシストディップチン', 'ディップチンアシスト', 'ニーリングイージーチンディップ', 'ニーリングチンディップ'], ['assisted_chin_up', 'assisted_dips']),
]:
    concept(id, name, aliases, MACHINE, exercises)

# Loading-system-sensitive names need an existing reviewed direct mapping or
# explicit loading system. A bare "プルダウン" is deliberately not an alias.
for id, name, aliases, exercise in [
    ('chest_press_stack', 'チェストプレス（スタック）', ['チェストプレス', 'シーテッドチェストプレス'], 'chest_press'),
    ('shoulder_press_stack', 'ショルダープレス（スタック）', ['ショルダープレス'], 'shoulder_press'),
    ('seated_row_stack', 'シーテッドロー（スタック）', ['シーテッドロー', 'シーテッド・ロー'], 'seated_row'),
    ('lat_pulldown_cable', 'ラットプルダウン（ケーブル）', ['ラットプルダウン'], 'lat_pulldown'),
]:
    concept(id, name, aliases, MACHINE, [exercise], require_direct=True)
concept('lat_cable_explicit', 'ラットプルダウン（ケーブル式）', ['ラットプルダウン（ケーブル）',
        'ラットマシン（ケーブル）', 'ラットプル(ケーブル)', 'ケーブルラットプルダウン'], MACHINE,
        ['lat_pulldown'], loads=['not_specified', 'cable_named'])
for id, name, aliases, exercise in [
    ('plate_chest_press', 'プレートロードチェストプレス', ['チェストプレス（プレートロード）', 'シーテッドチェストプレス（プレートロード）'], 'plate_loaded_chest_press'),
    ('plate_incline_press', 'プレートロードインクラインプレス', ['インクラインチェストプレス（プレートロード）', 'インクラインプレス（プレートロード）'], 'plate_loaded_incline_chest_press'),
    ('plate_shoulder_press', 'プレートロードショルダープレス', ['ショルダープレス（プレートロード）'], 'plate_loaded_shoulder_press'),
    ('plate_row', 'プレートロードシーテッドロー', ['シーテッドロー（プレートロード）'], 'plate_loaded_seated_row'),
    ('plate_pulldown', 'プレートロードラットプルダウン', ['ラットプルダウン（プレートロード）', 'プルダウン（プレートロード）', 'ワイドプルダウン（プレートロード）'], 'plate_loaded_lat_pulldown'),
    ('plate_leg_press', 'プレートロードレッグプレス', ['レッグプレス（プレートロード）', 'リニアレッグプレス（プレートロード）', '45°レッグプレス（プレートロード）'], 'leg_press'),
    ('plate_decline_press', 'プレートロードデクラインプレス', ['デクラインプレス（プレートロード）', 'デクラインチェストプレス（プレートロード）'], 'decline_press_machine'),
    ('plate_low_row', 'プレートロードローロー', ['ローロー（プレートロード）', 'アイソラテラルローロー（プレートロード）'], 'low_row'),
    ('plate_high_row', 'プレートロードハイロー', ['ハイロー（プレートロード）'], 'high_row'),
    ('plate_dy_row', 'プレートロードDYロー', ['DYロー（プレートロード）'], 'dy_row'),
    ('plate_hip_thrust', 'プレートロードヒップスラスト', ['ヒップスラスト（プレートロード）', 'グルートドライブ（プレートロード）'], 'machine_hip_thrust'),
]:
    concept(id, name, aliases, FREE + MACHINE, [exercise], loads=['plate_loaded_explicit'])
for id, name, aliases, exercise in [
    ('treadmill', 'トレッドミル', ['トレッドミル', 'ランニングマシン'], 'treadmill'),
    ('cross_trainer', 'クロストレーナー', ['クロストレーナー'], 'cross_trainer'),
    ('bike', 'アップライトバイク', ['アップライトバイク'], 'exercise_bike'),
    ('recumbent_bike', 'リカンベントバイク', ['リカンベントバイク'], 'recumbent_bike'),
    ('stair_climber', 'ステアクライマー', ['ステアクライマー', 'ステアマスター'], 'stair_climber'),
]:
    concept(id, name, aliases, ['有酸素'], [exercise], loads=['cardio'])
concept('tibialis_machine', '前脛骨筋マシン', ['ティビアドーシフレクション', 'ディビアドルシフレクション'],
        FREE + MACHINE, status='exercise_not_in_catalog')

RULES = []


def rule(requirements, exercises):
    for exercise in exercises:
        RULES.append(dict(id='canonical:' + exercise + ':' + '+'.join(requirements),
                          exercise_id=exercise, requires=requirements))


rule(['dumbbell', 'flat_bench'], ['flat_dumbbell_press', 'dumbbell_fly', 'dumbbell_pullover',
     'bulgarian_split_squat', 'one_arm_dumbbell_row', 'concentration_curl', 'triceps_kickback'])
rule(['dumbbell', 'incline_bench'], ['incline_dumbbell_press', 'incline_dumbbell_fly',
     'chest_supported_dumbbell_row', 'incline_dumbbell_curl', 'spider_curl',
     'dumbbell_shoulder_press', 'arnold_press', 'french_press'])
rule(['dumbbell', 'decline_bench'], ['decline_dumbbell_press', 'decline_dumbbell_fly'])
rule(['dumbbell', 'preacher_bench'], ['preacher_curl'])
rule(['ez_bar', 'preacher_bench'], ['preacher_curl'])
rule(['barbell', 'rack'], ['barbell_squat', 'front_squat', 'rack_pull', 'good_morning', 'military_press'])
rule(['barbell', 'rack', 'flat_bench'], ['bench_press', 'close_grip_bench_press'])
rule(['barbell', 'rack', 'incline_bench'], ['incline_barbell_press'])
rule(['barbell', 'rack', 'decline_bench'], ['decline_barbell_press'])
rule(['barbell', 'flat_bench'], ['hip_thrust', 'skull_crusher'])
rule(['ez_bar', 'flat_bench'], ['skull_crusher'])
rule(['smith', 'flat_bench'], ['smith_bench_press', 'smith_bulgarian_split_squat'])
rule(['smith', 'incline_bench'], ['smith_incline_press', 'smith_shoulder_press'])
rule(['smith', 'decline_bench'], ['smith_decline_press'])


def concepts_for(equipment, direct_ids=()):
    """Reviewed exact variants only; outputs proposals, never writes to DB."""
    name = key(equipment['name'])
    if key(equipment['normalized_name']) != name:
        return []
    result = []
    for id, c in CONCEPTS.items():
        if equipment['category'] not in c['categories'] or equipment['load_type'] not in c['loads']:
            continue
        match = name in c['aliases']
        if id == 'dumbbell' and not match:
            # Only a complete dumbbell designation + an optional weight range.
            # Excludes racks, areas, attachments, mixed bench entries and broken ranges.
            match = re.fullmatch(r'(?:ivanko)?ダンベル\(?(?:最大)?(?:[0-9]+(?:[~〜～-][0-9]+)?|[~〜～-][0-9]+)kg(?:ペア)?\)?', name) is not None
            match = match or re.fullmatch(r'パワーブロック\(可変式ダンベル(?:[0-9]+[~〜～-][0-9]+kg)?\)', name) is not None
        if match and (not c['require_direct'] or set(c['exercises']) <= set(direct_ids)):
            result.append(id)
    return result
