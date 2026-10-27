#!/usr/bin/env python3
"""
Generates firestore.rules (the "economy guard") from your Dart data.

  python3 tools/gen_economy_rules.py            # run from the project root
  -> writes firestore.rules (paste into Firebase Console > Firestore > Rules,
     or `firebase deploy --only firestore:rules`)

It fills the catalog into tools/firestore.rules.template: prices from
lib/models/hero_items.dart + hero_roster.dart and the stage targets from
lib/models/run_mode.dart. After changing a price, a rank/trial, or the
template itself, run it again and re-publish.

WHAT THE RULES ENFORCE (client-side cheating, e.g. editing coins in DevTools):
  * coins / xp / total_km / stage_records can only go UP together with
    a run record (users/{uid}/activities/{id}) written in the SAME transaction,
    and the amounts may not exceed what that record shows.
  * a run record must be humanly possible (<= 25 km/h, reward <= formula).
  * runs can't overlap in time (each run starts after the previous one ended).
  * buying an item/hero must pay at least its catalog price (weekly -25% ok).
  * free heroes with a level requirement need that much XP.
  * duel prizes only for the real winner of a finished challenge, scaled to
    the distance run, inside the daily coin cap.
  * streak / weekly-goal coins: 1 claim per 12 h / calendar week.
  * private data (email, height, weight) lives in users/{uid}/private and is
    readable only by its owner; chats only by their two (friend) members.
NOT covered (needs a server / Cloud Functions): fake GPS, colluding duel
partners, rule-locked items that are also priced.
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = ROOT / 'lib'

def balanced(src, start):
    """text of the (...) group that opens at src[start] == '('"""
    depth = 0
    for i in range(start, len(src)):
        if src[i] == '(':
            depth += 1
        elif src[i] == ')':
            depth -= 1
            if depth == 0:
                return src[start + 1:i]
    raise ValueError('unbalanced')

def calls(src, name):
    for m in re.finditer(r'\b' + name + r'\(', src):
        yield balanced(src, m.end() - 1)

# ── items ────────────────────────────────────────────────────────────────
items = {}
src = (LIB / 'models/hero_items.dart').read_text()
body = src[src.index('const List<HeroItem> kHeroItems'):]
for blk in calls(body, 'HeroItem'):
    m = re.match(r"\s*'(\w+)'", blk)
    if not m:
        continue
    coins = re.search(r'\bcoins:\s*(\d+)', blk)
    items[m.group(1)] = int(coins.group(1)) if coins else 0

# free starter ids every hero gets at sign-up (StarterPack in outfit_catalog.dart)
oc = (LIB / 'models/outfit_catalog.dart').read_text()
starter_const = re.search(r"kStarterOutfitId\s*=\s*'(\w+)'", oc)
starter_ids = ['wavy_mane', 'neutral']
if starter_const:
    starter_ids.append(starter_const.group(1))
blk = re.search(r'static const List<String> ownedItems = \[(.*?)\];', oc, re.S)
if blk:
    for q in re.findall(r"'(\w+)'", blk.group(1)):
        if q not in starter_ids:
            starter_ids.append(q)
for sid in starter_ids:
    items.setdefault(sid, 0)

# ── heroes ───────────────────────────────────────────────────────────────
heroes = {}
hero_stage = {}
hero_level = {}
src = (LIB / 'models/hero_roster.dart').read_text()
body = src[src.index('const List<HeroDef> kHeroes'):]
for blk in calls(body, 'HeroDef'):
    m = re.search(r"\bid:\s*'(\w+)'", blk)
    if not m:
        continue
    hid = m.group(1)
    g = re.search(r'\bcoinPrice:\s*(\d+)', blk)
    heroes[hid] = int(g.group(1)) if g else 0
    st = re.search(r"stageId:\s*'(\w+)'", blk)
    if st:
        hero_stage[hid] = st.group(1)
    lv = re.search(r"UnlockRule\([^)]*\blevel:\s*(\d+)", blk)
    if lv:
        hero_level[hid] = int(lv.group(1))

# ── stage / trial targets (km, seconds) ──────────────────────────────────
targets = {}
src = (LIB / 'models/run_mode.dart').read_text()
for name in ('kNovice', 'kVanguard', 'kSlayer'):
    m = re.search(r'const RunMode ' + name + r' = RunMode\(', src)
    blk = balanced(src, m.end() - 1)
    rid = re.search(r"id:\s*'(\w+)'", blk).group(1)
    km = float(re.search(r'targetKm:\s*([\d.]+)', blk).group(1))
    mins = int(re.search(r'clockMinutes:\s*(\d+)', blk).group(1))
    targets[rid] = (km, mins * 60)
for sp in re.finditer(r"_TrialSpec\('(\w+)',\s*'[^']*',\s*([\d.]+),\s*\[([\d,\s]+)\]", src):
    key, km, mins = sp.group(1), float(sp.group(2)), [int(x) for x in sp.group(3).split(',')]
    for mn in mins:
        targets['trial_%s_%d' % (key, mn)] = (km, mn * 60)

def num(v):
    return ('%g' % v) if isinstance(v, float) else str(v)

def dart_map(d, fmt=lambda v: v):
    return '{' + ', '.join("'%s': %s" % (k, fmt(v)) for k, v in d.items()) + '}'

item_coins = dict(items)
stage_map = '{' + ', '.join("'%s': [%s, %d]" % (k, num(v[0]), v[1]) for k, v in targets.items()) + '}'
hero_stage_map = dart_map(hero_stage, lambda v: "'%s'" % v)

BIG = 999999999

# ── fill the template ────────────────────────────────────────────────────
tmpl = (ROOT / 'tools' / 'firestore.rules.template').read_text()
# level a free hero needs -> minimum total XP (level L starts at 250*L*(L-1))
hero_min_xp = {k: 250 * v * (v - 1) for k, v in hero_level.items()}
out = (tmpl
       .replace('__ITEM_COINS__', dart_map(item_coins))
       .replace('__HERO_COINS__', dart_map(heroes))
       .replace('__HERO_STAGE__', hero_stage_map)
       .replace('__HERO_MIN_XP__', dart_map(hero_min_xp))
       .replace('__STAGE_TARGETS__', stage_map))
assert '__' not in out.replace('__name__', ''), 'unfilled placeholder in template'
(ROOT / 'firestore.rules').write_text(out)
print('items:', len(items), '| heroes:', len(heroes), '| stage targets:', len(targets))
print('wrote', ROOT / 'firestore.rules')
