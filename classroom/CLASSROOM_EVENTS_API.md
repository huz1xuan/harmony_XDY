# 课堂事件监听

```typescript
// XDYClassroom.ets

private static onLoadedCb?: () => void;
private static onClosedCb?: () => void;

static onLoaded(cb: () => void): void { XDYClassroom.onLoadedCb = cb; }
static onClosed(cb: () => void): void { XDYClassroom.onClosedCb = cb; }

// 触发：ClassroomPage.ets handleLoadWebView() 末尾
XDYClassroom.onLoadedCb?.();

// 触发：ClassroomPage.ets quit/handleLeaveChannel/onLoadIntercept 退出路径末尾
XDYClassroom.onClosedCb?.();
```

```typescript
// 客户使用
XDYClassroom.onLoaded(() => { /* 课堂加载完成 */ });
XDYClassroom.onClosed(() => { /* 课堂退出 */ });
XDYClassroom.launch(context, url);
```
