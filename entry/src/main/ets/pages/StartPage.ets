/**
 * 开始页面（纯色版）
 * 标题 + 关卡选择（1-1~1-10 白天，2-1~2-10 夜晚）+ 设置（音量）+ 商店（金币解锁卡槽）
 * 1-9 通关后弹僵王挑战信 → 解锁 1-10 传送带关
 */
import { router } from '@kit.ArkUI';
import { getLevelConfig, LEVELS, LevelConfig } from '../game/GameTypes';
import { UPGRADE_KEYS, UPGRADE_LABELS, UPGRADE_T1_PRICE, UPGRADE_T2_PRICE, MOWER_PRICE } from '../game/GameTypes';
import { DEBUG_DEFAULTS, DEBUG_TUNABLES, getConstValue, setConstValue } from '../game/GameTypes';
import { SaveData } from '../game/SaveData';
import { AlmanacView } from './AlmanacView';

/** 游戏结算页"前往商店"跳转参数：openShop 直接开商店；
 *  shopLevelId/shopResult 带来源关卡与胜负，商店底部显示"下一关/重玩本关"直达按钮 */
interface ShopParams {
  openShop?: boolean;
  shopLevelId?: string;
  shopResult?: string;   // 'win' | 'lose'
}

/** 调试面板单项（带当前值与生效时机） */
interface DebugItem {
  key: string;
  label: string;
  min: number;
  max: number;
  step: number;
  value: number;
  timing: string;   // 'now' = 立即生效 | 'next' = 下关/重开生效
}

/** 商店强化商品行 */
interface UpgradeItem {
  key: string;
  label: string;
  tier: number;   // 0/1/2
  desc: string;   // 下一级效果描述（满级显示当前2级效果）
}

/** 各强化各级效果描述（调试/商店展示用） */
const UPGRADE_DESC: Record<string, string[]> = {
  'wall': ['再种坚果：回满血 + 50%生命值的银色护甲', '再种坚果：回满血 + 125%生命值的金色护甲'],
  'pea': ['再种豌豆：随机发射 寒冰60% / 普通40%', '再种豌豆：回满血，随机 火焰50%(双倍) / 寒冰30% / 普通20%'],
  'peaArm': ['双发上再种双发：随机 石化40%（双倍伤害、无击退）/ 普通60%', '再种双发：强化并回满血，随机 石化60%（双倍伤害+轻微击退）/ 普通40%'],
  'ice': ['再种寒冰：随机 寒冰60% / 极寒40%（3连击冻结3秒）', '再种寒冰：回满血，随机 寒冰30% / 极寒70%，极寒附带冻伤7.5血/秒'],
  'sun': ['向日葵上再种向日葵：一次产出两份阳光', '再种向日葵：回满血，一次两份阳光且产出间隔缩短50%'],
  'sunBoost': ['阳光菇上再种阳光菇：立即长大，产超大阳光$50（未强化长大只产普通阳光25），左右地块金色+白色轮廓，地块植物攻速+25%', '再种阳光菇：超大阳光$75，左右地块植物攻速+50%'],
  'spore': ['小喷菇上再种小喷菇：左侧立即生成小喷菇复制体（浅色独立实体，可被种植替换），5秒后右侧再生成一个', '再种小喷菇：回满血，左/右侧（2.5秒后）各生成复制体，本体7.5秒后变复制体；种在复制体地块的植物攻速+25%（不与光能鼓舞叠加）'],
  'potato': ['土豆上再种土豆：立即发射炮弹（命中一格AOE 300伤害）', '再种土豆：炮弹伤害不变，每15秒自动发射（本行有僵尸时）'],
  'chomper': ['食人花上再种食人花：消化速度加快50%', '再种食人花：消化加快100%，吞后喷吐腐蚀液（5秒，僵尸15血/秒）'],
  'cherry': ['樱桃爆炸伤害×1.5（固定1600→2400，无需叠种，种下即生效）', '爆炸伤害×1.5，地面熔岩3秒（不可种植，僵尸50血/秒）'],
  'iceShroom': ['寒冰菇冰冻时长 4秒→6.5秒，解冻后减速时长翻倍（无需叠种，种下即生效）', '冰脆：冻结期间僵尸受伤+25%（持续6.5秒），保留1级效果'],
  'doom': ['毁灭菇伤害×1.5（1600→2400，无需叠种，种下即生效）', '弹坑变辐射坑：仅存续20秒且对踩上的僵尸每秒100伤害'],
  'hypno': ['被魅惑的僵尸回满血，啃咬速度+50%（魅惑菇被啃食时触发）', '被魅惑的僵尸获得精英强化：白内红双轮廓，血量/护甲/速度×2'],
  'scaredy': ['胆小菇上再种胆小菇：子弹50%概率暴击——伤害同时对护甲和本体生效', '再种胆小菇：暴击率提升至75%，子弹可穿透一名僵尸（有护甲也照常穿透），并回满血'],
  'fume': ['大喷菇上再种大喷菇：孢子雾化，射程提升至5格（基础4.5格对齐原版）', '再种大喷菇：孢子伤害+25%，且有2.5%概率直接吹落头部护甲（路障/铁桶/橄榄/黑橄榄整体移除），并回满血'],
};

