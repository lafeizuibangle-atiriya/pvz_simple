/**
 * 渲染模块：所有 Canvas 绘制函数
 * 只负责"画"，不修改任何游戏状态
 */
import {
  Entity, GAME_CONST, BulletKind, CardCooldown, CoinDrop, ConveyorItem, ExplosionFx, GroundFx, Plant, PlantKind,
  SelectItem, SunDrop, Zombie, ZombieKind
} from './GameTypes';
import { CARD_START_X, CARD_START_Y, calcCardPanelWidth, calcCardSlotSize, cardSlotPos, conveyorSlotPos, getCardVisual } from './CardFactory';
import { GameEngine } from './GameEngine';

// ====================== 通用绘制工具 ======================

function drawHpBar(ctx: CanvasRenderingContext2D, entity: Entity): void {
  ctx.save();
  const barWidth: number = entity.w;
  const barX: number = entity.x;
  const barY: number = entity.y - GAME_CONST.BAR_HEIGHT - GAME_CONST.BAR_PADDING;
  const hpRatio: number = entity.hp / entity.maxHp;
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(barX - 1, barY - 1, barWidth + 2, GAME_CONST.BAR_HEIGHT + 2);
  ctx.fillStyle = "#222222";
  ctx.fillRect(barX, barY, barWidth, GAME_CONST.BAR_HEIGHT);
  ctx.fillStyle = hpRatio > 0.3 ? "#4caf50" : "#f44336";
  ctx.fillRect(barX, barY, barWidth * hpRatio, GAME_CONST.BAR_HEIGHT);
  ctx.restore();
}

/**
 * 僵尸血条：本体血条竖向贴左侧，防具血条横向在头顶
 */
function drawZombieBars(ctx: CanvasRenderingContext2D, z: Zombie): void {
  ctx.save();
  if (z.hp < z.maxHp) {
    const ratio: number = Math.max(0, z.hp / z.maxHp);
    const bx: number = z.x - GAME_CONST.BAR_HEIGHT - 4;
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(bx - 1, z.y - 1, GAME_CONST.BAR_HEIGHT + 2, z.h + 2);
    ctx.fillStyle = "#222222";
    ctx.fillRect(bx, z.y, GAME_CONST.BAR_HEIGHT, z.h);
    ctx.fillStyle = ratio > 0.3 ? "#4caf50" : "#f44336";
    ctx.fillRect(bx, z.y + z.h * (1 - ratio), GAME_CONST.BAR_HEIGHT, z.h * ratio);
  }
  if (z.armorHp > 0) {
    const ratio: number = Math.max(0, z.armorHp / z.maxArmorHp);
    const by: number = z.y - GAME_CONST.BAR_HEIGHT - GAME_CONST.BAR_PADDING;
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(z.x - 1, by - 1, z.w + 2, GAME_CONST.BAR_HEIGHT + 2);
    ctx.fillStyle = "#222222";
    ctx.fillRect(z.x, by, z.w, GAME_CONST.BAR_HEIGHT);
    ctx.fillStyle = "#42a5f5";
    ctx.fillRect(z.x, by, z.w * ratio, GAME_CONST.BAR_HEIGHT);
  }
  ctx.restore();
}

