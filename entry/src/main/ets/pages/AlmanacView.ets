/**
 * 图鉴组件（原版式 Almanac）：植物页 + 僵尸页，条目 = 色块图标 + 名称 + 描述。
 * 主页与游戏内结算页共用；按植物解锁顺序排列，僵尸按登场顺序排列。
 */
import { PLANT_INTRO, ZOMBIE_INTRO } from '../game/GameTypes';
import { getCardVisual } from '../game/CardFactory';

/** 植物条目顺序（对齐解锁顺序） */
const ALMANAC_PLANTS: string[] = [
  'shooter', 'sunflower', 'cherry', 'wall', 'potato', 'ice', 'chomer', 'double',
  'puff', 'sunshroom', 'scaredy', 'fume', 'hypno', 'ice_shroom', 'doom_shroom'
];

/** 僵尸条目顺序（对齐登场顺序：通用 → 快速系 → 夜晚专属 → 精英） */
const ALMANAC_ZOMBIES: string[] = [
  'normal', 'cone', 'bucket', 'thief', 'pole', 'football', 'dark_football',
  'newspaper', 'door', 'dancer', 'elite'
];

@Component
export struct AlmanacView {
  @State tab: string = 'plant';   // plant | zombie

  build() {
    Column({ space: 10 }) {
      // ===== 页签 =====
      Row({ space: 10 }) {
        Button('植物图鉴')
          .layoutWeight(1)
          .height(40)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .backgroundColor(this.tab === 'plant' ? '#7cb342' : 'rgba(255,255,255,0.15)')
          .fontColor(this.tab === 'plant' ? '#ffffff' : '#c5e1a5')
          .borderRadius(20)
          .onClick(() => {
            this.tab = 'plant';
          })
        Button('僵尸图鉴')
          .layoutWeight(1)
          .height(40)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .backgroundColor(this.tab === 'zombie' ? '#c62828' : 'rgba(255,255,255,0.15)')
          .fontColor(this.tab === 'zombie' ? '#ffffff' : '#ef9a9a')
          .borderRadius(20)
          .onClick(() => {
            this.tab = 'zombie';
          })
      }
      .width('100%')

      // ===== 条目列表 =====
      Scroll() {
        Column({ space: 8 }) {
          if (this.tab === 'plant') {
            ForEach(ALMANAC_PLANTS, (key: string) => {
              Row({ space: 12 }) {
                // 色块图标（同卡面颜色）
                Text(PLANT_INTRO[key] !== undefined ? PLANT_INTRO[key].name.charAt(0) : '?')
                  .width(46)
                  .height(46)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#ffffff')
                  .textAlign(TextAlign.Center)
                  .backgroundColor(getCardVisual(key).color)
                  .borderRadius(8)
                  .border({ width: 2, color: '#33691e' })
                Column({ space: 3 }) {
                  Text(PLANT_INTRO[key] !== undefined ? PLANT_INTRO[key].name : getCardVisual(key).label)
                    .fontSize(17)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#ffe082')
                  Text(PLANT_INTRO[key] !== undefined ? PLANT_INTRO[key].desc : '')
                    .fontSize(13)
                    .fontColor('#fff8e1')
                    .lineHeight(18)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding(10)
              .backgroundColor('rgba(0,0,0,0.28)')
              .borderRadius(10)
            }, (key: string) => `p_${key}`)
          } else {
            ForEach(ALMANAC_ZOMBIES, (key: string) => {
              Row({ space: 12 }) {
                Text(ZOMBIE_INTRO[key] !== undefined ? ZOMBIE_INTRO[key].name.charAt(0) : '?')
                  .width(46)
                  .height(46)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#ffffff')
                  .textAlign(TextAlign.Center)
                  .backgroundColor(ZOMBIE_INTRO[key] !== undefined ? ZOMBIE_INTRO[key].color : '#757575')
                  .borderRadius(8)
                  .border({ width: 2, color: 'rgba(0,0,0,0.4)' })
                Column({ space: 3 }) {
                  Text(ZOMBIE_INTRO[key] !== undefined ? ZOMBIE_INTRO[key].name : key)
                    .fontSize(17)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#ef9a9a')
                  Text(ZOMBIE_INTRO[key] !== undefined ? ZOMBIE_INTRO[key].desc : '')
                    .fontSize(13)
                    .fontColor('#fff8e1')
                    .lineHeight(18)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding(10)
              .backgroundColor('rgba(0,0,0,0.28)')
              .borderRadius(10)
            }, (key: string) => `z_${key}`)
          }
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}
