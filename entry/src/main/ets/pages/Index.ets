/**
 * 游戏页面：Canvas 承载、点击事件分发、定时器、@State 与引擎的状态桥接
 * 顶部右上角：金币计数 + 铲子按钮（不占卡槽）+ 暂停按钮（最右上角）
 * 暂停菜单：继续 / 重新开始 / 返回主菜单 / BGM 与音效音量调节
 */
import { GAME_CONST, SelectItem, PLANT_INTRO, ZOMBIE_INTRO, getNextLevelId } from '../game/GameTypes';
import { getLevelConfig, getAllPlantsForLevel } from '../game/GameTypes';
import { GameEngine } from '../game/GameEngine';
import { renderGame } from '../game/GameRenderer';
import { createCardsForLevel, findCardAt, findConveyorAt, calcCardPanelWidth, getCardVisual } from '../game/CardFactory';
import { BgmPlayer } from '../game/BgmPlayer';
import { SaveData } from '../game/SaveData';
import { AlmanacView } from './AlmanacView';
import { router } from '@kit.ArkUI';

/** 开始页/选卡页传入的启动参数 */
interface StartParams {
  level: string;
  seeds?: string[];
}

/** 倍速选项（1.5 / 2 / 4 倍） */
const SPEED_OPTIONS: number[] = [1, 1.5, 2, 4];

@Entry
@Component
struct VerticalTDGame {
  // ====================== 画布 ======================
  private context: CanvasRenderingContext2D | null = null;
  @State canvasW: number = 0;
  @State canvasH: number = 0;

  // ====================== 游戏引擎（非状态，普通对象） ======================
  private engine: GameEngine = new GameEngine();
  private levelId: string = '1-1';

  // ====================== 需要驱动 UI 的状态（每帧从引擎同步） ======================
  @State gameOver: boolean = false;
  @State victory: boolean = false;
  @State showAlmanac: boolean = false; // 结算页图鉴浮层
  @State selectedPlant: string = "";
  @State sun: number = 100;
  @State speedMult: number = 1;
  @State paused: boolean = true;
  @State coins: number = 0;
  @State bgmSlider: number = 60;
  @State sfxSlider: number = 100;
  // ===== 关卡开始前的僵尸情报预览 =====
  @State zombiePreview: boolean = true;
  @State zombieRoster: string[] = [];

  private timerId: number = -1;
  private victorySaved: boolean = false; // 防止重复记通关
  private leftPanelW: number = 0;        // 左侧卡片区宽度（随屏幕高度自适应，点击判定与草坪定位共用）

  // ====================== 背景音乐 ======================
  private bgm: BgmPlayer = new BgmPlayer();

  // ====================== 卡片配置 ======================
  private cards: SelectItem[] = [];

