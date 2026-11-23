# pvz_simple · 植物大战僵尸简单版

![HarmonyOS](https://img.shields.io/badge/HarmonyOS-Next-0A59F7)
![ArkTS](https://img.shields.io/badge/ArkTS-5-lime)
![ArkUI](https://img.shields.io/badge/ArkUI-Canvas-34c759)
![TypeScript](https://img.shields.io/badge/TypeScript-3178c6)
![License](https://img.shields.io/badge/License-MIT-green)

基于 HarmonyOS ArkTS / ArkUI 的植物大战僵尸简化版，版本号 1.2.0。游戏画面用 Canvas 2D 逐帧绘制，逻辑、渲染、存档分离，不依赖第三方游戏引擎。

## 内容

- **20 个关卡**：1-1 ~ 1-10 白天关，2-1 ~ 2-10 夜晚关；1-9 通关后触发挑战信，解锁 1-10 传送带关。
- **植物**：白天有向日葵、豌豆射手、双发、寒冰射手、坚果墙、土豆雷、樱桃炸弹、食人花；夜晚增加小喷菇、阳光菇、胆小菇、大喷菇、魅惑菇、寒冰菇、毁灭菇。铲子不占卡槽。
- **僵尸**：普通、路障、铁桶、撑杆、橄榄球；夜晚增加读报、铁门、舞王与伴舞、黑橄榄、盗贼。另有精英强化和魅惑友军机制。
- **子弹**：豌豆、寒冰、孢子、火焰、石化、极寒、土豆炮弹。寒冰系可减速、冻结并附带冻伤；魅惑菇能让僵尸转为友军。
- **商店与强化**：僵尸掉落金币，可扩卡槽（6 → 9）、购买坚果包扎和小推车，另有一批两级强化（如阳光催化、炮击指南、孢子蔓延术、寒冰炼成术等）。
- **存档**：基于 `@ohos.data.preferences` 保存金币、卡槽、音量、关卡进度、挑战信、图鉴解锁状态和强化等级。
- **其他**：选卡页、植物图鉴（2-4 通关后解锁）、BGM 与音效、调试面板。

## 运行

用 DevEco Studio 打开项目根目录，等待依赖同步完成，选择模拟器或真机运行 `entry` 模块。

命令行构建需要先设置 `DEVECO_SDK_HOME`，并使用 DevEco Studio 自带的 node 与 hvigorw：

```bash
export DEVECO_SDK_HOME=<你的 HarmonyOS SDK 路径>
hvigorw assembleHap --no-daemon
```

## 结构

```
entry/src/main/ets/
├─ game/
│  ├─ GameTypes.ets      类型定义与数值配置
│  ├─ GameEngine.ets     游戏主循环与规则
│  ├─ GameRenderer.ets   Canvas 2D 绘制
│  ├─ CardFactory.ets    关卡植物卡生成
│  ├─ SaveData.ets       preferences 存档
│  ├─ BgmPlayer.ets      背景音乐
│  └─ SoundFx.ets        音效
└─ pages/
   ├─ StartPage.ets      主菜单、商店、设置、图鉴入口
   ├─ SelectPage.ets     选卡
   ├─ Index.ets          游戏主页面与结算
   └─ AlmanacView.ets    图鉴
```

`entry/src/main/resources/rawfile/` 存放音频资源，`base/media/` 存放图片资源。

## 说明

- 这是学习性质的简化实现，植物与僵尸的数值、关卡配置集中在 `GameTypes.ets`，方便调整。
- 素材仅用于本地学习演示。
