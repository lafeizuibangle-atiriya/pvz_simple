/**
 * 持久化存档：金币 / 卡槽数 / 音量设置 / 关卡进度 / 挑战信状态
 * 基于 @ohos.data.preferences（同步 API），StartPage 加载后全局可用
 */
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { FIRST_AID_PRICE, MAX_SLOTS, MOWER_PRICE, SLOT_PRICES, UPGRADE_KEYS, UPGRADE_T1_PRICE, UPGRADE_T2_PRICE } from './GameTypes';

export class SaveData {
  static coins: number = 0;            // 金币余额（僵尸掉落）
  static slots: number = 6;            // 卡槽数量（初始6，商店最多扩到9）
  static bgmVol: number = 0.6;         // BGM 音量 0~1
  static sfxVol: number = 1.0;         // 音效音量 0~1（默认最大，文件已做响度归一）
  static dayBeaten: number = 0;        // 已通关的最大白天关卡序号（1-9通关=9）
  static nightBeaten: number = 0;      // 已通关的最大夜晚关卡序号
  static letterPending: boolean = false; // 1-9通关后收到僵王挑战信（1-10 解锁）
  static letterSeen: boolean = false;
  static almanacUnlocked: boolean = false; // 2-4通关掉落图鉴后解锁主页/结算页图鉴入口
  static debugAllPlants: boolean = false; // 调试：所有关卡解锁全部植物（无视关卡进度）
  static wallFirstAid: boolean = false;   // 商店：坚果包扎术（对已种坚果再种坚果卡可回满血）
  static mowerOwned: boolean = false;     // 商店：小推车（每关开始每行就位一辆，僵尸到最左侧自动清行）
  static upgrades: Map<string, number> = new Map<string, number>(); // 强化等级：key → 0/1/2
  private static store: preferences.Preferences | null = null;

