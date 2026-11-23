/**
 * 游戏核心逻辑引擎
 * 职责：实体更新、僵尸/阳光/金币生成、种植与铲除、碰撞检测
 * 不包含任何 Canvas / UI 代码，方便单独测试和复用
 */
import {
  COIN_DROP_RATES, GAME_CONST, Bullet, BulletKind, CardCooldown, CardDropFx, CoinDrop, ConveyorItem, ExplosionFx, GroundFx,
  LevelConfig, MowerFx, Plant, PlantKind, SunDrop, Zombie, ZombieKind, getUnlockPlantForLevel
} from './GameTypes';
import { getCardCooldown, getPlantStats, calcCardSlotSize, conveyorSlotPos, CARD_START_X, CARD_START_Y } from './CardFactory';
import { SoundFxPlayer } from './SoundFx';

export class GameEngine {
  // ===== 画布尺寸与网格 =====
  canvasW: number = 0;
  canvasH: number = 0;
  leftPanelW: number = 0;               // 左侧卡片区宽度（setCanvasSize 注入，种植点击判定用）
  colCount: number = 0;                 // 航道数（行）= 关卡解锁的行数（1~6）
  cell: number = 0;                     // 草坪格子边长（按屏幕自适应）
  gridLeft: number = 0;                 // 草坪左上角 x（整体居中）
  gridTop: number = 0;                  // 草坪左上角 y（卡片栏之下）
  scale: number = 1;                    // 格子比例尺 = cell / CELL_REF（速度/距离类常量的缩放系数）
  // ===== 关卡与倍速 =====
  levelId: string = '1-1';              // 当前关卡 id（"1-1" / "2-3"）
  night: boolean = false;               // 夜晚关：无天降阳光、向日葵不产阳光
  conveyor: boolean = false;            // 传送带关（1-10）：随机免费植物
  shovelEnabled: boolean = false;       // 本关是否可用铲子（1-4 起解锁）
  totalWaves: number = 1;               // 本关总波数
  speedMult: number = 1;                // 游戏加速倍率（1 / 1.5 / 2 / 4）
  diffMult: number = 1;                 // 夜晚难度系数（随关数递增）
  allowRushZombies: boolean = false;    // 快速系僵尸（撑杆/橄榄球）是否允许登场：白天 1-4 起、夜晚全关
  wallFirstAid: boolean = false;        // 坚果包扎术（商店购买后）：对已种坚果再种坚果卡可回满血
  unlockedPlants: string[] = [PlantKind.SHOOTER]; // 本关可种的植物

  // ===== 实体 =====
  plants: Plant[] = [];
  zombies: Zombie[] = [];
  bullets: Bullet[] = [];
  sunDrops: SunDrop[] = [];
  coins: CoinDrop[] = [];               // 掉落金币（点击收集）
  conveyorItems: ConveyorItem[] = [];   // 传送带上待取的植物（两条带轮流发放，新卡缓落）
  conveyorSelected: number = -1;        // 当前选中的传送带条目（-1 = 未选中，种植成功后才销毁）
  nextConveyorLane: number = 0;         // 下次发放使用的传送带（0/1 轮流；渲染层读它画亮条）
  private conveyorBag: string[] = [];   // 加权配方袋当前剩余（抽空重洗，保证长期权重精确）
  zombieByCol: Zombie[][] = [];
  effects: ExplosionFx[] = [];   // 爆炸/孢子特效（渲染层只画，引擎负责生成和倒计时）
  groundFxs: GroundFx[] = [];    // 地面持续效果（腐蚀液/熔岩）
  upgrades: Map<string, number> = new Map<string, number>(); // 商店强化等级（StartPage 注入存档 Map）

  // ===== 小推车（商店购买后启用） =====
  mowerEnabled: boolean = false;        // 是否已购买小推车（进关前由页面注入存档状态）
  mowers: boolean[] = [];               // 各行小推车是否就位（触发一次后消耗，重开关卡重新就位）
  mowerFxs: MowerFx[] = [];             // 正在疾驰清行的小推车

  // ===== 音效（页面层调 init 注入资源管理器） =====
  sfx: SoundFxPlayer = new SoundFxPlayer();

  // ===== 引擎 → 页面回调（金币入账 / 通关存档由页面处理） =====
  onCoinGain: ((value: number) => void) | null = null;

  // ===== 游戏状态 =====
  gameOver: boolean = false;
  sun: number = GAME_CONST.START_SUN;
  frameCount: number = 0;
  /** 已经历的提速次数（每10秒+1）。刷怪间隔改为每次刷怪时实时计算，
   *  这样调试面板改 SPAWN_INTERVAL_INIT/MIN/DECREASE 立刻对下一次刷怪生效 */
  private speedUpSteps: number = 0;

  // ===== 卡片冷却 / 波次 =====
  cardCooldowns: CardCooldown[] = [];   // 各卡片剩余冷却帧数
  spawnCount: number = 0;               // 累计刷怪次数
  wave: number = 1;                     // 当前第几大波
  spawnsThisWave: number = 0;           // 本波已刷的普通僵尸数（攒满 WAVE_EVERY_N 触发大波）
  wavePreviewTimer: number = 0;         // 大波预警剩余帧数（>0 = 红字预警中，结束即大波进场）
  pendingBigWave: boolean = false;      // 预警已发出、大波尚未进场
  finalWaveSpawned: boolean = false;    // 最终波已进场 → 清场即胜利
  victory: boolean = false;             // 胜利结算
  // ===== 通关掉卡（最后一死的僵尸掉落下一关解锁的植物）=====
  cardDrop: CardDropFx | null = null;   // 掉落动画进行中（null = 无）
  dropCardKey: string = '';             // 本关掉落的植物 key（'' = 本关无新植物，胜利走普通结算）
  private lastDeathX: number = 0;       // 最后一只僵尸死亡的位置（掉卡起点）
  private lastDeathY: number = 0;
  startBannerTimer: number = GAME_CONST.START_BANNER_FRAMES; // 开局"准备种植你的植物"横幅剩余帧数

  // ===== 刷怪航道均衡（出怪平均，但不能连着5、6只同一列） =====
  private lastSpawnCol: number = -1;    // 上一次刷怪的航道
  private sameColStreak: number = 0;    // 同一航道连续出现的次数
  private recentSpawnCols: number[] = []; // 最近若干次刷怪落在哪些航道（滑动窗口）

  // ===== 时间驱动（帧数由真实时间差换算，不依赖定时器精度） =====
  private lastTickMs: number = 0;       // 上一次 update 的真实时间戳
  private tickFrames: number = 0;       // 本次 update 相当于多少虚拟帧
  private nextSpawnAt: number = 0;      // 下次刷怪的时间点（虚拟帧）
  private nextSpeedUpAt: number = GAME_CONST.FRAME_PER_30S;  // 下次提速时间点
  private nextSunDropAt: number = GAME_CONST.SUN_DROP_INTERVAL * GAME_CONST.SUN_DROP_INTERVAL_MULT; // 下次天降阳光时间点
  private nextConveyorAt: number = GAME_CONST.CONVEYOR_INTERVAL; // 下次传送带发放时间点

  // ====================== 生命周期 ======================

  setCanvasSize(w: number, h: number, leftPanelW: number = 0): void {
    if (this.canvasW === w && this.canvasH === h && this.cell > 0 && this.leftPanelW === leftPanelW) return;
    this.canvasW = w;
    this.canvasH = h;
    this.leftPanelW = leftPanelW;
    // 草坪固定 10 列，行数 = 关卡解锁行数（1~6），格子大小自适应：
    // 左侧留给卡片区（leftPanelW），草坪在剩余宽度内居中 → 场地整体右移
    const cellW = Math.floor((w - leftPanelW - 16) / GAME_CONST.LAWN_COLS);
    const cellH = Math.floor((h - GAME_CONST.TOP_ROW_H - 16) / Math.max(1, this.colCount));
    this.cell = Math.max(36, Math.min(110, Math.min(cellW, cellH)));
    this.gridLeft = leftPanelW
      + Math.max(8, Math.round((w - leftPanelW - this.cell * GAME_CONST.LAWN_COLS) / 2));
    this.gridTop = GAME_CONST.TOP_ROW_H
      + Math.max(4, Math.round((h - GAME_CONST.TOP_ROW_H - this.cell * this.colCount) / 2));
    // 格子比例尺：所有速度/距离类常量按 (cell / CELL_REF) 缩放，
    // 保证小屏手机与大平板上"每秒走几格/子弹飞几格"手感一致
    this.scale = this.cell / GAME_CONST.CELL_REF;
    this.rebuildZombieColumns();
  }

  /** 植物显示边长：格子比基准小则随格子缩小（大屏保持原尺寸不变） */
  private get plantW(): number {
    return Math.min(GAME_CONST.PLANT_W, Math.round(this.cell * 0.95));
  }

  /** 新手保护系数：前期关卡（1-1~1-3、2-1~2-2）小于1，缩放出怪节奏/大波规模/特殊僵尸登场 */
  earlyEase: number = 1;
  eliteAllowed: boolean = true;         // 精英强化僵尸是否允许登场（1-1~1-3 关闭：新手没有反制手段）
  levelChapter: number = 1;             // 当前章节（用于黑橄榄/精英按关卡门控）
  levelIndex: number = 1;               // 当前关数
  hardRamp: number = 1;                 // 后期难度爬升系数（5-9 关 >1）：出怪更快/大波更多/精英更密

  /** 僵尸显示边长：同植物，随格子自适应 */
  private get zombieW(): number {
    return Math.min(GAME_CONST.ZOMBIE_W, Math.round(this.cell * 0.95));
  }

  /** 设置关卡（进入页面前调用）：行数、总波数、可种植物、白天/夜晚/传送带都由配置决定 */
  setLevel(cfg: LevelConfig): void {
    this.levelId = cfg.id;
    this.levelChapter = cfg.chapter;
    this.levelIndex = cfg.index;
    this.night = cfg.night;
    this.conveyor = cfg.conveyor;
    this.shovelEnabled = cfg.shovel;
    this.totalWaves = cfg.waves;
    this.colCount = cfg.rows;
    this.unlockedPlants = cfg.unlocks;
    // 快速系僵尸按关卡门控（不只按时间）：白天 1-1~1-3 只有普通/路障/铁桶，1-4 起才有撑杆/橄榄球
    this.allowRushZombies = cfg.chapter === 2 || cfg.index >= 4;
    // 夜晚难度随关数递增（再降一点：0.03→0.02）
    this.diffMult = cfg.night ? 1 + 0.02 * (cfg.index - 1) : 1;
    // ===== 新手保护系数（越小于1越容易）：玩家刚接触、植物少又没钱叠种的关卡大幅放缓 =====
    //  1-1: 0.5 / 1-2: 0.7 / 1-3: 0.85 / 2-1: 0.7 / 2-2: 0.85，其余关卡 1（不影响调试参数）
    if (cfg.chapter === 1 && cfg.index === 1) {
      this.earlyEase = 0.5;
    } else if ((cfg.chapter === 1 && cfg.index === 2) || (cfg.chapter === 2 && cfg.index === 1)) {
      this.earlyEase = 0.7;
    } else if ((cfg.chapter === 1 && cfg.index === 3) || (cfg.chapter === 2 && cfg.index === 2)) {
      this.earlyEase = 0.85;
    } else {
      this.earlyEase = 1;
    }
    // 精英强化僵尸门控：1-1~1-3 不出精英（强化铁桶对新手过于超标）
    this.eliteAllowed = !(cfg.chapter === 1 && cfg.index <= 3);
    // 后期难度爬升：两章的 5~9 关（1-5~1-9、2-5~2-9）逐关加压，每关 +10%
    //  出怪间隔 ÷ 系数、大波数量 × 系数、精英概率 × 系数、多行刷怪 × 系数
    this.hardRamp = cfg.index >= 5 && cfg.index <= 9 ? 1 + 0.1 * (cfg.index - 4) : 1;
    this.speedUpSteps = 0;
    this.cell = 0;                     // 强制 setCanvasSize 重新按新行数计算格子
    this.initMowers();                 // 每关开始：已购买小推车的话每行就位一辆
  }

  /** 按当前行数重置小推车就位状态（进关 / 重新开始时调用） */
  private initMowers(): void {
    this.mowers = [];
    for (let i = 0; i < this.colCount; i++) {
      this.mowers.push(this.mowerEnabled);
    }
  }

  /**
   * 当前刷怪间隔（虚拟帧）——每次刷怪时实时计算，而非进关时算好存起来：
   * = 基准间隔 / 难度系数 − 提速次数 × 每次提速幅度，最后夹到下限
   * 夜晚无天降阳光，出怪再放缓一档（×1.3）
   */
  private calcSpawnInterval(): number {
    let interval: number = GAME_CONST.SPAWN_INTERVAL_INIT / this.diffMult * GAME_CONST.SPAWN_INTERVAL_MULT;
    if (this.night) {
      interval *= 1.3;
    }
    // 新手保护：前期关卡出怪更慢（除以 <1 的系数 = 拉长间隔）
    interval /= this.earlyEase;
    // 后期爬升：5-9 关出怪更快（除以 >1 的系数 = 缩短间隔）
    interval /= this.hardRamp;
    interval -= GAME_CONST.SPAWN_INTERVAL_DECREASE * this.speedUpSteps;
    return Math.max(this.calcMinSpawnInterval(), interval);
  }

  /** 刷怪间隔下限：同样受夜晚放缓修正 */
  private calcMinSpawnInterval(): number {
    let minInterval: number = GAME_CONST.SPAWN_INTERVAL_MIN / this.diffMult;
    if (this.night) {
      minInterval *= 1.3;
    }
    return minInterval / (this.earlyEase * this.hardRamp);
  }

  isPlantUnlocked(key: string): boolean {
    return this.unlockedPlants.indexOf(key) >= 0;
  }

  reset(): void {
    this.plants = [];
    this.zombies = [];
    this.bullets = [];
    this.sunDrops = [];
    this.coins = [];
    this.conveyorItems = [];
    this.conveyorSelected = -1;
    this.nextConveyorLane = 0;
    this.conveyorBag = [];
    this.effects = [];
    this.groundFxs = [];
    this.mowerFxs = [];
    this.frameCount = 0;
    this.speedUpSteps = 0;
    this.gameOver = false;
    this.sun = GAME_CONST.START_SUN;
    this.cardCooldowns = [];
    this.spawnCount = 0;
    this.wave = 1;
    this.spawnsThisWave = 0;
    this.wavePreviewTimer = 0;
    this.pendingBigWave = false;
    this.finalWaveSpawned = false;
    this.victory = false;
    this.cardDrop = null;
    this.dropCardKey = '';
    this.lastDeathX = 0;
    this.lastDeathY = 0;
    this.startBannerTimer = GAME_CONST.START_BANNER_FRAMES;
    this.lastSpawnCol = -1;
    this.sameColStreak = 0;
    this.recentSpawnCols = [];
    this.lastTickMs = 0;
    this.tickFrames = 0;
    this.nextSpawnAt = 0;
    this.nextSpeedUpAt = GAME_CONST.FRAME_PER_10S;
    this.nextSunDropAt = GAME_CONST.SUN_DROP_INTERVAL * GAME_CONST.SUN_DROP_INTERVAL_MULT;
    this.nextConveyorAt = GAME_CONST.CONVEYOR_INTERVAL;
    this.initMowers();
    this.rebuildZombieColumns();
  }

