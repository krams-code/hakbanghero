#!/usr/bin/env python3
"""
Generates firestore.rules (the "economy guard") from your Dart data.

  python3 tools/gen_economy_rules.py            # run from the project root
  -> writes firestore.rules (paste into Firebase Console > Firestore > Rules,
     or `firebase deploy --only firestore:rules`)

It reads prices from lib/models/hero_items.dart + hero_roster.dart and the
stage targets from lib/models/run_mode.dart, so after changing a price or a
rank/trial, run it again and re-publish.

WHAT THE RULES ENFORCE (client-side cheating, e.g. editing coins in DevTools):
  * coins / xp / total_km / stage_records can only go UP together with
    a run record (users/{uid}/activities/{id}) written in the SAME transaction,
    and the amounts may not exceed what that record shows.
  * a run record must be humanly possible (<= 25 km/h, reward <= formula).
  * one run per 30 s.
  * buying an item/hero must pay at least its catalog price (weekly -25% ok).
  * duel prizes only for the real winner of a finished challenge.
  * streak / weekly-goal coins: 1 claim per 12 h / 6 days.
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

# ── keep the friends / chat rules from the existing file ─────────────────
r2 = (ROOT / 'firestore_round2.rules').read_text()
tail_start = r2.index('    // ── friend codes')
tail = r2[tail_start:]
# duel prize can't be set higher than the real table (200/400/600/1000 coins)
tail = tail.replace(
    "&& request.resource.data.status == 'pending'\n        && request.resource.data.participants.size() == 2",
    "&& request.resource.data.status == 'pending'\n        && request.resource.data.reward is int\n        && request.resource.data.reward <= 1000\n        && request.resource.data.participants.size() == 2", 1)
assert 'reward <= 1000' in tail, 'could not patch the challenge create rule'

RULES = r"""// ─────────────────────────────────────────────────────────────────────────
// HakbangHero — Firestore rules WITH ECONOMY GUARD.
// GENERATED by tools/gen_economy_rules.py — do not edit by hand; edit the
// generator or your Dart data and run it again.
//
// TEST BEFORE PUBLISHING: Firebase Console > Firestore > Rules > Rules
// Playground, or the emulator. Keep your old rules copied somewhere so you
// can roll back in one click.
// ─────────────────────────────────────────────────────────────────────────
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() { return request.auth != null; }
    function isMe(uid)  { return signedIn() && request.auth.uid == uid; }

    // ── catalog (generated from hero_items.dart / hero_roster.dart) ──
    // Unknown ids cost 999999999, so they can never be "bought".
    function itemCoins(id) { return __ITEM_COINS__.get(id, __BIG__); }
    function heroCoins(id) { return __HERO_COINS__.get(id, __BIG__); }
    // earned heroes that need a cleared rank: hero id -> stage id
    function heroStage(id) { return __HERO_STAGE__.get(id, ''); }
    // rank / trial targets: mode id -> [km, seconds]
    function stageTarget(mode) { return __STAGE_TARGETS__.get(mode, [__BIG__, 0]); }

    // ── helpers over the user document ──
    function od(f, d) { return resource.data.get(f, d); }
    function nd(f, d) { return request.resource.data.get(f, d); }
    function changed(f) { return nd(f, null) != od(f, null); }
    function delta(f) { return nd(f, 0) - od(f, 0); }
    function epoch() { return timestamp.date(2000, 1, 1); }

    function actPath(uid, id) {
      return /databases/$(database)/documents/users/$(uid)/activities/$(id);
    }

    // ── a RUN (or duel) commit: reward must be justified by a new run record ──
    function runCommit() {
      return changed('last_run_id')
        && nd('last_run_id', '') is string
        && nd('last_run_id', '').size() > 0;
    }

    // Daily coin cap for runs/duels: the app keeps coins_today (+ the day
    // number, Manila time) and the rules make that counter honest.
    function coinDay() { return math.floor(float(request.time.toMillis() + 28800000) / 86400000.0); }
    function dailyCoinsOk() {
      return delta('coins') == 0
        || (nd('coins_today_day', -1) == coinDay()
            && nd('coins_today', 0)
               == (od('coins_today_day', -1) == coinDay() ? od('coins_today', 0) : 0)
                  + delta('coins')
            && nd('coins_today', 0) <= 12000);
    }

    function runAmountsOk(a) {
      // coins = the run's own coins + bonuses (daily quests, rank clears and
      // stars, challenges, ghost win). 1 crystal used to be worth 10 coins.
      return delta('coins') >= 0
        && dailyCoinsOk()
        && delta('coins') <= a.coinsEarned + 1500 + 300 * a.distanceKm
                             + (changed('stage_records') ? 3000 : 0)
        && delta('xp') >= 0 && delta('xp') <= a.xpEarned
        && delta('total_km') >= 0 && delta('total_km') <= a.distanceKm + 0.001
        && delta('total_sessions') == 1
        && delta('loot_chests') >= 0 && delta('loot_chests') <= 3
        && request.time > od('last_run_at', epoch()) + duration.value(30, 's');
    }

    function runOk(uid) {
      return runCommit()
        && existsAfter(actPath(uid, nd('last_run_id', '')))
        && !exists(actPath(uid, nd('last_run_id', '')))
        && runAmountsOk(getAfter(actPath(uid, nd('last_run_id', ''))).data);
    }

    // stage_records may change only for the mode of THIS run, and only if the
    // run record really cleared it (target distance inside the clock).
    function stageProof(a) {
      return a.get('stage_result', '') == 'STAGE CLEARED!'
        && request.resource.data.stage_records
             .diff(resource.data.get('stage_records', {}))
             .affectedKeys().hasOnly([a.mode])
        && a.distanceKm >= stageTarget(a.mode)[0] - 0.01
        && a.durationSeconds <= stageTarget(a.mode)[1] + 2;
    }

    // (runOk itself is enforced by economyOk whenever a run is committed)
    function stageOk(uid) {
      return !changed('stage_records')
        || (runChange() && runCommit()
            && stageProof(getAfter(actPath(uid, nd('last_run_id', ''))).data));
    }

    // ── duel prize: only the winner of a challenge that just finished ──
    function duelWinOk(uid) {
      return changed('last_duel_id')
        && nd('last_duel_id', '') is string
        && getAfter(/databases/$(database)/documents/challenges/$(nd('last_duel_id', ''))).data.winner == uid
        && getAfter(/databases/$(database)/documents/challenges/$(nd('last_duel_id', ''))).data.status == 'done'
        && get(/databases/$(database)/documents/challenges/$(nd('last_duel_id', ''))).data.status != 'done'
        && delta('coins') <= getAfter(/databases/$(database)/documents/challenges/$(nd('last_duel_id', ''))).data.reward;
    }

    // ── daily streak and weekly goal gifts ──
    function streakOk() {
      return nd('streak_claims', []).size() == od('streak_claims', []).size() + 1
        && nd('streak_claims', []).hasAll(od('streak_claims', []))
        && nd('streak_claim_at', null) == request.time
        && request.time > od('streak_claim_at', epoch()) + duration.value(12, 'h')
        && delta('coins') <= 4000;
    }

    function weeklyOk() {
      return changed('weekly_goal_claimed')
        && nd('weekly_claim_at', null) == request.time
        && request.time > od('weekly_claim_at', epoch()) + duration.value(6, 'd')
        && delta('coins') <= 500;
    }

    // ── shop: every new item / hero must be paid at (at least) catalog price ──
    // arrayUnion appends, so the NEW entries are the tail of the new array.
    function ci(ni, j) { return j < ni.size() ? itemCoins(ni[j]) : 0; }
    // weekly pick is 25% off: pay at least 75% of the price
    function minPay(v) { return math.floor(v * 0.75); }

    function itemCoinsMin(ni, k) {
      return minPay(ci(ni, k)) + minPay(ci(ni, k + 1)) + minPay(ci(ni, k + 2))
           + minPay(ci(ni, k + 3)) + minPay(ci(ni, k + 4)) + minPay(ci(ni, k + 5))
           + minPay(ci(ni, k + 6));
    }
    function heroCoinsMin(nh, k) { return k < nh.size() ? heroCoins(nh[k]) : 0; }
    function heroUnlockedByRank(nh, k) {
      return k >= nh.size()
        || heroStage(nh[k]) == ''
        || nd('stage_records', {}).get(heroStage(nh[k]), {}).get('stars', 0) > 0;
    }

    function ownershipOk() {
      return nd('owned_items', []).hasAll(od('owned_items', []))
        && nd('owned_heroes', []).hasAll(od('owned_heroes', []))
        && nd('owned_items', []).size() <= od('owned_items', []).size() + 7
        && nd('owned_heroes', []).size() <= od('owned_heroes', []).size() + 1
        && od('coins', 0) - nd('coins', 0)
             >= itemCoinsMin(nd('owned_items', []), od('owned_items', []).size())
                + heroCoinsMin(nd('owned_heroes', []), od('owned_heroes', []).size())
        && heroUnlockedByRank(nd('owned_heroes', []), od('owned_heroes', []).size());
    }

    function ownershipNeedsCheck() {
      return nd('owned_items', []).size() > od('owned_items', []).size()
          || nd('owned_heroes', []).size() > od('owned_heroes', []).size();
    }

    // weight / height only change at the weekly check-in (6-day tolerance),
    // and the first time they are set (old value missing)
    function checkInOk() {
      return (!changed('weight_kg') && !changed('height_cm') && !changed('body_tier'))
        || od('weight_kg', null) == null
        || (request.time - od('last_checkin_at', request.time - duration.value(30, 'd')))
             >= duration.value(6, 'd');
    }

    // one-time cash-in of an old crystal balance: 1 crystal = 10 coins
    function migrateOk() {
      return od('gems', 0) > 0 && nd('gems', 0) == 0
        && delta('coins') >= 0 && delta('coins') <= od('gems', 0) * 10;
    }

    // ── put it together ──
    // xp / km / runs / chests only ever go up through a run commit.
    function runChange() {
      return delta('xp') > 0 || delta('total_km') > 0
        || delta('total_sessions') > 0 || delta('loot_chests') > 0;
    }

    function economyOk(uid) {
      return
        checkInOk() &&
        // A run is verified ONCE (its coins are checked inside runOk).
        // Rules may only make ~10 document lookups per write: checking the
        // run separately for coins, xp, km and runs went over that limit and
        // every real run was refused with permission-denied.
        // Without a run, coins can always be SPENT, but only a duel / claim
        // adds them.
        (runChange()
            ? runOk(uid)
            : (delta('coins') <= 0 || duelWinOk(uid)
                || streakOk() || weeklyOk() || migrateOk()))
        // crystals no longer exist: the old balance can only be cashed in
        && delta('gems') <= 0
        && nd('coins', 0) >= 0
        // nobody lowers their own totals to dodge checks
        && delta('xp') >= 0 && delta('total_km') >= 0 && delta('total_sessions') >= 0
        && stageOk(uid)
        && (!ownershipNeedsCheck() || ownershipOk())
        && nd('owned_items', []).hasAll(od('owned_items', []))
        && nd('owned_heroes', []).hasAll(od('owned_heroes', []));
    }

    // Picking / switching the hero touches ONLY hero_id and owned_heroes, and
    // may add at most one FREE hero (price 0). This small check runs on its own
    // so choosing a hero never depends on the long economy check below.
    function heroSwitchOk() {
      return request.resource.data.diff(resource.data).affectedKeys()
               .hasOnly(['hero_id', 'owned_heroes'])
        && nd('hero_id', '') is string
        && nd('owned_heroes', []).hasAll(od('owned_heroes', []))
        && nd('owned_heroes', []).size() <= od('owned_heroes', []).size() + 1
        && (nd('owned_heroes', []).size() == od('owned_heroes', []).size()
            || (heroCoins(nd('owned_heroes', [])[od('owned_heroes', []).size()]) == 0
                && heroUnlockedByRank(nd('owned_heroes', []), od('owned_heroes', []).size())));
    }

    // a new account starts with the sign-up gift only
    function freshAccount() {
      return nd('coins', 0) <= 100 && nd('gems', 0) == 0
        && nd('xp', 0) == 0 && nd('total_km', 0) == 0
        && nd('total_sessions', 0) == 0
        && nd('owned_items', []).size() <= 12;
    }

    // a run record must be humanly possible and its reward must fit the formula
    // (utils/rewards.dart: 100 xp/km + 3 xp/min, x1.3 pace, x3.5 mode, + events)
    function activityOk(a) {
      return a.distanceKm is number && a.distanceKm >= 0
        && a.durationSeconds is int && a.durationSeconds >= 0
        && a.durationSeconds <= 172800
        && a.distanceKm <= a.durationSeconds / 3600.0 * 25 + 0.05
        && a.coinsEarned is int && a.coinsEarned >= 0
        && a.coinsEarned <= a.distanceKm * 10 * 3.5 + 1
        && a.xpEarned is int && a.xpEarned >= 0
        && a.xpEarned <= (a.distanceKm * 100 + a.durationSeconds / 60.0 * 5) * 1.3 * 3.5 + 2500;
    }

    // ── users ──
    match /users/{uid} {
      allow read: if signedIn();                 // leaderboard + friend profiles
      allow create: if isMe(uid) && freshAccount();
      allow update: if isMe(uid) && (heroSwitchOk() || economyOk(uid));
      allow delete: if isMe(uid);

      // weekly weight history (profile chart)
      match /weight_checkins/{id} {
        allow read: if isMe(uid);
        allow create: if isMe(uid)
          && request.resource.data.weight_kg is number
          && request.resource.data.weight_kg >= 20
          && request.resource.data.weight_kg <= 400;
        allow update, delete: if false;
      }

      match /activities/{id} {
        allow read: if isMe(uid);
        allow create: if isMe(uid) && activityOk(request.resource.data);
        allow update: if false;
        allow delete: if isMe(uid);
      }

      // Finished runs waiting to be counted. Uploaded the moment a run ends
      // (works on any device / weak signal), then counted by the normal,
      // fully checked run save and deleted. Gives no rewards by itself.
      match /pending_runs/{id} {
        allow read, delete: if isMe(uid);
        allow create: if isMe(uid) && request.resource.data.uid == uid;
        allow update: if false;
      }

__FRIENDS_SUBTREE__
    }

""" + "__TAIL__" + """
  }
}
"""

# the friends subcollection block lives inside `match /users/{uid}` in round2
fs = r2.index('      // Friendship is stored on BOTH players.')
fe = r2.index('    // ── friend codes')
friends_block = r2[fs:fe].rstrip()
# friends_block ends with the closing brace of `match /users/{uid}`: drop it
assert friends_block.rstrip().endswith('}')
friends_block = friends_block.rstrip()[:-1].rstrip()

out = (RULES
       .replace('__ITEM_COINS__', dart_map(item_coins))
              .replace('__HERO_COINS__', dart_map(heroes))
       .replace('__HERO_STAGE__', hero_stage_map)
       .replace('__STAGE_TARGETS__', stage_map)
       .replace('__BIG__', str(BIG))
       .replace('__FRIENDS_SUBTREE__', friends_block)
       .replace('__TAIL__', tail.rstrip()[: tail.rstrip().rindex('  }')].rstrip() + '\n'))

(ROOT / 'firestore.rules').write_text(out)
print('items:', len(items), '| heroes:', len(heroes), '| stage targets:', len(targets))
print('wrote', ROOT / 'firestore.rules')
