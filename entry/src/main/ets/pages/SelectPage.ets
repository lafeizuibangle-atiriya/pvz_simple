/**
 * 选卡页面：解锁植物数 > 卡槽数 时，开始游戏前先选卡（同原版）
 * 1-10 传送带关不走本页
 */
import { router } from '@kit.ArkUI';
import { SelectItem } from '../game/GameTypes';
import { createCardsForLevel } from '../game/CardFactory';
import { getLevelConfig } from '../game/GameTypes';
import { SaveData } from '../game/SaveData';

interface SelectParams {
  level: string;
}

interface IndexParams {
  level: string;
  seeds: string[];
}

@Entry
@Component
struct SelectPage {
  @State levelId: string = '1-1';
  @State selected: string[] = [];
  private cards: SelectItem[] = [];

  aboutToAppear(): void {
    const params = router.getParams() as SelectParams;
    if (params && params.level) {
      this.levelId = params.level;
    }
    const cfg = getLevelConfig(this.levelId);
    if (cfg !== null) {
      this.cards = createCardsForLevel(cfg.unlocks, cfg.night);
    }
  }

  private toggle(key: string): void {
    const idx: number = this.selected.indexOf(key);
    if (idx >= 0) {
      this.selected.splice(idx, 1);
      return;
    }
    if (this.selected.length >= SaveData.slots) {
      return; // 卡槽已满
    }
    this.selected.push(key);
  }

  private confirm(): void {
    if (this.selected.length === 0) return;
    const p: IndexParams = { level: this.levelId, seeds: this.selected };
    router.replaceUrl({ url: 'pages/Index', params: p });
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#1C2F0B')

      Column() {
        Text('选择卡片')
          .fontSize(40)
          .fontWeight(FontWeight.Bold)
          .fontColor('#eaf5d8')
          .margin({ top: 28 })

        Text(`${this.levelId}　卡槽 ${this.selected.length}/${SaveData.slots}`)
          .fontSize(18)
          .fontColor('#9fc46f')
          .margin({ top: 8 })

        Text('铲子不占卡槽，游戏中固定显示在右上角')
          .fontSize(14)
          .fontColor('#6f8a4b')
          .margin({ top: 6 })

        // 植物卡网格
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(this.cards, (c: SelectItem) => {
            Column() {
              Text(c.label)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#ffffff')
              Text(c.cost > 0 ? `${c.cost} 阳光` : '免费')
                .fontSize(13)
                .fontColor('#f0f0f0')
                .margin({ top: 4 })
            }
            .width(92)
            .height(76)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(c.color)
            .borderRadius(10)
            .border({ width: 3, color: this.selected.indexOf(c.key) >= 0 ? '#ffd700' : 'rgba(0,0,0,0.25)' })
            .margin(8)
            .onClick(() => this.toggle(c.key))
          }, (c: SelectItem) => c.key)
        }
        .margin({ top: 20 })

        Blank()

        Row({ space: 16 }) {
          Button('返回')
            .width(120)
            .height(48)
            .fontSize(18)
            .backgroundColor('rgba(255,255,255,0.15)')
            .fontColor('#eaf5d8')
            .onClick(() => {
              router.back();
            })
          Button('开始游戏')
            .width(180)
            .height(48)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .backgroundColor(this.selected.length > 0 ? '#3d8b28' : '#555555')
            .fontColor('#ffffff')
            .borderRadius(24)
            .onClick(() => this.confirm())
        }
        .margin({ bottom: '8%' })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
}
