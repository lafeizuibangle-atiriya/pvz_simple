/**
 * 背景音乐播放器：封装 @ohos.multimedia.media 的 AVPlayer 状态机
 *
 * 常见失败原因（也是大多数教程翻车的地方）：
 * 1. mp3 必须放在 entry/src/main/resources/rawfile/ 下
 * 2. rawfile 里的文件不能用普通路径，要用 resourceManager.getRawFd 拿到
 *    fd 描述符，再拼成 "fd://fd?offset=x&size=y" 给 AVPlayer
 * 3. AVPlayer 是状态机：设置 url 后要等 stateChange 到 'initialized'
 *    才能 prepare()，到 'prepared' 才能 play()，不能一上来就 play
 */
import media from '@ohos.multimedia.media';
import common from '@ohos.app.ability.common';
import resourceManager from '@ohos.resourceManager';
import { BusinessError } from '@ohos.base';

export class BgmPlayer {
  private player: media.AVPlayer | null = null;
  private volFactor: number = 0.6;          // 设置页音量 0~1（线性映射，0 = 静音）
  private mutedByUser: boolean = false;     // 用户归零导致的暂停（区别于切后台暂停）

  /**
   * 初始化并循环播放 rawfile 里的 bgm.mp3
   * 页面 aboutToAppear 里调用，不阻塞 UI（内部异步）
   */
  async init(context: common.Context): Promise<void> {
    if (this.player !== null) return;
    console.info('BGM: init 开始');
    try {
      const avPlayer: media.AVPlayer = await media.createAVPlayer();
      console.info('BGM: AVPlayer 创建成功');

      // 监听器必须在 fdSrc 赋值之前注册，否则会错过 initialized 回调
      avPlayer.on('stateChange', (state: string) => {
        console.info(`BGM: 状态切换 -> ${state}`);
        if (state === 'initialized') {
          avPlayer.prepare().catch((err: BusinessError) => {
            console.error(`BGM prepare failed: ${err.message}`);
          });
        } else if (state === 'prepared') {
          // loop 必须在 prepared 之后才能设置（idle/initialized 下会报 Operate Not Permit）
          avPlayer.loop = true;
          // setVolume 在本 SDK 为同步 void 方法（不是 Promise），直接调用
          if (this.volFactor <= 0) {
            // 进游戏时用户已把音量归零：直接不播
            this.mutedByUser = true;
          } else {
            avPlayer.setVolume(this.volFactor);
            avPlayer.play().then(() => {
              console.info('BGM: 开始播放');
            }).catch((err: BusinessError) => {
              console.error(`BGM play failed: ${err.message}`);
            });
          }
        }
      });

      avPlayer.on('error', (err: BusinessError) => {
        console.error(`BGM error: ${err.message}`);
      });

      // rawfile 文件用 fdSrc 属性（直接接收 fd+offset+size 三件套）
      // 注意：url 属性只接受纯数字的 fd://xxx，不支持 ?offset=&size= 参数形式
      const fd: resourceManager.RawFileDescriptor = await context.resourceManager.getRawFd('bgm.mp3');
      console.info(`BGM: getRawFd 成功 fd=${fd.fd} offset=${fd.offset} size=${fd.length}`);
      avPlayer.fdSrc = fd;

      this.player = avPlayer;
    } catch (err) {
      console.error(`BGM init failed: ${JSON.stringify(err)}`);
    }
  }

  /** 暂停（切后台时用） */
  pause(): void {
    if (this.player !== null) {
      this.player.pause().catch(() => {});
    }
  }

  /** 设置页调节 BGM 音量（0~1，线性映射）。归零 = 暂停播放（比 setVolume(0) 更彻底），调高则恢复 */
  setVolume(v: number): void {
    this.volFactor = Math.min(1.0, Math.max(0.0, v));
    if (this.player === null) return;
    if (this.volFactor <= 0) {
      // 归零：暂停播放，杜绝"音量为 0 却还有声音"的系统层差异
      this.mutedByUser = true;
      this.player.pause().catch(() => {});
    } else {
      this.player.setVolume(this.volFactor);
      if (this.mutedByUser) {
        this.mutedByUser = false;
        this.player.play().catch(() => {});
      }
    }
  }

  /** 恢复播放（切后台回来时用；用户归零静音期间不恢复） */
  resume(): void {
    if (this.player !== null && !this.mutedByUser) {
      this.player.play().catch(() => {});
    }
  }

  /** 停止并释放资源（页面销毁时必须调用，否则内存/音频泄漏） */
  stop(): void {
    const p = this.player;
    if (p !== null) {
      p.release().catch(() => {});
      this.player = null;
    }
  }
}