/** 横屏版：文字直接水平绘制 */
function drawText(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, fontSize: number, color: string = "#ffffff"): void {
  ctx.save();
  ctx.font = `bold ${fontSize}px sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillStyle = color;
  ctx.fillText(text, x, y);
  ctx.restore();
}

// ====================== 背景 ======================

export function drawBackground(ctx: CanvasRenderingContext2D, w: number, h: number, lanes: number,
  cell: number, gridLeft: number, gridTop: number, night: boolean): void {
  // 背景（草坪外）更浅，地块（草坪内）更深，形成明确区分
  const grass: string = night ? "#4a6b46" : "#8ec650";   // 最外层背景：浅绿
  const dim: string = night ? "#40603c" : "#7fbb42";     // 草坪区外围底色
  const dark: string = night ? "#31492e" : "#5f9930";    // 地块底色（比背景深）
  const dark2: string = night ? "#2b422a" : "#578f2b";   // 地块棋盘第二色（更深）
  const line: string = night ? "#24381f" : "#4c7d24";    // 格线
  const topBar: string = night ? "#141c14" : "#2e5118";
  ctx.fillStyle = grass;
  ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = dim;
  ctx.fillRect(0, GAME_CONST.TOP_ROW_H, w, h - GAME_CONST.TOP_ROW_H);
  const lawnW: number = cell * GAME_CONST.LAWN_COLS;
  const lawnH: number = cell * lanes;
  // 地块棋盘格：比背景更深的两档绿交替，与浅色背景拉开对比
  for (let r = 0; r < lanes; r++) {
    for (let c = 0; c < GAME_CONST.LAWN_COLS; c++) {
      ctx.fillStyle = (r + c) % 2 === 0 ? dark : dark2;
      ctx.fillRect(gridLeft + c * cell, gridTop + r * cell, cell, cell);
    }
  }
  ctx.strokeStyle = line;
  ctx.lineWidth = 1;
  for (let x = 0; x <= lawnW; x += cell) {
    ctx.beginPath();
    ctx.moveTo(gridLeft + x, gridTop);
    ctx.lineTo(gridLeft + x, gridTop + lawnH);
    ctx.stroke();
  }
  for (let r = 0; r <= lanes; r++) {
    const y: number = gridTop + r * cell;
    ctx.beginPath();
    ctx.moveTo(gridLeft, y);
    ctx.lineTo(gridLeft + lawnW, y);
    ctx.stroke();
  }
  ctx.fillStyle = topBar;
  ctx.fillRect(0, 0, w, GAME_CONST.TOP_ROW_H);
}

// ====================== 顶部选卡区 ======================

/** 左侧阳光计数槽：两列卡片区顶部的第一格 */
function drawSunText(ctx: CanvasRenderingContext2D, sun: number, slotSize: number): void {
  const x = CARD_START_X;
  const y = CARD_START_Y;
  ctx.fillStyle = "#f7b500";
  ctx.fillRect(x, y, slotSize, slotSize);
  ctx.fillStyle = "#ffd54a";
  ctx.fillRect(x, y, slotSize, 4);
  ctx.fillStyle = "#ffffff";
  ctx.beginPath();
  ctx.arc(x + slotSize / 2, y + slotSize * 0.3, slotSize * 0.19, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = "#f7b500";
  ctx.beginPath();
  ctx.arc(x + slotSize / 2, y + slotSize * 0.3, slotSize * 0.12, 0, Math.PI * 2);
  ctx.fill();
  drawText(ctx, `${sun}`, x + slotSize / 2, y + slotSize * 0.7, slotSize * 0.42);
}

function drawPlantCard(ctx: CanvasRenderingContext2D, item: SelectItem, x: number, y: number, slotSize: number, selectedKey: string, cdRatio: number = 0): void {
  if (item.key === "") {
    ctx.fillStyle = "#333333";
    ctx.fillRect(x, y, slotSize, slotSize);
    return;
  }
  if (selectedKey === item.key) {
    ctx.fillStyle = "#ffd700";
    ctx.fillRect(x - 3, y - 3, slotSize + 6, slotSize + 6);
  }
  ctx.fillStyle = "rgba(0,0,0,0.25)";
  ctx.fillRect(x + 2, y + 3, slotSize, slotSize);
  ctx.fillStyle = item.color;
  ctx.fillRect(x, y, slotSize, slotSize);
  ctx.fillStyle = "rgba(255,255,255,0.35)";
  ctx.fillRect(x, y, slotSize, 4);
  // 文字随卡槽大小自适应（卡槽 40~64px）
  const labelPx: number = item.label.length > 2 ? Math.round(slotSize * 0.36) : Math.round(slotSize * 0.5);
  drawText(ctx, item.label, x + slotSize / 2, y + slotSize * 0.34, labelPx);
  if (item.cost > 0) {
    drawText(ctx, `${item.cost}`, x + slotSize / 2, y + slotSize * 0.75, Math.round(slotSize * 0.36));
  } else {
    drawText(ctx, "0", x + slotSize / 2, y + slotSize * 0.75, Math.round(slotSize * 0.36));
  }
  if (cdRatio > 0) {
    ctx.fillStyle = "rgba(0,0,0,0.55)";
    ctx.fillRect(x, y, slotSize, slotSize * Math.min(1, cdRatio));
  }
}

function getCdRatio(cooldowns: CardCooldown[], key: string, maxCd: number): number {
  if (maxCd <= 0) return 0;
  for (const c of cooldowns) {
    if (c.key === key) return c.remain / maxCd;
  }
  return 0;
}

/** 普通关卡：左侧卡片面板（阳光槽 + 两列纵向植物卡，卡槽大小按屏高自适应） */
export function drawTopSelector(ctx: CanvasRenderingContext2D, sun: number, cards: SelectItem[],
  selectedKey: string, cooldowns: CardCooldown[], canvasH: number): void {
  const slotSize = calcCardSlotSize(cards.length, canvasH);
  // 左侧半透明底板，与草坪区分
  const panelW: number = calcCardPanelWidth(cards.length, canvasH);
  ctx.fillStyle = "rgba(0,0,0,0.32)";
  ctx.fillRect(0, 0, panelW, canvasH);
  drawSunText(ctx, sun, slotSize);
  for (let i = 0; i < cards.length; i++) {
    const pos: number[] = cardSlotPos(i + 1, slotSize);
    drawPlantCard(ctx, cards[i], pos[0], pos[1], slotSize, selectedKey,
      getCdRatio(cooldowns, cards[i].key, cards[i].cd));
  }
}

/**
 * 传送带关（1-10）：左右两条传送带（两列），从屏幕底部往上堆叠
 *  新卡从面板顶部缓落到底层空槽；只在"有卡片正在下落"的那条带画亮条，
 *  落定即熄灭——避免两条带在每次发卡时来回换色的抽搐感
 *  选中高亮按条目下标画金色边框（同种卡片两张时只亮选中的那张）
 */
export function drawConveyor(ctx: CanvasRenderingContext2D, items: ConveyorItem[], selectedIndex: number,
  cards: SelectItem[], canvasH: number): void {
  const slotSize = calcCardSlotSize(GAME_CONST.CONVEYOR_MAX, canvasH);
  const gap = GAME_CONST.CARD_GAP;
  const panelW: number = calcCardPanelWidth(GAME_CONST.CONVEYOR_MAX, canvasH);
  ctx.fillStyle = "rgba(0,0,0,0.32)";
  ctx.fillRect(0, 0, panelW, canvasH);

  // 两条传送带底色；正在下落卡片的那条带画稳定亮条（落定后消失，不轮流闪烁）
  const fallingLane: number = items.length > 0 && items[items.length - 1].fall > 0
    ? items[items.length - 1].lane : -1;
  for (let lane = 0; lane < 2; lane++) {
    const x: number = CARD_START_X - 4 + lane * (slotSize + gap);
    const beltW: number = slotSize + 8;
    ctx.fillStyle = lane === fallingLane ? "rgba(255,235,59,0.22)" : "rgba(0,0,0,0.25)";
    ctx.fillRect(x, 0, beltW, canvasH);
  }

  for (let i = 0; i < items.length; i++) {
    const it: ConveyorItem = items[i];
    const pos: number[] = conveyorSlotPos(it.lane, it.row, slotSize, canvasH);
    const y: number = pos[1] - it.fall; // 下落中：画在目标位上方
    let item: SelectItem | null = null;
    for (const c of cards) {
      if (c.key === it.key) {
        item = c;
        break;
      }
    }
    if (item === null) continue;
    drawPlantCard(ctx, item, pos[0], y, slotSize, "", 0);
    if (i === selectedIndex) {
      // 选中边框（不用 selectedKey，避免同种两张卡一起亮）
      ctx.strokeStyle = "#ffd700";
      ctx.lineWidth = 3;
      ctx.strokeRect(pos[0] - 3, y - 3, slotSize + 6, slotSize + 6);
    }
  }
  if (items.length === 0) {
    drawText(ctx, "传送带供应中…", CARD_START_X + slotSize, canvasH / 2, 18, "#9e9e9e");
  }
}

// ====================== 实体绘制 ======================

/** 商店强化过的植物（叠加强化任一维度即算）：右上角画金星与普通植物区分 */
function isPlantUpgraded(p: Plant): boolean {
  return p.enhanced || p.doubleSun || p.fastSun || p.cannon
    || p.armorTier > 0 || p.chewTier > 0 || p.sunBoostTier > 0
    || p.peaArmTier > 0 || p.sporeTier > 0
    || p.scaredyTier > 0 || p.fumeTier > 0;
}

function drawPlants(ctx: CanvasRenderingContext2D, plants: Plant[], night: boolean): void {
  for (const p of plants) {
    if (p.dead) continue;
    drawHpBar(ctx, p);
    // 蘑菇白天睡觉：灰色底 + "睡觉"角标（原版规则，行为层已同步休眠）
    const asleep: boolean = !night && (p.kind === PlantKind.PUFF
      || p.kind === PlantKind.SUNSHROOM || p.kind === PlantKind.SCAREDY
      || p.kind === PlantKind.FUME || p.kind === PlantKind.HYPNO
      || p.kind === PlantKind.ICE_SHROOM || p.kind === PlantKind.DOOM_SHROOM);
    switch (p.kind) {
      case PlantKind.POTATO:
        ctx.fillStyle = p.armed ? "#c62828" : "#eeeeee";
        ctx.fillRect(p.x, p.y, p.w, p.h);
        drawText(ctx, "土豆", p.x + p.w / 2, p.y + p.h / 2, 38);
        break;
      case PlantKind.CHERRY: {
        const blinking: boolean = p.armTimer < 32 && Math.floor(p.armTimer / 8) % 2 === 0;
        ctx.fillStyle = blinking ? "#1a1a1a" : "#d32f2f";
        ctx.fillRect(p.x, p.y, p.w, p.h);
        drawText(ctx, "樱桃", p.x + p.w / 2, p.y + p.h / 2, 38, "#ffffff");
        break;
      }
      case PlantKind.WALL: {
        // 坚果强化术：银色（1级护甲）/金色（2级护甲），普通为棕色
        let wallColor = "#8d6e63";
        if (p.armorTier === 1 && p.armorHp > 0) {
          wallColor = "#cfd8dc";
        } else if (p.armorTier === 2 && p.armorHp > 0) {
          wallColor = "#ffd700";
        }
        ctx.fillStyle = wallColor;
        ctx.fillRect(p.x, p.y, p.w, p.h);
        // 强化护甲剩一半以下时出现裂纹提示（颜色变暗）
        if (p.armorHp > 0 && p.armorHp < p.maxArmorHp * 0.5) {
          ctx.fillStyle = "rgba(0,0,0,0.25)";
          ctx.fillRect(p.x, p.y, p.w, p.h);
        }
        drawText(ctx, "坚果", p.x + p.w / 2, p.y + p.h / 2, 38);
        break;
      }
      case PlantKind.SHOOTER:
        ctx.fillStyle = "#4caf50";
        ctx.fillRect(p.x, p.y, p.w, p.h);
        drawText(ctx, "豌豆", p.x + p.w / 2, p.y + p.h / 2, 38);
        break;
      case PlantKind.DOUBLE:
        ctx.fillStyle = "#2e7d32";
        ctx.fillRect(p.x, p.y, p.w, p.h);
        drawText(ctx, "双发", p.x + p.w / 2, p.y + p.h / 2, 38);
        break;
      case PlantKind.SUNFLOWER:
        ctx.fillStyle = "#ffc107";
        ctx.fillRect(p.x, p.y, p.w, p.h);
        drawText(ctx, "向日葵", p.x + p.w / 2, p.y + p.h / 2, 32);
        break;
      case PlantKind.ICE:
        ctx.fillStyle = "#29b6f6";
        ctx.fillRect(p.x, p.y, p.w, p.h);
        drawText(ctx, "寒冰", p.x + p.w / 2, p.y + p.h / 2, 38);
        break;
      case PlantKind.CHOMER: {
        const digesting: boolean = p.digestTimer > 0;
        ctx.fillStyle = digesting ? "#4a148c" : "#ab47bc";
        ctx.fillRect(p.x, p.y, p.w, p.h);
        ctx.fillStyle = digesting ? "#6a1b9a" : "#ce93d8";
        ctx.fillRect(p.x, p.y, p.w, 5);
        drawText(ctx, "食人花", p.x + p.w / 2, p.y + p.h / 2, 30,
          digesting ? "#ce93d8" : "#ffffff");
        if (digesting) {
          drawText(ctx, "消化中", p.x + p.w / 2, p.y + p.h / 2 + 24, 18, "#b39ddb");
        }
        break;
      }
      // ===== 蘑菇系（夜晚；白天睡觉画灰色） =====
      case PlantKind.PUFF:
        // 小喷菇：体积比普通植物小一号（原版就是小蘑菇）；孢子蔓延术复制体颜色更浅
        ctx.fillStyle = asleep ? "#9e9e9e" : (p.sporeCopy ? "#b39ddb" : "#7e57c2");
        ctx.fillRect(p.x + 6, p.y + 10, p.w - 12, p.h - 10);
        drawText(ctx, "小喷菇", p.x + p.w / 2, p.y + p.h / 2 + 6, 24);
        if (p.sporeCopy) {
          drawText(ctx, "复制体", p.x + p.w / 2, p.y + p.h - 6, 14, "#ede7f6");
        }
        break;
      case PlantKind.SUNSHROOM: {
        // 阳光菇：小时浅黄瘦小，长大金黄饱满
        if (asleep) {
          ctx.fillStyle = "#9e9e9e";
          ctx.fillRect(p.x + 10, p.y + 16, p.w - 20, p.h - 16);
          drawText(ctx, "阳光菇", p.x + p.w / 2, p.y + p.h / 2 + 8, 20);
        } else if (p.grown) {
          ctx.fillStyle = "#ffb300";
          ctx.fillRect(p.x, p.y, p.w, p.h);
          drawText(ctx, "阳光菇", p.x + p.w / 2, p.y + p.h / 2, 28);
        } else {
          ctx.fillStyle = "#ffe082";
          ctx.fillRect(p.x + 10, p.y + 16, p.w - 20, p.h - 16);
          drawText(ctx, "阳光菇", p.x + p.w / 2, p.y + p.h / 2 + 8, 20);
        }
        break;
      }
      case PlantKind.SCAREDY: {
        // 胆小菇：僵尸靠近一格内变白缩起来，平时棕色正常攻击
        ctx.fillStyle = asleep ? "#9e9e9e" : (p.scared ? "#eceff1" : "#a1887f");
        ctx.fillRect(p.x, p.y, p.w, p.h);
        drawText(ctx, "胆小菇", p.x + p.w / 2, p.y + p.h / 2, 26, p.scared ? "#78909c" : "#ffffff");
        break;
      }
      case PlantKind.FUME:
        ctx.fillStyle = asleep ? "#9e9e9e" : "#5e35b1";
        ctx.fillRect(p.x, p.y, p.w, p.h);
        ctx.fillStyle = asleep ? "#bdbdbd" : "#7e57c2";
        ctx.fillRect(p.x, p.y, p.w, 5);
        drawText(ctx, "大喷菇", p.x + p.w / 2, p.y + p.h / 2, 28);
        break;
      case PlantKind.HYPNO:
        ctx.fillStyle = asleep ? "#9e9e9e" : "#f06292";
        ctx.fillRect(p.x, p.y, p.w, p.h);
        ctx.fillStyle = asleep ? "#bdbdbd" : "#f8bbd0";
        ctx.fillRect(p.x, p.y, p.w, 5);
        drawText(ctx, "魅惑菇", p.x + p.w / 2, p.y + p.h / 2, 28);
        break;
      case PlantKind.ICE_SHROOM:
        // 寒冰菇：种下瞬间全场冰冻（一次性，通常只能看到触发特效）
        ctx.fillStyle = asleep ? "#9e9e9e" : "#4fc3f7";
        ctx.fillRect(p.x + 4, p.y + 8, p.w - 8, p.h - 8);
        drawText(ctx, "寒冰菇", p.x + p.w / 2, p.y + p.h / 2, 24);
        break;
      case PlantKind.DOOM_SHROOM:
        // 毁灭菇：种下瞬间全场伤害 + 留坑（一次性）
        ctx.fillStyle = asleep ? "#9e9e9e" : "#546e7a";
        ctx.fillRect(p.x, p.y, p.w, p.h);
        ctx.fillStyle = asleep ? "#bdbdbd" : "#263238";
        ctx.fillRect(p.x, p.y, p.w, 5);
        drawText(ctx, "毁灭菇", p.x + p.w / 2, p.y + p.h / 2, 24);
        break;
      default:
        break;
    }
    // 白天睡觉角标（蘑菇系）
    if (asleep) {
      drawText(ctx, "睡觉", p.x + p.w / 2, p.y + p.h - 9, 16, "#fffde7");
    }
    // 强化标记：白色内轮廓 + 金色外轮廓 + 金星
    if (isPlantUpgraded(p)) {
      ctx.lineWidth = 3;
      ctx.strokeStyle = "#ffffff";
      ctx.strokeRect(p.x + 2, p.y + 2, p.w - 4, p.h - 4);
      ctx.strokeStyle = "#ffd700";
      ctx.strokeRect(p.x - 3, p.y - 3, p.w + 6, p.h + 6);
      drawText(ctx, "★", p.x + p.w - 8, p.y + 8, 22, "#ffd700");
    }
    // 孢子蔓延术标记：左上角紫色小圆点（带攻速+25% buff，不叠加只画一个）；
    // 已有金星强化标记时稍向右错开，避免遮挡
    if (p.sporeMark) {
      const dotX: number = p.x + (isPlantUpgraded(p) ? 26 : 10);
      ctx.fillStyle = "#d1c4e9";
      ctx.beginPath();
      ctx.arc(dotX, p.y + 10, 7, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = "#9575cd";
      ctx.beginPath();
      ctx.arc(dotX, p.y + 10, 4, 0, Math.PI * 2);
      ctx.fill();
    }
  }
}

function drawZombies(ctx: CanvasRenderingContext2D, zombies: Zombie[]): void {
  for (const z of zombies) {
    if (z.dead) continue;
    // 魅惑友军粉色；冻结深蓝；减速浅蓝；极寒染色中蓝；黑橄榄暗红；橄榄球深红；狂暴读报红；盗贼青绿；其余灰
    let body = "#757575";
    if (z.friendly) {
      body = "#f48fb1";
    } else if (z.frozenTimer > 0) {
      body = "#0d47a1";   // 被极寒冻结：深蓝
    } else if (z.slowTimer > 0) {
      body = "#90caf9";   // 减速：浅蓝（冻结解除后回到这一档）
    } else if (z.frostTinted) {
      body = "#64b5f6";   // 被极寒子弹击中过：中蓝（明显浅于冻结）
    } else if (z.zombieKind === ZombieKind.DarkFootball && z.armorHp > 0) {
      body = "#3e1010";   // 黑橄榄：比橄榄球更深的暗红
    } else if (z.zombieKind === ZombieKind.Thief) {
      body = "#00897b";   // 盗贼：青绿
    } else if (z.zombieKind === ZombieKind.Football && z.armorHp > 0) {
      body = "#8e1a1a";
    } else if (z.zombieKind === ZombieKind.Newspaper && z.enraged) {
      body = "#d84315";
    } else if (z.zombieKind === ZombieKind.Dancer) {
      body = "#e65100";
    } else if (z.zombieKind === ZombieKind.DancerMinion) {
      body = "#ef6c00";
    }
    ctx.fillStyle = body;
    ctx.fillRect(z.x, z.y, z.w, z.h);
    // ===== 精英强化僵尸：白色内轮廓 + 红色外轮廓 =====
    if (z.elite) {
      ctx.lineWidth = 3;
      ctx.strokeStyle = "#ffffff";
      ctx.strokeRect(z.x + 2, z.y + 2, z.w - 4, z.h - 4);
      ctx.strokeStyle = "#e53935";
      ctx.strokeRect(z.x - 3, z.y - 3, z.w + 6, z.h + 6);
    }
    drawZombieBars(ctx, z);
    const zombieWord: string = "僵尸";
    // 魅惑僵尸：不加"友军"字样，保持原有种类文字，仅身体颜色变粉（drawZombies 里已处理）
    if (z.zombieKind === ZombieKind.Cone && z.armorHp > 0) {
      drawText(ctx, "路障", z.x + z.w / 2, z.y + z.h / 2 - 13, 30, "#ff9800");
      drawText(ctx, zombieWord, z.x + z.w / 2, z.y + z.h / 2 + 14, 26, "#ffffff");
    } else if (z.zombieKind === ZombieKind.Bucket && z.armorHp > 0) {
      drawText(ctx, "铁桶", z.x + z.w / 2, z.y + z.h / 2 - 13, 30, "#a9b0b8");
      drawText(ctx, zombieWord, z.x + z.w / 2, z.y + z.h / 2 + 14, 26, "#ffffff");
    } else if ((z.zombieKind === ZombieKind.Football || z.zombieKind === ZombieKind.DarkFootball) && z.armorHp > 0) {
      drawText(ctx, z.zombieKind === ZombieKind.DarkFootball ? "黑橄榄" : "橄榄球",
        z.x + z.w / 2, z.y + z.h / 2 - 13, 28, "#ff8a80");
      drawText(ctx, zombieWord, z.x + z.w / 2, z.y + z.h / 2 + 14, 26, "#ffffff");
    } else if (z.zombieKind === ZombieKind.Thief) {
      drawText(ctx, "盗贼", z.x + z.w / 2, z.y + z.h / 2 - 13, 28, "#b2dfdb");
      drawText(ctx, zombieWord, z.x + z.w / 2, z.y + z.h / 2 + 14, 26, "#ffffff");
    } else if (z.zombieKind === ZombieKind.Newspaper) {
      if (z.armorHp > 0) {
        drawText(ctx, "报纸", z.x + z.w / 2, z.y + z.h / 2 - 13, 28, "#eceff1");
        drawText(ctx, zombieWord, z.x + z.w / 2, z.y + z.h / 2 + 14, 26, "#ffffff");
      } else {
        drawText(ctx, "狂暴！", z.x + z.w / 2, z.y + z.h / 2 - 13, 28, "#ff5722");
        drawText(ctx, zombieWord, z.x + z.w / 2, z.y + z.h / 2 + 14, 26, "#ffffff");
      }
    } else if (z.zombieKind === ZombieKind.Door && z.armorHp > 0) {
      drawText(ctx, "铁门", z.x + z.w / 2, z.y + z.h / 2 - 13, 28, "#cfd8dc");
      drawText(ctx, zombieWord, z.x + z.w / 2, z.y + z.h / 2 + 14, 26, "#ffffff");
    } else if (z.zombieKind === ZombieKind.Dancer) {
      drawText(ctx, "舞王", z.x + z.w / 2, z.y + z.h / 2, 30, "#ffcc80");
    } else if (z.zombieKind === ZombieKind.DancerMinion) {
      drawText(ctx, "伴舞", z.x + z.w / 2, z.y + z.h / 2, 28, "#ffe0b2");
    } else if (z.zombieKind === ZombieKind.Pole) {
      if (z.hasPole) {
        drawText(ctx, "撑杆", z.x + z.w / 2, z.y + z.h / 2 - 13, 28, "#ffeb3b");
      }
      drawText(ctx, zombieWord, z.x + z.w / 2, z.y + z.h / 2 + (z.hasPole ? 14 : 0), 30, body);
    } else {
      drawText(ctx, zombieWord, z.x + z.w / 2, z.y + z.h / 2, 34);
    }
  }
}

function drawBullets(ctx: CanvasRenderingContext2D, bullets: BulletLike[]): void {
  for (const b of bullets) {
    if (b.dead) continue;
    ctx.save();
    ctx.beginPath();
    ctx.arc(b.x, b.y, 7, 0, Math.PI * 2);
    ctx.fillStyle = "#ffffff";
    ctx.fill();
    let core = "#4caf50";
    if (b.kind === BulletKind.ICE) {
      core = "#00e5ff";
    } else if (b.kind === BulletKind.SPORE) {
      core = "#b39ddb"; // 蘑菇孢子：紫色
    } else if (b.kind === BulletKind.FIRE) {
      core = "#ff5252"; // 火焰：红
    } else if (b.kind === BulletKind.STONE) {
      core = "#8d8d8d"; // 石化：石色
    } else if (b.kind === BulletKind.FROST) {
      core = "#2962ff"; // 极寒：深蓝
    } else if (b.kind === BulletKind.SHELL) {
      core = "#4e342e"; // 土豆炮弹：深棕
    }
    ctx.fillStyle = core;
    ctx.beginPath();
    ctx.arc(b.x, b.y, b.kind === BulletKind.SHELL ? 10 : 6, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }
}

interface BulletLike {
  x: number;
  y: number;
  kind: BulletKind;
  dead: boolean;
}

function drawSunDrops(ctx: CanvasRenderingContext2D, sunDrops: SunDrop[]): void {
  for (const s of sunDrops) {
    if (s.dead) continue;
    const stolen: boolean = s.stolenBy !== null; // 被盗贼锁定：变红警告
    // 超大阳光（光能鼓舞 50/75）比普通阳光大一圈
    const big: boolean = s.value >= 50;
    const r1: number = big ? 27 : 19;
    const r2: number = big ? 22 : 15;
    const r3: number = big ? 12 : 8;
    ctx.save();
    ctx.beginPath();
    ctx.arc(s.x, s.y, r1, 0, Math.PI * 2);
    ctx.fillStyle = "#ffffff";
    ctx.fill();
    ctx.fillStyle = stolen ? "#e53935" : "#ffd700";
    ctx.beginPath();
    ctx.arc(s.x, s.y, r2, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = stolen ? "#b71c1c" : "#ffb300";
    ctx.beginPath();
    ctx.arc(s.x, s.y, r3, 0, Math.PI * 2);
    ctx.fill();
    if (big) {
      // 超大阳光外圈光环，一眼可辨
      ctx.strokeStyle = "rgba(255,235,59,0.7)";
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(s.x, s.y, r1 + 4, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.restore();
  }
}

/** 掉落货币：铜/银/金圆币 + 钻石（存档货币），按 kind 区分颜色与大小 */
function drawCoins(ctx: CanvasRenderingContext2D, coins: CoinDrop[]): void {
  for (const c of coins) {
    if (c.dead) continue;
    ctx.save();
    // 临近消失时闪烁提醒
    if (c.timer < 90 && Math.floor(c.timer / 10) % 2 === 0) {
      ctx.globalAlpha = 0.35;
    }
    if (c.kind === 'diamond') {
      // 钻石：大颗青蓝菱形 + 白色高光
      const r: number = 15;
      ctx.beginPath();
      ctx.moveTo(c.x, c.y - r);
      ctx.lineTo(c.x + r, c.y);
      ctx.lineTo(c.x, c.y + r);
      ctx.lineTo(c.x - r, c.y);
      ctx.closePath();
      ctx.fillStyle = "#26c6da";
      ctx.fill();
      ctx.beginPath();
      ctx.moveTo(c.x, c.y - r * 0.55);
      ctx.lineTo(c.x + r * 0.55, c.y);
      ctx.lineTo(c.x, c.y + r * 0.55);
      ctx.lineTo(c.x - r * 0.55, c.y);
      ctx.closePath();
      ctx.fillStyle = "#b2ebf2";
      ctx.fill();
      drawText(ctx, "◆", c.x, c.y, 12, "#ffffff");
    } else {
      // 三档圆币：铜/银/金
      let rim = "#ffd700";
      let core = "#f9a825";
      let word = "$";
      if (c.kind === 'copper') {
        rim = "#cd7f32";
        core = "#a0522d";
      } else if (c.kind === 'silver') {
        rim = "#cfd8dc";
        core = "#90a4ae";
      }
      ctx.beginPath();
      ctx.arc(c.x, c.y, 12, 0, Math.PI * 2);
      ctx.fillStyle = "#ffffff";
      ctx.fill();
      ctx.beginPath();
      ctx.arc(c.x, c.y, 10, 0, Math.PI * 2);
      ctx.fillStyle = rim;
      ctx.fill();
      ctx.beginPath();
      ctx.arc(c.x, c.y, 6, 0, Math.PI * 2);
      ctx.fillStyle = core;
      ctx.fill();
      drawText(ctx, word, c.x, c.y, 12, "#fff8e1");
    }
    ctx.restore();
  }
}

// ====================== 小推车 ======================

/** 单辆小推车：灰色车身 + 深灰推手 + 黑色滚轮 */
function drawMower(ctx: CanvasRenderingContext2D, x: number, centerY: number): void {
  ctx.save();
  // 车身
  ctx.fillStyle = "#9e9e9e";
  ctx.fillRect(x, centerY - 12, 30, 18);
  ctx.fillStyle = "#cfd8dc";
  ctx.fillRect(x, centerY - 12, 30, 5);
  // 推手（斜向后上方的深灰杆）
  ctx.fillStyle = "#616161";
  ctx.fillRect(x - 8, centerY - 22, 6, 14);
  // 滚轮
  ctx.fillStyle = "#212121";
  ctx.beginPath();
  ctx.arc(x + 7, centerY + 8, 5, 0, Math.PI * 2);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(x + 23, centerY + 8, 5, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

/**
 * 绘制小推车：已购买时每行草坪左侧停一辆（待命）；
 * 触发后的小推车正在草坪上向右疾驰清行
 */
function drawMowers(ctx: CanvasRenderingContext2D, engine: GameEngine): void {
  if (engine.mowerEnabled) {
    for (let col = 0; col < engine.colCount; col++) {
      if (!engine.mowers[col]) continue;
      drawMower(ctx, engine.gridLeft - 34, engine.gridTop + col * engine.cell + engine.cell / 2);
    }
  }
  for (const m of engine.mowerFxs) {
    drawMower(ctx, m.x, engine.gridTop + m.col * engine.cell + engine.cell / 2);
  }
}

// ====================== 特效 ======================

function drawEffects(ctx: CanvasRenderingContext2D, effects: ExplosionFx[]): void {
  for (const fx of effects) {
    const progress: number = 1 - fx.timer / fx.maxTimer;
    ctx.save();
    ctx.globalAlpha = 1 - progress;
    if (fx.fxKind === 'fume') {
      // 大喷菇孢子群：紫色横带云雾（高约多半格）
      const bandH: number = 44;
      ctx.fillStyle = fx.color !== undefined ? fx.color : "#9575cd";
      ctx.fillRect(fx.x - fx.radius, fx.y - bandH / 2, fx.radius * 2, bandH);
      ctx.globalAlpha = (1 - progress) * 0.6;
      ctx.fillStyle = "#d1c4e9";
      ctx.fillRect(fx.x - fx.radius * 0.8, fx.y - bandH / 3, fx.radius * 1.6, bandH * 0.66);
    } else if (fx.fxKind === 'freeze_all' || fx.fxKind === 'doom_all') {
      // 寒冰菇（全屏蓝闪）/ 毁灭菇（全屏灰闪）：覆盖整个画布，快速渐隐
      ctx.fillStyle = fx.color !== undefined ? fx.color : "#ffffff";
      ctx.fillRect(fx.x - fx.radius, fx.y - fx.radius, fx.radius * 2, fx.radius * 2);
      ctx.globalAlpha = (1 - progress) * 0.5;
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(fx.x - fx.radius, fx.y - fx.radius, fx.radius * 2, fx.radius * 2);
    } else {
      const r: number = fx.radius * (0.4 + 0.6 * progress);
      ctx.fillStyle = "#ff6d00";
      ctx.beginPath();
      ctx.arc(fx.x, fx.y, r, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = "#ffd54a";
      ctx.beginPath();
      ctx.arc(fx.x, fx.y, r * 0.55, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }
}

// ====================== 地面持续效果 ======================

/** 光能鼓舞：被鼓舞阳光菇左右两格地块画金色外框+白色内框（2级线更粗更醒目），渲染在植物之下 */
function drawSunBoostCells(ctx: CanvasRenderingContext2D, engine: GameEngine): void {
  for (const m of engine.plants) {
    if (m.dead || m.kind !== PlantKind.SUNSHROOM || m.sunBoostTier <= 0) continue;
    const tier: number = m.sunBoostTier;
    const colIndex: number = Math.round((m.x - engine.gridLeft) / engine.cell);
    for (const dc of [-1, 1]) {
      const cx: number = engine.gridLeft + (colIndex + dc) * engine.cell;
      const cy: number = engine.gridTop + m.col * engine.cell;
      if (cx < engine.gridLeft - 1 || cx >= engine.gridLeft + engine.cell * GAME_CONST.LAWN_COLS) continue;
      // 金色外框
      ctx.save();
      ctx.strokeStyle = "#ffd54a";
      ctx.lineWidth = tier === 2 ? 4 : 3;
      ctx.strokeRect(cx + 2, cy + 2, engine.cell - 4, engine.cell - 4);
      // 白色内框
      ctx.strokeStyle = "rgba(255,255,255,0.85)";
      ctx.lineWidth = tier === 2 ? 2 : 1.5;
      ctx.strokeRect(cx + 6, cy + 6, engine.cell - 12, engine.cell - 12);
      ctx.restore();
    }
  }
}

/** 腐蚀液（紫色块）/熔岩（橙红块）/毁灭菇弹坑（深灰坑），渲染在草地之上、植物之下 */
function drawGroundFxs(ctx: CanvasRenderingContext2D, fxs: GroundFx[], cell: number): void {
  for (const g of fxs) {
    ctx.save();
    if (g.kind === 'lava') {
      ctx.fillStyle = "rgba(255,87,34,0.8)";
    } else if (g.kind === 'crater' || g.kind === 'radiation') {
      // 毁灭菇弹坑：深灰圆坑 + 边缘焦土色（辐射坑为绿色调），随剩余时间渐隐
      const radiation: boolean = g.kind === 'radiation';
      ctx.fillStyle = radiation ? "rgba(27,94,32,0.85)" : "rgba(38,50,56,0.85)";
      ctx.beginPath();
      ctx.arc(g.x, g.y, cell * 0.42, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = radiation ? "rgba(104,159,56,0.9)" : "rgba(78,52,46,0.9)";
      ctx.lineWidth = 4;
      ctx.stroke();
      if (radiation) {
        // 辐射坑中央画 radioactive 感的绿色光点
        ctx.fillStyle = "rgba(156,204,101,0.5)";
        ctx.beginPath();
        ctx.arc(g.x, g.y, cell * 0.18, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();
      continue;
    } else {
      ctx.fillStyle = "rgba(123,31,162,0.6)";
    }
    ctx.fillRect(g.x - cell / 2, g.y - cell / 2, cell, cell);
    ctx.restore();
  }
}

// ====================== 通关掉卡（新植物解锁） ======================

/**
 * 最后一只僵尸掉落的种子包：绿色包装 + 内嵌植物卡面。
 * 下落时左右摇摆，落地后金色光环脉冲 + 四角星光闪烁（解锁特效）
 */
function drawCardDrop(ctx: CanvasRenderingContext2D, engine: GameEngine): void {
  const c = engine.cardDrop;
  if (c === null) return;
  const size: number = 76;
  const vis = getCardVisual(c.key);
  ctx.save();
  ctx.translate(c.x, c.y);

  if (c.landed) {
    // 金色光环脉冲
    const pulse: number = 0.5 + 0.5 * Math.sin(engine.frameCount * 0.15);
    ctx.strokeStyle = `rgba(255,215,0,${(0.45 + 0.4 * pulse).toFixed(2)})`;
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(0, 0, size * 0.72 + pulse * 8, 0, Math.PI * 2);
    ctx.stroke();
    // 四角星光（旋转小十字）
    const spin: number = engine.frameCount * 0.05;
    for (let i = 0; i < 4; i++) {
      const ang: number = spin + i * Math.PI / 2;
      const sx: number = Math.cos(ang) * size * 0.95;
      const sy: number = Math.sin(ang) * size * 0.95;
      const tw: number = 4 + 3 * Math.sin(engine.frameCount * 0.2 + i);
      ctx.strokeStyle = "#fff59d";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(sx - tw, sy);
      ctx.lineTo(sx + tw, sy);
      ctx.moveTo(sx, sy - tw);
      ctx.lineTo(sx, sy + tw);
      ctx.stroke();
    }
  }

  // 投影
  ctx.fillStyle = "rgba(0,0,0,0.3)";
  ctx.fillRect(-size / 2 + 3, -size / 2 + 4, size, size);
  if (c.key === 'letter') {
    // 挑战书：米黄信封 + 盖口折线 + 红色火漆印
    ctx.fillStyle = "#efe3c0";
    ctx.fillRect(-size / 2, -size / 2, size, size);
    ctx.strokeStyle = "#c9b68a";
    ctx.lineWidth = 2;
    ctx.strokeRect(-size / 2, -size / 2, size, size);
    ctx.beginPath();
    ctx.moveTo(-size / 2, -size / 2);
    ctx.lineTo(0, size * 0.1);
    ctx.lineTo(size / 2, -size / 2);
    ctx.stroke();
    ctx.fillStyle = "#c62828";
    ctx.beginPath();
    ctx.arc(0, size * 0.1, size * 0.14, 0, Math.PI * 2);
    ctx.fill();
    drawText(ctx, "挑战书", 0, size * 0.32, 16, "#6d4c41");
  } else if (c.key === 'almanac') {
    // 图鉴：棕色封面 + 书脊 + 主题字
    ctx.fillStyle = "#8d6e63";
    ctx.fillRect(-size / 2, -size / 2, size, size);
    ctx.fillStyle = "#5d4037";
    ctx.fillRect(-size / 2, -size / 2, 10, size);
    ctx.strokeStyle = "#d7ccc8";
    ctx.lineWidth = 2;
    ctx.strokeRect(-size / 2 + 14, -size / 2 + 8, size - 20, size - 16);
    drawText(ctx, "图 鉴", 0, -size * 0.05, 20, "#ffe0b2");
    drawText(ctx, "plants · zombies", 0, size * 0.22, 10, "#bcaaa4");
  } else {
    // 绿色种子包外框
    ctx.fillStyle = "#33691e";
    ctx.fillRect(-size / 2, -size / 2, size, size);
    ctx.fillStyle = "#558b2f";
    ctx.fillRect(-size / 2, -size / 2, size, 9);
    ctx.fillStyle = "rgba(255,255,255,0.25)";
    ctx.fillRect(-size / 2, size / 2 - 4, size, 4);
    // 内嵌植物卡面
    ctx.fillStyle = vis.color;
    ctx.fillRect(-size / 2 + 7, -size / 2 + 12, size - 14, size - 24);
    drawText(ctx, vis.label, 0, -size * 0.1, 20);
    drawText(ctx, vis.cost > 0 ? `${vis.cost}` : "0", 0, size * 0.28, 18, "#fff59d");
  }
  ctx.restore();
}

// ====================== 总渲染入口 ======================

/**
 * 开局横幅："准备种植你的植物"（用户要求字号加大）
 * 三阶段揭示："准备" → "准备种植" → "准备种植你的植物！"
 */
function drawStartBanner(ctx: CanvasRenderingContext2D, w: number, h: number, remain: number): void {
  const total: number = GAME_CONST.START_BANNER_FRAMES;
  const elapsed: number = total - remain;
  const progress: number = elapsed / total;

  let text: string = "准备";
  if (progress >= 0.62) {
    text = "准备种植你的植物！";
  } else if (progress >= 0.32) {
    text = "准备种植";
  }

  let alpha: number = 1;
  if (elapsed < 16) {
    alpha = elapsed / 16;
  } else if (remain < 22) {
    alpha = remain / 22;
  }

  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.font = "bold 56px sans-serif"; // 用户要求加大
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.lineWidth = 7;
  ctx.strokeStyle = "rgba(0,0,0,0.55)";
  ctx.strokeText(text, w / 2, h / 2);
  ctx.fillStyle = "#ffe082";
  ctx.fillText(text, w / 2, h / 2);
  ctx.restore();
}

export function drawGameOverOverlay(ctx: CanvasRenderingContext2D, w: number, h: number): void {
  ctx.fillStyle = "rgba(0, 0, 0, 0.7)";
  ctx.fillRect(0, 0, w, h);
}

/**
 * 每帧总入口：背景 → 选卡区/传送带 → 实体 → 特效 → 横幅 → 结束遮罩
 */
export function renderGame(ctx: CanvasRenderingContext2D, engine: GameEngine, cards: SelectItem[],
  selectedKey: string): void {
  drawBackground(ctx, engine.canvasW, engine.canvasH, engine.colCount,
    engine.cell, engine.gridLeft, engine.gridTop, engine.night);
  drawGroundFxs(ctx, engine.groundFxs, engine.cell);
  drawSunBoostCells(ctx, engine);   // 光能鼓舞：左右两格地块金+白轮廓（在植物之下）
  if (engine.conveyor) {
    drawConveyor(ctx, engine.conveyorItems, engine.conveyorSelected, cards, engine.canvasH);
  } else {
    drawTopSelector(ctx, engine.sun, cards, selectedKey, engine.cardCooldowns, engine.canvasH);
  }
  drawPlants(ctx, engine.plants, engine.night);
  drawZombies(ctx, engine.zombies);
  drawBullets(ctx, engine.bullets);
  drawSunDrops(ctx, engine.sunDrops);
  drawCoins(ctx, engine.coins);
  drawEffects(ctx, engine.effects);
  if (engine.startBannerTimer > 0 && !engine.gameOver) {
    drawStartBanner(ctx, engine.canvasW, engine.canvasH, engine.startBannerTimer);
  }
  // 波次预警（原版红字，用户要求字号加大）
  if (engine.wavePreviewTimer > 0 && !engine.gameOver) {
    ctx.save();
    ctx.font = "bold 54px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.lineWidth = 7;
    ctx.strokeStyle = "rgba(0,0,0,0.6)";
    const warnCx: number = engine.gridLeft + (engine.canvasW - engine.gridLeft) / 2;
    ctx.strokeText("一大波僵尸正在接近！", warnCx, engine.canvasH / 2);
    ctx.fillStyle = "#ff5252";
    ctx.fillText("一大波僵尸正在接近！", warnCx, engine.canvasH / 2);
    ctx.restore();
  }
  // 波次信息 + 下一波进度条（草坪区域顶部居中，避开左侧卡片区）：攒怪进度 / 大波预警倒计时
  if (!engine.gameOver && !engine.victory) {
    const playCx: number = engine.gridLeft + (engine.canvasW - engine.gridLeft) / 2;
    drawText(ctx, `${engine.levelId}　第${engine.wave}/${engine.totalWaves}波`,
      playCx, 26, 22, "#ffe082");
    const barW: number = 240;
    const barH: number = 10;
    const bx: number = playCx - barW / 2;
    const by: number = 42;
    let ratio: number;
    let label: string;
    if (engine.pendingBigWave) {
      // 预警期：进度条按倒计时填满，变红闪烁提示大波即将进场
      ratio = 1 - engine.wavePreviewTimer / GAME_CONST.WAVE_PREVIEW_FRAMES;
      label = "大波来袭！";
    } else {
      // 常规期：本波已刷怪数 / 触发大波所需数量
      ratio = engine.spawnsThisWave / GAME_CONST.WAVE_EVERY_N;
      label = `下一波 ${Math.round(Math.min(1, ratio) * 100)}%`;
    }
    ratio = Math.max(0, Math.min(1, ratio));
    ctx.fillStyle = "rgba(255,255,255,0.18)";
    ctx.fillRect(bx, by, barW, barH);
    ctx.fillStyle = engine.pendingBigWave ? "#ff5252" : "#ffca28";
    ctx.fillRect(bx, by, barW * ratio, barH);
    ctx.strokeStyle = "rgba(0,0,0,0.5)";
    ctx.lineWidth = 1;
    ctx.strokeRect(bx, by, barW, barH);
    drawText(ctx, label, playCx, by + barH + 12, 14, "#e6ee9c");
  }
  // 小推车：待命（草坪左侧）/ 疾驰中（草坪上），画在实体之上
  drawMowers(ctx, engine);
  // 通关掉卡：最上层（最后一只僵尸掉落的新植物种子包）
  drawCardDrop(ctx, engine);
  if (engine.gameOver) {
    drawGameOverOverlay(ctx, engine.canvasW, engine.canvasH);
  }
}
