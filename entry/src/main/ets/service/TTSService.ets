import { textToSpeech } from '@kit.CoreSpeechKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_TTS';

export interface TTSCallback {
  onStart?: () => void;
  onComplete?: () => void;
  onError?: (error: string) => void;
  onProgress?: (progress: number) => void;
}

export class TTSService {
  private static instance: TTSService | null = null;
  private ttsEngine: textToSpeech.TextToSpeechEngine | null = null;
  private currentText: string = '';
  private callback: TTSCallback | null = null;

  static getInstance(): TTSService {
    if (!TTSService.instance) {
      TTSService.instance = new TTSService();
    }
    return TTSService.instance;
  }

  async init(): Promise<void> {
    if (this.ttsEngine) return;

    try {
      const config: textToSpeech.CreateEngineParams = {
        language: 'zh-CN',
        person: 0,
        online: 1
      };
      this.ttsEngine = await textToSpeech.createEngine(config);
      hilog.info(DOMAIN, TAG, 'TTS engine created');
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'TTS init failed: %{public}s', error.message);
      throw error;
    }
  }

  async speak(text: string, callback?: TTSCallback): Promise<void> {
    if (!this.ttsEngine) {
      await this.init();
    }

    this.currentText = text;
    this.callback = callback || null;

    try {
      callback?.onStart?.();

      const params: textToSpeech.SpeakParams = {
        requestId: Date.now().toString(),
        extraParams: {}
      };

      await this.ttsEngine!.speak(text, params);
      hilog.info(DOMAIN, TAG, 'TTS speak started');

      callback?.onComplete?.();
    } catch (err) {
      const error = err as BusinessError;
      const msg = error.message || String(err);
      hilog.error(DOMAIN, TAG, 'TTS speak failed: %{public}s', msg);
      callback?.onError?.(msg);
    }
  }

  async stop(): Promise<void> {
    if (!this.ttsEngine) return;

    try {
      await this.ttsEngine.stop();
      hilog.info(DOMAIN, TAG, 'TTS stopped');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'TTS stop failed');
    }
  }

  async release(): Promise<void> {
    if (!this.ttsEngine) return;

    try {
      await this.ttsEngine.shutdown();
      this.ttsEngine = null;
      hilog.info(DOMAIN, TAG, 'TTS engine released');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'TTS release failed');
    }
  }
}