  private rebuildZombieColumns(): void {
    this.zombieByCol = new Array(this.colCount);
    for (let i = 0; i < this.colCount; i++) {
      this.zombieByCol[i] = [];
    }
    // 重建映射时把场上已有的僵尸装回去（防"无敌僵尸"）
    for (const z of this.zombies) {
      if (!z.dead && z.col >= 0 && z.col < this.colCount) {
        this.zombieByCol[z.col].push(z);
      }
    }
  }

  /** 每帧调用：推进全部游戏逻辑（暂停时页面层不调用） */
  update(): void {
    if (this.canvasW <= 0 || this.canvasH <= 0) return;

    const now = Date.now();
    if (this.lastTickMs === 0) {
      this.lastTickMs = now;
    }
    let dtMs = now - this.lastTickMs;
    this.lastTickMs = now;
    if (dtMs > 250) {
      dtMs = 250; // 切后台/卡顿保护：单次最多按250ms推进，防止瞬移
    }
    this.tickFrames = dtMs / 1000 * GAME_CONST.FRAME_RATE;
    this.tickFrames *= this.speedMult;
    this.frameCount += this.tickFrames;

    if (this.gameOver) return;

    if (this.frameCount >= this.nextSpeedUpAt) {
      this.speedUpSteps += 1;           // 提速只记次数，具体间隔由 calcSpawnInterval 实时算
      this.nextSpeedUpAt += GAME_CONST.FRAME_PER_10S; // 每10秒提速一次
    }
    this.tickCooldowns();
    this.updateEffects();
    if (this.pendingBigWave && this.wavePreviewTimer > 0) {
      this.wavePreviewTimer = Math.max(0, this.wavePreviewTimer - this.tickFrames);
      if (this.wavePreviewTimer === 0) {
        this.spawnBigWave();
      }
    }
    if (this.startBannerTimer > 0) {
      this.startBannerTimer = Math.max(0, this.startBannerTimer - this.tickFrames);
    }
    this.spawnSunDropIfNeeded();
    this.updateConveyor();
    this.spawnZombieIfNeeded();
    this.cleanDeadPlantZombieRelation();
    this.updateZombies();
    this.updatePlants();
    this.updateBullets();
    this.updateSunDrops();
    this.updateCoins();
    this.updateGroundFxs();
    this.updateMowers();
    this.cleanDeadEntities();
    this.updateCardDrop();
    if (this.finalWaveSpawned && this.zombies.length === 0 && this.gameOver === false) {
      if (this.cardDrop === null && this.dropCardKey === '') {
        // 清场：最后一只僵尸掉落"下一关解锁的植物"卡片，播放掉落+解锁特效后才进结算；
        // 没有新植物的关（1-9 挑战信 / 2-7 之后 / 最终关）直接胜利
        const unlockKey: string = getUnlockPlantForLevel(this.levelId);
        if (unlockKey !== '') {
          this.dropCardKey = unlockKey;
          const lawnLeft: number = this.gridLeft + this.cell * 0.5;
          const lawnRight: number = this.gridLeft + this.cell * GAME_CONST.LAWN_COLS - this.cell * 0.5;
          const lawnCy: number = this.gridTop + this.colCount * this.cell / 2;
          const startX: number = Math.min(lawnRight, Math.max(lawnLeft,
            this.lastDeathX > 0 ? this.lastDeathX : (lawnLeft + lawnRight) / 2));
          this.cardDrop = {
            key: unlockKey,
            x: startX,
            y: this.lastDeathY > 0 ? this.lastDeathY : lawnCy,
            targetY: lawnCy,
            sway: Math.random() * 6, landed: false, timer: 90
          };
        } else {
          this.victory = true;
        }
      } else if (this.cardDrop === null && this.dropCardKey !== '') {
        this.victory = true; // 防御：掉卡对象丢失时保证仍能进结算
      }
    }
  }

  /** 通关掉卡动画：卡片从最后死亡位置摇摆下落到草坪中央，落地发光+音效，稍停后进结算 */
  private updateCardDrop(): void {
    const c = this.cardDrop;
    if (c === null) return;
    if (!c.landed) {
      c.sway += 0.1 * this.tickFrames;
      c.x += Math.sin(c.sway) * 0.8 * this.tickFrames;
      c.y += Math.max(2, 3.2 * this.scale) * this.tickFrames;
      if (c.y >= c.targetY) {
        c.y = c.targetY;
        c.landed = true;
        this.sfx.play('points');
      }
    } else {
      c.timer -= this.tickFrames;
      if (c.timer <= 0) {
        this.victory = true;
      }
    }
  }

  /**
   * 本关登场僵尸名单（关卡开始前情报预览用）。
   * 与刷怪逻辑严格同源：通用池恒有普通/路障/铁桶/盗贼（只按登场帧数门控）；
   * 快速系看 allowRushZombies（黑橄榄另看章节/关数门控，与 spawnZombie 一致）；
   * 夜晚专属（读报/铁门/舞王）同样只按登场帧数门控，夜晚全关可能登场；
   * 精英只看 eliteAllowed。
   */
  getZombieRoster(): string[] {
    const list: string[] = ['normal', 'cone', 'bucket', 'thief'];
    if (this.allowRushZombies) {
      list.push('pole', 'football');
      if (this.levelChapter === 2 || this.levelIndex >= 7) {
        list.push('dark_football');
      }
    }
    if (this.night) {
      list.push('newspaper', 'door', 'dancer');
    }
    if (this.eliteAllowed) {
      list.push('elite');
    }
    return list;
  }

  // ====================== 生成逻辑 ======================

  private spawnSunDropIfNeeded(): void {
    // 夜晚无天降阳光（原版规则），阳光全靠阳光菇
    if (this.night || this.conveyor) return;
    // 游戏结束（胜利/失败）或通关掉卡动画期间停止掉阳光，下一关或重玩本关时恢复
    if (this.gameOver || this.victory || this.cardDrop !== null) return;
    if (this.frameCount < this.nextSunDropAt || this.colCount <= 0) return;
    this.nextSunDropAt += GAME_CONST.SUN_DROP_INTERVAL * GAME_CONST.SUN_DROP_INTERVAL_MULT;
    const rowIndex = Math.floor(Math.random() * this.colCount);
    const targetX = this.gridLeft + this.cell / 2
      + Math.random() * (this.cell * GAME_CONST.LAWN_COLS - this.cell);
    const targetY = this.gridTop + rowIndex * this.cell + this.cell / 2;
    this.sunDrops.push({
      x: targetX, y: -20, w: 24, h: 24,
      value: GAME_CONST.SUN_NORMAL_VALUE, targetX: targetX, targetY: targetY,
      moveProgress: 0, moveSpeed: GAME_CONST.SUN_FALL_SPEED, pauseTimer: 30,
      hasLanded: false, dead: false,
      collecting: false, stolenBy: null
    });
  }

  /**
   * 传送带（1-10）：两条带轮流发放，新卡从顶部缓落到该带底层空槽
   *  发放用加权配方袋（20张一组，数量即权重），保证低权重植物也会稳定出现
   */
  private updateConveyor(): void {
    if (!this.conveyor) return;
    // 通关掉卡动画期间停止发放（清场结算中，不再需要新卡）
    if (this.cardDrop !== null) return;
    // 所有卡片持续下落，落到目标槽位（fall = 0）即停
    const fallSpeed: number = GAME_CONST.CONVEYOR_FALL_SPEED * this.scale * this.tickFrames;
    for (const it of this.conveyorItems) {
      if (it.fall > 0) {
        it.fall = Math.max(0, it.fall - fallSpeed);
      }
    }
    if (this.conveyorItems.length >= GAME_CONST.CONVEYOR_MAX) return;
    if (this.frameCount < this.nextConveyorAt) return;

    const perLane: number = GAME_CONST.CONVEYOR_MAX / 2;
    let lane: number = this.nextConveyorLane;
    if (this.laneCount(lane) >= perLane) {
      lane = 1 - lane;            // 轮到的带满了 → 放到另一条
      if (this.laneCount(lane) >= perLane) return; // 两条都满：装满即停，等取卡后再补
    }
    this.nextConveyorAt = this.frameCount + GAME_CONST.CONVEYOR_INTERVAL;
    this.nextConveyorLane = 1 - lane; // 下次换另一条带

    // 取该条带最小空闲槽位行（取走中间卡后新卡补到空位，避免与旧卡重叠）
    const used: boolean[] = [false, false, false, false];
    for (const it of this.conveyorItems) {
      if (it.lane === lane && it.row >= 0 && it.row < perLane) {
        used[it.row] = true;
      }
    }
    let row: number = -1;
    for (let r = 0; r < perLane; r++) {
      if (!used[r]) {
        row = r;
        break;
      }
    }
    if (row < 0) return; // 没有空位：跳过（正常不会发生，防御性保护）
    // 计算下落起点（面板顶部之上）到目标槽位的距离
    const slotSize: number = calcCardSlotSize(GAME_CONST.CONVEYOR_MAX, this.canvasH);
    const target: number[] = conveyorSlotPos(lane, row, slotSize, this.canvasH);
    const startY: number = CARD_START_Y - slotSize;
    this.conveyorItems.push({
      key: this.drawFromConveyorBag(), lane: lane, row: row,
      fall: Math.max(0, target[1] - startY), 
    });
  }

  /** 某条传送带上的卡片数 */
  private laneCount(lane: number): number {
    let n: number = 0;
    for (const it of this.conveyorItems) {
      if (it.lane === lane) n++;
    }
    return n;
  }

  /** 从加权配方袋抽一张；袋空则重洗（Fisher-Yates），长期比例精确贴合权重 */
  private drawFromConveyorBag(): string {
    if (this.conveyorBag.length === 0) {
      this.conveyorBag = GAME_CONST.CONVEYOR_BAG.slice();
      for (let i = this.conveyorBag.length - 1; i > 0; i--) {
        const j: number = Math.floor(Math.random() * (i + 1));
        const tmp: string = this.conveyorBag[i];
        this.conveyorBag[i] = this.conveyorBag[j];
        this.conveyorBag[j] = tmp;
      }
    }
    return this.conveyorBag.pop() as string;
  }

  /** 点选传送带条目：再点同一个取消，点其他条目切换（同种卡片不会同时选中两个） */
  selectConveyorAt(index: number): void {
    if (index < 0 || index >= this.conveyorItems.length) {
      this.conveyorSelected = -1;
      return;
    }
    this.conveyorSelected = (this.conveyorSelected === index) ? -1 : index;
    if (this.conveyorSelected >= 0) {
      this.sfx.play('seedlift');
    }
  }

  /** 种植成功后销毁选中的传送带条目，同带上方卡片下移一格补位 */
  takeSelectedConveyorItem(): void {
    if (this.conveyorSelected < 0 || this.conveyorSelected >= this.conveyorItems.length) return;
    const removedLane: number = this.conveyorItems[this.conveyorSelected].lane;
    const removedRow: number = this.conveyorItems[this.conveyorSelected].row;
    this.conveyorItems.splice(this.conveyorSelected, 1);
    this.conveyorSelected = -1;
    for (const it of this.conveyorItems) {
      if (it.lane === removedLane && it.row > removedRow) {
        it.row--; // 槽位下移（渲染按 row 计算位置，视觉上自动滑落）
      }
    }
  }

  private spawnZombieIfNeeded(): void {
    if (this.finalWaveSpawned) return;
    if (this.pendingBigWave) return;
    if (this.frameCount < GAME_CONST.START_NO_SPAWN_FRAME / this.earlyEase) return;
    if (this.frameCount < this.nextSpawnAt) return;
    if (this.zombies.length >= GAME_CONST.MAX_ZOMBIE_COUNT) return;
    this.nextSpawnAt = this.frameCount + this.calcSpawnInterval();

    // 波次要求动态化：第一波最少，之后按波次要求系数逐波递增（第N波 = 基准×(1+(N-1)×系数)）
    const waveNeed: number = Math.max(1, Math.round(GAME_CONST.WAVE_EVERY_N
      * (1 + (this.wave - 1) * GAME_CONST.WAVE_REQ_MULT)));
    if (this.spawnsThisWave >= waveNeed) {
      this.pendingBigWave = true;
      this.wavePreviewTimer = GAME_CONST.WAVE_PREVIEW_FRAMES;
      this.spawnsThisWave = 0;
      this.sfx.play(this.wave >= this.totalWaves ? 'finalwave' : 'hugewave');
      return;
    }
    this.spawnsThisWave++;

    const col: number = this.pickSpawnColumn();
    this.recordSpawnCol(col);
    this.spawnZombie(col, 0);

    // 多行同时出现：25% 第二行、8% 第三行（各选不同航道）
    //  新手保护期概率缩小 ×earlyEase；后期 5-9 关放大 ×hardRamp（上限 60%/30%）
    if (this.zombies.length < GAME_CONST.MAX_ZOMBIE_COUNT - 1
      && Math.random() < Math.min(0.6, GAME_CONST.MULTI_LANE_CHANCE_2 * this.earlyEase * this.hardRamp)) {
      const col2: number = this.otherColumn(col);
      this.recordSpawnCol(col2);
      this.spawnZombie(col2, 0);
      if (this.zombies.length < GAME_CONST.MAX_ZOMBIE_COUNT - 1
        && Math.random() < Math.min(0.3, GAME_CONST.MULTI_LANE_CHANCE_3 * this.earlyEase * this.hardRamp)) {
        const col3: number = this.otherColumn(this.otherColumn(col2));
        this.recordSpawnCol(col3);
        this.spawnZombie(col3, 0);
      }
    }
  }

  /** 生成一大波（预警结束后调用）：洗牌轮转分配航道 + 出场错位 */
  private spawnBigWave(): void {
    // 大波数量动态化：基础 × (1+(波次-1)×波次出怪系数)，第一波最少、越往后越多；
    //  新手保护期同比例缩小（最少 2 只）；后期 5-9 关按 hardRamp 放大
    const count: number = Math.max(2,
      Math.round(GAME_CONST.BIG_WAVE_COUNT * (1 + (this.wave - 1) * GAME_CONST.WAVE_SPAWN_MULT)
        * this.earlyEase * this.hardRamp));
    const waveCols: number[] = this.pickWaveColumns(count);
    for (let i = 0; i < waveCols.length; i++) {
      this.recordSpawnCol(waveCols[i]);
      this.spawnZombie(waveCols[i], i * GAME_CONST.BIG_WAVE_STAGGER);
    }
    if (this.wave >= this.totalWaves) {
      this.finalWaveSpawned = true;
    } else {
      this.wave++;
    }
    this.pendingBigWave = false;
  }

