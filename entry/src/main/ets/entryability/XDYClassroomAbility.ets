import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

export default class XDYClassroomAbility extends UIAbility {
  private storage = new LocalStorage();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'XDYClassroom', 'XDYClassroomAbility onCreate');
    const url = want.parameters?.classroomUrl as string ?? '';
    this.storage.setOrCreate('classroomUrl', url);
    hilog.info(DOMAIN, 'XDYClassroom', 'Classroom URL: %{public}s', url);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'XDYClassroom', 'XDYClassroomAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'XDYClassroom', 'onWindowStageCreate');
    windowStage.getMainWindow((err, win) => {
      if (!err.code) {
        win.setPreferredOrientation(window.Orientation.LANDSCAPE);
        win.setWindowLayoutFullScreen(true);
        win.setWindowSystemBarEnable([]);
      }
    });
    windowStage.loadContent('pages/Index', this.storage, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'XDYClassroom', 'Failed to load page: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'XDYClassroom', 'ClassroomPage loaded');
    });
  }

  onForeground(): void {}
  onBackground(): void {}
}