  aboutToAppear(): void {
    const settings: RenderingContextSettings = new RenderingContextSettings(true);
    this.context = new CanvasRenderingContext2D(settings);

    // 关卡参数：开始页/选卡页传入关卡 id 与选中的植物
    const params = router.getParams() as StartParams;
    this.levelId = (params && params.level) ? params.level : '1-1';
    const cfg = getLevelConfig(this.levelId);
    // 小推车状态需在 setLevel 之前注入（setLevel 内会按行数初始化每行推车就位）
    this.engine.mowerEnabled = SaveData.mowerOwned;
    if (cfg !== null) {
      this.engine.setLevel(cfg);
    }
    if (this.engine.conveyor) {
      // 传送带关：显示配方袋内植物的卡面样式（颜色/名字），点击选中后免费种植
      const bagKeys: string[] = GAME_CONST.CONVEYOR_BAG;
      const poolKeys: string[] = [];
      for (const k of bagKeys) {
        let dup: boolean = false;
        for (const p of poolKeys) {
          if (p === k) {
            dup = true;
            break;
          }
        }
        if (!dup) {
          poolKeys.push(k);
        }
      }
      this.cards = createCardsForLevel(poolKeys, false);
    } else if (SaveData.debugAllPlants && cfg !== null) {
      // 调试模式：无视关卡进度与卡槽上限，全部植物直接可用
      this.cards = createCardsForLevel(getAllPlantsForLevel(cfg.night), cfg.night);
    } else if (params && params.seeds && params.seeds.length > 0) {
      // 选卡模式：只显示玩家选中的植物
      const all: SelectItem[] = createCardsForLevel(cfg !== null ? cfg.unlocks : [], cfg !== null ? cfg.night : false);
      const chosen: SelectItem[] = [];
      for (const key of params.seeds) {
        for (const c of all) {
          if (c.key === key) {
            chosen.push(c);
            break;
          }
        }
      }
      this.cards = chosen;
    } else {
      this.cards = createCardsForLevel(cfg !== null ? cfg.unlocks : [], cfg !== null ? cfg.night : false);
    }

    // 音量：从存档读取并应用（用户要求初始音效更大，SoundFx 默认因子已上调）
    this.bgmSlider = Math.round(SaveData.bgmVol * 100);
    this.sfxSlider = Math.round(SaveData.sfxVol * 100);
    this.bgm.setVolume(SaveData.bgmVol);
    this.engine.sfx.setVolume(SaveData.sfxVol);
    // 商店坚果包扎术状态同步给引擎
    this.engine.wallFirstAid = SaveData.wallFirstAid;
    // 商店强化等级表注入引擎（同一 Map 引用，商店购买后即时生效）
    this.engine.upgrades = SaveData.upgrades;

    // 金币：引擎回调 → 立即入账存档
    this.coins = SaveData.coins;
    this.engine.onCoinGain = (value: number): void => {
      this.coins = SaveData.addCoins(value);
    };

    // 开始播放背景音乐（异步）+ 预加载音效
    this.bgm.init(getContext(this));
    this.engine.sfx.init(getContext(this));
    // 关卡开始前：展示本关登场僵尸情报，玩家点"开始战斗"后才进入游戏
    this.zombieRoster = this.engine.getZombieRoster();
  }

  /** 僵尸情报预览点"开始战斗"：关闭预览、解除暂停并播报开局音效 */
  startBattle(): void {
    this.zombiePreview = false;
    this.paused = false;
    setTimeout(() => {
      this.engine.sfx.play('readysetplant');
    }, 300);
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    this.bgm.stop();
    this.engine.sfx.release();
  }

  onPageShow(): void {
    this.bgm.resume();
  }

  onPageHide(): void {
    // 切到后台自动暂停：后台定时器可能被系统冻结，回来后由玩家手动继续
    this.bgm.pause();
    if (!this.gameOver && !this.victory) {
      this.paused = true;
    }
  }

  resetGame(): void {
    this.engine.reset();
    this.selectedPlant = "";
    this.sun = this.engine.sun;
    this.gameOver = this.engine.gameOver;
    this.victory = this.engine.victory;
    this.victorySaved = false;
    this.paused = false;
    setTimeout(() => {
      this.engine.sfx.play('readysetplant');
    }, 400);
  }

  /** 下一关 id（与解锁掉卡共用 GameTypes.getNextLevelId） */
  private getNextLevel(): string {
    return getNextLevelId(this.levelId);
  }

  /** 胜利后进入下一关：replaceUrl 替换当前页，避免返回栈越叠越深 */
  private goNextLevel(): void {
    const next: string = this.getNextLevel();
    if (next === '') return;
    const cfg = getLevelConfig(next);
    if (cfg === null) return;
    const params: StartParams = { level: next };
    if (!cfg.conveyor && cfg.unlocks.length > SaveData.slots) {
      // 解锁植物多于卡槽 → 先选卡
      router.replaceUrl({ url: 'pages/SelectPage', params: params });
    } else {
      router.replaceUrl({ url: 'pages/Index', params: params });
    }
  }

  /** 结算页前往商店：回到主页并自动弹出商店（携带来源关卡与胜负，商店内可直达下一关/重玩本关） */
  private goShop(): void {
    router.replaceUrl({
      url: 'pages/StartPage',
      params: { openShop: true, shopLevelId: this.levelId, shopResult: this.victory ? 'win' : 'lose' }
    });
  }

