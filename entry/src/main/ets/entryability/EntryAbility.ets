import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { WindowUtils } from '../utils/WindowUtils';
import { PreferenceService } from '../service/PreferenceService';
import { AudioService } from '../service/AudioService';

const DOMAIN = 0x0000;
const TAG = 'ListenBook';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    PreferenceService.init(this.context).then(() => {
      this.restoreColorMode();
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'PreferenceService init failed: %{public}s', JSON.stringify(err));
    });
  }

  private async restoreColorMode(): Promise<void> {
    const mode = await PreferenceService.getColorMode();
    if (mode !== ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
      try {
        this.context.getApplicationContext().setColorMode(mode);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'Restore colorMode failed: %{public}s', JSON.stringify(err));
      }
    }
  }

  onDestroy(): void {
    AudioService.getInstance().release().catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'AudioService release failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    WindowUtils.setupImmersive(windowStage).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'Immersive setup failed: %{public}s', JSON.stringify(err));
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
    });
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
  }

  onBackground(): void {
  }
}
