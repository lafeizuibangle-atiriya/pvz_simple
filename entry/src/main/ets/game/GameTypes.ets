/**
 * 游戏数据模型与全局常量
 * 只存放类型定义和数值配置，不含任何逻辑
 */

export enum PlantKind {
  SUNFLOWER = 'sunflower',
  SHOOTER = 'shooter',
  DOUBLE = 'double',
  ICE = 'ice',
  WALL = 'wall',
  POTATO = 'potato',
  CHERRY = 'cherry',  // 樱桃炸弹（一次性，种下约1.2秒后爆炸）
  CHOMER = 'chomer',  // 食人花：一口吞掉正前方一只僵尸，之后进入最长约42秒的消化期
  // ===== 夜晚蘑菇系 =====
  PUFF = 'puff',          // 小喷菇：0费，攻击前方4格，孢子（紫）
  SUNSHROOM = 'sunshroom',// 阳光菇：夜晚产阳光，会长大（小15 → 大25且更快）
  SCAREDY = 'scaredy',    // 胆小菇：整行攻击，前方一格内有僵尸时变白不攻击
  FUME = 'fume',          // 大喷菇：孢子群打前方4格，无视铁门直接伤本体
  HYPNO = 'hypno',        // 魅惑菇：啃食它的僵尸变成友军（粉色）
  ICE_SHROOM = 'ice_shroom',   // 寒冰菇：种下瞬间全场冰冻（全屏蓝闪），解冻后附带减速，一次性
  DOOM_SHROOM = 'doom_shroom', // 毁灭菇：种下瞬间全场巨额伤害（全屏灰闪），原地留坑30秒不可种植，一次性
  SHOVEL = 'shovel'
}

export enum BulletKind {
  PEA = 'pea',
  ICE = 'ice',
  SPORE = 'spore',  // 蘑菇孢子（紫色）
  FIRE = 'fire',    // 火焰子弹：双倍伤害（红），命中解除寒冰/极寒全部效果
  STONE = 'stone',  // 石化子弹：双倍伤害（石色），轻微击退，不影响寒冰效果
  FROST = 'frost',  // 极寒子弹：深蓝，同一僵尸命中3次冻结3秒，减速同寒冰不叠加
  SHELL = 'shell'   // 土豆炮弹：命中引爆一格AOE（炮击指南术）
}

export enum ZombieKind {
  Normal = 'normal',
  Cone = 'cone',    // 路障僵尸
  Bucket = 'bucket', // 铁桶僵尸
  Pole = 'pole',     // 撑杆僵尸：快速移动，碰到第一株植物时撑杆跳过，之后变普通僵尸
  Football = 'football', // 橄榄球僵尸：深红头盔、防具极厚、同撑杆的快速，掉盔后仍保持快速
  // ===== 夜晚僵尸 =====
  Newspaper = 'newspaper', // 读报僵尸：报纸防具，报纸被打烂后狂暴（加速+加速啃）
  Door = 'door',           // 铁门僵尸：铁门防具，孢子群可无视铁门直接伤本体
  Dancer = 'dancer',       // 舞王僵尸：快速入场，走到第二格召唤伴舞，走走停停
  DancerMinion = 'dancer_minion', // 伴舞僵尸：与舞王保持队形，舞王被挡则停
  DarkFootball = 'dark_football', // 黑橄榄僵尸：同橄榄球但护甲2.5倍
  Thief = 'thief'          // 盗贼僵尸：定期偷取地上阳光（阳光变红飞向它，被偷走不入账）
}

export interface Entity {
  x: number;
  y: number;
  w: number;
  h: number;
  hp: number;
  maxHp: number;
  dead: boolean;
}

export interface Plant extends Entity {
  fireTimer: number;
  col: number;
  kind: PlantKind;
  sunTimer: number;
  armTimer: number;
  armed: boolean;
  digestTimer: number;  // 食人花消化剩余帧数（>0 = 消化中，颜色变深且不能再吃）
  growTimer: number;    // 阳光菇成长剩余帧数（>0 = 还没长大）
  grown: boolean;       // 阳光菇是否已长大
  scared: boolean;      // 胆小菇是否处于害怕状态（变白、不攻击）
  scaredyTier: number;  // 孢子狙击术等级（胆小菇专属）：0/1（子弹50%暴击：护甲+本体同伤）/2（75%暴击+穿透一名僵尸）
  fumeTier: number;     // 孢子雾化术等级（大喷菇专属）：0（射程4.5格）/1（5格）/2（伤害+25%+2.5%吹落头部护甲）
  // ===== 商店强化 =====
  enhanced: boolean;    // 射手/寒冰/双发被强化（解锁特殊子弹）
  doubleSun: boolean;   // 阳光催化：一次产两份阳光
  fastSun: boolean;     // 阳光催化2：产阳光间隔减半
  cannon: boolean;      // 炮击指南：土豆可发射炮弹
  cannonAuto: boolean;  // 炮击指南2：每15秒自动发射（本行有僵尸）
  cannonTimer: number;  // 炮击指南2：自动发射倒计时
  armorHp: number;      // 坚果强化护甲当前值（僵尸先啃护甲）
  maxArmorHp: number;   // 坚果强化护甲上限
  armorTier: number;    // 0无 1银(50%) 2金(125%)
  chewTier: number;     // 铁齿铜牙等级：0/1（消化快50%）/2（快100%+腐蚀液）
  sunBoostTier: number; // 光能鼓舞等级（阳光菇专属）：0（普通阳光25）/1（超大阳光50+邻格攻速+25%）/2（超大阳光75+攻速+50%）
  peaArmTier: number;   // 豌豆武装等级（双发专属）：0/1（石化40%无击退）/2（石化60%+轻微击退+回满血）
  // ===== 孢子蔓延术（小喷菇专属） =====
  sporeCopy: boolean;       // 是否为小喷菇复制体（颜色更浅、独立实体，任何植物可种植替换）
  sporeMark: boolean;       // 孢子蔓延术2：种在复制体地块上的植物标记（攻速+25%，与光能鼓舞不叠加）
  sporeTier: number;        // 本体已完成的孢子蔓延等级（防同等级重复叠种）
  sporeSpawnTimer: number;  // 右侧复制体生成倒计时（帧，0=无）
  sporeSelfTimer: number;   // 孢子蔓延术2：本体7.5秒后变复制体倒计时（帧，0=无）
}

export interface Zombie extends Entity {
  speed: number;
  isEating: boolean;
  targetPlant: Plant | null;
  col: number;
  slowTimer: number;
  zombieKind: ZombieKind;
  armorHp: number;     // 防具血量
  maxArmorHp: number;  // 防具最大血量
  hasPole: boolean;    // 撑杆僵尸是否还有撑杆（跳过后变为普通僵尸）
  friendly: boolean;   // 魅惑：友军僵尸（粉色），向右走攻击其他僵尸，走出右边缘消失
  enraged: boolean;    // 读报僵尸狂暴（报纸被打烂）
  auxTimer: number;    // 通用辅助计时（舞王走/停循环）
  summoned: boolean;   // 舞王是否已召唤过伴舞
  walkPause: boolean;  // 舞王当前是否处于"停"阶段
  leader: Zombie | null; // 伴舞僵尸跟随的舞王
  targetFriendly: Zombie | null; // 敌方僵尸正在啃咬的魅惑友军（被友军阻挡）
  // ===== 极寒子弹（寒冰炼成术） =====
  frozenTimer: number;  // 冻结剩余帧（>0 完全停止，深蓝）
  frostHits: number;    // 极寒子弹累计命中次数（满FROST_FREEZE_HITS次冻结；冻结期间也计数，满3刷新冻结）
  frostbite: boolean;   // 冻伤debuff开关（实际持续由 frostbiteTimer 驱动）
  frostbiteTimer: number; // 冻伤剩余帧（寒冰炼成术2：5秒，再次击中刷新）
  frostTinted: boolean; // 被极寒子弹击中过（变蓝）
  // ===== 精英强化僵尸 / 盗贼僵尸 =====
  elite: boolean;       // 精英：白内红外双轮廓，速度/血量/护甲全2倍
  stealTimer: number;   // 盗贼偷取倒计时（帧）
  brittleTimer: number; // 冰脆debuff（极寒封冻术2）：受伤+25%
}