  // ====================== 刷怪航道分配（均衡） ======================

  private pickSpawnColumn(): number {
    const n: number = this.colCount;
    if (n <= 1) return 0;

    let col: number = Math.floor(Math.random() * n);

    // 1) 连列保护：同一航道最多连着 MAX_SAME_COL_STREAK 只
    if (col === this.lastSpawnCol && this.sameColStreak >= GAME_CONST.MAX_SAME_COL_STREAK) {
      col = this.otherColumn(col);
    }

    // 2) 近期均衡：窗口内每列上限 = ceil(窗口/列数) + 1
    const quota: number = Math.ceil(GAME_CONST.RECENT_SPAWN_WINDOW / n) + 1;
    let guard: number = 0;
    while (guard < 4 && this.recentColCount(col) >= quota) {
      col = this.otherColumn(col);
      guard++;
    }
    return col;
  }

  private otherColumn(current: number): number {
    const n: number = this.colCount;
    if (n <= 1) return 0;
    let col: number = Math.floor(Math.random() * n);
    if (col === current) {
      col = (current + 1 + Math.floor(Math.random() * (n - 1))) % n;
    }
    return col;
  }

  private recentColCount(col: number): number {
    let count: number = 0;
    for (const c of this.recentSpawnCols) {
      if (c === col) count++;
    }
    return count;
  }

  private recordSpawnCol(col: number): void {
    this.recentSpawnCols.push(col);
    if (this.recentSpawnCols.length > GAME_CONST.RECENT_SPAWN_WINDOW) {
      this.recentSpawnCols.shift();
    }
    if (col === this.lastSpawnCol) {
      this.sameColStreak++;
    } else {
      this.lastSpawnCol = col;
      this.sameColStreak = 1;
    }
  }

  private pickWaveColumns(count: number): number[] {
    const n: number = this.colCount;
    const cols: number[] = [];
    if (n <= 0) return cols;
    if (n === 1) {
      for (let i = 0; i < count; i++) {
        cols.push(0);
      }
      return cols;
    }
    while (cols.length < count) {
      const order: number[] = [];
      for (let c = 0; c < n; c++) {
        order.push(c);
      }
      for (let k = order.length - 1; k > 0; k--) {
        const j: number = Math.floor(Math.random() * (k + 1));
        const tmp: number = order[k];
        order[k] = order[j];
        order[j] = tmp;
      }
      for (const c of order) {
        if (cols.length < count) {
          cols.push(c);
        }
      }
    }
    // 后处理：相邻同列 → 与后面第一个不同列的交换
    for (let i = 1; i < cols.length; i++) {
      if (cols[i] !== cols[i - 1]) continue;
      for (let j = i + 1; j < cols.length; j++) {
        if (cols[j] !== cols[i - 1]) {
          const tmp: number = cols[i];
          cols[i] = cols[j];
          cols[j] = tmp;
          break;
        }
      }
    }
    return cols;
  }

  private up(key: string): number {
    const v: number | undefined = this.upgrades.get(key);
    return v === undefined ? 0 : v;
  }

  /** 生成一只僵尸（白天：路障/铁桶/撑杆/橄榄球；夜晚：+读报/铁门/舞王） */
  /** 特殊僵尸登场帧：新手保护期（earlyEase<1）按比例延后出现，如 1-1 路障 60 秒、铁桶 2 分钟后才登场 */
  private lateFrame(base: number): number {
    return base / this.earlyEase;
  }

  private spawnZombie(col: number, stagger: number = 0): void {
    let zombieKind: ZombieKind = ZombieKind.Normal;
    let armorHp = 0;
    let maxArmorHp = 0;
    let bodyHp = GAME_CONST.ZOMBIE_BODY_HP;
    let hasPole = false;
    let speedMult = 1;

    if (this.night) {
      // ===== 夜晚专属僵尸（按登场帧数分阶段混入） =====
      const roll = Math.random();
      if (this.frameCount >= this.lateFrame(GAME_CONST.NEWSPAPER_START_FRAME) && roll < GAME_CONST.NEWSPAPER_SPAWN_RATE) {
        // 读报僵尸：报纸150甲，破报后狂暴（2-2 起）
        zombieKind = ZombieKind.Newspaper;
        armorHp = GAME_CONST.NEWSPAPER_ARMOR_HP;
        maxArmorHp = GAME_CONST.NEWSPAPER_ARMOR_HP;
      } else if (this.frameCount >= this.lateFrame(GAME_CONST.DOOR_START_FRAME) && roll < GAME_CONST.NEWSPAPER_SPAWN_RATE + GAME_CONST.DOOR_SPAWN_RATE) {
        // 铁门僵尸：铁门1100甲，孢子无视铁门（2-4 起）
        zombieKind = ZombieKind.Door;
        armorHp = GAME_CONST.DOOR_ARMOR_HP;
        maxArmorHp = GAME_CONST.DOOR_ARMOR_HP;
      } else if (this.frameCount >= this.lateFrame(GAME_CONST.DANCER_START_FRAME) && roll < GAME_CONST.NEWSPAPER_SPAWN_RATE + GAME_CONST.DOOR_SPAWN_RATE + GAME_CONST.DANCER_SPAWN_RATE) {
        // 舞王僵尸：快速入场+召唤伴舞+走走停停（2-5 起）
        zombieKind = ZombieKind.Dancer;
        bodyHp = GAME_CONST.DANCER_HP;
        speedMult = GAME_CONST.DANCER_ENTRY_SPEED_MULT;
      }
    }
    if (zombieKind === ZombieKind.Normal) {
      // ===== 通用僵尸池（白天/夜晚共用；撑杆/橄榄球需关卡门控通过才登场） =====
      if (this.allowRushZombies && this.frameCount >= this.lateFrame(GAME_CONST.FOOTBALL_START_FRAME) && Math.random() < GAME_CONST.FOOTBALL_SPAWN_RATE) {
        // 黑橄榄僵尸：1-7 起（夜晚全关）才会登场；同橄榄球（2倍速）但护甲2.5倍
        if (Math.random() < GAME_CONST.DARK_FOOTBALL_CHANCE
          && (this.levelChapter === 2 || this.levelIndex >= 7)) {
          zombieKind = ZombieKind.DarkFootball;
          armorHp = GAME_CONST.DARK_FOOTBALL_ARMOR_HP;
          maxArmorHp = GAME_CONST.DARK_FOOTBALL_ARMOR_HP;
          speedMult = GAME_CONST.FOOTBALL_SPEED_MULT;
        } else {
          zombieKind = ZombieKind.Football;
          armorHp = GAME_CONST.FOOTBALL_ARMOR_HP;
          maxArmorHp = GAME_CONST.FOOTBALL_ARMOR_HP;
          speedMult = GAME_CONST.FOOTBALL_SPEED_MULT;
        }
      } else if (this.allowRushZombies && this.frameCount >= this.lateFrame(GAME_CONST.POLE_START_FRAME) && Math.random() < GAME_CONST.POLE_SPAWN_RATE) {
        zombieKind = ZombieKind.Pole;
        bodyHp = GAME_CONST.POLE_ZOMBIE_HP;
        hasPole = true;
        speedMult = GAME_CONST.POLE_SPEED_MULT;
      } else if (this.frameCount >= this.lateFrame(GAME_CONST.THIEF_START_FRAME) && Math.random() < GAME_CONST.THIEF_SPAWN_RATE) {
        // 盗贼僵尸：每2秒尝试偷地上阳光
        zombieKind = ZombieKind.Thief;
        bodyHp = GAME_CONST.ZOMBIE_BODY_HP;
      } else if (this.frameCount >= this.lateFrame(GAME_CONST.CONE_START_FRAME)) {
        const rand = Math.random();
        if (rand < GAME_CONST.CONE_SPAWN_RATE) {
          zombieKind = ZombieKind.Normal;
        } else if (rand < GAME_CONST.BUCKET_SPAWN_RATE) {
          if (this.frameCount >= this.lateFrame(GAME_CONST.BUCKET_START_FRAME)) {
            zombieKind = ZombieKind.Cone;
            armorHp = GAME_CONST.CONE_ARMOR_HP;
            maxArmorHp = GAME_CONST.CONE_ARMOR_HP;
          }
        } else if (this.frameCount >= this.lateFrame(GAME_CONST.BUCKET_START_FRAME)
          && Math.random() < this.earlyEase) {
          // 铁桶登场再过一道 earlyEase 概率门：前期关铁桶更稀少（1-1 仅约2.5%）
          zombieKind = ZombieKind.Bucket;
          armorHp = GAME_CONST.BUCKET_ARMOR_HP;
          maxArmorHp = GAME_CONST.BUCKET_ARMOR_HP;
        }
      }
    }

    const newZombie: Zombie = {
      // 出生在草坪右缘外约 0.6 格处（按格子基准，手机/平板入场距离一致）
      x: this.gridLeft + this.cell * GAME_CONST.LAWN_COLS + this.cell * 0.6 + stagger * this.scale,
      y: this.gridTop + col * this.cell + (this.cell - this.zombieW) / 2,
      w: this.zombieW, h: this.zombieW,
      hp: bodyHp * GAME_CONST.ZOMBIE_HP_MULT,
      maxHp: bodyHp * GAME_CONST.ZOMBIE_HP_MULT, dead: false,
      speed: GAME_CONST.ZOMBIE_SPEED * this.scale * speedMult * this.diffMult,
      isEating: false,
      targetPlant: null, col: col, slowTimer: 0,
      zombieKind: zombieKind,
      armorHp: armorHp * GAME_CONST.ZOMBIE_ARMOR_MULT,
      maxArmorHp: maxArmorHp * GAME_CONST.ZOMBIE_ARMOR_MULT,
      hasPole: hasPole,
      friendly: false, enraged: false,
      auxTimer: 0, summoned: false, walkPause: false,
      leader: null,
      targetFriendly: null,
      frozenTimer: 0, frostHits: 0, frostbite: false, frostbiteTimer: 0, frostTinted: false,
      elite: false, stealTimer: GAME_CONST.THIEF_STEAL_INTERVAL, brittleTimer: 0
    };
    // ===== 精英强化僵尸：白内红外双轮廓，速度/血量/护甲按 ELITE_MULT 强化 =====
    //  1-1~1-3 关闭（eliteAllowed=false）；精英橄榄球 1-6 起、精英黑橄榄 1-8 起（夜晚全关可）；
    //  后期 5-9 关概率 × hardRamp（1-9 达 12%）
    if (this.eliteAllowed && this.eliteAllowedForKind(newZombie.zombieKind)
      && Math.random() < Math.min(0.5, GAME_CONST.ELITE_CHANCE * this.hardRamp)) {
      const em: number = GAME_CONST.ELITE_MULT;
      newZombie.elite = true;
      newZombie.hp *= em;
      newZombie.maxHp *= em;
      newZombie.armorHp *= em;
      newZombie.maxArmorHp *= em;
      newZombie.speed *= em;
    }
    this.zombies.push(newZombie);
    this.zombieByCol[col].push(newZombie);
  }

  /** 精英按僵尸种类的关卡门控：精英橄榄球 1-6 起、精英黑橄榄 1-8 起（夜晚章节全关可），其余种类只看 eliteAllowed */
  private eliteAllowedForKind(kind: ZombieKind): boolean {
    if (kind === ZombieKind.Football) {
      return this.levelChapter === 2 || this.levelIndex >= 6;
    }
    if (kind === ZombieKind.DarkFootball) {
      return this.levelChapter === 2 || this.levelIndex >= 8;
    }
    return true;
  }

  // ====================== 实体更新 ======================

  private cleanDeadPlantZombieRelation(): void {
    for (const p of this.plants) {
      if (!p.dead) continue;
      for (const z of this.zombies) {
        if (!z.dead && z.targetPlant === p) {
          z.isEating = false;
          z.targetPlant = null;
        }
      }
    }
  }

