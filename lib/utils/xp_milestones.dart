import '../screens/shop/avatar_shop_screen.dart' show kShopCatalog, ShopItem;
import 'player_stats.dart';

/// What the EXP bar's sub-text says. Driven by the REAL shop catalog: any
/// free item with `unlockLevel > 1` is an XP milestone reward, and
/// `isShopItemUnlocked` unlocks it automatically at that level.
class XpMilestone {
  final String text;
  final ShopItem? item;
  const XpMilestone(this.text, this.item);
}

/// The next free (XP-gated) item above [level], or a plain XP target.
XpMilestone nextXpMilestone(int totalXp) {
  final lv = LevelProgress.fromXp(totalXp);
  ShopItem? next;
  for (final i in kShopCatalog) {
    if (i.price == 0 && i.unlockLevel > lv.level) {
      if (next == null || i.unlockLevel < next.unlockLevel) next = i;
    }
  }
  if (next != null) {
    return XpMilestone(
        'Next Free Item: ${next.name} at Level ${next.unlockLevel}!', next);
  }
  final need = lv.xpNeeded - lv.xpIntoLevel;
  return XpMilestone('Earn $need XP to clear Milestone ${lv.level}!', null);
}