/** 掉落金币：点击收集，超时自动入账（存档货币，可在商店买卡槽） */
export interface CoinDrop {
  x: number;
  y: number;
  w: number;
  h: number;
  value: number;
  kind: string;  // 'copper' | 'silver' | 'gold' | 'diamond'（渲染区分颜色/大小）
  timer: number;   // 剩余存在帧数，到 0 自动入账
  dead: boolean;
  collecting: boolean; // 已被收集（点击或超时）：飞向右上角金钱计数器途中
}

/** 爆炸/孢子群特效：由引擎生成、渲染层只画 */
export interface ExplosionFx {
  x: number;
  y: number;
  radius: number;   // 最大半径
  timer: number;    // 剩余显示帧数
  maxTimer: number; // 总显示时长（用于计算渐隐/扩散进度）
  color?: string;   // 特效主色（默认橙红爆炸；大喷菇用紫色云）
  fxKind?: string;  // 'fume' = 孢子群（画成横向云带）
}

/** 地面持续效果：腐蚀液（紫色）/熔岩（不可种植，僵尸持续掉血） */
export interface GroundFx {
  x: number;
  y: number;
  timer: number;  // 剩余帧数
  kind: string;   // 'digest' | 'lava'
}

/** 小推车（商店购买）：触发后从草坪左侧向右疾驰，清空所在行的僵尸 */
export interface MowerFx {
  col: number;   // 所在行
  x: number;     // 当前位置（车头）
}

/** 传送带上的植物（1-10）：两条传送带轮流发放，新卡从顶部缓落到所属层的底层槽位 */
export interface ConveyorItem {
  key: string;    // 植物类型
  lane: number;   // 所属传送带（0=左列 1=右列）
  row: number;    // 层内槽位（0 = 最底层，向上堆叠）
  fall: number;   // 剩余下落距离（px，随时间递减到 0 = 落定） */
}

export interface Bullet {
  x: number;
  y: number;
  w: number;
  h: number;
  damage: number;
  speed: number;
  col: number;
  kind: BulletKind;
  dead: boolean;
  knock: number;   // 命中击退距离（px，乘格子比例尺）：0 = 无击退，石化子弹按等级指定
  startX: number;  // 孢子射程限制：从起点算起最多走 range 像素
  range: number;   // 最大飞行距离（0 = 无限制）
  crit?: boolean;        // 孢子狙击术：暴击子弹，伤害同时对护甲和本体生效
  pierceLeft?: number;   // 孢子狙击术2：剩余可穿透僵尸数（0/未定义 = 命中即消失）
  hitZombies?: Zombie[]; // 已命中过的僵尸（穿透飞行时防重复命中）
}

export interface SunDrop {
  x: number;
  y: number;
  w: number;
  h: number;
  value: number;
  targetX: number;
  targetY: number;
  moveProgress: number;
  moveSpeed: number;
  pauseTimer: number;
  hasLanded: boolean;
  dead: boolean;
  collecting: boolean;      // 被玩家点击：飞向左上角阳光计数器，到达后入账
  stolenBy: Zombie | null;  // 被盗贼锁定：变红缓慢飞向该盗贼，接触即消失
}

export interface SelectItem {
  key: string;
  label: string;
  color: string;
  cost: number;
  cd: number;  // 卡片冷却帧数（0 = 无冷却，如铲子）
}

/** 卡片冷却运行时状态：key + 剩余帧数 */
export interface CardCooldown {
  key: string;
  remain: number;
}

/** 关卡配置：1-1~1-10 白天（1-10 传送带），2-1~2-10 夜晚 */
export interface LevelConfig {
  id: string;        // "1-1" / "2-3"
  chapter: number;   // 1 = 白天，2 = 夜晚
  index: number;     // 章内序号（1 起）
  rows: number;      // 草坪行数（1-1 单行 → 1-6 起全 6 行）
  waves: number;     // 大波总数
  night: boolean;    // 夜晚：无天降阳光、向日葵不产阳光
  conveyor: boolean; // 传送带关（1-10）：随机免费植物，不选卡
  unlocks: string[]; // 本关可用植物（铲子由 shovel 字段单独控制）
  shovel: boolean;   // 本关是否可用铲子
}

function dayUnlocks(n: number): string[] {
  // 对齐原版解锁顺序：豌豆(1-1) → 向日葵(1-2) → 樱桃(1-3) → 坚果(1-4) → 铲子(1-5起，shovel字段) → 土豆(1-6) → 寒冰(1-7) → 食人花(1-8) → 双发(1-9)
  const base: string[] = [PlantKind.SHOOTER];
  if (n >= 2) base.push(PlantKind.SUNFLOWER);
  if (n >= 3) base.push(PlantKind.CHERRY);
  if (n >= 4) base.push(PlantKind.WALL);
  if (n >= 6) base.push(PlantKind.POTATO);
  if (n >= 7) base.push(PlantKind.ICE);
  if (n >= 8) base.push(PlantKind.CHOMER);
  if (n >= 9) base.push(PlantKind.DOUBLE);
  return base;
}

function nightUnlocks(n: number): string[] {
  // 2-4 通关掉图鉴（图鉴不是植物）→ 魅惑菇及之后的植物整体后移一关
  const base: string[] = [PlantKind.PUFF];
  if (n >= 2) base.push(PlantKind.SUNSHROOM);
  if (n >= 3) base.push(PlantKind.SCAREDY);
  if (n >= 4) base.push(PlantKind.FUME);
  if (n >= 6) base.push(PlantKind.HYPNO);
  if (n >= 7) base.push(PlantKind.ICE_SHROOM);
  if (n >= 8) base.push(PlantKind.DOOM_SHROOM);
  return base;
}

const ALL_DAY: string[] = [PlantKind.SHOOTER, PlantKind.SUNFLOWER, PlantKind.POTATO,
  PlantKind.ICE, PlantKind.WALL, PlantKind.CHOMER, PlantKind.DOUBLE, PlantKind.CHERRY];

const ALL_NIGHT: string[] = [PlantKind.PUFF, PlantKind.SUNSHROOM, PlantKind.SCAREDY,
  PlantKind.FUME, PlantKind.HYPNO];

/** 调试模式"一键解锁全部植物"：白天关给全部白天植物，夜晚关给全部植物（白天+蘑菇） */
export function getAllPlantsForLevel(night: boolean): string[] {
  return night ? ALL_DAY.concat(ALL_NIGHT) : ALL_DAY.slice();
}