@Entry
@Component
struct StartPage {
  private entering: boolean = false;
  @State selectedLevel: string = '1-1';
  @State coins: number = 0;
  @State slots: number = 6;
  @State dialog: string = 'none';   // none | settings | shop | letter | debug | almanac
  @State bgmSlider: number = 60;
  @State sfxSlider: number = 100;
  @State debugItems: DebugItem[] = [];  // 调试面板参数（打开面板时按当前值构建）
  @State debugAllPlants: boolean = false; // 调试：全植物解锁开关（面板内显示状态）
  @State upgradeList: UpgradeItem[] = []; // 商店强化商品（打开商店时按存档构建）
  @State mowerOwned: boolean = false;    // 商店：小推车是否已购买
  @State shopReturnLevel: string = '';   // 从结算页进商店时带的来源关卡（空 = 普通入口）
  @State shopReturnResult: string = '';  // 来源结果：'win' → 显示下一关按钮；'lose' → 重玩本关按钮
  @State levelTick: number = 0;          // 关卡解锁状态版本号：解锁变化时 +1，驱动关卡芯片重渲染

  aboutToAppear(): void {
    // 存档加载（首次进入时初始化）
    SaveData.init(getContext(this));
    this.refresh();
    // 游戏结算页"前往商店"带参跳转：回到主页并直接打开商店（携带来源关卡与胜负）
    const params = router.getParams() as ShopParams | null;
    if (params && params.openShop) {
      this.shopReturnLevel = params.shopLevelId !== undefined ? params.shopLevelId : '';
      this.shopReturnResult = params.shopResult !== undefined ? params.shopResult : '';
      this.openShop();
      return;
    }
    // 1-9 通关后收到挑战信
    if (SaveData.letterPending && !SaveData.letterSeen) {
      this.dialog = 'letter';
    }
  }

  /** 从游戏页返回时触发（aboutToAppear 不会再次执行）：
   *  复位进入标志（否则开始按钮永远无响应）+ 刷新金币（游戏中捡的金币已实时入账存档） */
  onPageShow(): void {
    this.entering = false;
    this.refresh();
  }

  private refresh(): void {
    this.coins = SaveData.coins;
    this.slots = SaveData.slots;
    this.mowerOwned = SaveData.mowerOwned;
    this.bgmSlider = Math.round(SaveData.bgmVol * 100);
    this.sfxSlider = Math.round(SaveData.sfxVol * 100);
    this.levelTick += 1; // 关卡解锁状态可能已变（通关/一键解锁），驱动芯片刷新
  }

  private openShop(): void {
    this.refresh();
    this.refreshUpgrades();
    this.dialog = 'shop';
  }

  /** 按存档构建强化商品列表 */
  private refreshUpgrades(): void {
    const list: UpgradeItem[] = [];
    for (const k of UPGRADE_KEYS) {
      const tier: number = SaveData.getUpgrade(k);
      list.push({
        key: k,
        label: UPGRADE_LABELS[k],
        tier: tier,
        desc: UPGRADE_DESC[k][tier >= 2 ? 1 : tier]
      });
    }
    this.upgradeList = list;
  }

  /** 购买强化（tier=1 首购 250；tier=2 升级 300，需先买1） */
  private buyUpgrade(key: string, tier: number): void {
    if (SaveData.buyUpgrade(key, tier)) {
      this.refresh();
      this.refreshUpgrades();
    }
  }

  // ====================== 调试面板 ======================

