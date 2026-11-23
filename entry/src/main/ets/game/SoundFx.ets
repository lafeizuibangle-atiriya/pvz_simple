/**
 * 音效播放器（SoundPool 版）
 *
 * 【音效文件来源】rawfile 里的 15 个 wav 来自原版音频（main.pak 提取的 Ogg Vorbis
 * 原件 / 网上流传的完整音效包，两者实测内容一致），用 ffmpeg 解码成干净 PCM。
 * 注意：游戏目录 cached/sounds/*.wav 不是可播放音频，只是 pak 数据的混淆副本
 * （逐字节 XOR 0xF7），直接当 PCM 播就是刺耳噪声。
 *
 * 【文件规格为什么要这样定】
 * - 单声道 44.1kHz 16bit：SoundPool 只播「解码后 ≤1MB」的资源，超出部分会被
 *   截断（立体声 44.1kHz 上限仅约 5.6 秒，hugewave 这类长音会被切尾）。
 *   转单声道后全部 <1MB，且体积减半、预加载内存减半。
 * - 开头静音已裁掉：原版 splat3 有 90ms、explosion 70ms、hugewave 100ms 的起音
 *   空白，这是「音效听起来慢半拍」的真实来源。现在起音都在 8ms 内。
 * - 电平：峰值 ≤70% 且向 -21dBFS 对齐（增益 = min(峰值上限/峰值, 目标响度/RMS)，
 *   数学上不可能削波）。削波会产生刺耳杂音，切勿把音效拉到 90% 满幅。
 *
 * 【兼容性说明——本 SDK 版本的接口实况，改代码前先看】
 * - PlayParameters 只有 loop / rate / priority，没有 leftVol/rightVol（编译会报错）
 * - pool.on 的事件枚举与文档版本不一致（'loadFinished'/'loadError' 会编译报错），
 *   所以这里不订阅事件：load() 成功返回 soundID 即标记就绪。
 *   音效都是玩家交互后才触发（距 init 至少数秒），解码早已完成，实际够用
 * - rendererFlags 必须为 0：1 表示低时延渲染器，但 ArkTS 接口不支持，传 1 会没声音
 * - createSoundPool 支持的 usage：UNKNOWN / MUSIC / MOVIE / AUDIOBOOK（混音模式，
 *   不会打断其他音频播放）。不要改成 GAME，那不是 SoundPool 的合法取值
 * - 音量可通过 PlayParameters.leftVolume/rightVolume 调节（本 SDK 实测支持），
 *   设置页滑条 0~1 线性映射，0 为完全静音
 */
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { resourceManager } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 全部音效清单：rawfile 下的同名 .wav（新增音效加进这个数组即可） */
const SFX_NAMES: string[] = [
  'plant', 'points', 'chomp', 'throw', 'splat3', 'shovel',
  'cherrybomb', 'explosion', 'potato_mine', 'polevault', 'finalwave',
  'hugewave', 'shieldhit', 'seedlift', 'readysetplant', 'bigchomp',
  'diamond', 'plastichit2', 'shieldhit2', 'coin'
];

export class SoundFxPlayer {
  /** 最大并发流数量：8 只僵尸同时啃食 + 多颗豌豆命中的重叠余量。
   *  太小会导致后续播放请求排队等待，表现就是「音效慢半拍」 */
  private static readonly MAX_STREAMS: number = 16;
  /** 同名音效的最小间隔（毫秒）：防止同一次点击被派发两次造成叠音 */
  private static readonly DEDUP_MS: number = 70;
  private pool: media.SoundPool | null = null;
  // 音效名 → soundID（load 成功后记录；未加载完成的播放调用直接跳过）
  private soundIds: Map<string, number> = new Map();
  // 节流表：音效名 → 上次播放时间戳（高频音效防刷屏）
  private lastPlayAt: Map<string, number> = new Map();
  // 调试辅助：每种音效只在第一次播放时打一条日志，确认 play 被调用
  private playedOnce: Set<string> = new Set();
  // 音量（0~1）：设置页滑条直接映射，0 = 完全静音（play 直接跳过）
  // 文件已做响度归一（峰值 70%），1.0 即为最大不失真音量
  private volumeFactor: number = 1.0;