function buildLevels(): LevelConfig[] {
  const list: LevelConfig[] = [];
  for (let n = 1; n <= 10; n++) {
    list.push({
      id: `1-${n}`, chapter: 1, index: n,
      rows: n >= 6 ? 6 : n,
      // 波次：1-1 一波（教学）→ 1-2 两波 → 1-3~1-4 三波 → 1-5~1-8 四波 → 1-9 五波 → 1-10 六波（挑战关）
      waves: n === 1 ? 1 : (n === 2 ? 2 : (n <= 4 ? 3 : (n <= 8 ? 4 : (n === 9 ? 5 : 6)))),
      night: false,
      conveyor: n === 10,
      // 1-10 传送带：植物随机发放（排除向日葵/土豆），unlocks 仅作占位
      unlocks: n === 10 ? ALL_DAY : dayUnlocks(n),
      shovel: n >= 5          // 1-4 通关掉铲子 → 1-5 起可用（对齐原版）
    });
  }
  for (let n = 1; n <= 10; n++) {
    list.push({
      id: `2-${n}`, chapter: 2, index: n,
      rows: n >= 3 ? 6 : (n === 1 ? 4 : 5),
      // 夜晚波次：2-1~2-4 三波 → 2-5~2-7 四波 → 2-8~2-10 五波
      waves: n <= 4 ? 3 : (n <= 7 ? 4 : 5),
      night: true,
      conveyor: false,
      // 夜晚关卡：蘑菇系 + 已解锁的全部白天植物（植物同步解锁，跨章节可用）
      unlocks: nightUnlocks(n).concat(dayUnlocks(9)),
      shovel: true           // 1-4 之后铲子全关可用
    });
  }
  return list;
}

export const LEVELS: LevelConfig[] = buildLevels();

export function getLevelConfig(id: string): LevelConfig | null {
  for (const lv of LEVELS) {
    if (lv.id === id) return lv;
  }
  return null;
}