  private openDebug(): void {
    const items: DebugItem[] = [];
    for (const t of DEBUG_TUNABLES) {
      items.push({
        key: t.key, label: t.label, min: t.min, max: t.max, step: t.step,
        value: getConstValue(t.key), timing: t.timing
      });
    }
    this.debugItems = items;
    this.debugAllPlants = SaveData.debugAllPlants;
    this.dialog = 'debug';
  }

  /** 调试参数显示值：浮点步进参数保留两位小数，整数不显示小数点 */
  private formatDebugValue(item: DebugItem): string {
    return item.step < 1 ? item.value.toFixed(2) : `${item.value}`;
  }

  /** 调试开关：全部植物无视关卡进度解锁（卡槽上限也忽略） */
  private toggleAllPlants(): void {
    SaveData.debugAllPlants = !SaveData.debugAllPlants;
    SaveData.save();
    this.debugAllPlants = SaveData.debugAllPlants;
  }

  /** 拖动滑条：热写 GAME_CONST（下一关/重开生效）并刷新面板 */
  private applyDebugValue(key: string, raw: number): void {
    const idx: number = this.debugItems.findIndex((it: DebugItem) => it.key === key);
    if (idx < 0) return;
    const item: DebugItem = this.debugItems[idx];
    // 浮点步进（僵尸移速 0.01）按两位小数取整，避免 0.19200000001
    const value: number = item.step < 1 ? Math.round(raw * 100) / 100 : Math.round(raw);
    setConstValue(key, value);
    const updated: DebugItem = {
      key: item.key, label: item.label, min: item.min, max: item.max, step: item.step,
      value: value, timing: item.timing
    };
    const next: DebugItem[] = this.debugItems.slice();
    next[idx] = updated;
    this.debugItems = next;
  }

  /** 一键解锁全部关卡（白天 1-10 + 夜晚 2-10，跳过挑战信） */
  private unlockAllLevels(): void {
    SaveData.dayBeaten = 10;
    SaveData.nightBeaten = 10;
    SaveData.letterSeen = true;
    SaveData.letterPending = false;
    SaveData.save();
    this.refresh();
  }

  /** 恢复全部调试参数默认值 */
  private resetDebugDefaults(): void {
    for (const t of DEBUG_TUNABLES) {
      setConstValue(t.key, DEBUG_DEFAULTS[t.key]);
    }
    this.openDebug(); // 重新按默认值构建面板
  }

  private startGame(): void {
    if (this.entering) return;
    this.startLevel(this.selectedLevel);
  }

  /** 进入指定关卡（商店"下一关/重玩本关"直达按钮与主页开始按钮共用） */
  private startLevel(levelId: string): void {
    if (this.entering) return;
    const cfg = getLevelConfig(levelId);
    if (cfg === null) return;
    if (!SaveData.isLevelUnlocked(levelId)) return;
    this.entering = true;
    if (cfg.conveyor) {
      // 1-10 传送带关：不选卡直接开始（同原版）
      router.pushUrl({ url: 'pages/Index', params: { level: levelId } });
    } else if (cfg.unlocks.length > SaveData.slots) {
      // 解锁植物数超过卡槽数 → 先选卡（同原版）
      router.pushUrl({ url: 'pages/SelectPage', params: { level: levelId } });
    } else {
      router.pushUrl({ url: 'pages/Index', params: { level: levelId } });
    }
  }

  /** 商店直达按钮：胜利 → 下一关（1-10 → 2-1，2-10 后无）；失败 → 重玩本关 */
  private shopNextLevel(): string {
    const parts: string[] = this.shopReturnLevel.split('-');
    if (parts.length !== 2) return '';
    const chapter: number = Number(parts[0]);
    const index: number = Number(parts[1]);
    if (chapter === 1) {
      return index >= 10 ? '2-1' : `1-${index + 1}`;
    }
    if (chapter === 2) {
      return index >= 10 ? '' : `2-${index + 1}`;
    }
    return '';
  }

