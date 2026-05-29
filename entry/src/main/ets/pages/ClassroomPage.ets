import { ClassroomView } from '@xdy/classroom';

const localStorage: LocalStorage = new LocalStorage();

@Entry(localStorage)
@Component
struct ClassroomPage {
  aboutToAppear(): void {
    // 从 Want 参数或 AppStorage 获取课堂 URL（解决跨 HAR Ability 的 LocalStorage 传递问题）
    const url = AppStorage.get<string>('xdy_classroom_url');
    if (url && url.length > 0) {
      localStorage.setOrCreate('classroomUrl', url);
    }
  }

  build() {
    Stack() {
      ClassroomView()
    }
    .width('100%')
    .height('100%')
  }
}
