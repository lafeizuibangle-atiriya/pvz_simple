/**
 * 卡片配置工厂：卡片数据、植物属性表、卡片命中检测
 * 绘制与点击共用同一份坐标计算，避免两处硬编码不同步
 */
import { GAME_CONST, ConveyorItem, PlantKind, SelectItem } from './GameTypes';

/** 卡片区域起始坐标（绘制与命中检测共用）：卡片区在草坪左侧，纵向两列排列 */
export const CARD_START_X: number = 12;
export const CARD_START_Y: number = 12;

/** 卡片列数：卡槽并排两列，向下延伸，不再占用草坪上方的横向空间 */
const CARD_COLS: number = 2;

/**
 * 按卡片行数与画布高度计算卡槽边长（40 ~ CARD_SLOT_SIZE 自适应）：
 * 布局 = 上边距 + 阳光槽1行 + 行间隔 + rows行卡槽 + (rows-1)个间隔 + 下边距
 * 绘制、命中检测、草坪位置计算三处共用，保证不会不同步
 */
export function calcCardSlotSize(cardCount: number, canvasH: number): number {
  const rows: number = Math.max(1, Math.ceil(cardCount / CARD_COLS));
  const gap: number = GAME_CONST.CARD_GAP;
  const usable: number = canvasH - CARD_START_Y * 2 - gap * rows;
  const slot: number = Math.floor(usable / (rows + 1)); // +1 = 阳光槽那一行
  return Math.max(40, Math.min(GAME_CONST.CARD_SLOT_SIZE, slot));
}

/** 左侧卡片区总宽度（引擎算草坪位置 / 渲染画底板 / 点击判定共用） */
export function calcCardPanelWidth(cardCount: number, canvasH: number): number {
  const slot: number = calcCardSlotSize(cardCount, canvasH);
  return CARD_START_X * 2 + slot * CARD_COLS + GAME_CONST.CARD_GAP * (CARD_COLS - 1);
}

/**
 * 选卡模式槽位坐标（index 0 = 阳光槽，1..n = 植物卡，两列纵向）：
 * 返回 [x, y]
 */
export function cardSlotPos(index: number, slotSize: number): number[] {
  if (index <= 0) {
    return [CARD_START_X, CARD_START_Y];
  }
  const i: number = index - 1;
  const col: number = i % CARD_COLS;
  const row: number = Math.floor(i / CARD_COLS);
  return [
    CARD_START_X + col * (slotSize + GAME_CONST.CARD_GAP),
    CARD_START_Y + slotSize + GAME_CONST.CARD_GAP + row * (slotSize + GAME_CONST.CARD_GAP)
  ];
}

/** 植物属性：费用 + 血量（新增植物只需在这里加一行） */
export interface PlantStats {
  cost: number;
  hp: number;
}

/** 全部白天植物卡（选卡页/卡片栏按关卡过滤） */
export function createDayCards(): SelectItem[] {
  return [
    { key: PlantKind.SHOOTER, label: "豌豆", color: "#4caf50", cost: 100, cd: GAME_CONST.CD_FAST },
    { key: PlantKind.SUNFLOWER, label: "向日葵", color: "#ffc107", cost: 50, cd: GAME_CONST.CD_FAST },
    { key: PlantKind.POTATO, label: "土豆", color: "#bca06a", cost: 25, cd: GAME_CONST.CD_POTATO },
    { key: PlantKind.ICE, label: "寒冰", color: "#29b6f6", cost: 175, cd: GAME_CONST.CD_FAST },
    { key: PlantKind.WALL, label: "坚果", color: "#8d6e63", cost: 50, cd: GAME_CONST.CD_SLOW },
    { key: PlantKind.CHOMER, label: "食人花", color: "#ab47bc", cost: 150, cd: GAME_CONST.CD_FAST },
    { key: PlantKind.DOUBLE, label: "双发", color: "#2e7d32", cost: 200, cd: GAME_CONST.CD_FAST },
    { key: PlantKind.CHERRY, label: "樱桃", color: "#e53935", cost: 150, cd: GAME_CONST.CD_CHERRY }
  ];
}

/** 全部夜晚蘑菇卡 */
export function createNightCards(): SelectItem[] {
  return [
    { key: PlantKind.PUFF, label: "小喷菇", color: "#7e57c2", cost: 0, cd: GAME_CONST.CD_FAST },
    { key: PlantKind.SUNSHROOM, label: "阳光菇", color: "#ffca28", cost: 25, cd: GAME_CONST.CD_FAST },
    { key: PlantKind.SCAREDY, label: "胆小菇", color: "#a1887f", cost: 25, cd: GAME_CONST.CD_FAST },
    { key: PlantKind.FUME, label: "大喷菇", color: "#5e35b1", cost: 75, cd: GAME_CONST.CD_SLOW },
    { key: PlantKind.HYPNO, label: "魅惑菇", color: "#f06292", cost: 75, cd: GAME_CONST.CD_SLOW },
    { key: PlantKind.ICE_SHROOM, label: "寒冰菇", color: "#4fc3f7", cost: 75, cd: GAME_CONST.CD_VERY_SLOW },
    { key: PlantKind.DOOM_SHROOM, label: "毁灭菇", color: "#546e7a", cost: 125, cd: GAME_CONST.CD_VERY_SLOW }
  ];
}

/** 某关卡可用的卡片列表（按 unlocks 顺序过滤；卡片池白天+夜晚合并，
 *  这样夜晚关卡的 unlocks 里包含白天植物时也能正常建卡） */
