import { ClassroomView } from './pages/ClassroomPage';

/**
 * Navigation 集成所需的 NavDestination 内容组件
 * 通过 NavPathStack 传递的 classroomUrl 参数创建课堂
 */
@Component
export struct ClassroomNavContent {
  @Prop url: string = '';
  private storage: LocalStorage = new LocalStorage();

  aboutToAppear(): void {
    this.storage.setOrCreate('classroomUrl', this.url);
  }

  build() {
    Stack() {
      ClassroomView()
    }
    .width('100%')
    .height('100%')
  }
}

/**
 * Navigation 路由 Builder，客户在 .navDestination() 中注册即可
 * 用法：.navDestination('xdy_classroom', wrapBuilder(classroomNavBuilder))
 */
@Builder
export function classroomNavBuilder(name: string, param: Object): void {
  ClassroomNavContent({ url: (param as Record<string, string>)?.classroomUrl ?? '' })
}