export interface GameConstType {
  GRID_SIZE: number;
  LAWN_COLS: number;              // 草坪列数（固定10列，全设备相同）
  LAWN_ROWS: number;              // 草坪行数上限（固定6行，全设备相同；实际行数=关卡解锁数）
  PLANT_W: number;
  PLANT_H: number;
  ZOMBIE_W: number;
  ZOMBIE_H: number;
  BAR_HEIGHT: number;
  BAR_PADDING: number;
  ZOMBIE_SPEED: number;
  BULLET_SPEED: number;
  POTATO_TRIGGER_DIST: number;     // 土豆武装后，僵尸靠近到该距离即引爆
  MAX_ZOMBIE_COUNT: number;
  SPAWN_INTERVAL_INIT: number;
  SPAWN_INTERVAL_MULT: number;    // 刷怪间隔倍率（调试可调，1 = 基准）
  SPAWN_INTERVAL_DECREASE: number;
  SPAWN_INTERVAL_MIN: number;
  TOP_ROW_H: number;
  SUN_PANEL_H: number;
  SELECTOR_AREA_H: number;
  FRAME_PER_30S: number;
  FRAME_PER_10S: number;          // 每10秒刷新提速周期（刷怪间隔递减计时用）
  START_NO_SPAWN_FRAME: number;
  CARD_SLOT_SIZE: number;
  CARD_GAP: number;
  START_SUN: number;              // 开局阳光
  SLOW_SPEED_FACTOR: number;      // 减速时移速倍率
  SUN_LIFETIME_FRAMES: number;    // 阳光落地后存在时长（不点就消失）
  CD_FAST: number;                // 快速卡片冷却（射手/向日葵）
  CD_SLOW: number;                // 慢速卡片冷却（坚果）
  CD_POTATO: number;              // 土豆雷冷却（原版30秒×0.75）
  CD_VERY_SLOW: number;           // 极慢卡片冷却（樱桃/寒冰菇/毁灭菇：对齐原版50秒）
  WAVE_EVERY_N: number;           // 波次要求基准：第一波需要攒够N次刷怪才触发大波
  WAVE_REQ_MULT: number;          // 波次要求系数：每波要求递增比例（第N波要求 = 基准×(1+(N-1)×系数)）
  BIG_WAVE_COUNT: number;         // 一大波的基础僵尸数量
  WAVE_SPAWN_MULT: number;        // 波次出怪系数：大波数量随波次递增比例（第N波 = 基础×(1+(N-1)×系数)）
  WAVE_PREVIEW_FRAMES: number;    // 大波预警时长：红字显示多久后大波才进场（原版节奏）
  TOTAL_WAVES: number;            // 兜底值：实际每关总波数 = 关卡配置（engine.totalWaves）
  START_BANNER_FRAMES: number;    // 开局"准备种植你的植物"横幅显示时长
  MAX_SAME_COL_STREAK: number;    // 同一航道最多连续出现几只僵尸（防"一路僵尸"）
  RECENT_SPAWN_WINDOW: number;    // 航道均衡统计窗口：看最近N次刷怪落在哪些列
  BIG_WAVE_STAGGER: number;       // 大波中每只僵尸的出场错位（像素），避免完全重叠
  SUN_DROP_INTERVAL: number;      // 天降阳光基准间隔（夜晚无天降阳光）
  SUN_DROP_INTERVAL_MULT: number; // 天降阳光间隔倍率（调试可调，1 = 基准）
  SUN_NORMAL_VALUE: number;       // 普通阳光面额（向日葵/天降阳光）
  CONE_START_FRAME: number;       // 路障僵尸开始出现的帧数
  BUCKET_START_FRAME: number;     // 铁桶僵尸开始出现的帧数
  ZOMBIE_BODY_HP: number;          // 僵尸本体血量
  CONE_ARMOR_HP: number;           // 路障防具血量
  BUCKET_ARMOR_HP: number;         // 铁桶防具血量
  CONE_SPAWN_RATE: number;         // 路障生成累计概率阈值
  BUCKET_SPAWN_RATE: number;       // 铁桶生成累计概率阈值
  SHOOTER_FIRE_INTERVAL: number;   // 射手射击间隔（帧）
  SUNFLOWER_SUN_INTERVAL: number;  // 向日葵产阳光间隔（帧）
  SUNFLOWER_FIRST_SUN_FRAMES: number; // 向日葵首次产阳光等待（对齐原版约7秒，明显快于常规间隔）
  POTATO_ARM_FRAMES: number;       // 土豆武装所需帧数
  ZOMBIE_EAT_DPS: number;          // 僵尸每帧啃食伤害
  ICE_SLOW_FRAMES: number;         // 寒冰减速持续帧数
  FRAME_RATE: number;              // 虚拟帧率：真实秒数 × FRAME_RATE = 帧数
  CHERRY_FUSE_FRAMES: number;      // 种下到爆炸的引信时间
  CD_CHERRY: number;               // 樱桃炸弹冷却
  POLE_ZOMBIE_HP: number;          // 撑杆僵尸血量（原版 340，无防具）
  POLE_SPEED_MULT: number;         // 持杆时移动速度倍率（原版"快"，约2倍）
  POLE_START_FRAME: number;        // 撑杆僵尸开始登场的帧数
  POLE_SPAWN_RATE: number;         // 撑杆僵尸生成概率
  FOOTBALL_ZOMBIE_HP: number;      // 橄榄球僵尸本体血量（原版200，与普通相同）
  FOOTBALL_ARMOR_HP: number;       // 橄榄球头盔防具血量（原版1400）
  FOOTBALL_SPEED_MULT: number;     // 移速倍率（原版"快速"，同撑杆僵尸持杆速度）
  FOOTBALL_START_FRAME: number;    // 橄榄球僵尸开始登场的帧数（晚于铁桶）
  FOOTBALL_SPAWN_RATE: number;     // 登场后生成概率
  CHOMER_DIGEST_FRAMES: number;    // 吞下僵尸后的消化时长（原版约42秒）
  CHOMER_BITE_CELL_PAD: number;    // 食人花咬合容差：一格 + 2px
  // ===== 音效 =====
  SFX_EAT_THROTTLE_MS: number;     // 啃食音效最小间隔（防刷屏）
  SFX_SPLAT_THROTTLE_MS: number;   // 豌豆命中音效最小间隔
  SUN_FALL_SPEED: number;          // 阳光下落速度（progress/帧，越小越慢）
  // ===== 金币（按僵尸种类概率掉落，掉落后再分档：铜44%/银34%/金21%/钻石1%） =====
  COIN_COPPER_VALUE: number;       // 铜币面额
  COIN_SILVER_VALUE: number;       // 银币面额
  COIN_GOLD_VALUE: number;         // 金币面额
  COIN_DIAMOND_VALUE: number;      // 钻石面额
  COIN_LIFETIME_FRAMES: number;    // 金币存在时长（超时自动入账）
  COIN_DROP_MULT: number;          // 全局掉率倍率（调试面板可调，1 = 使用各僵尸基础掉率）
  COIN_ELITE_BONUS: number;        // 精英僵尸额外掉率加成
  MOWER_SPEED: number;             // 小推车疾驰速度（px/帧）
  CELL_REF: number;                // 速度/距离基准格边长：实际速度 = 常量 × (cell / CELL_REF)，保证手机/平板手感一致
  // ===== 传送带（1-10） =====
  CONVEYOR_INTERVAL: number;       // 传送带发放植物的间隔（帧）
  CONVEYOR_MAX: number;            // 传送带上最多堆几个（两条带各一半）
  CONVEYOR_FALL_SPEED: number;     // 新卡下落速度（px/帧，按格子比例尺缩放）
  CONVEYOR_BAG: string[];          // 加权配方袋：20 张一组（数量即权重），抽空重洗
  // ===== 读报僵尸（原版数据） =====
  NEWSPAPER_ARMOR_HP: number;      // 报纸防具血量（原版150）
  NEWSPAPER_RAGE_SPEED_MULT: number; // 狂暴后移速倍率（原版约2.5倍）
  NEWSPAPER_RAGE_EAT_MULT: number;   // 狂暴后啃食速度倍率（原版2倍）
  NEWSPAPER_START_FRAME: number;     // 读报僵尸开始登场的帧数（2-2 起）
  NEWSPAPER_SPAWN_RATE: number;
  // ===== 铁门僵尸（原版数据） =====
  DOOR_ARMOR_HP: number;           // 铁门防具血量（原版1100，同铁桶）
  DOOR_START_FRAME: number;        // 铁门僵尸开始登场的帧数（2-4 起）
  DOOR_SPAWN_RATE: number;
  // ===== 舞王僵尸 =====
  DANCER_HP: number;               // 舞王本体血量
  DANCER_ENTRY_SPEED_MULT: number; // 入场快速倍率（走到第二格前）
  DANCER_START_FRAME: number;      // 舞王开始登场的帧数（2-5 起）
  DANCER_SPAWN_RATE: number;
  DANCER_WALK_FRAMES: number;      // 走多久
  DANCER_PAUSE_FRAMES: number;     // 停多久
  DANCER_MINION_HP: number;        // 伴舞血量（同普通僵尸）
  // ===== 黑橄榄/盗贼/精英/多行刷怪 =====
  DARK_FOOTBALL_ARMOR_HP: number;  // 黑橄榄护甲（橄榄球1400×1.5）
  DARK_FOOTBALL_CHANCE: number;    // 橄榄球登场后黑橄榄占比
  THIEF_START_FRAME: number;       // 盗贼登场帧数
  THIEF_SPAWN_RATE: number;        // 盗贼生成概率
  THIEF_STEAL_INTERVAL: number;    // 盗贼每2秒尝试偷一次
  ELITE_CHANCE: number;            // 精英强化僵尸出现概率（速度/血/甲强化）
  ELITE_MULT: number;              // 精英强化倍率（作用于速度/血量/护甲）
  ZOMBIE_HP_MULT: number;          // 僵尸本体血量全局倍率
  ZOMBIE_ARMOR_MULT: number;       // 僵尸护甲全局倍率（路障/铁桶/橄榄球/铁门/报纸等）
  BULLET_DMG_MULT: number;         // 子弹伤害全局倍率（豌豆/寒冰/极寒/火焰/石化/孢子）
  MULTI_LANE_CHANCE_2: number;     // 普通刷怪同时出第2行的概率
  MULTI_LANE_CHANCE_3: number;     // 同时出第3行的概率
  // ===== 蘑菇系（原版数据） =====
  SHROOM_RANGE_CELLS: number;      // 小喷菇/大喷菇射程（原版4格）
  SUNSHROOM_SMALL_VALUE: number;   // 小时候每次产15
  SUNSHROOM_SMALL_INTERVAL: number;// 小时候产阳光间隔（同向日葵24秒）
  SUNSHROOM_GROW_FRAMES: number;   // 长大所需时间（原版约2分钟，压缩到60秒）
  SUNSHROOM_BIG_VALUE: number;     // 长大后产25
  SUNSHROOM_BIG_INTERVAL: number;  // 长大后间隔略快于向日葵
  SCAREDY_CELLS: number;           // 胆小菇害怕距离（1格）
  SCAREDY_CRIT_T1: number;         // 孢子狙击术1：暴击概率（50%）
  SCAREDY_CRIT_T2: number;         // 孢子狙击术2：暴击概率（75%）
  FUME_INTERVAL: number;           // 大喷菇喷孢子间隔（原版1.5秒）
  FUME_RANGE_CELLS: number;        // 大喷菇射程（原版4.5格）
  FUME_RANGE_UP_CELLS: number;     // 孢子雾化术1：射程（5格）
  FUME_DMG_UP_MULT: number;        // 孢子雾化术2：伤害倍率（+25%）
  FUME_STRIP_ARMOR_CHANCE: number; // 孢子雾化术2：吹落头部护甲概率（2.5%）
  ICE_SHROOM_FREEZE_FRAMES: number; // 寒冰菇全场冰冻时长（约4秒）
  ICE_SHROOM_FREEZE_FRAMES_UP: number; // 极寒封冻术1：全场冰冻时长（6.5秒）
  ICE_BRITTLE_FRAMES: number;      // 冰脆debuff时长（极寒封冻术2，6.5秒）
  ICE_BRITTLE_MULT: number;        // 冰脆受伤倍率（+25%）
  DOOM_DAMAGE: number;             // 毁灭菇全场伤害（固定值，同爆炸统一伤害）
  CRATER_FRAMES: number;           // 毁灭菇坑存在时长（30秒，期间不可种植）
  CRATER_FRAMES_SHORT: number;     // 湮灭核心术2：辐射坑存在时长（20秒）
  RADIATION_DPS: number;           // 湮灭核心术2：辐射坑每秒掉血
  // ===== 商店强化（子弹/地面效果数值） =====
  FROST_FREEZE_FRAMES: number;     // 极寒冻结时长（3秒，满FROST_FREEZE_HITS次命中触发/刷新）
  FROST_FREEZE_HITS: number;       // 极寒冻结所需命中次数（3次，冻结期间也计数，满3刷新冻结）
  FROSTBITE_FRAMES: number;        // 极寒冻伤持续时间（5秒，再次击中刷新）
  FROSTBITE_DPS: number;           // 冻伤每秒掉血（无视护甲，不叠加）
  DIGEST_POOL_FRAMES: number;      // 铁齿铜牙2腐蚀液持续（5秒）
  DIGEST_POOL_DPS: number;         // 腐蚀液每秒掉血
  LAVA_FRAMES: number;             // 火药强化2熔岩持续（3秒）
  LAVA_DPS: number;                // 熔岩每秒掉血
  POTATO_CANNON_INTERVAL: number;  // 炮击指南2自动发射间隔（15秒）
  SHELL_DAMAGE: number;            // 土豆炮弹AOE伤害
  CHERRY_BASE_DAMAGE: number;      // 樱桃基础爆炸伤害（固定值，强化后 ×1.5）
  EXPLOSION_DAMAGE: number;        // 土豆雷/樱桃/毁灭菇统一爆炸伤害（橄榄球总血量200+1400=1600，向上取百）
  STONE_KNOCKBACK: number;         // 石化子弹击退距离（px）
}