  /** 页面 aboutToAppear 时调用一次：创建 SoundPool 并预加载全部音效 */
  async init(context: common.Context): Promise<void> {
    if (this.pool !== null) return;
    try {
      const renderInfo: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC, // 模拟器上验证过能出声的流
        rendererFlags: 0
      };
      const pool: media.SoundPool = await media.createSoundPool(SoundFxPlayer.MAX_STREAMS, renderInfo);
      this.pool = pool;

      const resMgr: resourceManager.ResourceManager = context.resourceManager;
      for (const name of SFX_NAMES) {
        try {
          const fd: resourceManager.RawFileDescriptor = resMgr.getRawFdSync(`${name}.wav`);
          const soundId: number = await pool.load(fd.fd, fd.offset, fd.length);
          this.soundIds.set(name, soundId);
          console.info(`SFX loaded: ${name} id=${soundId}`);
        } catch (err) {
          console.error(`SFX load failed: ${name} ${JSON.stringify(err)}`);
        }
      }
      console.info(`SFX init done: ${this.soundIds.size}/${SFX_NAMES.length} loaded`);
    } catch (err) {
      console.error(`SFX init failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 播放音效（未加载完成时静默跳过，不影响游戏逻辑）
   * @param throttleMs 最小播放间隔（0 = 不节流），间隔内的重复调用直接忽略
   */
  play(name: string, throttleMs: number = 0): void {
    // 静音开关：音量为 0 时不创建播放流（比 setVolume(0) 更彻底，杜绝"归零仍有声"）
    if (this.pool === null || this.volumeFactor <= 0) return;
    const now: number = Date.now();
    const last: number | undefined = this.lastPlayAt.get(name);
    const gap: number = last === undefined ? Number.MAX_SAFE_INTEGER : now - last;
    // 生效间隔 = max(调用方节流值, DEDUP_MS)
    // DEDUP_MS 用于消除"同一次点击被派发两次"导致的叠音（种植音效响两次）
    const limit: number = throttleMs > SoundFxPlayer.DEDUP_MS ? throttleMs : SoundFxPlayer.DEDUP_MS;
    if (gap < limit) {
      // 只有落在极短去重窗口内的重复才打日志（用来定位重复派发）
      if (gap < SoundFxPlayer.DEDUP_MS) {
        console.info(`SFX dedup ${name}: ignored repeat after ${gap}ms`);
      }
      return;
    }
    this.lastPlayAt.set(name, now);
    const soundId = this.soundIds.get(name);
    if (soundId === undefined) return;
    if (!this.playedOnce.has(name)) {
      this.playedOnce.add(name);
      console.info(`SFX first play: ${name}`);
    }
    // 本 SDK 的 PlayParameters 实测支持 leftVolume/rightVolume（0~1.0，双声道取左值）
    const vol: number = this.volumeFactor;
    const params: media.PlayParameters = { loop: 0, leftVolume: vol, rightVolume: vol }; // 0 = 只播一次
    this.pool.play(soundId, params).catch((err: BusinessError) => {
      console.error(`SFX ${name} play failed: ${err.message}`);
    });
  }

  /** 设置页调节音效音量（0~1，线性映射：0 静音，1 最大不失真） */
  setVolume(v: number): void {
    this.volumeFactor = Math.min(1.0, Math.max(0.0, v));
  }

  /** 页面销毁时调用：先卸载全部音效，再释放 SoundPool（顺序不能反） */
  async release(): Promise<void> {
    if (this.pool === null) return;
    const pool = this.pool;
    this.pool = null;
    const names: string[] = Array.from(this.soundIds.keys());
    for (const name of names) {
      const soundId = this.soundIds.get(name);
      if (soundId === undefined) continue;
      try {
        await pool.unload(soundId);
      } catch (err) {
        console.error(`SFX unload failed: ${name}`);
      }
    }
    this.soundIds.clear();
    this.playedOnce.clear();
    try {
      await pool.release();
      console.info('SFX released');
    } catch (err) {
      console.error(`SFX release failed: ${JSON.stringify(err)}`);
    }
  }
}