  @Builder
  LevelChip(lv: LevelConfig) {
    Text(lv.id)
      .width(58)
      .height(40)
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .textAlign(TextAlign.Center)
      .fontColor(this.selectedLevel === lv.id ? '#1b5e20'
        : (this.levelTick >= 0 && SaveData.isLevelUnlocked(lv.id) ? '#c8e6a0' : '#5a6b4a'))
      .backgroundColor(this.selectedLevel === lv.id ? '#aed581'
        : (this.levelTick >= 0 && SaveData.isLevelUnlocked(lv.id) ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.3)'))
      .borderRadius(8)
      .border({ width: 2, color: this.selectedLevel === lv.id ? '#7cb342' : 'rgba(255,255,255,0.15)' })
      .onClick(() => {
        if (SaveData.isLevelUnlocked(lv.id)) {
          this.selectedLevel = lv.id;
        }
      })
  }

  @Builder
  UpgradeRow(item: UpgradeItem) {
    Column({ space: 4 }) {
      Text(`${item.label}${item.tier === 2 ? '（已满级）' : item.tier === 1 ? `（已购1级，升级$${UPGRADE_T2_PRICE}）` : `（1级 $${UPGRADE_T1_PRICE}）`}`)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#eaf5d8')
      Text(item.tier >= 2 ? item.desc : `1级：${UPGRADE_DESC[item.key][0]}　2级：${UPGRADE_DESC[item.key][1]}`)
        .fontSize(11)
        .fontColor('#9fc46f')
        .lineHeight(16)
      if (item.tier === 0) {
        Button(this.coins >= UPGRADE_T1_PRICE ? `购买  $${UPGRADE_T1_PRICE}` : '金币不足')
          .width(150).height(34).fontSize(14).fontWeight(FontWeight.Bold)
          .backgroundColor(this.coins >= UPGRADE_T1_PRICE ? '#3d8b28' : '#555555')
          .fontColor('#ffffff').borderRadius(17)
          .onClick(() => {
            this.buyUpgrade(item.key, 1);
          })
      } else if (item.tier === 1) {
        Button(this.coins >= UPGRADE_T2_PRICE ? `升级2级  $${UPGRADE_T2_PRICE}` : '金币不足')
          .width(150).height(34).fontSize(14).fontWeight(FontWeight.Bold)
          .backgroundColor(this.coins >= UPGRADE_T2_PRICE ? '#3d8b28' : '#555555')
          .fontColor('#ffffff').borderRadius(17)
          .onClick(() => {
            this.buyUpgrade(item.key, 2);
          })
      } else {
        Text('已升满2级（替换1级效果）')
          .fontSize(12)
          .fontColor('#aed581')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack() {
      // 纯色背景
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#1C2F0B')

      Column()
        .width('100%')
        .height('26%')
        .backgroundColor('#2E5118')
        .position({ x: 0, y: '37%' })

      Column() {
        // ===== 标题 =====
        Text('pvz简单版')
          .fontSize(56)
          .fontWeight(FontWeight.Bold)
          .fontColor('#eaf5d8')
          .shadow({ radius: 6, color: 'rgba(0,0,0,0.6)', offsetX: 3, offsetY: 3 })
          .margin({ top: '5%' })

        // ===== 金币 + 设置 + 商店 =====
        Row({ space: 12 }) {
          Text(`$${this.coins}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffd700')
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .backgroundColor('rgba(0,0,0,0.35)')
            .borderRadius(18)
          Button('设置')
            .height(38)
            .fontSize(16)
            .backgroundColor('rgba(255,255,255,0.15)')
            .fontColor('#eaf5d8')
            .onClick(() => {
              this.refresh();
              this.dialog = 'settings';
            })
          Button('商店')
            .height(38)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#8d6e63')
            .fontColor('#ffffff')
            .onClick(() => {
              // 普通入口：清空结算页带来的直达状态
              this.shopReturnLevel = '';
              this.shopReturnResult = '';
              this.openShop();
            })
          Button('图鉴')
            .height(38)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#00695c')
            .fontColor('#ffffff')
            .onClick(() => {
              this.dialog = 'almanac';
            })
          Button('调试')
            .height(38)
            .fontSize(16)
            .backgroundColor('rgba(255,255,255,0.15)')
            .fontColor('#ffd54a')
            .onClick(() => {
              this.openDebug();
            })
        }
        .margin({ top: 12 })

        // ===== 白天关卡 1-1 ~ 1-10 =====
        Text('白天冒险（通关解锁下一关）')
          .fontSize(14)
          .fontColor('#8ba760')
          .margin({ top: '3%', bottom: 8 })
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(LEVELS, (lv: LevelConfig) => {
            if (lv.chapter === 1) {
              this.LevelChip(lv)
            }
          }, (lv: LevelConfig) => `d${lv.id}`)
        }
        .width('92%')

        // ===== 夜晚关卡 2-1 ~ 2-10 =====
        Text('黑夜（1-10 通关后解锁）')
          .fontSize(14)
          .fontColor('#8ba760')
          .margin({ top: 10, bottom: 8 })
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(LEVELS, (lv: LevelConfig) => {
            if (lv.chapter === 2) {
              this.LevelChip(lv)
            }
          }, (lv: LevelConfig) => `n${lv.id}`)
        }
        .width('92%')

        Blank()

        Button('开始游戏')
          .width('52%')
          .height(54)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')
          .backgroundColor(SaveData.isLevelUnlocked(this.selectedLevel) ? '#3d8b28' : '#555555')
          .borderRadius(27)
          .border({ width: 3, color: '#255512' })
          .shadow({ radius: 10, color: 'rgba(0,0,0,0.4)', offsetX: 0, offsetY: 4 })
          .margin({ bottom: '6%' })
          .onClick(() => this.startGame())
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)

      // ====================== 弹窗层 ======================
      if (this.dialog === 'letter') {
        // 僵王挑战信（1-9 通关后）
        Column({ space: 14 }) {
          Text('✉ 一封挑战信')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#eaf5d8')
          Text('致草坪主人：\n\n你的草地守得不错。但僵王博士向你发出正式邀请——\n第 1-10 关，植物将由传送带随机供应，\n不必选卡，无法携带向日葵与土豆。\n\n敢来吗？\n\n—— 僵王博士')
            .fontSize(17)
            .fontColor('#c8e6a0')
            .lineHeight(26)
            .textAlign(TextAlign.Center)
          Button('应战！')
            .width(160).height(46).fontSize(18).fontWeight(FontWeight.Bold)
            .backgroundColor('#3d8b28').fontColor('#ffffff').borderRadius(23)
            .onClick(() => {
              SaveData.letterSeen = true;
              SaveData.save();
              this.dialog = 'none';
            })
        }
        .width('88%')
        .constraintSize({ maxWidth: 560 })
        .padding(20)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#2E5118')
        .borderRadius(16)
        .border({ width: 3, color: '#7cb342' })
      }

      if (this.dialog === 'settings') {
        // 设置：音量调节
        Column({ space: 12 }) {
          Text('设置')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#eaf5d8')
          Text(`背景音乐　${this.bgmSlider}%`)
            .fontSize(15).fontColor('#9fc46f')
          Slider({ value: this.bgmSlider, min: 0, max: 100, step: 1 })
            .width(260)
            .onChange((value: number) => {
              this.bgmSlider = Math.round(value);
              SaveData.bgmVol = this.bgmSlider / 100;
              SaveData.save();
            })
          Text(`游戏音效　${this.sfxSlider}%`)
            .fontSize(15).fontColor('#9fc46f')
          Slider({ value: this.sfxSlider, min: 0, max: 100, step: 1 })
            .width(260)
            .onChange((value: number) => {
              this.sfxSlider = Math.round(value);
              SaveData.sfxVol = this.sfxSlider / 100;
              SaveData.save();
            })
          Button('完成')
            .width(120).height(42).fontSize(16)
            .backgroundColor('#3d8b28').fontColor('#ffffff').borderRadius(21)
            .onClick(() => {
              this.dialog = 'none';
            })
          Text('音量保存后，进入游戏或游戏内暂停菜单调整即时生效')
            .fontSize(11)
            .fontColor('#6f8a4b')
        }
        .width('88%')
        .constraintSize({ maxWidth: 480 })
        .padding(20)
        .backgroundColor('#2E5118')
        .borderRadius(16)
        .border({ width: 3, color: '#7cb342' })
      }

      if (this.dialog === 'shop') {
        // 商店：卡槽 + 坚果包扎术 + 强化体系（可滚动）
        Column({ space: 10 }) {
          Text('戴夫商店')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#eaf5d8')
          Text(`金币：$${this.coins}`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffd700')

          Scroll() {
            Column({ space: 12 }) {
              // ===== 卡槽 =====
              Text(`当前卡槽：${this.slots} 个`)
                .fontSize(15)
                .fontColor('#c8e6a0')
              if (SaveData.nextSlotPrice() < 0) {
                Text('卡槽已全部解锁！')
                  .fontSize(14)
                  .fontColor('#9fc46f')
              } else {
                Text(`解锁第 ${this.slots + 1} 个卡槽需要 $${SaveData.nextSlotPrice()}`)
                  .fontSize(14)
                  .fontColor('#c8e6a0')
                  .textAlign(TextAlign.Center)
                Button(this.coins >= SaveData.nextSlotPrice() ? '购买' : '金币不足')
                  .width(150).height(38).fontSize(15).fontWeight(FontWeight.Bold)
                  .backgroundColor(this.coins >= SaveData.nextSlotPrice() ? '#3d8b28' : '#555555')
                  .fontColor('#ffffff').borderRadius(19)
                  .onClick(() => {
                    if (SaveData.buySlot() > 0) {
                      this.refresh();
                    }
                  })
              }

              // ===== 小推车（一次性永久购买） =====
              Divider().color('rgba(255,255,255,0.15)')
              Column({ space: 4 }) {
                Text('小推车')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#eaf5d8')
                Text('每行草坪一辆，僵尸抵达最左侧时自动出击、清空整行僵尸（每关开始重新就位）')
                  .fontSize(11)
                  .fontColor('#9fc46f')
                  .lineHeight(16)
                Text(`售价 $${MOWER_PRICE}`)
                  .fontSize(12)
                  .fontColor('#ffd700')
                if (this.mowerOwned) {
                  Text('已拥有：每关开始时草坪左侧自动就位')
                    .fontSize(12)
                    .fontColor('#aed581')
                } else {
                  Button(this.coins >= MOWER_PRICE ? `购买  $${MOWER_PRICE}` : '金币不足')
                    .width(150).height(34).fontSize(14).fontWeight(FontWeight.Bold)
                    .backgroundColor(this.coins >= MOWER_PRICE ? '#3d8b28' : '#555555')
                    .fontColor('#ffffff').borderRadius(17)
                    .onClick(() => {
                      if (SaveData.buyMower()) {
                        this.refresh();
                      }
                    })
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)

              // ===== 强化体系（1级$250 / 2级$300，买2替换1） =====
              Divider().color('rgba(255,255,255,0.15)')
              ForEach(this.upgradeList, (item: UpgradeItem) => {
                this.UpgradeRow(item)
              }, (item: UpgradeItem) => `${item.key}_${item.tier}`)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .align(Alignment.Top)

          // ===== 从结算页进商店：直达下一关 / 重玩本关 =====
          if (this.shopReturnLevel !== '' && this.shopReturnResult === 'win'
            && this.shopNextLevel() !== '') {
            Button(`前往下一关 ${this.shopNextLevel()}`)
              .width('100%').height(44).fontSize(16).fontWeight(FontWeight.Bold)
              .backgroundColor('#3d8b28').fontColor('#ffffff').borderRadius(22)
              .onClick(() => {
                this.dialog = 'none';
                this.startLevel(this.shopNextLevel());
              })
          } else if (this.shopReturnLevel !== '' && this.shopReturnResult === 'lose') {
            Button(`重新游玩本关 ${this.shopReturnLevel}`)
              .width('100%').height(44).fontSize(16).fontWeight(FontWeight.Bold)
              .backgroundColor('#ff7043').fontColor('#ffffff').borderRadius(22)
              .onClick(() => {
                this.dialog = 'none';
                this.startLevel(this.shopReturnLevel);
              })
          }

          Button('关闭')
            .width(120).height(40).fontSize(15)
            .backgroundColor('rgba(255,255,255,0.15)').fontColor('#eaf5d8').borderRadius(20)
            .onClick(() => {
              this.dialog = 'none';
            })
        }
        .width('90%')
        .constraintSize({ maxWidth: 640 })
        .height('88%')
        .padding(18)
        .backgroundColor('#2E5118')
        .borderRadius(16)
        .border({ width: 3, color: '#8d6e63' })
      }

      if (this.dialog === 'almanac') {
        // 图鉴：植物 + 僵尸资料（2-4 通关掉落解锁）
        Column({ space: 12 }) {
          Text('图 鉴')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffd54a')
          if (SaveData.almanacUnlocked) {
            AlmanacView()
              .layoutWeight(1)
          } else {
            Column({ space: 10 }) {
              Text('🔒 图鉴尚未解锁')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#ffe082')
              Text('通关 2-4（黑夜第四关）后，最后一只僵尸会掉落图鉴')
                .fontSize(15)
                .fontColor('#fff8e1')
                .textAlign(TextAlign.Center)
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          }
          Button('返回')
            .width(120).height(42).fontSize(16)
            .backgroundColor('#3d8b28').fontColor('#ffffff').borderRadius(21)
            .onClick(() => {
              this.dialog = 'none';
            })
        }
        .width('88%')
        .height('76%')
        .constraintSize({ maxWidth: 520 })
        .padding(16)
        .backgroundColor('#2E5118')
        .borderRadius(16)
        .border({ width: 3, color: '#7cb342' })
      }

      if (this.dialog === 'debug') {
        // 调试面板：一键解锁关卡 + 参数热调 + 恢复默认
        Column({ space: 10 }) {
          Text('调试面板')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffd54a')

          Button('一键解锁全部关卡')
            .width('100%').height(42).fontSize(16).fontWeight(FontWeight.Bold)
            .backgroundColor('#3d8b28').fontColor('#ffffff').borderRadius(21)
            .onClick(() => {
              this.unlockAllLevels();
            })

          Button('增加金钱 +$500')
            .width('100%').height(42).fontSize(16).fontWeight(FontWeight.Bold)
            .backgroundColor('#f9a825').fontColor('#1b5e20').borderRadius(21)
            .onClick(() => {
              SaveData.addCoins(500);
              this.refresh();
            })

          Button('清空金钱（$0）')
            .width('100%').height(42).fontSize(16).fontWeight(FontWeight.Bold)
            .backgroundColor('rgba(255,255,255,0.15)').fontColor('#ef9a9a').borderRadius(21)
            .onClick(() => {
              SaveData.coins = 0;
              SaveData.save();
              this.refresh();
            })

          Button(this.debugAllPlants ? '全部植物解锁：开（点此关闭）' : '一键解锁全部植物：关（点此开启）')
            .width('100%').height(42).fontSize(16).fontWeight(FontWeight.Bold)
            .backgroundColor(this.debugAllPlants ? '#ffd54a' : 'rgba(255,255,255,0.15)')
            .fontColor(this.debugAllPlants ? '#1b5e20' : '#ffd54a')
            .borderRadius(21)
            .onClick(() => {
              this.toggleAllPlants();
            })

          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.debugItems, (item: DebugItem) => {
                Column({ space: 2 }) {
                  Row({ space: 6 }) {
                    Text(item.label)
                      .fontSize(14)
                      .fontColor('#c8e6a0')
                      .layoutWeight(1)
                    Text(item.timing === 'now' ? '立即' : '下关')
                      .fontSize(10)
                      .fontColor(item.timing === 'now' ? '#aed581' : '#ffb74d')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor('rgba(0,0,0,0.3)')
                      .borderRadius(6)
                    Text(this.formatDebugValue(item))
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#ffd54a')
                  }
                  .width('100%')
                  Slider({ value: item.value, min: item.min, max: item.max, step: item.step })
                    .width('100%')
                    .onChange((value: number) => {
                      this.applyDebugValue(item.key, value);
                    })
                }
                .width('100%')
              }, (item: DebugItem) => `${item.key}_${item.value}`)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .align(Alignment.Top)

          Text('「立即」：下次触发即生效（新刷僵尸/下一发子弹/下一次刷怪）\n「下关」：重开本关或进入下一关后生效')
            .fontSize(12)
            .fontColor('#6f8a4b')

          Row({ space: 12 }) {
            Button('恢复默认设置')
              .width(150).height(42).fontSize(16).fontWeight(FontWeight.Bold)
              .backgroundColor('#b71c1c').fontColor('#ffffff').borderRadius(21)
              .onClick(() => {
                this.resetDebugDefaults();
              })
            Button('关闭')
              .width(110).height(42).fontSize(16)
              .backgroundColor('rgba(255,255,255,0.15)').fontColor('#eaf5d8').borderRadius(21)
              .onClick(() => {
                this.dialog = 'none';
              })
          }
        }
        .width('90%')
        .constraintSize({ maxWidth: 560 })
        .height('86%')
        .padding(18)
        .backgroundColor('#2E5118')
        .borderRadius(16)
        .border({ width: 3, color: '#ffd54a' })
      }
    }
    .width('100%')
    .height('100%')
  }
}