export const GAME_CONST: GameConstType = {
  GRID_SIZE: 60,   // 仅作实体尺寸的基准参考，草坪格子大小改为按屏幕自适应（engine.cell）
  LAWN_COLS: 10,   // 草坪 10 列 × 6 行
  LAWN_ROWS: 6,
  PLANT_W: 58,
  PLANT_H: 58,
  ZOMBIE_W: 56,
  ZOMBIE_H: 56,
  BAR_HEIGHT: 6,
  BAR_PADDING: 8,
  ZOMBIE_SPEED: 0.192,  // 约5.2秒走一格；撑杆/橄榄球/狂暴读报另有倍率
  BULLET_SPEED: 1.6,
  POTATO_TRIGGER_DIST: 30,
  MAX_ZOMBIE_COUNT: 30,   // 大波最多 8+9*2=26 只，留余量
  SPAWN_INTERVAL_INIT: 1300,      // 刷怪间隔调高：开局给玩家更多发育时间
  SPAWN_INTERVAL_MULT: 1,         // 刷怪间隔倍率（调试可调）
  SPAWN_INTERVAL_DECREASE: 12,    // 每10秒提速一次（幅度12）
  SPAWN_INTERVAL_MIN: 340,        // 刷怪间隔下限（原380）
  TOP_ROW_H: 86,
  SUN_PANEL_H: 50,
  SELECTOR_AREA_H: 90,
  FRAME_PER_30S: Math.round(30 * 1000 / 16),
  FRAME_PER_10S: Math.round(10 * 1000 / 16),  // 刷怪提速周期（用户要求每10秒增强）
  START_NO_SPAWN_FRAME: Math.round(28 * 1000 / 16),
  CARD_SLOT_SIZE: 64,
  CARD_GAP: 8,
  START_SUN: 50,
  SLOW_SPEED_FACTOR: 0.5,
  SUN_LIFETIME_FRAMES: 313,
  CD_FAST: 235,                  // 冷却减半（原470）：给叠种强化留出机会
  CD_SLOW: 937,                  // 冷却减半（原1875）
  CD_POTATO: 1406,               // 土豆雷：原版30秒×0.75（用户调整）
  CD_VERY_SLOW: 3125,            // 极慢冷却（原版50秒）：寒冰菇/毁灭菇，一次性植物不减免
  WAVE_EVERY_N: 12,               // 波次要求基准：第一波12次刷怪触发大波（后续按系数递增）
  WAVE_REQ_MULT: 0.25,            // 波次要求系数：第2波15、第3波19、第4波24……越往后越难触发大波
  BIG_WAVE_COUNT: 6,              // 降难：8→6，大波压力更小
  WAVE_SPAWN_MULT: 0.33,          // 波次出怪系数：第2波8只、第3波11只……对齐旧版每波+2的节奏
  WAVE_PREVIEW_FRAMES: 312,
  TOTAL_WAVES: 5,
  START_BANNER_FRAMES: 200,
  MAX_SAME_COL_STREAK: 3,
  RECENT_SPAWN_WINDOW: 8,
  BIG_WAVE_STAGGER: 6,
  SUN_DROP_INTERVAL: 625,        // 天降阳光基准约10秒一个（对齐原版）
  SUN_DROP_INTERVAL_MULT: 1,     // 天降阳光间隔倍率（调试可调）
  SUN_NORMAL_VALUE: 25,          // 普通阳光面额（原版25）
  CONE_START_FRAME: 3750,
  BUCKET_START_FRAME: 7500,
  ZOMBIE_BODY_HP: 200,
  CONE_ARMOR_HP: 370,
  BUCKET_ARMOR_HP: 1100,
  CONE_SPAWN_RATE: 0.6,
  BUCKET_SPAWN_RATE: 0.95,       // 铁桶概率压低：路障60~95%，仅95~100%（5%）出铁桶
  SHOOTER_FIRE_INTERVAL: 134,
  SUNFLOWER_SUN_INTERVAL: 1500,
  SUNFLOWER_FIRST_SUN_FRAMES: 437, // 首次产阳光约7秒（62.5帧/秒），之后按常规间隔
  POTATO_ARM_FRAMES: 940,
  ZOMBIE_EAT_DPS: 0.32,
  ICE_SLOW_FRAMES: 625,
  FRAME_RATE: 62.5,
  CHERRY_FUSE_FRAMES: 75,
  CD_CHERRY: 3125,               // 樱桃冷却：对齐原版50秒（一次性植物不减免）
  POLE_ZOMBIE_HP: 340,
  POLE_SPEED_MULT: 2,
  POLE_START_FRAME: 5000,
  POLE_SPAWN_RATE: 0.2,
  FOOTBALL_ZOMBIE_HP: 200,
  FOOTBALL_ARMOR_HP: 1400,
  FOOTBALL_SPEED_MULT: 2,
  FOOTBALL_START_FRAME: 11250,
  FOOTBALL_SPAWN_RATE: 0.1,
  CHOMER_DIGEST_FRAMES: 2625,
  CHOMER_BITE_CELL_PAD: 2,
  SFX_EAT_THROTTLE_MS: 1400,
  SFX_SPLAT_THROTTLE_MS: 200,
  SUN_FALL_SPEED: 0.0055,        // 略低于原版（原0.006），下落稍慢一点
  // ===== 金币四档面额 =====
  COIN_COPPER_VALUE: 5,
  COIN_SILVER_VALUE: 10,
  COIN_GOLD_VALUE: 20,
  COIN_DIAMOND_VALUE: 1000,
  COIN_LIFETIME_FRAMES: 480,     // 约7.7秒后自动入账
  COIN_DROP_MULT: 1,             // 全局掉率倍率（调试可调）
  COIN_ELITE_BONUS: 0.15,        // 精英僵尸额外+15%掉率
  MOWER_SPEED: 8,                // 小推车疾驰速度（约2倍豌豆速度，几秒扫完整行）
  CELL_REF: 90,                  // 速度基准格边长（平板典型格子大小，手机格子小则速度等比放慢）
  // ===== 传送带 =====
  CONVEYOR_INTERVAL: 240,        // 约4秒补一张：发卡速度再减半（原120），不满就补、装满才停
  CONVEYOR_MAX: 16,              // 两条传送带各 8 个槽位（共16）
  CONVEYOR_FALL_SPEED: 2,        // 新卡从顶部缓落到槽位（约1~2秒落定）
  // 加权配方袋（20张=100%）：豌豆10% 寒冰30% 双发30% 坚果10% 食人花5% 樱桃10% 土豆5%
  // 按袋抽取保证低权重植物也一定会出现，长期数量精确贴合权重
  CONVEYOR_BAG: [
    PlantKind.SHOOTER, PlantKind.SHOOTER,                       // 豌豆 2/20
    PlantKind.ICE, PlantKind.ICE, PlantKind.ICE,
    PlantKind.ICE, PlantKind.ICE, PlantKind.ICE,                // 寒冰 6/20
    PlantKind.DOUBLE, PlantKind.DOUBLE, PlantKind.DOUBLE,
    PlantKind.DOUBLE, PlantKind.DOUBLE, PlantKind.DOUBLE,       // 双发 6/20
    PlantKind.WALL, PlantKind.WALL,                             // 坚果 2/20
    PlantKind.CHOMER,                                           // 食人花 1/20
    PlantKind.CHERRY, PlantKind.CHERRY,                         // 樱桃 2/20
    PlantKind.POTATO                                            // 土豆 1/20
  ],
  // ===== 读报僵尸（原版：报纸150甲，破报后移速2.5倍+啃食2倍） =====
  NEWSPAPER_ARMOR_HP: 150,
  NEWSPAPER_RAGE_SPEED_MULT: 2.5,
  NEWSPAPER_RAGE_EAT_MULT: 2,
  NEWSPAPER_START_FRAME: 1875,   // 2-2 登场：约30秒后
  NEWSPAPER_SPAWN_RATE: 0.18,
  // ===== 铁门僵尸（原版：铁门1100甲，孢子无视铁门伤本体） =====
  DOOR_ARMOR_HP: 1100,
  DOOR_START_FRAME: 5000,        // 2-4 登场：约80秒后
  DOOR_SPAWN_RATE: 0.15,
  // ===== 舞王僵尸 =====
  DANCER_HP: 500,
  DANCER_ENTRY_SPEED_MULT: 2.5,  // 快速入场走到第二格
  DANCER_START_FRAME: 7500,      // 2-5 登场：约120秒后
  DANCER_SPAWN_RATE: 0.12,
  DANCER_WALK_FRAMES: 190,       // 走约3秒
  DANCER_PAUSE_FRAMES: 90,       // 停约1.4秒
  DANCER_MINION_HP: 200,
  // ===== 黑橄榄/盗贼/精英/多行刷怪 =====
  DARK_FOOTBALL_ARMOR_HP: 2100,  // 橄榄球1400×1.5（强化黑橄榄不再难以处理）
  DARK_FOOTBALL_CHANCE: 0.3,
  THIEF_START_FRAME: 3750,       // 约60秒后登场
  THIEF_SPAWN_RATE: 0.1,
  THIEF_STEAL_INTERVAL: 125,     // 2秒（62.5帧/秒）
  ELITE_CHANCE: 0.08,
  ELITE_MULT: 2,                 // 精英：速度/血量/护甲 ×2
  ZOMBIE_HP_MULT: 1,
  ZOMBIE_ARMOR_MULT: 1,
  BULLET_DMG_MULT: 1,
  MULTI_LANE_CHANCE_2: 0.25,
  MULTI_LANE_CHANCE_3: 0.08,
  // ===== 蘑菇系 =====
  SHROOM_RANGE_CELLS: 4,         // 小喷菇/大喷菇射程4格
  SUNSHROOM_SMALL_VALUE: 12.5,   // 小时候每次产12.5（用户调整）
  SUNSHROOM_SMALL_INTERVAL: 1500,
  SUNSHROOM_GROW_FRAMES: 3750,   // 60秒长大
  SUNSHROOM_BIG_VALUE: 25,       // 长大后产普通阳光25（未买强化；1级强化50/2级75由引擎分支决定）
  SUNSHROOM_BIG_INTERVAL: 1500,  // 对齐原版24秒（原版大小阳光菇同间隔）
  SCAREDY_CELLS: 1,
  SCAREDY_CRIT_T1: 0.5,           // 孢子狙击术1：50%暴击
  SCAREDY_CRIT_T2: 0.75,          // 孢子狙击术2：75%暴击
  FUME_INTERVAL: 94,             // 原版1.5秒 → 94帧
  FUME_RANGE_CELLS: 4.5,         // 大喷菇射程对齐原版4.5格
  FUME_RANGE_UP_CELLS: 5,        // 孢子雾化术1：射程5格
  FUME_DMG_UP_MULT: 1.25,        // 孢子雾化术2：伤害+25%
  FUME_STRIP_ARMOR_CHANCE: 0.025, // 孢子雾化术2：2.5%吹落头部护甲
  ICE_SHROOM_FREEZE_FRAMES: 250, // 全场冰冻约4秒（解冻后接减速）
  ICE_SHROOM_FREEZE_FRAMES_UP: 406, // 极寒封冻术1：6.5秒
  ICE_BRITTLE_FRAMES: 406,       // 冰脆6.5秒（极寒封冻术2）
  ICE_BRITTLE_MULT: 1.25,        // 冰脆受伤+25%
  DOOM_DAMAGE: 1600,             // 毁灭菇全场伤害（与土豆雷/樱桃统一：橄榄球总血量1600）
  CRATER_FRAMES: 1875,           // 坑30秒（62.5帧/秒）
  CRATER_FRAMES_SHORT: 1250,     // 湮灭核心术2：辐射坑20秒
  RADIATION_DPS: 100,            // 湮灭核心术2：辐射坑每秒100伤害
  // ===== 商店强化 =====
  FROST_FREEZE_FRAMES: 188,      // 3秒（62.5帧/秒）
  FROST_FREEZE_HITS: 3,          // 3次命中即冻结（原5次）
  FROSTBITE_FRAMES: 312,         // 极寒冻伤持续5秒，再次击中刷新
  FROSTBITE_DPS: 7.5,
  DIGEST_POOL_FRAMES: 312,       // 5秒
  DIGEST_POOL_DPS: 15,
  LAVA_FRAMES: 188,              // 3秒
  LAVA_DPS: 50,
  POTATO_CANNON_INTERVAL: 938,   // 15秒
  SHELL_DAMAGE: 300,
  CHERRY_BASE_DAMAGE: 1600,
  EXPLOSION_DAMAGE: 1600,
  STONE_KNOCKBACK: 4,            // 石化击退（用户逐步削弱：12→4）
};