  private updateZombies(): void {
    for (const z of this.zombies) {
      if (z.dead) continue;

      // ===== 极寒冻结：完全停止（不移动不啃食） =====
      if (z.frozenTimer > 0) {
        z.frozenTimer = Math.max(0, z.frozenTimer - this.tickFrames);
      }
      // 冰脆debuff倒计时（极寒封冻术2：冻结期间受伤+25%）
      if (z.brittleTimer > 0) {
        z.brittleTimer = Math.max(0, z.brittleTimer - this.tickFrames);
      }
      // 冻伤debuff倒计时（寒冰炼成术2：持续5秒，再次被极寒击中刷新）
      if (z.frostbiteTimer > 0) {
        z.frostbiteTimer = Math.max(0, z.frostbiteTimer - this.tickFrames);
        if (z.frostbiteTimer === 0) {
          z.frostbite = false;
        }
      }
      if (z.frozenTimer > 0) {
        continue;
      }

      // ===== 冻伤debuff（寒冰炼成术2）：每秒7.5血，无视护甲，不叠加 =====
      // 橄榄球/黑橄榄/铁门僵尸：护甲未破时免疫冻伤
      const armoredKind: boolean = z.zombieKind === ZombieKind.Football
        || z.zombieKind === ZombieKind.DarkFootball || z.zombieKind === ZombieKind.Door;
      if (z.frostbite && !(armoredKind && z.armorHp > 0)) {
        z.hp -= GAME_CONST.FROSTBITE_DPS / GAME_CONST.FRAME_RATE * this.tickFrames;
      }

      // ===== 盗贼僵尸：每2秒锁定一个未被盗、未被收集的落地阳光 =====
      if (z.zombieKind === ZombieKind.Thief) {
        z.stealTimer -= this.tickFrames;
        if (z.stealTimer <= 0) {
          z.stealTimer = GAME_CONST.THIEF_STEAL_INTERVAL;
          for (const s of this.sunDrops) {
            if (!s.dead && !s.collecting && s.stolenBy === null && s.hasLanded) {
              s.stolenBy = z; // 锁定：阳光变红缓慢飞向该盗贼
              break;
            }
          }
        }
      }

      // ===== 魅惑友军僵尸：粉色，向右走，攻击挡路的其他僵尸，走出右边缘消失 =====
      if (z.friendly) {
        const victim: Zombie | null = this.findZombieTarget(z);
        if (victim !== null) {
          // 友军啃咬其他僵尸：速率与普通僵尸啃食一致；深度催眠术1级 +50% → 1.5倍
          const biteMult: number = this.up('hypno') >= 1 ? 1.5 : 1;
          victim.hp -= GAME_CONST.ZOMBIE_EAT_DPS * biteMult * this.tickFrames;
          this.sfx.play('chomp', GAME_CONST.SFX_EAT_THROTTLE_MS);
        } else {
          z.x += z.speed * this.tickFrames;
          if (z.x > this.canvasW + 30) {
            z.dead = true; // 走出右边缘：安静离场，不掉金币不计负
          }
        }
        if (z.hp <= 0) {
          z.dead = true;
        }
        continue;
      }

      // ===== 舞王僵尸：入场快速 → 第二格召唤伴舞 → 走走停停 =====
      if (z.zombieKind === ZombieKind.Dancer) {
        this.updateDancer(z);
        if (z.hp <= 0) {
          z.dead = true;
          this.maybeDropCoin(z);
        }
        continue;
      }

      if (z.isEating && (z.targetPlant === null || z.targetPlant.dead)) {
        z.isEating = false;
        z.targetPlant = null;
      }
      // 被击退等离开接触范围 → 停止虚空啃食（啃食必须保持身体接触）
      if (z.isEating && z.targetPlant !== null && !this.checkAABBPlantZombie(z.targetPlant, z)) {
        z.isEating = false;
        z.targetPlant = null;
      }
      if (z.isEating && z.targetPlant !== null) {
        if (z.targetPlant.kind === PlantKind.POTATO && z.targetPlant.armed) {
          z.isEating = false;
          z.targetPlant = null;
        } else if (z.targetPlant.kind === PlantKind.HYPNO && this.night) {
          // ===== 魅惑菇：啃食它的僵尸变成友军（粉色），转身攻击其他僵尸；白天睡觉不生效 =====
          // 深度催眠术：1级 回满血+啃咬提速50%；2级 另获精英强化（白内红双轮廓，五项×ELITE_MULT）
          const hypno: Plant = z.targetPlant;
          const hypnoTier: number = this.up('hypno');
          hypno.dead = true;       // 被啃的魅惑菇消失（原版行为）
          z.friendly = true;
          if (hypnoTier >= 1) {
            z.hp = z.maxHp;        // 回满血（本体；护甲保持被魅惑前的剩余值）
          }
          if (hypnoTier >= 2 && !z.elite) {
            // 精英不能被二次强化：已是精英的僵尸只吃1级效果（回满血+啃咬提速）
            const em: number = GAME_CONST.ELITE_MULT;
            z.elite = true;        // 精英强化：白内红双轮廓（渲染只看 elite，友军同样生效）
            z.hp *= em;
            z.maxHp *= em;
            z.armorHp *= em;
            z.maxArmorHp *= em;
            z.speed *= em;
          }
          z.isEating = false;
          z.targetPlant = null;
          this.sfx.play('bigchomp');
        } else if (z.targetPlant.hp > 0 || z.targetPlant.armorHp > 0) {
          const eatMult: number = z.enraged ? GAME_CONST.NEWSPAPER_RAGE_EAT_MULT : 1;
          this.damagePlant(z.targetPlant, GAME_CONST.ZOMBIE_EAT_DPS * eatMult * this.tickFrames);
          this.sfx.play('chomp', GAME_CONST.SFX_EAT_THROTTLE_MS);
          if (z.targetPlant.hp <= 0) {
            z.targetPlant.dead = true;
            z.isEating = false;
            z.targetPlant = null;
          }
        } else {
          z.isEating = false;
          z.targetPlant = null;
        }
      } else {
        // ===== 友军阻挡：前方碰到魅惑友军僵尸 → 停下啃咬它（友军只受敌方僵尸伤害） =====
        this.refreshFriendlyTarget(z);
        if (z.targetFriendly !== null) {
          const eatMult: number = z.enraged ? GAME_CONST.NEWSPAPER_RAGE_EAT_MULT : 1;
          this.applyZombieDamage(z.targetFriendly, GAME_CONST.ZOMBIE_EAT_DPS * eatMult * this.tickFrames);
          this.sfx.play('chomp', GAME_CONST.SFX_EAT_THROTTLE_MS);
        } else {
          if (z.slowTimer > 0) {
            z.slowTimer = Math.max(0, z.slowTimer - this.tickFrames);
            z.x -= z.speed * GAME_CONST.SLOW_SPEED_FACTOR * this.tickFrames;
          } else {
            z.x -= z.speed * this.tickFrames;
          }
          if (z.x + z.w < this.gridLeft) {
            this.handleZombieReachHouse(z);
          }
          if (z.x < this.canvasW) {
            const hitPlant: Plant | null = this.findPlantColliding(z);
            if (hitPlant !== null) {
              if (z.hasPole) {
                z.hasPole = false;
                z.speed = GAME_CONST.ZOMBIE_SPEED * this.scale * this.diffMult;
                z.x = hitPlant.x - this.cell;
                this.sfx.play('polevault');
              } else {
                z.isEating = true;
                z.targetPlant = hitPlant;
              }
            }
          }
        }
      }
      if (z.hp <= 0) {
        z.dead = true;
        this.maybeDropCoin(z);
      }
    }
    // 伴舞队形：舞王还活着且伴舞没在啃植物时，x 与舞王同步
    this.syncMinionFormation();
  }

  /** 舞王：入场快速走2格 → 恢复原速并召唤伴舞 → 走走停停（伴舞被挡则停） */
  private updateDancer(z: Zombie): void {
    if (!z.summoned) {
      // 入场阶段：从出生点快速走 2 格（按格子基准，所有设备一致），
      // 走完或中途被植物挡住即结束入场：恢复原速 + 召唤伴舞
      const entryTargetX: number = this.gridLeft
        + (GAME_CONST.LAWN_COLS - 2) * this.cell;
      z.x -= z.speed * this.tickFrames;
      const blocked: Plant | null = this.findPlantColliding(z);
      if (z.x <= entryTargetX || blocked !== null) {
        z.summoned = true;
        z.speed = GAME_CONST.ZOMBIE_SPEED * this.scale * this.diffMult;
        z.auxTimer = GAME_CONST.DANCER_WALK_FRAMES;
        z.walkPause = false;
        this.summonMinions(z);
        this.sfx.play('hugewave'); // 召唤伴舞音效（复用大波音）
        if (blocked !== null) {
          z.isEating = true;       // 被植物挡住：落地就地开吃
          z.targetPlant = blocked;
        }
      }
      return;
    }
    // 走停循环
    z.auxTimer -= this.tickFrames;
    if (z.auxTimer <= 0) {
      z.walkPause = !z.walkPause;
      z.auxTimer = z.walkPause ? GAME_CONST.DANCER_PAUSE_FRAMES : GAME_CONST.DANCER_WALK_FRAMES;
    }
    // 前面的伴舞被植物挡住（正在啃）→ 舞王也不走
    let minionBlocked: boolean = false;
    for (const m of this.zombies) {
      if (m.dead || m.leader !== z) continue;
      if (m.isEating) {
        minionBlocked = true;
        break;
      }
    }
    if (z.walkPause || minionBlocked) return;
    // 前方被魅惑友军阻挡 → 停下啃咬
    this.refreshFriendlyTarget(z);
    if (z.targetFriendly !== null) {
      this.applyZombieDamage(z.targetFriendly, GAME_CONST.ZOMBIE_EAT_DPS * this.tickFrames);
      this.sfx.play('chomp', GAME_CONST.SFX_EAT_THROTTLE_MS);
      return;
    }
    // 移动 + 啃植物（普通僵尸逻辑）
    if (z.isEating && (z.targetPlant === null || z.targetPlant.dead)) {
      z.isEating = false;
      z.targetPlant = null;
    }
    // 被击退等离开接触范围 → 停止虚空啃食
    if (z.isEating && z.targetPlant !== null && !this.checkAABBPlantZombie(z.targetPlant, z)) {
      z.isEating = false;
      z.targetPlant = null;
    }
    if (z.isEating && z.targetPlant !== null) {
      if (z.targetPlant.hp > 0 || z.targetPlant.armorHp > 0) {
        this.damagePlant(z.targetPlant, GAME_CONST.ZOMBIE_EAT_DPS * this.tickFrames);
        this.sfx.play('chomp', GAME_CONST.SFX_EAT_THROTTLE_MS);
        if (z.targetPlant.hp <= 0) {
          z.targetPlant.dead = true;
          z.isEating = false;
          z.targetPlant = null;
        }
      }
      return;
    }
    z.x -= z.speed * this.tickFrames;
    if (z.x + z.w < this.gridLeft) {
      this.handleZombieReachHouse(z);
    }
    if (z.x < this.canvasW) {
      const hitPlant: Plant | null = this.findPlantColliding(z);
      if (hitPlant !== null) {
        z.isEating = true;
        z.targetPlant = hitPlant;
      }
    }
  }

  /** 舞王走到第二格时召唤上下左右的伴舞（保持队形） */
  private summonMinions(dancer: Zombie): void {
    const positions: number[] = [];
    if (dancer.col > 0) positions.push(dancer.col - 1);              // 上
    if (dancer.col < this.colCount - 1) positions.push(dancer.col + 1); // 下
    positions.push(dancer.col);                                      // 前后（同行）
    for (const col of positions) {
      const minion: Zombie = {
        x: dancer.x + (col === dancer.col ? 26 : 0),
        y: this.gridTop + col * this.cell + (this.cell - this.zombieW) / 2,
        w: this.zombieW, h: this.zombieW,
        hp: GAME_CONST.DANCER_MINION_HP, maxHp: GAME_CONST.DANCER_MINION_HP, dead: false,
        speed: GAME_CONST.ZOMBIE_SPEED * this.scale * this.diffMult,
        isEating: false, targetPlant: null, col: col, slowTimer: 0,
        zombieKind: ZombieKind.DancerMinion,
        armorHp: 0, maxArmorHp: 0, hasPole: false,
        friendly: false, enraged: false,
        auxTimer: 0, summoned: false, walkPause: false,
        leader: dancer,
        targetFriendly: null,
        frozenTimer: 0, frostHits: 0, frostbite: false, frostbiteTimer: 0, frostTinted: false,
        elite: false, stealTimer: 0, brittleTimer: 0
      };
      this.zombies.push(minion);
      this.zombieByCol[col].push(minion);
    }
  }

  /** 伴舞队形同步：跟随舞王的 x（正在啃植物/啃友军的不动，舞王死了就自由行动） */
  private syncMinionFormation(): void {
    for (const m of this.zombies) {
      if (m.dead || m.zombieKind !== ZombieKind.DancerMinion || m.leader === null) continue;
      if (m.isEating || m.targetFriendly !== null) continue;
      if (m.leader.dead) {
        m.leader = null; // 舞王阵亡 → 伴舞变普通僵尸行为
        continue;
      }
      m.x = m.leader.x + (m.col === m.leader.col ? 26 : 0);
    }
  }

  /** 友军僵尸的攻击目标：同一行、在右侧（前进方向）、最近的其他（敌对）僵尸 */
  private findZombieTarget(friendly: Zombie): Zombie | null {
    const fx: number = friendly.x + friendly.w;
    let best: Zombie | null = null;
    let bestGap: number = 26; // 允许一点点贴脸误差
    for (const z of this.zombies) {
      if (z.dead || z.friendly) continue;
      if (z.col !== friendly.col) continue;
      const gap: number = z.x - fx;
      if (gap > bestGap) continue;
      if (best === null || gap < bestGap) {
        bestGap = gap;
        best = z;
      }
    }
    return best;
  }

  /** 友军阻挡检测：敌方僵尸同行、左侧有魅惑友军且前缘接触/重叠 → 返回该友军（被挡住，停下啃咬） */
  private findFriendlyBlocking(z: Zombie): Zombie | null {
    let best: Zombie | null = null;
    let bestGap: number = 8; // 允许一点贴脸误差
    for (const f of this.zombies) {
      if (f.dead || !f.friendly || f.col !== z.col) continue;
      const gap: number = z.x - (f.x + f.w); // 敌军前缘 - 友军后缘（负数=已重叠）
      if (gap > bestGap) continue;
      if (best === null || gap < bestGap) {
        bestGap = gap;
        best = f;
      }
    }
    return best;
  }

  /** 维护敌方僵尸的友军啃咬目标：目标死亡/被击退脱离接触（间隙>8px）时重新检测，防止虚空啃咬 */
  private refreshFriendlyTarget(z: Zombie): void {
    if (z.targetFriendly !== null
      && (z.targetFriendly.dead || !z.targetFriendly.friendly
        || z.x - (z.targetFriendly.x + z.targetFriendly.w) > 8)) {
      z.targetFriendly = null;
    }
    if (z.targetFriendly === null) {
      z.targetFriendly = this.findFriendlyBlocking(z);
    }
  }

  /**
   * 僵尸死亡按种类概率掉落货币（友军不掉；食人花整只吞掉不掉）：
   * 第一步按 COIN_DROP_RATES 判定本种类掉不掉（越弱掉率越低，精英额外+15%），
   * 第二步在掉落时按 档位：铜$5(44%) / 银$10(34%) / 金$20(21%) / 钻石$1000(1%) 分配
   */
  private maybeDropCoin(z: Zombie): void {
    if (z.friendly) return;
    const table: Record<string, number> = COIN_DROP_RATES;
    const rateVal: number | undefined = table[z.zombieKind as string];
    let rate: number = rateVal === undefined ? 0.15 : rateVal;
    rate = rate * GAME_CONST.COIN_DROP_MULT + (z.elite ? GAME_CONST.COIN_ELITE_BONUS : 0);
    rate = Math.min(1, Math.max(0, rate));
    if (Math.random() >= rate) return; // 未命中掉率：什么都不掉

    const roll: number = Math.random();
    let value: number = GAME_CONST.COIN_COPPER_VALUE;
    let kind: string = 'copper';
    if (roll >= 0.99) {
      value = GAME_CONST.COIN_DIAMOND_VALUE;
      kind = 'diamond';
    } else if (roll >= 0.78) {
      value = GAME_CONST.COIN_GOLD_VALUE;
      kind = 'gold';
    } else if (roll >= 0.44) {
      value = GAME_CONST.COIN_SILVER_VALUE;
      kind = 'silver';
    }
    this.coins.push({
      x: z.x + z.w / 2, y: z.y + z.h / 2,
      w: 20, h: 20,
      value: value, kind: kind,
      timer: GAME_CONST.COIN_LIFETIME_FRAMES,
      dead: false, collecting: false
    });
  }

  /** 僵尸抵达草坪最左侧：本行有小推车就触发清行，否则走出屏幕后判负 */
  private handleZombieReachHouse(z: Zombie): void {
    if (this.mowerEnabled && this.mowers[z.col]) {
      this.mowers[z.col] = false;  // 消耗本行小推车（每关重置）
      this.mowerFxs.push({ col: z.col, x: this.gridLeft });
      this.sfx.play('polevault');
      return;
    }
    if (z.x + z.w < 0) {
      this.gameOver = true; // 没有小推车（或本行已用完）：走出屏幕即失败
    }
  }

  /** 小推车疾驰推进：向右移动，碾过所在行所有（非友军）僵尸并正常掉落金币 */
  private updateMowers(): void {
    if (this.mowerFxs.length === 0) return;
    for (const m of this.mowerFxs) {
      m.x += GAME_CONST.MOWER_SPEED * this.scale * this.tickFrames;
      for (const z of this.zombies) {
        if (z.dead || z.friendly || z.col !== m.col) continue;
        if (z.x + z.w / 2 <= m.x + this.cell * 0.3) {
          z.hp = 0;
          z.armorHp = 0;
          z.dead = true;
          this.maybeDropCoin(z);
        }
      }
    }
    // 驶出屏幕右侧：本次清行结束
    this.mowerFxs = this.mowerFxs.filter((m: MowerFx) => m.x < this.canvasW + 60);
  }

