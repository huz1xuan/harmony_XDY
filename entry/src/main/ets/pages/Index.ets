import { ClassroomView, XDYClassroom } from '@xdy/classroom';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

const TEST_URL = '';
// 为空则进入学点云默认登录页面，填入有效 URL 则直接进入课堂，注意不能直接注释掉

const localStorage: LocalStorage = new LocalStorage();
localStorage.setOrCreate('classroomUrl', TEST_URL);

@Entry(localStorage)
@Component
struct Index {
  @State showEmbedded: boolean = false;
  @State urlInput: string = TEST_URL;

  aboutToAppear(): void {
    XDYClassroom.onLoaded(() => {
      promptAction.showToast({ message: '（XDYClassroom.onLoaded）课堂加载完成', duration: 2000 });
    });
    XDYClassroom.onClosed(() => {
      promptAction.showToast({ message: '（XDYClassroom.onClosed）课堂已退出', duration: 2000 });
    });
  }

  build() {
    if (this.showEmbedded) {
      // ===== 模式二：嵌入式（零文件零配置）=====
      Stack() {
        ClassroomView()

        Button('← 返回')
          .position({ x: 12, y: 12 })
          .zIndex(100)
          .backgroundColor('#66000000')
          .fontColor(Color.White)
          .borderRadius(8)
          .onClick(() => this.showEmbedded = false)
      }
      .width('100%')
      .height('100%')
    } else {
      // ===== 模式选择 =====
      Column({ space: 16 }) {
        Text('学点云课堂 SDK')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 40 })

        Text('课堂 URL')
          .fontSize(12)
          .fontColor('#999')

        TextInput({ text: this.urlInput })
          .width('85%')
          .height(40)
          .fontSize(12)
          .borderRadius(6)
          .onChange((value: string) => {
            this.urlInput = value;
            localStorage.setOrCreate('classroomUrl', value);
          })

        Button('Ability 模式（独立窗口 · 横屏全屏）')
          .width('85%')
          .height(48)
          .fontSize(15)
          .borderRadius(8)
          .onClick(() => {
            const ctx = getContext(this) as common.UIAbilityContext;
            XDYClassroom.launch(ctx, this.urlInput);
          })

        Button('嵌入式模式（页面内嵌 · 零文件零配置）')
          .width('85%')
          .height(48)
          .fontSize(15)
          .borderRadius(8)
          .backgroundColor('#E8F5E9')
          .fontColor('#2E7D32')
          .onClick(() => {
            localStorage.setOrCreate('classroomUrl', this.urlInput);
            this.showEmbedded = true;
          })

        Divider().width('85%').margin({ top: 8 })

        Text('Ability：1 文件 + 1 JSON  |  嵌入：纯依赖零配置')
          .fontSize(11)
          .fontColor('#CCC')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }
}
