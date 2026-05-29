import { common, Want } from '@kit.AbilityKit';

/**
 * 学点云课堂 SDK 入口类
 * 客户通过该类启动课堂
 */
export class XDYClassroom {
  /**
   * 启动课堂（新 UIAbility）
   * @param context - 调用方的 UIAbilityContext
   * @param url - 完整的课堂 H5 URL（含鉴权信息）
   * @param abilityName - 课堂 Ability 名称，默认 'XDYClassroomAbility'
   */
  static launch(context: common.UIAbilityContext, url: string, abilityName?: string): void {
    const want: Want = {
      bundleName: context.abilityInfo.bundleName,
      abilityName: abilityName ?? 'XDYClassroomAbility',
      parameters: {
        classroomUrl: url
      }
    };
    context.startAbility(want).then(() => {
      console.info('[XDY] 课堂启动成功');
    }).catch((err: Error) => {
      console.error('[XDY] 课堂启动失败: ' + err.message);
    });
  }
}