  /** 僵尸啃食植物：有强化护甲先扣护甲（溢出部分扣本体） */
  private damagePlant(plant: Plant, amount: number): void {
    if (plant.armorHp > 0) {
      plant.armorHp -= amount;
      if (plant.armorHp < 0) {
        plant.hp += plant.armorHp;
        plant.armorHp = 0;
      }
    } else {
      plant.hp -= amount;
    }
    if (plant.hp <= 0) {
      plant.dead = true;
    }
  }

  /** 炮击指南术：土豆发射炮弹，命中后一格AOE 300 伤害 */
  private firePotatoShell(p: Plant): void {
    this.bullets.push({
      x: p.x + p.w / 2, y: p.y + p.h / 2, w: 16, h: 16,
      damage: 0, speed: GAME_CONST.BULLET_SPEED * this.scale * 2, col: p.col,
      kind: BulletKind.SHELL, dead: false,
      knock: 0,
      startX: p.x, range: 0
    });
    this.sfx.play('throw', 100);
  }

  /** 地面效果推进：倒计时 + 对踩在上面的僵尸持续掉血（无视护甲） */
  private updateGroundFxs(): void {
    this.groundFxs = this.groundFxs.filter((g: GroundFx) => {
      g.timer -= this.tickFrames;
      return g.timer > 0;
    });
    if (this.groundFxs.length === 0) return;
    for (const g of this.groundFxs) {
      // 弹坑只挡种植不掉血；熔岩/腐蚀液/辐射坑对踩上的僵尸持续掉血（无视护甲）
      if (g.kind !== 'lava' && g.kind !== 'digest' && g.kind !== 'radiation') continue;
      const dps: number = g.kind === 'lava' ? GAME_CONST.LAVA_DPS
        : (g.kind === 'radiation' ? GAME_CONST.RADIATION_DPS : GAME_CONST.DIGEST_POOL_DPS);
      for (const z of this.zombies) {
        if (z.dead || z.friendly) continue;
        if (Math.abs(z.x + z.w / 2 - g.x) <= this.cell / 2
          && Math.abs(z.y + z.h / 2 - g.y) <= this.cell / 2) {
          z.hp -= dps / GAME_CONST.FRAME_RATE * this.tickFrames;
          if (z.hp <= 0) {
            z.dead = true;
            this.maybeDropCoin(z);
          }
        }
      }
    }
  }

  private updatePlants(): void {
    for (const p of this.plants) {
      if (p.dead) continue;
      switch (p.kind) {
        case PlantKind.POTATO:
          this.updatePotato(p);
          break;
        case PlantKind.CHERRY:
          this.updateCherry(p);
          break;
        case PlantKind.CHOMER:
          this.updateChomer(p);
          break;
        case PlantKind.SHOOTER:
        case PlantKind.DOUBLE:
        case PlantKind.ICE:
          this.updateShooter(p);
          break;
        case PlantKind.SUNFLOWER:
          this.updateSunflower(p);
          break;
        case PlantKind.PUFF:
          this.updatePuff(p);
          break;
        case PlantKind.SUNSHROOM:
          this.updateSunshroom(p);
          break;
        case PlantKind.SCAREDY:
          this.updateScaredy(p);
          break;
        case PlantKind.FUME:
          this.updateFume(p);
          break;
        case PlantKind.HYPNO:
          break; // 魅惑菇被动：僵尸啃到时触发（updateZombies 里处理）
        default:
          break;
      }
    }
  }

  private updateCherry(p: Plant): void {
    p.armTimer -= this.tickFrames;
    if (p.armTimer > 0) return;
    p.dead = true;
    // 火药强化术：爆炸伤害 ×1.5（1级/2级都是），2级额外地面熔岩3秒（不可种植，僵尸50血/秒）
    const tier: number = this.up('cherry');
    const damage: number = GAME_CONST.CHERRY_BASE_DAMAGE * (tier >= 1 ? 1.5 : 1);
    // 3×3 爆炸范围：命中判定为以中心 ±1.5 格的正方形（explodeArea 按 |dx|/|dy| 判定）
    this.explodeArea(p.x + p.w / 2, p.y + p.h / 2, this.cell * 1.5, this.cell * 1.5, damage);
    if (tier === 2) {
      this.groundFxs.push({
        x: p.x + p.w / 2, y: p.y + p.h / 2,
        timer: GAME_CONST.LAVA_FRAMES, kind: 'lava'
      });
    }
    this.sfx.play('explosion');
  }

  private updateChomer(p: Plant): void {
    if (p.digestTimer > 0) {
      p.digestTimer = Math.max(0, p.digestTimer - this.tickFrames);
      // 铁齿铜牙2：消化完毕才吐出腐蚀液——占据正前方 2 格，持续 5 秒（僵尸 15 血/秒）
      if (p.digestTimer === 0 && p.chewTier === 2) {
        for (let i = 1; i <= 2; i++) {
          this.groundFxs.push({
            x: p.x + p.w / 2 + this.cell * i, y: p.y + p.h / 2,
            timer: GAME_CONST.DIGEST_POOL_FRAMES, kind: 'digest'
          });
        }
      }
      return;
    }
    const cx: number = p.x + p.w / 2;
    const cy: number = p.y + p.h / 2;
    let target: Zombie | null = null;
    let bestGap: number = Number.MAX_VALUE;

    for (const z of this.zombieByCol[p.col]) {
      if (z.dead || z.friendly) continue; // 食人花不吃友军
      const zx: number = z.x + z.w / 2;
      const zy: number = z.y + z.h / 2;
      if (Math.abs(zy - cy) > this.cell / 2) continue;
      const gap: number = zx - cx;
      if (gap < 0) continue;
      // 咬合窗口约 2 格：能吞到正前方一格上正在啃坚果等的僵尸（按"本帧僵尸位移"动态扩展防跳判）
      const bite: number = this.cell * 2 + GAME_CONST.CHOMER_BITE_CELL_PAD * this.scale
        + z.speed * this.tickFrames;
      if (gap > bite) continue;
      if (gap < bestGap) {
        bestGap = gap;
        target = z;
      }
    }

    if (target !== null) {
      target.hp = 0;
      target.armorHp = 0;
      target.dead = true; // 整只吞掉：不掉金币
      // 铁齿铜牙：1级消化快50%，2级快100%
      p.digestTimer = GAME_CONST.CHOMER_DIGEST_FRAMES
        * (p.chewTier === 1 ? 0.67 : p.chewTier === 2 ? 0.5 : 1);
      this.sfx.play('bigchomp');
    }
  }

  private explodeArea(cx: number, cy: number, killRange: number, fxRadius: number, damage: number): void {
    for (const z of this.zombies) {
      if (z.dead || z.friendly) continue; // 友方植物不伤害魅惑友军
      const zcX = z.x + z.w / 2;
      const zcY = z.y + z.h / 2;
      if (Math.abs(zcX - cx) <= killRange && Math.abs(zcY - cy) <= killRange) {
        // 先扣防具再扣本体（樱桃强化后伤害可被高防具部分抵挡的框架）
        let remain = damage;
        if (z.armorHp > 0) {
          if (z.armorHp >= remain) {
            z.armorHp -= remain;
            remain = 0;
          } else {
            remain -= z.armorHp;
            z.armorHp = 0;
          }
        }
        z.hp -= remain;
        if (z.hp <= 0) {
          z.dead = true;
          this.maybeDropCoin(z);
        }
      }
    }
    this.effects.push({
      x: cx, y: cy, radius: fxRadius,
      timer: 24, maxTimer: 24
    });
  }

  private updatePotato(p: Plant): void {
    // 炮击指南术2：每15秒自动发射（本行有僵尸才发）
    if (p.cannon && p.cannonAuto) {
      p.cannonTimer -= this.tickFrames;
      if (p.cannonTimer <= 0) {
        const hasTarget = this.zombieByCol[p.col].some((z: Zombie) =>
          !z.dead && !z.friendly && z.x < this.canvasW && z.x > p.x);
        if (hasTarget) {
          this.firePotatoShell(p);
          p.cannonTimer = GAME_CONST.POTATO_CANNON_INTERVAL;
        } else {
          p.cannonTimer = 30; // 没僵尸：稍后重试
        }
      }
    }
    if (!p.armed) {
      p.armTimer -= this.tickFrames;
      if (p.armTimer <= 0) {
        p.armed = true;
      }
      return;
    }
    const potatoCenterX = p.x + p.w / 2;
    const potatoCenterY = p.y + p.h / 2;
    for (const z of this.zombies) {
      if (z.dead || z.friendly) continue;
      const zombieCenterX = z.x + z.w / 2;
      const zombieCenterY = z.y + z.h / 2;
      if (Math.abs(zombieCenterY - potatoCenterY) > this.cell / 2) continue;
      if (Math.abs(zombieCenterX - potatoCenterX) <= GAME_CONST.POTATO_TRIGGER_DIST * this.scale) {
        for (const target of this.zombies) {
          if (target.dead || target.friendly) continue;
          const tCX = target.x + target.w / 2;
          const tCY = target.y + target.h / 2;
          if (Math.abs(tCY - potatoCenterY) > this.cell / 2) continue;
          if (Math.abs(tCX - potatoCenterX) <= this.cell + this.zombieW / 2) {
            // 固定伤害（不再直接清空）：与樱桃/毁灭菇统一，先扣护甲再扣本体
            this.applyZombieDamage(target, GAME_CONST.EXPLOSION_DAMAGE);
            if (target.hp <= 0) {
              target.dead = true;
              this.maybeDropCoin(target);
            }
          }
        }
        this.effects.push({
          x: potatoCenterX, y: potatoCenterY, radius: 60,
          timer: 18, maxTimer: 18
        });
        this.sfx.play('potato_mine');
        p.dead = true;
        break;
      }
    }
  }
  /** 光能鼓舞：被鼓舞阳光菇左右两格地块上的植物攻速加成
   *  1级 ×1.25（+25%），2级 ×1.5（+50%）；孢子蔓延术2的地块标记 +25%，
   *  两者取最大值不叠加；返回 fireTimer 消耗倍率 */
  private fireRate(p: Plant): number {
    let mult: number = 1;
    if (p.sporeMark) {
      mult = 1.25; // 孢子蔓延术2：种在复制体地块上的植物攻速+25%
    }
    for (const m of this.plants) {
      if (m.dead || m === p || m.kind !== PlantKind.SUNSHROOM || m.sunBoostTier <= 0) continue;
      if (m.col !== p.col) continue;                        // 必须同行
      if (Math.abs(m.x - p.x) <= this.cell * 1.6) {         // 左右相邻一格
        mult = Math.max(mult, m.sunBoostTier === 2 ? 1.5 : 1.25);
      }
    }
    return mult;
  }

  /** 豌豆/双发/寒冰：本行有非友军僵尸进入画面即开火；强化后按商店等级随机发射特殊子弹 */
  private updateShooter(p: Plant): void {
    p.fireTimer -= this.tickFrames * this.fireRate(p);
    const hasZombieInCol = this.zombieByCol[p.col].some((z: Zombie) =>
      !z.dead && !z.friendly && z.x < this.canvasW);
    if (hasZombieInCol && p.fireTimer <= 0) {
      if (p.kind === PlantKind.SHOOTER && p.enhanced) {
        // 豌豆强化术：1级 寒冰60%/普通40%；2级 火焰50%/寒冰30%/普通20%（火焰双倍伤害）
        const tier: number = this.up('pea');
        const r: number = Math.random();
        let kind: BulletKind = BulletKind.PEA;
        let dmg = 20;
        if (tier === 1) {
          kind = r < 0.6 ? BulletKind.ICE : BulletKind.PEA;
        } else {
          if (r < 0.5) {
            kind = BulletKind.FIRE;
            dmg = 40;
          } else if (r < 0.8) {
            kind = BulletKind.ICE;
          }
        }
        this.bullets.push(this.makePea(p, kind, 0, dmg));
      } else if (p.kind === PlantKind.DOUBLE && p.enhanced) {
        // 豌豆武装：1级 石化40%（双倍伤害、无击退）/普通60%；
        //          2级 石化60%（双倍伤害+轻微击退）/普通40%（子弹等级按植物自身 peaArmTier）
        const tier: number = p.peaArmTier;
        const stoneChance: number = tier === 2 ? 0.6 : 0.4;
        const isStone: boolean = Math.random() < stoneChance;
        const kind: BulletKind = isStone ? BulletKind.STONE : BulletKind.PEA;
        const dmg: number = isStone ? 40 : 20;
        const knock: number = isStone && tier === 2 ? GAME_CONST.STONE_KNOCKBACK : 0;
        this.bullets.push(this.makePea(p, kind, -6, dmg, knock));
        this.bullets.push(this.makePea(p, kind, 6, dmg, knock));
      } else if (p.kind === PlantKind.ICE && p.enhanced) {
        // 寒冰炼成术：1级 寒冰60%/极寒40%；2级 寒冰30%/极寒70%（3连击冻结、2级附带冻伤）
        const tier: number = this.up('ice');
        const kind: BulletKind = Math.random() < (tier === 1 ? 0.6 : 0.3)
          ? BulletKind.ICE : BulletKind.FROST;
        this.bullets.push(this.makePea(p, kind, 0, 20));
      } else {
        switch (p.kind) {
          case PlantKind.SHOOTER:
            this.bullets.push(this.makePea(p, BulletKind.PEA, 0, 20));
            break;
          case PlantKind.DOUBLE:
            this.bullets.push(this.makePea(p, BulletKind.PEA, -6, 20));
            this.bullets.push(this.makePea(p, BulletKind.PEA, 6, 20));
            break;
          case PlantKind.ICE:
            this.bullets.push(this.makePea(p, BulletKind.ICE, 0, 20));
            break;
          default:
            break;
        }
      }
      p.fireTimer = GAME_CONST.SHOOTER_FIRE_INTERVAL;
      this.sfx.play('throw', 100);
    }
  }

  /** 生成豌豆类子弹；knock = 命中击退距离（px，0 = 无击退），石化子弹按武装等级指定 */
  private makePea(p: Plant, kind: BulletKind, offset: number, damage: number, knock: number = 0): Bullet {
    return {
      x: p.x + p.w / 2 + offset, y: p.y + p.h / 2, w: 12, h: 12,
      damage: damage * GAME_CONST.BULLET_DMG_MULT, speed: GAME_CONST.BULLET_SPEED * this.scale, col: p.col,
      kind: kind, dead: false,
      knock: knock,
      startX: p.x + p.w / 2 + offset, range: 0
    };
  }