export function createCardsForLevel(unlocks: string[], night: boolean): SelectItem[] {
  const pool: SelectItem[] = createDayCards().concat(createNightCards());
  const result: SelectItem[] = [];
  for (const key of unlocks) {
    for (const c of pool) {
      if (c.key === key) {
        result.push(c);
        break;
      }
    }
  }
  return result;
}

/** 查询某种植物/工具的冷却帧数（种植成功后由引擎调用） */
export function getCardCooldown(key: string): number {
  for (const c of createDayCards()) {
    if (c.key === key) return c.cd;
  }
  for (const c of createNightCards()) {
    if (c.key === key) return c.cd;
  }
  return 0;
}

/** 卡片外观（通关掉落卡/解锁结算页/图鉴共用）：含铲子/图鉴/挑战书特例 */
export interface CardVisual {
  label: string;
  color: string;
  cost: number;
}

export function getCardVisual(key: string): CardVisual {
  if (key === 'shovel') {
    return { label: '铲子', color: '#546e7a', cost: 0 };
  }
  if (key === 'almanac') {
    return { label: '图鉴', color: '#8d6e63', cost: 0 };
  }
  if (key === 'letter') {
    return { label: '挑战书', color: '#efe3c0', cost: 0 };
  }
  for (const c of createDayCards()) {
    if (c.key === key) {
      return { label: c.label, color: c.color, cost: c.cost };
    }
  }
  for (const c of createNightCards()) {
    if (c.key === key) {
      return { label: c.label, color: c.color, cost: c.cost };
    }
  }
  return { label: '植物', color: '#4caf50', cost: 0 };
}

export function getPlantStats(kind: PlantKind): PlantStats {
  switch (kind) {
    case PlantKind.POTATO:
      return { cost: 25, hp: 60 };
    case PlantKind.SUNFLOWER:
      return { cost: 50, hp: 60 };
    case PlantKind.SHOOTER:
      return { cost: 100, hp: 60 };
    case PlantKind.ICE:
      return { cost: 175, hp: 60 };  // 175：用户调整（叠种同价）
    case PlantKind.DOUBLE:
      return { cost: 200, hp: 60 };
    case PlantKind.WALL:
      // 原版坚果4000血是普通植物300的13.3倍；这里普通植物60血 → 60×13.3 ≈ 800
      return { cost: 50, hp: 800 };
    case PlantKind.CHERRY:
      return { cost: 150, hp: 60 };
    case PlantKind.CHOMER:
      return { cost: 150, hp: 60 };
    // ===== 蘑菇系（原版定价） =====
    case PlantKind.PUFF:
      return { cost: 0, hp: 60 };      // 原版小喷菇0阳光
    case PlantKind.SUNSHROOM:
      return { cost: 25, hp: 60 };     // 原版阳光菇25
    case PlantKind.SCAREDY:
      return { cost: 25, hp: 60 };     // 原版胆小菇25
    case PlantKind.FUME:
      return { cost: 75, hp: 60 };     // 用户调整：原版100→75
    case PlantKind.HYPNO:
      return { cost: 75, hp: 60 };     // 原版魅惑菇75
    case PlantKind.ICE_SHROOM:
      return { cost: 75, hp: 60 };     // 原版寒冰菇75
    case PlantKind.DOOM_SHROOM:
      return { cost: 125, hp: 60 };    // 原版毁灭菇125
    default:
      return { cost: 0, hp: 60 };
  }
}

/**
 * 命中检测：点击点落在哪张卡片上（左侧两列卡槽，阳光槽在最上方）
 * 铲子在右上角按钮，不在卡片栏里；返回 null 表示没点中任何卡片
 */
export function findCardAt(cards: SelectItem[], clickX: number, clickY: number, canvasH: number): SelectItem | null {
  const slotSize = calcCardSlotSize(cards.length, canvasH);
  for (let i = 0; i < cards.length; i++) {
    const pos: number[] = cardSlotPos(i + 1, slotSize);
    if (clickX >= pos[0] && clickX <= pos[0] + slotSize
      && clickY >= pos[1] && clickY <= pos[1] + slotSize) {
      return cards[i];
    }
  }
  return null;
}

/**
 * 传送带槽位坐标（绘制与命中检测共用）：
 * 两条带 = 左右两列，从屏幕底部往上堆叠（row 0 = 最底层）
 * 返回 [x, y]（槽位左上角）
 */
export function conveyorSlotPos(lane: number, row: number, slotSize: number, canvasH: number): number[] {
  const x: number = CARD_START_X + lane * (slotSize + GAME_CONST.CARD_GAP);
  const y: number = canvasH - CARD_START_Y - (row + 1) * slotSize - row * GAME_CONST.CARD_GAP;
  return [x, y];
}

/** 传送带条目命中检测：返回点击的条目在 conveyorItems 里的下标（-1 = 未点中）
 *  下落中的卡片按当前绘制位置（目标槽位上方 fall 像素）判定，边下落边可点 */
export function findConveyorAt(items: ConveyorItem[], clickX: number, clickY: number, canvasH: number): number {
  const slotSize = calcCardSlotSize(GAME_CONST.CONVEYOR_MAX, canvasH);
  for (let i = 0; i < items.length; i++) {
    const pos: number[] = conveyorSlotPos(items[i].lane, items[i].row, slotSize, canvasH);
    const y: number = pos[1] - items[i].fall;
    if (clickX >= pos[0] && clickX <= pos[0] + slotSize
      && clickY >= y && clickY <= y + slotSize) {
      return i;
    }
  }
  return -1;
}