/** 商店：解锁第7/8/9个卡槽的金币价格（初始6个卡槽，上限9） */
export const SLOT_PRICES: number[] = [500, 1000, 2000];
export const MAX_SLOTS: number = 9;

/** 商店：小推车价格（一次性永久购买，每关开始时每行草坪自动就位一辆） */
export const MOWER_PRICE: number = 100;

/**
 * 各僵尸种类死亡掉落金币的基础概率（key = ZombieKind 枚举值）：
 * 越弱的基础僵尸掉率越低，越稀有/强力的掉率越高
 */
export const COIN_DROP_RATES: Record<string, number> = {
  'normal': 0.15,         // 普通僵尸
  'cone': 0.25,           // 路障僵尸
  'bucket': 0.35,         // 铁桶僵尸
  'pole': 0.25,           // 撑杆僵尸
  'football': 0.45,       // 橄榄球僵尸
  'dark_football': 0.55,  // 黑橄榄僵尸
  'newspaper': 0.30,      // 读报僵尸
  'door': 0.40,           // 铁门僵尸
  'dancer': 0.50,         // 舞王僵尸
  'dancer_minion': 0.10,  // 伴舞僵尸（数量多，掉率压低）
  'thief': 0.30           // 盗贼僵尸
};

/** 商店：坚果包扎术（原版 Wall-nut First Aid，价格参考原版 $5000） */
export const FIRST_AID_PRICE: number = 5000;