  /** 小喷菇：0费，射程4格，射速同射手，孢子（紫）；白天睡觉不攻击；
   *  孢子蔓延术：蔓延计时（白天睡觉也照常计时蔓延） */
  private updatePuff(p: Plant): void {
    if (p.sporeSpawnTimer > 0) {
      p.sporeSpawnTimer -= this.tickFrames;
      if (p.sporeSpawnTimer <= 0) {
        p.sporeSpawnTimer = 0;
        this.spawnPuffCopy(p, 1); // 延时后往右侧生成复制体
      }
    }
    if (p.sporeSelfTimer > 0) {
      p.sporeSelfTimer -= this.tickFrames;
      if (p.sporeSelfTimer <= 0) {
        p.sporeSelfTimer = 0;
        p.sporeCopy = true; // 孢子蔓延术2：本体7.5秒后变成复制体（颜色变浅、可被种植替换）
      }
    }
    if (!this.night) return; // 蘑菇白天睡觉（原版规则）
    p.fireTimer -= this.tickFrames * this.fireRate(p);
    const maxDist: number = GAME_CONST.SHROOM_RANGE_CELLS * this.cell;
    const inRange = this.zombieByCol[p.col].some((z: Zombie) => {
      if (z.dead || z.friendly || z.x >= this.canvasW) return false;
      const gap: number = z.x - (p.x + p.w / 2);
      return gap > -10 && gap <= maxDist;
    });
    if (inRange && p.fireTimer <= 0) {
      this.bullets.push({
        x: p.x + p.w / 2, y: p.y + p.h / 2, w: 10, h: 10,
        damage: 20 * GAME_CONST.BULLET_DMG_MULT, speed: GAME_CONST.BULLET_SPEED * this.scale, col: p.col,
        kind: BulletKind.SPORE, dead: false,
        knock: 0,
        startX: p.x + p.w / 2, range: maxDist
      });
      p.fireTimer = GAME_CONST.SHOOTER_FIRE_INTERVAL;
      this.sfx.play('throw', 150);
    }
  }

  /** 孢子蔓延术：在 p 紧邻（offset 方向一格，同一行）生成小喷菇复制体；
   *  紧邻格已有植物时改为强化该植物（获得 sporeMark 攻速+25%，效果与种在复制体地块一致）
   *  复制体为独立实体（颜色更浅、属性同小喷菇），任何植物都可种植在其地块上并替换它
   *  注意：Plant.col 实际是行索引，列位置必须用 x 坐标推算 */
  private spawnPuffCopy(p: Plant, offset: number): void {
    const x: number = p.x + offset * this.cell;
    // 越界（草坪左右边界之外）：无处生成
    if (x < this.gridLeft || x + this.plantW > this.gridLeft + GAME_CONST.LAWN_COLS * this.cell) {
      return;
    }
    const neighbor: Plant | null = this.findPlantAt(x, p.y);
    if (neighbor !== null) {
      // 紧邻格被占：给该植物强化（与种在复制体地块相同：sporeMark 攻速+25%），不生成复制体
      if (!neighbor.sporeMark) {
        neighbor.sporeMark = true;
        this.sfx.play('plant');
      }
      return;
    }
    const cx: number = x + this.plantW / 2;
    const cy: number = p.y + this.plantW / 2;
    for (const g of this.groundFxs) {
      if ((g.kind === 'lava' || g.kind === 'crater' || g.kind === 'radiation')
        && Math.abs(g.x - cx) <= this.cell / 2
        && Math.abs(g.y - cy) <= this.cell / 2) {
        return; // 弹坑/熔岩上不能生成
      }
    }
    const stats = getPlantStats(PlantKind.PUFF);
    const copy: Plant = {
      x: x, y: p.y, w: this.plantW, h: this.plantW,
      hp: stats.hp, maxHp: stats.hp, dead: false,
      fireTimer: 0, col: p.col, kind: PlantKind.PUFF, sunTimer: 0, armTimer: 0, armed: false,
      digestTimer: 0, growTimer: 0, grown: false, scared: false, scaredyTier: 0, fumeTier: 0,
      enhanced: false, doubleSun: false, fastSun: false,
      cannon: false, cannonAuto: false, cannonTimer: 0,
      armorHp: 0, maxArmorHp: 0, armorTier: 0, chewTier: 0, sunBoostTier: 0, peaArmTier: 0,
      sporeCopy: true, sporeMark: false, sporeTier: 0, sporeSpawnTimer: 0, sporeSelfTimer: 0
    };
    this.plants.push(copy);
    this.sfx.play('plant');
  }

  /** 阳光菇：夜晚产阳光（向日葵夜里罢工）；小时候产15，60秒长大后产25且更快；白天睡觉不产 */
  private updateSunshroom(p: Plant): void {
    if (!this.night) return; // 蘑菇白天睡觉（原版规则）
    if (p.growTimer > 0) {
      p.growTimer -= this.tickFrames;
      if (p.growTimer <= 0) {
        p.grown = true;
        p.sunTimer = GAME_CONST.SUNSHROOM_BIG_INTERVAL;
      }
    }
    p.sunTimer -= this.tickFrames;
    if (p.sunTimer <= 0) {
      // 光能鼓舞：未强化长大产普通阳光25；1级超大阳光50、2级75；未长大产小阳光
      let value: number = p.grown ? GAME_CONST.SUNSHROOM_BIG_VALUE : GAME_CONST.SUNSHROOM_SMALL_VALUE;
      if (p.grown && p.sunBoostTier === 1) value = 50;
      if (p.grown && p.sunBoostTier === 2) value = 75;
      const bigSun: boolean = value >= 50;             // 超大阳光（强化产出50/75）：渲染更大一圈
      const dropSize: number = bigSun ? 40 : 24;
      const targetX = p.x + (p.w - 18) / 2;
      const targetY = p.y + p.h / 2;
      this.sunDrops.push({
        x: p.x + p.w / 2, y: p.y + p.h / 2, w: dropSize, h: dropSize,
        value: value, targetX: targetX, targetY: targetY,
        moveProgress: 0, moveSpeed: GAME_CONST.SUN_FALL_SPEED,
        pauseTimer: GAME_CONST.SUN_LIFETIME_FRAMES,
        hasLanded: false, dead: false,
        collecting: false, stolenBy: null
      });
      p.sunTimer = p.grown ? GAME_CONST.SUNSHROOM_BIG_INTERVAL : GAME_CONST.SUNSHROOM_SMALL_INTERVAL;
    }
  }

  /**
   * 胆小菇：整行攻击；前方一格内有僵尸 → 变白不攻击（原版行为）；白天睡觉不攻击。
   * 孢子狙击术：1级子弹50%概率暴击（伤害同时对护甲和本体生效）；2级75%暴击+子弹可穿透一名僵尸
   */
  private updateScaredy(p: Plant): void {
    if (!this.night) return; // 蘑菇白天睡觉（原版规则）
    const px: number = p.x + p.w / 2;
    let scared: boolean = false;
    let hasTarget: boolean = false;
    for (const z of this.zombieByCol[p.col]) {
      if (z.dead || z.friendly || z.x >= this.canvasW) continue;
      const gap: number = z.x - px;
      if (gap > -10) hasTarget = true;
      if (gap > -10 && gap <= GAME_CONST.SCAREDY_CELLS * this.cell) {
        scared = true;
        break;
      }
    }
    p.scared = scared;
    if (scared) return; // 害怕时不攻击（原版行为，强化不改）
    p.fireTimer -= this.tickFrames * this.fireRate(p);
    if (hasTarget && p.fireTimer <= 0) {
      const tier: number = p.scaredyTier;
      const critChance: number = tier >= 2 ? GAME_CONST.SCAREDY_CRIT_T2
        : (tier >= 1 ? GAME_CONST.SCAREDY_CRIT_T1 : 0);
      this.bullets.push({
        x: px, y: p.y + p.h / 2, w: 10, h: 10,
        damage: 20 * GAME_CONST.BULLET_DMG_MULT, speed: GAME_CONST.BULLET_SPEED * this.scale, col: p.col,
        kind: BulletKind.SPORE, dead: false,
        knock: 0,
        startX: px, range: 0, // 整行射程
        crit: critChance > 0 && Math.random() < critChance,
        pierceLeft: tier >= 2 ? 1 : 0,
        hitZombies: []
      });
      p.fireTimer = GAME_CONST.SHOOTER_FIRE_INTERVAL;
      this.sfx.play('throw', 150);
    }
  }

  /**
   * 大喷菇：孢子群横扫，范围内所有僵尸都受伤；射程对齐原版4.5格。
   * 伤害分流（原版规则）：铁门/读报僵尸 → 护甲和本体同时受创；其他护甲 → 先护甲后本体。
   * 孢子雾化术：1级射程提升至5格；2级伤害+25%，且有2.5%概率直接吹落头部护甲（路障/铁桶/橄榄/黑橄榄）
   */
  private updateFume(p: Plant): void {
    if (!this.night) return; // 蘑菇白天睡觉（原版规则）
    p.fireTimer -= this.tickFrames * this.fireRate(p);
    const px: number = p.x + p.w / 2;
    const maxDist: number = (p.fumeTier >= 1 ? GAME_CONST.FUME_RANGE_UP_CELLS
      : GAME_CONST.FUME_RANGE_CELLS) * this.cell;
    const inRange = this.zombieByCol[p.col].some((z: Zombie) => {
      if (z.dead || z.friendly || z.x >= this.canvasW) return false;
      const gap: number = z.x - px;
      return gap > -10 && gap <= maxDist;
    });
    if (!inRange || p.fireTimer > 0) return;
    p.fireTimer = GAME_CONST.FUME_INTERVAL;
    let dmg: number = 20 * GAME_CONST.BULLET_DMG_MULT;
    if (p.fumeTier >= 2) dmg *= GAME_CONST.FUME_DMG_UP_MULT; // 雾化术2：伤害+25%
    for (const z of this.zombieByCol[p.col]) {
      if (z.dead || z.friendly) continue;
      const gap: number = (z.x + z.w / 2) - px;
      if (gap < -10 || gap > maxDist + z.w) continue;
      if (z.zombieKind === ZombieKind.Door || z.zombieKind === ZombieKind.Newspaper) {
        // 铁门/报纸：护甲和本体同时受创（原版孢子规则）
        this.applyZombieDamageBoth(z, dmg);
      } else {
        this.applyZombieDamage(z, dmg); // 其他护甲：先护甲后本体
      }
      // 雾化术2：小概率吹落头部护甲（仅路障/铁桶/橄榄/黑橄榄；报纸铁门不适用）
      if (p.fumeTier >= 2 && z.armorHp > 0 && !z.friendly && !z.dead
        && (z.zombieKind === ZombieKind.Cone || z.zombieKind === ZombieKind.Bucket
          || z.zombieKind === ZombieKind.Football || z.zombieKind === ZombieKind.DarkFootball)
        && Math.random() < GAME_CONST.FUME_STRIP_ARMOR_CHANCE) {
        z.armorHp = 0;
        z.zombieKind = ZombieKind.Normal;
      }
    }
    // 紫色孢子云特效：随射程变化的云带
    this.effects.push({
      x: px + maxDist / 2, y: p.y + p.h / 2,
      radius: maxDist / 2,
      timer: 18, maxTimer: 18,
      color: "#9575cd", fxKind: 'fume'
    });
    this.sfx.play('throw', 150);
  }

  /** 读报僵尸狂暴：报纸被打烂 → 移速2.5倍 + 啃食2倍 */
  private enrageNewspaper(z: Zombie): void {
    if (z.enraged) return;
    z.enraged = true;
    z.speed = GAME_CONST.ZOMBIE_SPEED * this.scale * GAME_CONST.NEWSPAPER_RAGE_SPEED_MULT * this.diffMult;
  }

  /** 向日葵：只在白天产阳光（夜晚罢工）；阳光催化：一次两份，2级间隔减半 */
  private updateSunflower(p: Plant): void {
    // 夜晚向日葵照常产阳光（夜晚仅天空不掉落阳光）
    p.sunTimer -= this.tickFrames;
    if (p.sunTimer <= 0) {
      const targetX = p.x + (p.w - 18) / 2;
      const targetY = p.y + p.h / 2;
      this.sunDrops.push({
        x: p.x + p.w / 2, y: p.y + p.h / 2, w: 24, h: 24,
        value: GAME_CONST.SUN_NORMAL_VALUE, targetX: targetX, targetY: targetY,
        moveProgress: 0, moveSpeed: GAME_CONST.SUN_FALL_SPEED, pauseTimer: GAME_CONST.SUN_LIFETIME_FRAMES,
        hasLanded: false, dead: false, collecting: false, stolenBy: null
      });
      // 阳光催化术：一次产出两个阳光（错开一点位置方便都点到）
      if (p.doubleSun) {
        this.sunDrops.push({
          x: p.x + p.w / 2, y: p.y + p.h / 2, w: 24, h: 24,
          value: GAME_CONST.SUN_NORMAL_VALUE, targetX: targetX + 26, targetY: targetY,
          moveProgress: 0, moveSpeed: GAME_CONST.SUN_FALL_SPEED, pauseTimer: GAME_CONST.SUN_LIFETIME_FRAMES,
          hasLanded: false, dead: false, collecting: false, stolenBy: null
        });
      }
      // 阳光催化术2：产出间隔缩短50%
      p.sunTimer = p.fastSun
        ? GAME_CONST.SUNFLOWER_SUN_INTERVAL / 2
        : GAME_CONST.SUNFLOWER_SUN_INTERVAL;
    }
  }

