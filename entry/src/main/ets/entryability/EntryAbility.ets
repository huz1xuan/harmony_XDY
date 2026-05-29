import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'XDYClassroom', 'EntryAbility onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'XDYClassroom', 'EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.getMainWindow((err, win) => {
      if (!err.code) {
        win.setPreferredOrientation(window.Orientation.LANDSCAPE);
        win.setWindowLayoutFullScreen(true);
        win.setWindowSystemBarEnable([]);
      }
    });
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'XDYClassroom', 'Failed to load page: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'XDYClassroom', 'Page loaded successfully');
    });
  }

  onForeground(): void {}
  onBackground(): void {}
}