  gameLoop(): void {
    if (!this.context) return;
    if (this.canvasW <= 0 || this.canvasH <= 0) return;

    // 暂停时不推进逻辑，但仍重绘（暂停菜单是 ArkUI 浮层，画布保持最后一帧即可）
    if (!this.paused) {
      this.engine.update();
    }
    renderGame(this.context, this.engine, this.cards, this.selectedPlant);
    this.sun = this.engine.sun;
    this.gameOver = this.engine.gameOver;
    this.victory = this.engine.victory;
    // 通关：写存档（每关只记一次）；首次通关有金币奖励，同步刷新金币显示
    if (this.victory && !this.victorySaved) {
      this.victorySaved = true;
      SaveData.markWon(this.levelId);
      // 1-9 通关：挑战信在胜利结算页直接展示，标记已读（不再回主页重复弹）
      if (this.levelId === '1-9') {
        SaveData.letterSeen = true;
      }
      SaveData.save();
      this.coins = SaveData.coins;
    }
  }

  /** 1-9 通关 → 胜利结算页直接展示僵王挑战信（替换普通胜利文案，按钮与胜利一致） */
  private isLetterVictory(): boolean {
    return this.levelId === '1-9' && SaveData.letterPending;
  }

  /** 解锁结算标题：铲子/挑战书/图鉴各有专属文案，其余为新植物 */
  private unlockTitle(key: string): string {
    if (key === 'shovel') return "你得到了一把铲子！";
    if (key === 'letter') return "你收到了一封挑战书！";
    if (key === 'almanac') return "你得到了一本图鉴！";
    return "你得到了一株新植物！";
  }

  onCanvasClick(event: ClickEvent): void {
    if (this.gameOver || this.victory || this.paused) return;
    if (this.canvasW <= 0 || this.canvasH <= 0) return;

    // 1. 优先拾取金币（存档货币）
    if (this.engine.collectCoinAt(event.x, event.y)) {
      return;
    }
    // 2. 收集阳光（夜晚来自阳光菇）
    if (this.engine.collectSunAt(event.x, event.y)) {
      return;
    }
    // 3. 左侧卡片区：传送带取植物 / 卡片栏选卡（两列纵向面板）
    if (event.x <= this.leftPanelW) {
      if (this.engine.conveyor) {
        // 传送带：点击只选中/取消选中（卡片保留在带上），种植成功后才销毁
        const idx: number = findConveyorAt(this.engine.conveyorItems, event.x, event.y, this.canvasH);
        if (idx >= 0) {
          this.engine.selectConveyorAt(idx);
          this.selectedPlant = this.engine.conveyorSelected >= 0
            ? this.engine.conveyorItems[this.engine.conveyorSelected].key : "";
        } else {
          this.engine.conveyorSelected = -1;
          this.selectedPlant = "";
        }
        return;
      }
      const item = findCardAt(this.cards, event.x, event.y, this.canvasH);
      if (item === null) {
        this.selectedPlant = "";
      } else if (item.key !== "" && this.engine.isCardReady(item.key) && this.sun >= item.cost) {
        if (this.selectedPlant === item.key) {
          this.selectedPlant = "";
        } else {
          this.selectedPlant = item.key;
          this.engine.sfx.play('seedlift');
        }
      }
      return;
    }
    // 4. 网格区域：种植 / 铲除
    const handled = this.engine.handleGridClick(event.x, event.y, this.selectedPlant);
    if (handled) {
      // 传送带关：种植成功才销毁选中的卡片
      if (this.engine.conveyor && this.engine.conveyorSelected >= 0) {
        this.engine.takeSelectedConveyorItem();
      }
      this.selectedPlant = "";
    }
  }