// ====================== 商店强化体系（1级 $250，2级 $300 需先买1，买2替换1） ======================

export const UPGRADE_T1_PRICE: number = 250;
export const UPGRADE_T2_PRICE: number = 300;

/** 强化 key（与存档/引擎 Map 对应） */
// 强化道具顺序 = 对应植物解锁顺序：豌豆(初始) → 向日葵(1-1) → 樱桃(1-2) → 坚果(1-3) → 土豆(1-5) → 寒冰(1-6) → 食人花(1-7) → 双发(1-8) → 小喷菇(2-1) → 阳光菇(2-2) → 胆小菇(2-3) → 大喷菇(2-4) → 魅惑菇(2-5) → 寒冰菇(2-6) → 毁灭菇(2-7)
export const UPGRADE_KEYS: string[] = ['pea', 'sun', 'cherry', 'wall', 'potato', 'ice', 'chomper', 'peaArm', 'spore', 'sunBoost', 'scaredy', 'fume', 'hypno', 'iceShroom', 'doom'];

export const UPGRADE_LABELS: Record<string, string> = {
  'pea': '豌豆强化术',
  'sun': '阳光催化术',
  'cherry': '火药强化术',
  'wall': '坚果强化术',
  'potato': '炮击指南术',
  'ice': '寒冰炼成术',
  'chomper': '铁齿铜牙',
  'peaArm': '豌豆武装',
  'spore': '孢子蔓延术',
  'sunBoost': '光能鼓舞',
  'scaredy': '孢子狙击术',
  'fume': '孢子雾化术',
  'hypno': '深度催眠术',
  'iceShroom': '极寒封冻术',
  'doom': '湮灭核心术'
};

// ====================== 调试面板（开始页） ======================

/** 调试面板可调的数值参数（key 对应 GAME_CONST 字段名）
 *  timing 说明生效时机：
 *  - 'now'  ：滑条一动就对"下一次触发"生效（新刷僵尸、下一次子弹/刷怪/大波）
 *  - 'next' ：进关时一次性读取（如开局阳光），需重开本关或进下一关才生效
 */
export interface DebugTunable {
  key: string;
  label: string;
  min: number;
  max: number;
  step: number;
  timing: string;   // 'now' = 立即生效 | 'next' = 下关/重开生效
}

export const DEBUG_TUNABLES: DebugTunable[] = [
  { key: 'START_SUN', label: '开局阳光', min: 0, max: 2000, step: 50, timing: 'next' },
  { key: 'SPAWN_INTERVAL_MULT', label: '刷怪间隔倍率', min: 0.2, max: 3, step: 0.05, timing: 'now' },
  { key: 'SPAWN_INTERVAL_MIN', label: '最快刷怪（帧）', min: 100, max: 1000, step: 20, timing: 'now' },
  { key: 'SPAWN_INTERVAL_DECREASE', label: '每10秒提速幅度', min: 0, max: 50, step: 1, timing: 'now' },
  { key: 'WAVE_EVERY_N', label: '波次要求基准（只）', min: 4, max: 40, step: 1, timing: 'now' },
  { key: 'WAVE_REQ_MULT', label: '波次要求系数', min: 0, max: 1, step: 0.05, timing: 'now' },
  { key: 'BIG_WAVE_COUNT', label: '大波基础数量', min: 2, max: 30, step: 1, timing: 'now' },
  { key: 'WAVE_SPAWN_MULT', label: '波次出怪系数', min: 0, max: 1, step: 0.05, timing: 'now' },
  { key: 'ZOMBIE_SPEED', label: '僵尸移速', min: 0.05, max: 0.6, step: 0.01, timing: 'now' },
  { key: 'ZOMBIE_BODY_HP', label: '僵尸本体血量', min: 50, max: 2000, step: 50, timing: 'now' },
  { key: 'ZOMBIE_HP_MULT', label: '僵尸血量倍率', min: 0.1, max: 5, step: 0.1, timing: 'now' },
  { key: 'ZOMBIE_ARMOR_MULT', label: '僵尸护甲倍率', min: 0.1, max: 5, step: 0.1, timing: 'now' },
  { key: 'ZOMBIE_EAT_DPS', label: '僵尸啃食速度', min: 0.1, max: 1.5, step: 0.02, timing: 'now' },
  { key: 'ELITE_CHANCE', label: '强化僵尸概率', min: 0, max: 0.5, step: 0.01, timing: 'now' },
  { key: 'ELITE_MULT', label: '强化僵尸倍率', min: 1, max: 4, step: 0.5, timing: 'now' },
  { key: 'BULLET_DMG_MULT', label: '子弹伤害倍率', min: 0.5, max: 5, step: 0.5, timing: 'now' },
  { key: 'DARK_FOOTBALL_CHANCE', label: '黑橄榄概率', min: 0, max: 1, step: 0.05, timing: 'now' },
  { key: 'THIEF_SPAWN_RATE', label: '盗贼出现概率', min: 0, max: 0.5, step: 0.01, timing: 'now' },
  { key: 'THIEF_START_FRAME', label: '盗贼登场时间（帧）', min: 0, max: 15000, step: 500, timing: 'now' },
  { key: 'THIEF_STEAL_INTERVAL', label: '盗贼偷窃间隔（帧）', min: 31, max: 1000, step: 31, timing: 'now' },
  { key: 'MULTI_LANE_CHANCE_2', label: '双行刷怪概率', min: 0, max: 0.6, step: 0.01, timing: 'now' },
  { key: 'MULTI_LANE_CHANCE_3', label: '三行刷怪概率', min: 0, max: 0.4, step: 0.01, timing: 'now' },
  { key: 'FROSTBITE_DPS', label: '冻伤每秒伤害', min: 0, max: 30, step: 0.5, timing: 'now' },
  { key: 'SUN_DROP_INTERVAL_MULT', label: '天降阳光间隔倍率', min: 0.2, max: 3, step: 0.05, timing: 'now' },
  { key: 'COIN_DROP_MULT', label: '金币掉率倍率', min: 0, max: 3, step: 0.1, timing: 'now' }
];