  private updateBullets(): void {
    for (const b of this.bullets) {
      if (b.dead) continue;
      b.x += b.speed * this.tickFrames;
      // 孢子射程限制（小喷菇4格，胆小菇整行）
      if (b.range > 0 && b.x - b.startX > b.range) {
        b.dead = true;
        continue;
      }
      for (const z of this.zombieByCol[b.col]) {
        if (z.dead || b.dead || z.friendly || z.x > this.canvasW) continue;
        // 穿透子弹：已命中过的僵尸不再重复结算
        if (b.hitZombies !== undefined && b.hitZombies.length > 0 && b.hitZombies.indexOf(z) !== -1) continue;
      if (this.checkAABBBulletZombie(b, z)) {
        // 土豆炮弹：命中即引爆一格AOE
        if (b.kind === BulletKind.SHELL) {
          b.dead = true;
          this.explodeArea(b.x, b.y, this.cell, 60, GAME_CONST.SHELL_DAMAGE);
          this.sfx.play('explosion');
          break;
        }
        const hadArmor: boolean = z.armorHp > 0;
        const armorKind: ZombieKind = z.zombieKind; // 护甲材质（applyZombieDamage 内可能重置种类）
          if (b.crit === true) {
            // 孢子狙击术暴击：护甲和本体同时受创（无视护甲分流）
            this.applyZombieDamageBoth(z, b.damage);
          } else {
            this.applyZombieDamage(z, b.damage); // 护甲先行，溢出进本体（读报狂暴在内部处理）
          }
          // ===== 特殊子弹效果 =====
          if (b.kind === BulletKind.ICE) {
            z.slowTimer = GAME_CONST.ICE_SLOW_FRAMES;
          } else if (b.kind === BulletKind.FIRE) {
            // 火焰：解除寒冰/极寒的全部效果（减速、冻结、冻伤及计时、计数、染色）
            z.slowTimer = 0;
            z.frozenTimer = 0;
            z.frostbite = false;
            z.frostbiteTimer = 0;
            z.frostHits = 0;
            z.frostTinted = false;
          } else if (b.kind === BulletKind.STONE) {
            // 石化：按子弹自带击退值击退（武装1级=0无击退 / 2级=轻微击退），不影响寒冰/极寒效果
            z.x += b.knock * this.scale;
          } else if (b.kind === BulletKind.FROST) {
            // 极寒：减速同寒冰（不叠加）；累计命中3次冻结3秒（冻结期间也计数，满3次刷新冻结为3秒）；染色深蓝
            z.frostTinted = true;
            z.slowTimer = Math.max(z.slowTimer, GAME_CONST.ICE_SLOW_FRAMES);
            z.frostHits += 1;
            if (z.frostHits >= GAME_CONST.FROST_FREEZE_HITS) {
              z.frozenTimer = GAME_CONST.FROST_FREEZE_FRAMES; // 首次触发或冻结中刷新：都是3秒
              z.frostHits = 0;
            }
            // 寒冰炼成术2：附带冻伤（每秒7.5血，无视护甲；持续5秒，再次击中刷新）
            if (this.up('ice') === 2) {
              z.frostbite = true;
              z.frostbiteTimer = GAME_CONST.FROSTBITE_FRAMES;
            }
          }
          if (hadArmor) {
            // 护甲音效按材质区分：路障/橄榄球头盔（塑料）→ plastichit2；铁桶/铁门（金属）→ shieldhit2
            const plastic: boolean = armorKind === ZombieKind.Cone
              || armorKind === ZombieKind.Football || armorKind === ZombieKind.DarkFootball;
            this.sfx.play(plastic ? 'plastichit2' : 'shieldhit2', GAME_CONST.SFX_SPLAT_THROTTLE_MS);
          } else {
            this.sfx.play('splat3', GAME_CONST.SFX_SPLAT_THROTTLE_MS);
          }
          if (b.hitZombies !== undefined) {
            b.hitZombies.push(z);
          }
          if ((b.pierceLeft ?? 0) > 0) {
            // 孢子狙击术2穿透：命中后子弹继续飞行，可再打一名僵尸（有护甲也照常结算）
            b.pierceLeft = (b.pierceLeft ?? 1) - 1;
          } else {
            b.dead = true;
          }
          break;
        }
      }
      if (b.x > this.canvasW + 20) {
        b.dead = true;
      }
    }
  }

  private updateSunDrops(): void {
    // 左上角阳光计数器中心（收集飞行终点）
    const counterX: number = CARD_START_X + 32;
    const counterY: number = CARD_START_Y + 32;
    for (const s of this.sunDrops) {
      if (s.dead) continue;
      // ===== 被玩家点击：飞向计数器，到达入账 =====
      if (s.collecting) {
        const k = 1 - Math.pow(0.78, this.tickFrames);
        s.x += (counterX - s.x) * k;
        s.y += (counterY - s.y) * k;
        const dxC: number = s.x - counterX;
        const dyC: number = s.y - counterY;
        if (dxC * dxC + dyC * dyC <= 10 * 10) {
          this.sun += s.value;
          s.dead = true;
          this.sfx.play('points');
        }
        continue;
      }
      // ===== 被盗贼锁定：变红缓慢飞向盗贼，接触即消失（不入账） =====
      if (s.stolenBy !== null) {
        const thief: Zombie | null = s.stolenBy;
        if (thief.dead) {
          s.stolenBy = null; // 盗贼死亡：阳光恢复正常
          continue;
        }
        const tx: number = thief.x + thief.w / 2;
        const ty: number = thief.y + thief.h / 2;
        const k = 1 - Math.pow(0.985, this.tickFrames);
        s.x += (tx - s.x) * k;
        s.y += (ty - s.y) * k;
        const dxT: number = s.x - tx;
        const dyT: number = s.y - ty;
        if (dxT * dxT + dyT * dyT <= (thief.w / 2) * (thief.w / 2)) {
          s.dead = true; // 被偷走：阳光数不增加
        }
        continue;
      }
      if (!s.hasLanded) {
        s.moveProgress += s.moveSpeed * this.tickFrames;
        if (s.moveProgress >= 1) {
          s.moveProgress = 1;
          s.hasLanded = true;
          s.pauseTimer = GAME_CONST.SUN_LIFETIME_FRAMES;
        }
        const k = 1 - Math.pow(0.92, this.tickFrames);
        s.x = s.x + (s.targetX - s.x) * k;
        s.y = s.y + (s.targetY - s.y) * k;
      } else {
        s.pauseTimer -= this.tickFrames;
        if (s.pauseTimer <= 0) {
          s.collecting = true; // 超时自动收集：飞向阳光计数器再入账（与点击收集同路径）
        }
      }
    }
  }

  private updateCoins(): void {
    // 右上角金钱计数器中心（金币飞行终点，与 HUD 的 $ 计数位置对齐）
    const counterX: number = this.canvasW - 110;
    const counterY: number = CARD_START_Y + 32;
    for (const c of this.coins) {
      if (c.dead) continue;
      // ===== 已收集：飞向右上角金钱计数器，到达入账 =====
      if (c.collecting) {
        const k = 1 - Math.pow(0.78, this.tickFrames);
        c.x += (counterX - c.x) * k;
        c.y += (counterY - c.y) * k;
        const dxC: number = c.x - counterX;
        const dyC: number = c.y - counterY;
        if (dxC * dxC + dyC * dyC <= 12 * 12) {
          this.finishCoin(c);
        }
        continue;
      }
      c.timer -= this.tickFrames;
      if (c.timer <= 0) {
        c.collecting = true; // 超时自动收集：同样飞向金钱计数器再入账
      }
    }
  }

  /** 金币到账：置死 + 回调页面层入账存档 + 到账音效（钻石专用音效，其余金币用金币音） */
  private finishCoin(c: CoinDrop): void {
    c.dead = true;
    if (this.onCoinGain !== null) {
      this.onCoinGain(c.value);
    }
    this.sfx.play(c.kind === 'diamond' ? 'diamond' : 'coin');
  }

  /**
   * 僵尸受击的统一结算（子弹 / 孢子群共用）：
   * 先扣护甲，溢出部分进本体；护甲被打碎时读报僵尸狂暴、防具类型还原为普通
   */
  private applyZombieDamage(z: Zombie, dmg: number): void {
    if (z.brittleTimer > 0) {
      dmg = dmg * GAME_CONST.ICE_BRITTLE_MULT; // 冰脆：受伤+25%
    }
    let remainDmg: number = dmg;
    if (z.armorHp > 0) {
      if (z.armorHp >= remainDmg) {
        z.armorHp -= remainDmg;
        remainDmg = 0;
      } else {
        remainDmg -= z.armorHp;
        z.armorHp = 0;
        if (z.zombieKind === ZombieKind.Newspaper) {
          this.enrageNewspaper(z); // 读报僵尸：报纸被打烂 → 狂暴
        }
        z.zombieKind = ZombieKind.Normal;
      }
    }
    if (remainDmg > 0) {
      z.hp -= remainDmg;
    }
  }

  /**
   * 双承伤结算（孢子狙击暴击 / 大喷菇对铁门·读报）：
   * 同一次伤害同时作用于护甲与本体（护甲不打分流，本体也吃满额）；
   * 护甲被打碎时读报僵尸狂暴、防具类型还原为普通（与常规结算一致）
   */
  private applyZombieDamageBoth(z: Zombie, dmg: number): void {
    if (z.brittleTimer > 0) {
      dmg = dmg * GAME_CONST.ICE_BRITTLE_MULT; // 冰脆：受伤+25%
    }
    if (z.armorHp > 0) {
      z.armorHp -= dmg;
      if (z.armorHp <= 0) {
        z.armorHp = 0;
        if (z.zombieKind === ZombieKind.Newspaper) {
          this.enrageNewspaper(z); // 读报僵尸：报纸被打烂 → 狂暴
        }
        z.zombieKind = ZombieKind.Normal;
      }
    }
    z.hp -= dmg;
  }

  /**
   * 点击收集金币，命中返回 true（组件层据此吞掉这次点击）
   */
  collectCoinAt(clickX: number, clickY: number): boolean {
    for (const c of this.coins) {
      if (c.dead || c.collecting) continue;
      const dx = clickX - c.x;
      const dy = clickY - c.y;
      if (dx * dx + dy * dy <= 28 * 28) {
        c.collecting = true; // 点击收集：飞向金钱计数器再入账
        return true;
      }
    }
    return false;
  }

  /**
   * 点击收集阳光（夜晚关卡阳光来自阳光菇）
   * 命中后阳光起飞，飞向左上角计数器后入账；被盗贼锁定的阳光无法拾取
   */
  collectSunAt(clickX: number, clickY: number): boolean {
    const counterX: number = CARD_START_X + 32;
    const counterY: number = CARD_START_Y + 32;
    for (const s of this.sunDrops) {
      if (s.dead || s.collecting || s.stolenBy !== null) continue;
      const dx = clickX - s.x;
      const dy = clickY - s.y;
      if (dx * dx + dy * dy <= 30 * 30) {
        s.collecting = true; // 起飞：到达计数器后由 updateSunDrops 入账
        s.targetX = counterX;
        s.targetY = counterY;
        return true;
      }
    }
    return false;
  }

  private cleanDeadEntities(): void {
    // 盗贼死亡：释放其锁定的阳光（恢复正常）
    for (const z of this.zombies) {
      if (!z.dead) continue;
      // 记录死亡位置：清场后最后一只死亡的僵尸在此掉落新植物卡片
      this.lastDeathX = z.x + z.w / 2;
      this.lastDeathY = z.y + z.h / 2;
      for (const s of this.sunDrops) {
        if (s.stolenBy === z) {
          s.stolenBy = null;
        }
      }
    }
    this.plants = this.plants.filter((p: Plant) => !p.dead);
    this.bullets = this.bullets.filter((b: Bullet) => !b.dead);
    this.zombies = this.zombies.filter((z: Zombie) => !z.dead);
    this.sunDrops = this.sunDrops.filter((s: SunDrop) => !s.dead);
    this.coins = this.coins.filter((c: CoinDrop) => !c.dead);
    for (let c = 0; c < this.colCount; c++) {
      this.zombieByCol[c] = this.zombieByCol[c].filter((z: Zombie) => !z.dead);
    }
  }

  // ====================== 碰撞检测 ======================

  private checkAABBPlantZombie(p: Plant, z: Zombie): boolean {
    if (p.kind === PlantKind.POTATO && p.armed) {
      return false;
    }
    return p.x < z.x + z.w && p.x + p.w > z.x && p.y < z.y + z.h && p.y + p.h > z.y;
  }

  private checkAABBBulletZombie(b: Bullet, z: Zombie): boolean {
    return b.x < z.x + z.w && b.x + b.w > z.x && b.y < z.y + z.h && b.y + b.h > z.y;
  }

  private findPlantColliding(z: Zombie): Plant | null {
    for (const p of this.plants) {
      if (p.dead) continue;
      if (this.checkAABBPlantZombie(p, z)) {
        return p;
      }
    }
    return null;
  }

  private updateEffects(): void {
    this.effects = this.effects.filter((fx: ExplosionFx) => {
      fx.timer -= this.tickFrames;
      return fx.timer > 0;
    });
  }

  // ====================== 卡片冷却 ======================

  isCardReady(key: string): boolean {
    for (const c of this.cardCooldowns) {
      if (c.key === key) return c.remain <= 0;
    }
    return true;
  }

  private startCooldown(key: string): void {
    const cd = getCardCooldown(key);
    if (cd <= 0) return;
    for (const c of this.cardCooldowns) {
      if (c.key === key) {
        c.remain = cd;
        return;
      }
    }
    this.cardCooldowns.push({ key: key, remain: cd });
  }

  private tickCooldowns(): void {
    this.cardCooldowns = this.cardCooldowns.filter((c: CardCooldown) => {
      c.remain -= this.tickFrames;
      return c.remain > 0;
    });
  }

  // ====================== 玩家操作（种植 / 铲除） ======================

  /**
   * 处理网格区域的点击（卡片/传送带由组件层处理）
   * 返回是否产生了实际操作（种下/铲除），组件层据此取消选中
   */
  handleGridClick(clickX: number, clickY: number, selectedKey: string): boolean {
    if (selectedKey === "") return false;
    if (clickX < this.leftPanelW) return false; // 左侧卡片区不参与种植

    const col: number = Math.floor((clickX - this.gridLeft) / this.cell);
    const lane: number = Math.floor((clickY - this.gridTop) / this.cell);
    if (col < 0 || col >= GAME_CONST.LAWN_COLS || lane < 0 || lane >= this.colCount) return false;

    // 熔岩地面（火药强化术2）/ 毁灭菇弹坑（含辐射坑）不可种植
    const plantCx: number = this.gridLeft + col * this.cell + this.cell / 2;
    const plantCy: number = this.gridTop + lane * this.cell + this.cell / 2;
    for (const g of this.groundFxs) {
      if ((g.kind === 'lava' || g.kind === 'crater' || g.kind === 'radiation')
        && Math.abs(g.x - plantCx) <= this.cell / 2
        && Math.abs(g.y - plantCy) <= this.cell / 2) {
        return false;
      }
    }

    const plantX: number = this.gridLeft + col * this.cell + (this.cell - this.plantW) / 2;
    const plantY: number = this.gridTop + lane * this.cell
      + (this.cell - this.plantW) / 2;

    if (selectedKey === PlantKind.SHOVEL) {
      return this.shovelPlantAt(plantX, plantY);
    }

    const existing: Plant | null = this.findPlantAt(plantX, plantY);
    if (existing !== null && existing.sporeCopy) {
      // 孢子蔓延术复制体地块：任何植物都可以种植，种植后替换复制体
      existing.dead = true;
      const ok: boolean = this.createPlant(selectedKey, plantX, plantY, lane);
      if (!ok) {
        existing.dead = false; // 种植失败（阳光不足/冷却中）恢复复制体
        return false;
      }
      // 孢子蔓延术2：种在复制体地块上的植物获得攻速+25%（与光能鼓舞取最大值不叠加），带紫色小圆标记（1级无此效果）
      if (this.up('spore') === 2) {
        const planted: Plant | null = this.findPlantAt(plantX, plantY);
        if (planted !== null) {
          planted.sporeMark = true;
        }
      }
      return ok;
    }
    if (existing === null) {
      return this.createPlant(selectedKey, plantX, plantY, lane);
    }
    return this.tryUpgradePlant(existing, selectedKey);
  }

