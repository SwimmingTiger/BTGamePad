import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'MouseFeedback';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Ability onBackground');
  }
}