  /** StartPage.aboutToAppear 调用一次 */
  static init(context: common.Context): void {
    if (SaveData.store !== null) return;
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: 'pvz_save' });
      SaveData.store = store;
      SaveData.coins = Number(store.getSync('coins', 0));
      SaveData.slots = Number(store.getSync('slots', 6));
      SaveData.bgmVol = Number(store.getSync('bgmVol', 0.6));
      SaveData.sfxVol = Number(store.getSync('sfxVol', 1.0));
      SaveData.dayBeaten = Number(store.getSync('dayBeaten', 0));
      SaveData.nightBeaten = Number(store.getSync('nightBeaten', 0));
      SaveData.letterPending = store.getSync('letterPending', false) as boolean;
      SaveData.letterSeen = store.getSync('letterSeen', false) as boolean;
      SaveData.almanacUnlocked = store.getSync('almanacUnlocked', false) as boolean;
      SaveData.debugAllPlants = store.getSync('debugAllPlants', false) as boolean;
      SaveData.wallFirstAid = store.getSync('wallFirstAid', false) as boolean;
      SaveData.mowerOwned = store.getSync('mowerOwned', false) as boolean;
      for (const k of UPGRADE_KEYS) {
        SaveData.upgrades.set(k, Number(store.getSync('up_' + k, 0)));
      }
    } catch (err) {
      console.error(`SaveData init failed: ${JSON.stringify(err)}`);
    }
  }

  /** 内存值落盘（异步 flush，不阻塞 UI） */
  static save(): void {
    const store = SaveData.store;
    if (store === null) return;
    try {
      store.putSync('coins', SaveData.coins);
      store.putSync('slots', SaveData.slots);
      store.putSync('bgmVol', SaveData.bgmVol);
      store.putSync('sfxVol', SaveData.sfxVol);
      store.putSync('dayBeaten', SaveData.dayBeaten);
      store.putSync('nightBeaten', SaveData.nightBeaten);
      store.putSync('letterPending', SaveData.letterPending);
      store.putSync('letterSeen', SaveData.letterSeen);
      store.putSync('almanacUnlocked', SaveData.almanacUnlocked);
      store.putSync('debugAllPlants', SaveData.debugAllPlants);
      store.putSync('wallFirstAid', SaveData.wallFirstAid);
      store.putSync('mowerOwned', SaveData.mowerOwned);
      for (const k of UPGRADE_KEYS) {
        store.putSync('up_' + k, SaveData.getUpgrade(k));
      }
      store.flush();
    } catch (err) {
      console.error(`SaveData save failed: ${JSON.stringify(err)}`);
    }
  }

  /** 拾取金币：立即入账并落盘，返回新余额 */
  static addCoins(value: number): number {
    SaveData.coins += value;
    SaveData.save();
    return SaveData.coins;
  }

  /** 下一个待解锁卡槽的价格（全部解锁完返回 -1） */
  static nextSlotPrice(): number {
    if (SaveData.slots >= MAX_SLOTS) return -1;
    return SLOT_PRICES[SaveData.slots - 6];
  }

  /** 商店购买卡槽：成功返回新卡槽数，金币不足返回 -1 */
  static buySlot(): number {
    const price: number = SaveData.nextSlotPrice();
    if (price < 0) return -1;
    if (SaveData.coins < price) return -1;
    SaveData.coins -= price;
    SaveData.slots += 1;
    SaveData.save();
    return SaveData.slots;
  }

  /** 商店购买坚果包扎术：成功返回 true，已拥有或金币不足返回 false */
  static buyFirstAid(): boolean {
    if (SaveData.wallFirstAid) return false;
    if (SaveData.coins < FIRST_AID_PRICE) return false;
    SaveData.coins -= FIRST_AID_PRICE;
    SaveData.wallFirstAid = true;
    SaveData.save();
    return true;
  }

  /** 商店购买小推车（一次性永久）：成功返回 true，已拥有或金币不足返回 false */
  static buyMower(): boolean {
    if (SaveData.mowerOwned) return false;
    if (SaveData.coins < MOWER_PRICE) return false;
    SaveData.coins -= MOWER_PRICE;
    SaveData.mowerOwned = true;
    SaveData.save();
    return true;
  }

  /** 读取强化等级：0未买 / 1一级 / 2二级（二级替换一级效果） */
  static getUpgrade(key: string): number {
    const v: number | undefined = SaveData.upgrades.get(key);
    return v === undefined ? 0 : v;
  }

  /** 购买/升级强化：1级需未购买；2级需已购1级；金币不足返回 false */
  static buyUpgrade(key: string, tier: number): boolean {
    const cur: number = SaveData.getUpgrade(key);
    if (tier === 1 && cur >= 1) return false;
    if (tier === 2 && cur !== 1) return false;
    const price: number = tier === 1 ? UPGRADE_T1_PRICE : UPGRADE_T2_PRICE;
    if (SaveData.coins < price) return false;
    SaveData.coins -= price;
    SaveData.upgrades.set(key, tier);
    SaveData.save();
    return true;
  }

  /** 首次通关奖励：所有关卡统一 $300；重打已通关卡不重复发放 */
  static readonly FIRST_CLEAR_REWARD: number = 300;

  /** 通关记录：更新进度、发挑战信、发首次通关奖励 */
  static markWon(levelId: string): void {
    let reward: number = 0;
    if (levelId === `1-${SaveData.dayBeaten + 1}` && SaveData.dayBeaten < 10) {
      SaveData.dayBeaten += 1;
      // 1-9 通关 → 收到僵王挑战信（1-10 传送带关解锁）
      if (SaveData.dayBeaten === 9) {
        SaveData.letterPending = true;
      }
      reward = SaveData.FIRST_CLEAR_REWARD;
    } else if (levelId === `2-${SaveData.nightBeaten + 1}` && SaveData.nightBeaten < 10) {
      SaveData.nightBeaten += 1;
      // 2-4 通关掉落图鉴 → 解锁图鉴入口（主页 + 结算页）
      if (SaveData.nightBeaten >= 4) {
        SaveData.almanacUnlocked = true;
      }
      reward = SaveData.FIRST_CLEAR_REWARD;
    } else {
      return; // 非下一关（如重打已通关卡）不重复发奖励
    }
    // 首次通关奖励入账（addCoins 内部会落盘；未达成新进度时上面已 return 不发）
    if (reward > 0) {
      SaveData.addCoins(reward);
    } else {
      SaveData.save();
    }
  }

  /** 关卡是否已解锁：白天数 ≤ dayBeaten+1；夜晚需白天通全 + 夜晚数 ≤ nightBeaten+1 */
  static isLevelUnlocked(levelId: string): boolean {
    const parts: string[] = levelId.split('-');
    const chapter: number = Number(parts[0]);
    const index: number = Number(parts[1]);
    if (chapter === 1) {
      return index <= SaveData.dayBeaten + 1;
    }
    if (chapter === 2) {
      return SaveData.dayBeaten >= 10 && index <= SaveData.nightBeaten + 1;
    }
    return false;
  }
}