  build() {
    Stack() {
      Canvas(this.context)
        .width('100%')
        .height('100%')
        .onClick((e: ClickEvent) => this.onCanvasClick(e))

      // ====================== 右上角：金币 + 铲子 + 暂停 ======================
      Row({ space: 8 }) {
        // 金币计数（僵尸掉落，商店可用）
        Text(`$${this.coins}`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffd700')
          .backgroundColor('rgba(0,0,0,0.45)')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(16)

        // 铲子按钮（不占卡槽，固定右上；1-4 起解锁）
        if (this.engine.shovelEnabled) {
          Button('铲')
            .width(44)
            .height(44)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.selectedPlant === 'shovel' ? '#607d8b' : '#ffffff')
            .backgroundColor(this.selectedPlant === 'shovel' ? '#ffd700' : '#546e7a')
            .borderRadius(10)
            .onClick(() => {
              this.selectedPlant = this.selectedPlant === 'shovel' ? '' : 'shovel';
              this.engine.sfx.play('seedlift');
            })
        }

        // 暂停按钮（最右上角）
        Button('II')
          .width(44)
          .height(44)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')
          .backgroundColor('rgba(0,0,0,0.55)')
          .borderRadius(10)
          .onClick(() => {
            this.paused = true;
          })
      }
      .position({ x: '100%', y: 8 })
      .markAnchor({ x: '100%', y: 0 })
      .margin({ right: 10 })

      // ====================== 倍速控制（右下角悬浮） ======================
      Row({ space: 6 }) {
        ForEach(SPEED_OPTIONS, (opt: number) => {
          Button(`${opt}x`)
            .height(32)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.speedMult === opt ? "#1b5e20" : "#ffffff")
            .backgroundColor(this.speedMult === opt ? "#aed581" : "rgba(0,0,0,0.5)")
            .borderRadius(16)
            .onClick(() => {
              this.speedMult = opt;
              this.engine.speedMult = opt;
            })
        }, (opt: number) => `${opt}`)
      }
      .position({ x: '100%', y: '100%' })
      .markAnchor({ x: '100%', y: '100%' })
      .margin({ right: 12, bottom: 12 })

      // ====================== 僵尸情报预览（每关开始前展示本关登场僵尸） ======================
      if (this.zombiePreview && !this.gameOver && !this.victory) {
        Column({ space: 12 }) {
          Text('僵尸来袭！')
            .fontSize(Math.max(26, Math.round(this.canvasH * 0.055)))
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffd54a')
          Text(`${this.levelId}　本关登场僵尸情报`)
            .fontSize(Math.max(14, Math.round(this.canvasH * 0.024)))
            .fontColor('#c5e1a5')
          Scroll() {
            Column({ space: 10 }) {
              ForEach(this.zombieRoster, (k: string) => {
                Row({ space: 12 }) {
                  Text(ZOMBIE_INTRO[k] !== undefined ? ZOMBIE_INTRO[k].name : k)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#101010')
                    .backgroundColor(ZOMBIE_INTRO[k] !== undefined ? ZOMBIE_INTRO[k].color : '#757575')
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .borderRadius(8)
                  Text(ZOMBIE_INTRO[k] !== undefined ? ZOMBIE_INTRO[k].desc : '')
                    .fontSize(15)
                    .fontColor('#eaf5d8')
                    .layoutWeight(1)
                }
                .width('92%')
                .padding(8)
                .backgroundColor('rgba(255,255,255,0.07)')
                .borderRadius(10)
              }, (k: string) => k)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)

          Button('开始战斗！')
            .width(220).height(50).fontSize(20).fontWeight(FontWeight.Bold)
            .backgroundColor('#7cb342').fontColor('#ffffff').borderRadius(25)
            .onClick(() => this.startBattle())
        }
        .width('100%')
        .height('100%')
        .padding({ top: 30, bottom: 24 })
        .backgroundColor('rgba(0,0,0,0.84)')
      }

      // ====================== 暂停菜单 ======================
      if (this.paused && !this.zombiePreview && !this.gameOver && !this.victory) {
        Column({ space: 14 }) {
          Text('已暂停')
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#eaf5d8')

          Button('继续游戏')
            .width(200).height(46).fontSize(18).fontWeight(FontWeight.Bold)
            .backgroundColor('#3d8b28').fontColor('#ffffff').borderRadius(23)
            .onClick(() => {
              this.paused = false;
            })

          Button('重新开始')
            .width(200).height(46).fontSize(18)
            .backgroundColor('rgba(255,255,255,0.15)').fontColor('#eaf5d8').borderRadius(23)
            .onClick(() => {
              this.resetGame();
            })

          Button('返回主菜单')
            .width(200).height(46).fontSize(18)
            .backgroundColor('rgba(255,255,255,0.15)').fontColor('#eaf5d8').borderRadius(23)
            .onClick(() => {
              router.back();
            })

          // ===== 音量设置 =====
          Column({ space: 6 }) {
            Text(`背景音乐　${this.bgmSlider}%`)
              .fontSize(15).fontColor('#9fc46f')
            Slider({ value: this.bgmSlider, min: 0, max: 100, step: 1 })
              .width(260)
              .onChange((value: number) => {
                this.bgmSlider = Math.round(value);
                SaveData.bgmVol = this.bgmSlider / 100;
                this.bgm.setVolume(SaveData.bgmVol);
                SaveData.save();
              })
            Text(`游戏音效　${this.sfxSlider}%`)
              .fontSize(15).fontColor('#9fc46f')
            Slider({ value: this.sfxSlider, min: 0, max: 100, step: 1 })
              .width(260)
              .onChange((value: number) => {
                this.sfxSlider = Math.round(value);
                SaveData.sfxVol = this.sfxSlider / 100;
                this.engine.sfx.setVolume(SaveData.sfxVol);
                SaveData.save();
              })
          }
          .margin({ top: 10 })
          .padding(14)
          .backgroundColor('rgba(0,0,0,0.35)')
          .borderRadius(12)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0,0,0,0.75)')
      }

      // ====================== 失败结算 ======================
      if (this.gameOver) {
        Column({ space: 16 }) {
          Text("游戏失败")
            .fontSize(Math.max(28, Math.round(this.canvasH * 0.08)))
            .fontWeight(FontWeight.Bold)
            .fontColor("#ff4444")
          Text("打不过？去商店买个强化再战！")
            .fontSize(Math.max(14, Math.round(this.canvasH * 0.028)))
            .fontColor("#ffe0b2")
          Row({ space: 14 }) {
            Button("再来一次")
              .width(140).height(48).fontSize(18).fontWeight(FontWeight.Bold)
              .backgroundColor("#ff4444").fontColor("#ffffff").borderRadius(24)
              .onClick(() => this.resetGame())
            Button("前往商店")
              .width(140).height(48).fontSize(18)
              .backgroundColor("#8d6e63").fontColor("#ffffff").borderRadius(24)
              .onClick(() => this.goShop())
            Button("返回主菜单")
              .width(140).height(48).fontSize(18)
              .backgroundColor("rgba(255,255,255,0.2)").fontColor("#ffffff").borderRadius(24)
              .onClick(() => router.back())
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      // ====================== 胜利结算 ======================
      if (this.victory) {
        Column({ space: 14 }) {
          if (this.engine.dropCardKey !== '') {
            // ===== 解锁结算（原版式）：掉落物大卡 + 名称 + 介绍（植物/铲子/挑战书/图鉴通用） =====
            Text(this.unlockTitle(this.engine.dropCardKey))
              .fontSize(Math.max(26, Math.round(this.canvasH * 0.06)))
              .fontWeight(FontWeight.Bold)
              .fontColor("#ffd54a")
            // 大号种子包卡片（同掉落卡面：绿包装 + 植物色卡面 + 费用）
            Stack({ alignContent: Alignment.Center }) {
              Column({ space: 8 }) {
                Text(getCardVisual(this.engine.dropCardKey).label)
                  .fontSize(30)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(getCardVisual(this.engine.dropCardKey).label === '挑战书' ? '#6d4c41' : '#ffffff')
                // 挑战书/图鉴无费用概念，不显示阳光行
                if (this.engine.dropCardKey !== 'letter' && this.engine.dropCardKey !== 'almanac') {
                  Text(getCardVisual(this.engine.dropCardKey).cost > 0
                    ? `${getCardVisual(this.engine.dropCardKey).cost} 阳光` : '0 阳光')
                    .fontSize(18)
                    .fontColor('#fff59d')
                }
              }
              .width(Math.max(120, Math.round(this.canvasH * 0.22)))
              .height(Math.max(150, Math.round(this.canvasH * 0.28)))
              .justifyContent(FlexAlign.Center)
              .backgroundColor(getCardVisual(this.engine.dropCardKey).color)
              .borderWidth(6)
              .borderColor('#33691e')
              .borderRadius(10)
              .shadow({ radius: 18, color: 'rgba(255,215,0,0.55)', offsetX: 0, offsetY: 0 })
            }

            Text(PLANT_INTRO[this.engine.dropCardKey] !== undefined
              ? PLANT_INTRO[this.engine.dropCardKey].name : getCardVisual(this.engine.dropCardKey).label)
              .fontSize(Math.max(20, Math.round(this.canvasH * 0.035)))
              .fontWeight(FontWeight.Bold)
              .fontColor('#ffe082')
            Text(PLANT_INTRO[this.engine.dropCardKey] !== undefined
              ? PLANT_INTRO[this.engine.dropCardKey].desc : '')
              .fontSize(Math.max(15, Math.round(this.canvasH * 0.026)))
              .fontColor('#fff8e1')
              .textAlign(TextAlign.Center)
              .lineHeight(22)
              .padding({ left: 26, right: 26, top: 12, bottom: 12 })
              .backgroundColor('rgba(141,110,99,0.35)')
              .borderRadius(8)
          } else {
            Text(this.isLetterVictory() ? "✉ 一封挑战信" : "守住啦！")
              .fontSize(Math.max(28, Math.round(this.canvasH * 0.08)))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.isLetterVictory() ? "#ffd54a" : "#7cb342")
            if (this.isLetterVictory()) {
              Text("致草坪主人：\n\n你的草地守得不错。但僵王博士不会善罢甘休——\n下一关（1-10），僵尸将组织强烈攻势！\n植物将由传送带随机供应，不必选卡。\n\n敢来吗？\n\n—— 僵王博士")
                .fontSize(Math.max(14, Math.round(this.canvasH * 0.03)))
                .fontColor("#ffe0b2")
                .lineHeight(24)
                .textAlign(TextAlign.Center)
            } else {
              Text(`${this.engine.totalWaves} 波僵尸全部击退，金币已入账`)
                .fontSize(Math.max(14, Math.round(this.canvasH * 0.03)))
                .fontColor("#dcedc8")
            }
          }
          // 前期教学关通关提示：引导新手进商店买强化
          if (this.levelId === '1-1' || this.levelId === '1-2') {
            Text("首次通关奖励已到账！快去商店购买强化升级，后面的关卡会更轻松～")
              .fontSize(Math.max(14, Math.round(this.canvasH * 0.028)))
              .fontColor("#ffd54a")
              .textAlign(TextAlign.Center)
              .padding({ left: 30, right: 30 })
          }
          Row({ space: 12 }) {
            // 最后一关（2-5）通关后没有下一关，隐藏该按钮
            if (this.getNextLevel() !== '') {
              Button("下一关")
                .width(140).height(48).fontSize(18).fontWeight(FontWeight.Bold)
                .backgroundColor("#7cb342").fontColor("#ffffff").borderRadius(24)
                .onClick(() => this.goNextLevel())
            }
            Button("再来一次")
              .width(130).height(48).fontSize(18).fontWeight(FontWeight.Bold)
              .backgroundColor("#3d8b28").fontColor("#ffffff").borderRadius(24)
              .onClick(() => this.resetGame())
            Button("回到主页")
              .width(130).height(48).fontSize(18)
              .backgroundColor("rgba(255,255,255,0.2)").fontColor("#ffffff").borderRadius(24)
              .onClick(() => router.back())
            Button("查看图鉴")
              .width(130).height(48).fontSize(18)
              .backgroundColor("#00695c").fontColor("#ffffff").borderRadius(24)
              .onClick(() => {
                this.showAlmanac = true;
              })
            Button("前往商店")
              .width(130).height(48).fontSize(18)
              .backgroundColor("#8d6e63").fontColor("#ffffff").borderRadius(24)
              .onClick(() => this.goShop())
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor("rgba(0,0,0,0.7)")
      }

      // ====================== 图鉴浮层（结算页查看，点返回回到结算） ======================
      if (this.showAlmanac) {
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
              this.showAlmanac = false;
            })
        }
        .width('88%')
        .constraintSize({ maxWidth: 520, maxHeight: '86%' })
        .padding(16)
        .backgroundColor('#2E5118')
        .borderRadius(16)
        .border({ width: 3, color: '#7cb342' })
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.canvasW = Number(newArea.width);
      this.canvasH = Number(newArea.height);
      // 左侧卡片区宽度按卡片数与屏高自适应（传送带按容量算，避免发放时跳动）
      const panelCount: number = this.engine.conveyor ? GAME_CONST.CONVEYOR_MAX : this.cards.length;
      this.leftPanelW = calcCardPanelWidth(panelCount, this.canvasH);
      this.engine.setCanvasSize(this.canvasW, this.canvasH, this.leftPanelW);
      if (this.timerId === -1) {
        this.timerId = setInterval(() => this.gameLoop(), 16);
      }
    })
  }
}
