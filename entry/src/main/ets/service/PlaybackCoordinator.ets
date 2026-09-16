/** 单一声音出口；不依赖具体播放服务，避免 Audio/TTS 循环依赖。 */
export class PlaybackCoordinator {
  static speechActive: boolean = false;
  static stopSpeech: (() => Promise<void>) | null = null;

  static async useAudio(): Promise<boolean> {
    if (PlaybackCoordinator.speechActive) {
      await PlaybackCoordinator.stopSpeech?.();
    }
    return !PlaybackCoordinator.speechActive;
  }
}
