import { ClassroomView } from '@xdy/classroom';

const localStorage: LocalStorage = new LocalStorage();

@Entry(localStorage)
@Component
struct Index {
  build() {
    Stack() {
      ClassroomView()
    }
    .width('100%')
    .height('100%')
  }
}