/** 调试参数默认值（恢复默认用，与 GAME_CONST 初始值保持一致） */
export const DEBUG_DEFAULTS: Record<string, number> = {
  'START_SUN': 50,
  'SPAWN_INTERVAL_MULT': 1,
  'SPAWN_INTERVAL_MIN': 340,
  'SPAWN_INTERVAL_DECREASE': 12,
  'WAVE_EVERY_N': 12,
  'WAVE_REQ_MULT': 0.25,
  'BIG_WAVE_COUNT': 6,
  'WAVE_SPAWN_MULT': 0.33,
  'ZOMBIE_SPEED': 0.192,
  'ZOMBIE_BODY_HP': 200,
  'ZOMBIE_HP_MULT': 1,
  'ZOMBIE_ARMOR_MULT': 1,
  'ZOMBIE_EAT_DPS': 0.32,
  'ELITE_CHANCE': 0.08,
  'ELITE_MULT': 2,
  'BULLET_DMG_MULT': 1,
  'DARK_FOOTBALL_CHANCE': 0.3,
  'THIEF_SPAWN_RATE': 0.1,
  'THIEF_START_FRAME': 3750,
  'THIEF_STEAL_INTERVAL': 125,
  'MULTI_LANE_CHANCE_2': 0.25,
  'MULTI_LANE_CHANCE_3': 0.08,
  'FROSTBITE_DPS': 7.5,
  'SUN_DROP_INTERVAL_MULT': 1,
  'COIN_DROP_MULT': 1
};

/** 通关掉落的新植物卡片（最后一只僵尸掉落 → 落地发光 → 进入解锁结算页） */
export interface CardDropFx {
  key: string;       // 掉落的植物（或 'shovel'）
  x: number;         // 当前位置（卡片中心）
  y: number;
  targetY: number;   // 落点 y（草坪中央）
  sway: number;      // 下落时左右摇摆的相位
  landed: boolean;   // 是否已落地（落地后开始发光 + 倒计时进结算）
  timer: number;     // 落地后剩余帧数（到 0 → victory）
}

/** 卡片掉落特效由引擎持有、渲染层绘制 */

/** 通关解锁物品的介绍文案（key 同 PlantKind / 'shovel' / 'almanac' / 'letter'） */
export interface PlantIntro {
  name: string;
  desc: string;
}

export const PLANT_INTRO: Record<string, PlantIntro> = {
  'shooter': { name: '豌豆射手', desc: '向前方发射豌豆，是最可靠的攻击手' },
  'sunflower': { name: '向日葵', desc: '定期生产阳光，是种植经济的基础' },
  'wall': { name: '坚果墙', desc: '血量极厚的防线，为后排争取时间' },
  'ice': { name: '寒冰射手', desc: '发射寒冰豌豆，命中后使僵尸减速' },
  'potato': { name: '土豆地雷', desc: '武装后炸飞踩到它的僵尸，便宜好用' },
  'double': { name: '双发射手', desc: '一次发射两颗豌豆，火力翻倍' },
  'chomer': { name: '食人花', desc: '一口吞掉正前方的僵尸，随后长时间消化' },
  'cherry': { name: '樱桃炸弹', desc: '炸掉一定区域内的所有僵尸' },
  'puff': { name: '小喷菇', desc: '零阳光的蘑菇炮台，攻击前方4格' },
  'sunshroom': { name: '阳光菇', desc: '夜晚生产阳光，长大后产量更高' },
  'scaredy': { name: '胆小菇', desc: '攻击整行僵尸，但僵尸靠近时会害怕缩起' },
  'fume': { name: '大喷菇', desc: '孢子群攻击前方4.5格，铁门和报纸的护甲与本体同时受创' },
  'hypno': { name: '魅惑菇', desc: '啃食它的僵尸会变成你的友军' },
  'ice_shroom': { name: '寒冰菇', desc: '种下瞬间冻住全场僵尸并使其减速' },
  'doom_shroom': { name: '毁灭菇', desc: '种下瞬间毁灭全场僵尸，原地留下弹坑' },
  'shovel': { name: '铲子', desc: '铲除场上一株植物，腾出宝贵格子' },
  'almanac': { name: '图鉴', desc: '记录所有植物与僵尸的详细资料，可从主页或结算页随时查阅' },
  'letter': { name: '僵王的挑战书', desc: '致草坪主人：你的草地守得不错。但僵王博士不会善罢甘休——下一关（1-10），僵尸将组织强烈攻势！植物将由传送带随机供应，不必选卡。敢来吗？——僵王博士' }
};

/** 僵尸图鉴（关卡开始前的情报预览）：name/desc + 色块颜色（与渲染层身体色一致） */
export interface ZombieIntro {
  name: string;
  desc: string;
  color: string;
}

export const ZOMBIE_INTRO: Record<string, ZombieIntro> = {
  'normal': { name: '普通僵尸', desc: '缓慢前进的老式僵尸，啃食植物', color: '#757575' },
  'cone': { name: '路障僵尸', desc: '头顶路障提供额外防护，更耐打', color: '#ff9800' },
  'bucket': { name: '铁桶僵尸', desc: '铁桶大幅提升防护，需集中火力', color: '#a9b0b8' },
  'pole': { name: '撑杆僵尸', desc: '持杆快速前进，遇到植物撑杆跳过', color: '#ffeb3b' },
  'football': { name: '橄榄球僵尸', desc: '头盔极厚且移速飞快，威胁很大', color: '#8e1a1a' },
  'dark_football': { name: '黑橄榄僵尸', desc: '比橄榄球更硬的强化版，护甲极厚', color: '#3e1010' },
  'thief': { name: '盗贼僵尸', desc: '会偷走地上的阳光，优先集火击杀', color: '#00897b' },
  'newspaper': { name: '读报僵尸', desc: '报纸被打烂后会狂暴加速', color: '#eceff1' },
  'door': { name: '铁门僵尸', desc: '手持铁门防护极高，孢子伤门也伤本体', color: '#cfd8dc' },
  'dancer': { name: '舞王僵尸', desc: '会召唤伴舞僵尸一起前进', color: '#e65100' },
  'elite': { name: '精英僵尸', desc: '偶发强化个体：速度、血量、护甲翻倍', color: '#e53935' }
};

/** 下一关 id：1-N → 1-(N+1)，1-10 → 2-1，2-N → 2-(N+1)，2-10 之后无下一关（返回空串） */
export function getNextLevelId(id: string): string {
  const parts: string[] = id.split('-');
  if (parts.length < 2) return '';
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

/**
 * 通关本关后掉落的物品 key（= 下一关新解锁的植物 / 特殊道具）。
 * 特例：1-4 通关掉铲子（1-5 解锁铲子，对齐原版）；1-9 通关掉僵王挑战书；
 *       2-4 通关掉图鉴（图鉴非植物 → 魅惑菇及之后植物整体后移一关）。
 * 无掉落的关（2-8 之后 / 最终关）返回空串。
 */
export function getUnlockPlantForLevel(id: string): string {
  const cfg = getLevelConfig(id);
  if (cfg === null) return '';
  if (id === '1-4') return 'shovel';
  if (id === '1-9') return 'letter';
  if (id === '2-4') return 'almanac';
  const nextId: string = getNextLevelId(id);
  if (nextId === '') return '';
  const ncfg = getLevelConfig(nextId);
  if (ncfg === null) return '';
  for (const k of ncfg.unlocks) {
    let owned: boolean = false;
    for (const cur of cfg.unlocks) {
      if (cur === k) {
        owned = true;
        break;
      }
    }
    if (!owned) return k;
  }
  return '';
}

/** 读 GAME_CONST 数值字段 */
export function getConstValue(key: string): number {
  const table: Record<string, number> = GAME_CONST as object as Record<string, number>;
  return table[key];
}

/** 写 GAME_CONST 数值字段（运行时热调：多数参数下次触发即生效，见 DEBUG_TUNABLES 的 timing 标注） */
export function setConstValue(key: string, value: number): void {
  const table: Record<string, number> = GAME_CONST as object as Record<string, number>;
  table[key] = value;
}