  /**
   * 商店强化：对同格同类植物再次种植卡牌 → 强化（正常扣阳光+冷却）
   * 坚果=回血+护甲(银50%/金125%)；豌豆/双发/寒冰=解锁特殊子弹；向日葵=双产/加速；
   * 土豆=发射炮弹；食人花=消化加速
   */
  private tryUpgradePlant(existing: Plant, selectedKey: string): boolean {
    if (existing.dead) return false;
    // 孢子蔓延进行中（等待生成右复制体 / 等待本体转化为复制体）：不能被任何卡牌叠种
    if (existing.sporeSpawnTimer > 0 || existing.sporeSelfTimer > 0) return false;
    let upKey = '';
    if (selectedKey === PlantKind.WALL && existing.kind === PlantKind.WALL) {
      upKey = 'wall';
    } else if (selectedKey === PlantKind.SHOOTER && existing.kind === PlantKind.SHOOTER) {
      upKey = 'pea';
    } else if (selectedKey === PlantKind.DOUBLE && existing.kind === PlantKind.DOUBLE) {
      // 豌豆武装：双发射手卡叠种到双发射手上（双发专属）
      upKey = 'peaArm';
    } else if (selectedKey === PlantKind.SUNSHROOM && existing.kind === PlantKind.SUNSHROOM) {
      // 光能鼓舞：阳光菇卡叠种到阳光菇上（需商店购买，1级立即长大+超大阳光50，2级75）
      upKey = 'sunBoost';
    } else if (selectedKey === PlantKind.PUFF && existing.kind === PlantKind.PUFF) {
      // 孢子蔓延术：小喷菇卡叠种到小喷菇上（需商店购买，生成复制体向两侧蔓延）
      upKey = 'spore';
    } else if (selectedKey === PlantKind.ICE && existing.kind === PlantKind.ICE) {
      upKey = 'ice';
    } else if (selectedKey === PlantKind.SUNFLOWER && existing.kind === PlantKind.SUNFLOWER) {
      upKey = 'sun';
    } else if (selectedKey === PlantKind.POTATO && existing.kind === PlantKind.POTATO) {
      upKey = 'potato';
    } else if (selectedKey === PlantKind.CHOMER && existing.kind === PlantKind.CHOMER) {
      upKey = 'chomper';
    } else if (selectedKey === PlantKind.SCAREDY && existing.kind === PlantKind.SCAREDY) {
      // 孢子狙击术：胆小菇卡叠种到胆小菇上（胆小菇专属）
      upKey = 'scaredy';
    } else if (selectedKey === PlantKind.FUME && existing.kind === PlantKind.FUME) {
      // 孢子雾化术：大喷菇卡叠种到大喷菇上（大喷菇专属）
      upKey = 'fume';
    }
    if (upKey === '') return false;

    const tier: number = this.up(upKey);
    const legacyAid: boolean = upKey === 'wall' && tier === 0 && this.wallFirstAid;
    if (tier === 0 && !legacyAid) return false;

    const stats = getPlantStats(selectedKey as PlantKind);
    // 传送带关：植物免费发放，叠种升级同样免费且无冷却（否则永远凑不齐阳光）
    if (!this.conveyor && this.sun < stats.cost) return false;

    if (upKey === 'wall') {
      if (tier >= 1) {
        // 强化术：回满血 + 护甲（1级银50%，2级金125%）
        existing.hp = existing.maxHp;
        existing.armorTier = tier;
        existing.maxArmorHp = existing.maxHp * (tier === 1 ? 0.5 : 1.25);
        existing.armorHp = existing.maxArmorHp;
      } else {
        // 旧包扎术：仅回满血
        if (existing.hp >= existing.maxHp) return false;
        existing.hp = existing.maxHp;
      }
    } else if (upKey === 'pea' || upKey === 'ice') {
      if (existing.enhanced) return false; // 已强化不可重复
      existing.enhanced = true;
      if (tier === 2) existing.hp = existing.maxHp;
    } else if (upKey === 'peaArm') {
      // 豌豆武装：1级石化40%无击退；2级石化60%+轻微击退，叠种时回满血（可从1级叠升）
      if (existing.peaArmTier >= tier) return false;
      existing.peaArmTier = tier;
      existing.enhanced = true;
      if (tier === 2) existing.hp = existing.maxHp;
    } else if (upKey === 'sun') {
      if (existing.doubleSun) return false;
      existing.doubleSun = true;
      if (tier === 2) {
        existing.fastSun = true;
        existing.hp = existing.maxHp;
      }
      // 叠种刷新产阳光计时：与刚种下一样享受一次约7秒的快速首产
      existing.sunTimer = GAME_CONST.SUNFLOWER_FIRST_SUN_FRAMES;
    } else if (upKey === 'potato') {
      if (existing.cannon) return false;
      existing.cannon = true;
      existing.cannonAuto = tier === 2;
      existing.cannonTimer = GAME_CONST.POTATO_CANNON_INTERVAL;
      this.firePotatoShell(existing); // 种下立即发射一枚
    } else if (upKey === 'chomper') {
      if (existing.chewTier >= tier) return false;
      existing.chewTier = tier;
    } else if (upKey === 'sunBoost') {
      // 光能鼓舞：1级立即长大+超大阳光50；2级升级到75（可从1级叠升，同等级重复无效）
      if (existing.sunBoostTier >= tier) return false;
      existing.sunBoostTier = tier;
      existing.grown = true;
      existing.growTimer = 0;
      existing.sunTimer = Math.min(existing.sunTimer, GAME_CONST.SUNSHROOM_BIG_INTERVAL);
    } else if (upKey === 'scaredy') {
      // 孢子狙击术：1级子弹50%暴击（护甲+本体同时受伤）；2级75%暴击+穿透一名僵尸+回满血（可从1级叠升，同等级重复无效）
      if (existing.scaredyTier >= tier) return false;
      existing.scaredyTier = tier;
      if (tier === 2) {
        existing.hp = existing.maxHp;
        existing.scared = false;
      }
    } else if (upKey === 'fume') {
      // 孢子雾化术：1级射程4.5→5格；2级伤害+25%+2.5%概率吹落头部护甲+回满血（可从1级叠升，同等级重复无效）
      if (existing.fumeTier >= tier) return false;
      existing.fumeTier = tier;
      if (tier === 2) {
        existing.hp = existing.maxHp;
        existing.fireTimer = 0; // 立即喷一轮
      }
    } else if (upKey === 'spore') {
      // 孢子蔓延术：1级左侧立即生成复制体+5秒后右侧再生成一个；
      // 2级回满血+左侧复制体+2.5秒后右侧复制体+本体7.5秒后变复制体（可从1级叠升，蔓延中不可重复叠种）
      if (existing.sporeTier >= tier || existing.sporeSpawnTimer > 0 || existing.sporeSelfTimer > 0) {
        return false;
      }
      existing.sporeTier = tier;
      if (!existing.sporeMark) existing.sporeMark = true; // 被叠种的自己同样获得紫圆buff（攻速+25%）
      if (tier === 2) existing.hp = existing.maxHp; // 2级叠种回满血
      this.spawnPuffCopy(existing, -1);             // 立即往左侧生成复制体
      existing.sporeSpawnTimer = tier === 2 ? 150 : 300; // 2级2.5秒 / 1级5秒后右侧再生成
      if (tier === 2) existing.sporeSelfTimer = 450;     // 2级：本体7.5秒后变成复制体
    }

    if (!this.conveyor) {
      this.sun -= stats.cost;
      this.startCooldown(selectedKey);
    }
    this.sfx.play('plant');
    return true;
  }

  private findPlantAt(plantX: number, plantY: number): Plant | null {
    for (const p of this.plants) {
      if (p.dead) continue; // 跳过已死亡实体（尚未被清理循环移除）
      if (Math.abs(p.x - plantX) < 2 && Math.abs(p.y - plantY) < 2) {
        return p;
      }
    }
    return null;
  }

  private shovelPlantAt(plantX: number, plantY: number): boolean {
    const target = this.findPlantAt(plantX, plantY);
    if (target !== null) {
      target.dead = true;
      this.sfx.play('shovel');
      return true;
    }
    return false;
  }

  /** 寒冰菇：种下瞬间冰冻全场僵尸（全屏蓝色闪光），解冻后接一段减速；一次性，用后消失 */
  private triggerIceShroom(p: Plant): void {
    const tier: number = this.up('iceShroom'); // 极寒封冻术：1级冰冻6.5秒+减速翻倍，2级冰脆
    for (const z of this.zombies) {
      if (z.dead || z.friendly) continue;
      z.frozenTimer = tier >= 1
        ? GAME_CONST.ICE_SHROOM_FREEZE_FRAMES_UP
        : GAME_CONST.ICE_SHROOM_FREEZE_FRAMES;
      // 冻结期间 slowTimer 不倒计时（updateZombies 冻结分支直接跳过），解冻后自然生效
      z.slowTimer = Math.max(z.slowTimer, tier >= 1 ? GAME_CONST.ICE_SLOW_FRAMES * 2 : GAME_CONST.ICE_SLOW_FRAMES);
      if (tier === 2) {
        z.brittleTimer = GAME_CONST.ICE_BRITTLE_FRAMES; // 冰脆6.5秒：冻结期间受伤+25%
      }
    }
    // 全屏蓝色效果：以画布中心为圆心的超大覆盖矩形（渲染层按 fxKind 画）
    this.effects.push({
      x: this.canvasW / 2, y: this.canvasH / 2,
      radius: Math.max(this.canvasW, this.canvasH),
      timer: 30, maxTimer: 30,
      color: "#4fc3f7", fxKind: 'freeze_all'
    });
    p.dead = true; // 一次性植物
    this.sfx.play('explosion');
  }

  /** 毁灭菇：种下瞬间对全场僵尸造成巨额伤害（全屏灰色闪光），原地留坑30秒不可种植；一次性 */
  private triggerDoomShroom(p: Plant): void {
    const tier: number = this.up('doom'); // 湮灭核心术：1级伤害×1.5，2级辐射坑20秒
    for (const z of this.zombies) {
      if (z.dead || z.friendly) continue;
      this.applyZombieDamage(z, tier >= 1 ? GAME_CONST.DOOM_DAMAGE * 1.5 : GAME_CONST.DOOM_DAMAGE); // 先扣护甲再扣本体
      if (z.hp <= 0) {
        z.dead = true;
        this.maybeDropCoin(z);
      }
    }
    this.effects.push({
      x: this.canvasW / 2, y: this.canvasH / 2,
      radius: Math.max(this.canvasW, this.canvasH),
      timer: 30, maxTimer: 30,
      color: "#616161", fxKind: 'doom_all'
    });
    // 原地留下弹坑：2级为辐射坑（20秒，对踩上的僵尸每秒100伤害）；期间该格不可种植
    this.groundFxs.push({
      x: p.x + p.w / 2, y: p.y + p.h / 2,
      timer: tier === 2 ? GAME_CONST.CRATER_FRAMES_SHORT : GAME_CONST.CRATER_FRAMES,
      kind: tier === 2 ? 'radiation' : 'crater'
    });
    p.dead = true; // 一次性植物
    this.sfx.play('explosion');
  }

  /**
   * 种植：查属性表 → 扣阳光（传送带免费）→ 建实体 → 特殊初始化
   */
  private createPlant(selectedKey: string, plantX: number, plantY: number, col: number): boolean {
    // 关卡解锁校验（传送带关的植物来自发放队列，同样放行）
    if (!this.conveyor && !this.isPlantUnlocked(selectedKey)) {
      return false;
    }
    let kind: PlantKind | null = null;
    switch (selectedKey) {
      case PlantKind.POTATO: kind = PlantKind.POTATO; break;
      case PlantKind.SUNFLOWER: kind = PlantKind.SUNFLOWER; break;
      case PlantKind.SHOOTER: kind = PlantKind.SHOOTER; break;
      case PlantKind.DOUBLE: kind = PlantKind.DOUBLE; break;
      case PlantKind.ICE: kind = PlantKind.ICE; break;
      case PlantKind.WALL: kind = PlantKind.WALL; break;
      case PlantKind.CHERRY: kind = PlantKind.CHERRY; break;
      case PlantKind.CHOMER: kind = PlantKind.CHOMER; break;
      case PlantKind.PUFF: kind = PlantKind.PUFF; break;
      case PlantKind.SUNSHROOM: kind = PlantKind.SUNSHROOM; break;
      case PlantKind.SCAREDY: kind = PlantKind.SCAREDY; break;
      case PlantKind.FUME: kind = PlantKind.FUME; break;
      case PlantKind.HYPNO: kind = PlantKind.HYPNO; break;
      case PlantKind.ICE_SHROOM: kind = PlantKind.ICE_SHROOM; break;
      case PlantKind.DOOM_SHROOM: kind = PlantKind.DOOM_SHROOM; break;
      default: return false;
    }
    const stats = getPlantStats(kind);
    if (!this.conveyor) {
      if (this.sun < stats.cost) return false;
      this.sun -= stats.cost;
    }

    const p: Plant = {
      x: plantX, y: plantY, w: this.plantW, h: this.plantW,
      hp: stats.hp, maxHp: stats.hp, dead: false,
      fireTimer: 0, col: col, kind: kind, sunTimer: 0, armTimer: 0, armed: false,
      digestTimer: 0, growTimer: 0, grown: false, scared: false, scaredyTier: 0, fumeTier: 0,
      enhanced: false, doubleSun: false, fastSun: false,
      cannon: false, cannonAuto: false, cannonTimer: 0,
      armorHp: 0, maxArmorHp: 0, armorTier: 0, chewTier: 0, sunBoostTier: 0, peaArmTier: 0,
      sporeCopy: false, sporeMark: false, sporeTier: 0, sporeSpawnTimer: 0, sporeSelfTimer: 0
    };
    if (kind === PlantKind.POTATO) {
      p.armTimer = GAME_CONST.POTATO_ARM_FRAMES;
    }
    if (kind === PlantKind.CHERRY) {
      p.armTimer = GAME_CONST.CHERRY_FUSE_FRAMES;
      this.sfx.play('cherrybomb');
    }
    if (kind === PlantKind.SUNFLOWER) {
      p.sunTimer = GAME_CONST.SUNFLOWER_FIRST_SUN_FRAMES; // 首次产出对齐原版：约7秒，快于常规24秒间隔
    }
    if (kind === PlantKind.SUNSHROOM) {
      p.growTimer = GAME_CONST.SUNSHROOM_GROW_FRAMES;
      p.sunTimer = GAME_CONST.SUNSHROOM_SMALL_INTERVAL;
    }
    if (kind === PlantKind.ICE_SHROOM) {
      this.triggerIceShroom(p);   // 寒冰菇：种下瞬间全场冰冻，用后消失
    }
    if (kind === PlantKind.DOOM_SHROOM) {
      this.triggerDoomShroom(p);  // 毁灭菇：种下瞬间全场伤害 + 留坑，用后消失
    }
    this.plants.push(p);
    if (!this.conveyor) {
      this.startCooldown(kind);
    }
    this.sfx.play('plant');
    return true;
  }
}
