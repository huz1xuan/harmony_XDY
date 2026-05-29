import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

/**
 * 学点云课堂 UIAbility 模板
 * 客户需要将此文件拷贝到自己的项目中，并在 module.json5 中注册
 */
export default class XDYClassroomAbility extends UIAbility {
  private storage = new LocalStorage();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'XDYClassroom', 'XDYClassroomAbility onCreate');
    // 从 Want 中取出课堂 URL，存入 LocalStorage 供页面读取
    const url = want.parameters?.classroomUrl as string ?? '';
    this.storage.setOrCreate('classroomUrl', url);
    hilog.info(DOMAIN, 'XDYClassroom', 'Classroom URL: %{public}s', url);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'XDYClassroom', 'XDYClassroomAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'XDYClassroom', 'XDYClassroomAbility onWindowStageCreate');

    // 配置横屏、全屏、隐藏状态栏
    windowStage.getMainWindow((err, win) => {
      if (!err.code) {
        win.setPreferredOrientation(window.Orientation.LANDSCAPE);
        win.setWindowLayoutFullScreen(true);
        win.setWindowSystemBarEnable([]);
      }
    });

    // 加载课堂页面，传入 LocalStorage
    windowStage.loadContent('pages/ClassroomPage', this.storage, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'XDYClassroom', 'Failed to load ClassroomPage: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'XDYClassroom', 'ClassroomPage loaded successfully');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'XDYClassroom', 'XDYClassroomAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'XDYClassroom', 'XDYClassroomAbility onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'XDYClassroom', 'XDYClassroomAbility onBackground');
  }
}
