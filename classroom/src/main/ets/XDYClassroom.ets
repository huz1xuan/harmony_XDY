import { common, Want } from '@kit.AbilityKit';

/**
 * 学点云课堂 SDK 入口类
 * 客户通过该类启动课堂
 */
export class XDYClassroom {
  /**
   * 启动课堂（新 UIAbility，独立窗口，横屏全屏）
   * @param context - 调用方的 UIAbilityContext
   * @param url - 完整的课堂 H5 URL（含鉴权信息）
   * @param abilityName - 课堂 Ability 名称，默认 'XDYClassroomAbility'
   */
  static launch(context: common.UIAbilityContext, url: string, abilityName?: string): void {
    // 通过 AppStorage 传递 URL，避免跨 HAR Ability 的 Want 参数序列化问题
    AppStorage.setOrCreate<string>('xdy_classroom_url', url);

    const want: Want = {
      bundleName: context.abilityInfo.bundleName,
      moduleName: context.abilityInfo.moduleName,
      abilityName: abilityName ?? 'XDYClassroomAbility',
    };
    context.startAbility(want).then(() => {
      console.info('[XDY] 课堂启动成功');
    }).catch((err: Error) => {
      console.error('[XDY] 课堂启动失败: ' + err.message);
    });
  }

  /**
   * 通过 Navigation 嵌入课堂（无独立窗口，嵌入客户页面流）
   * @param navPathStack - 客户 Navigation 的 NavPathStack
   * @param url - 完整的课堂 H5 URL（含鉴权信息）
   *
   * 前提：客户需在 Navigation 中注册路由：
   *   import { classroomNavBuilder } from '@xdy/classroom';
   *   Navigation(navStack) { ... }
   *     .navDestination('xdy_classroom', wrapBuilder(classroomNavBuilder))
   */
  static pushTo(navPathStack: object, url: string): void {
    try {
      (navPathStack as Record<string, Function>)['pushPathByName']?.('xdy_classroom', { classroomUrl: url }, false);
      console.info('[XDY] Navigation 课堂跳转成功');
    } catch (e) {
      console.error('[XDY] Navigation 课堂跳转失败: ' + (e as Error).message);
    }
  }
}
