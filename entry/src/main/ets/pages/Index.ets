import webview from '@ohos.web.webview';
import display from '@ohos.display';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import {
  XrtcEngine, IEngineEventHandler, UserParam, UserUUID, TipInfo,
  LocalAudioStats, RemoteAudioStats, LocalVideoStats, RemoteVideoStats,
  ConnStateType, RoleType, RenderMode, RtcType, InitParams,
  AudioScenarioType, VideoEncodeType
} from '@av/xrtc';

// ===== 数据接口定义 =====
interface ViewCellData {
  id: string; width: number; height: number; left: number; top: number;
  radius: number; userRole: string; volumeBtn: number; zoomBtn: number;
  openDrag: boolean; openZoomControl: boolean;
  videoAudioBtn: number; videoMuteBtn: number; audioMuteBtn: number;
}
interface MemberInfo {
  uid: number; userName: string; userRole: string;
  audioMuted: boolean; videoMuted: boolean;
}
interface RtcModelInfo { uid: number; audioMute: number; videoMute: number; }
@Observed
class PlayerViewInfo {
  vid: string = '';
  userId: number = 0;
  userRole: string = '';
  userName: string = '';
  isPlaying: boolean = false;
  surfaceId: string = '';
  audioMuted: boolean = false;
  videoMuted: boolean = false;
  channelId: string = '';
  left: number = 0;
  top: number = 0;
  width: number = 0;
  height: number = 0;
  radius: number = 0;
  visible: boolean = false;
  volumeBtn: number = 0;
  zoomBtn: number = 0;

  constructor(init?: Partial<PlayerViewInfo>) {
    if (init) {
      this.vid = init.vid ?? '';
      this.userId = init.userId ?? 0;
      this.userRole = init.userRole ?? '';
      this.userName = init.userName ?? '';
      this.isPlaying = init.isPlaying ?? false;
      this.surfaceId = init.surfaceId ?? '';
      this.audioMuted = init.audioMuted ?? false;
      this.videoMuted = init.videoMuted ?? false;
      this.channelId = init.channelId ?? '';
      this.left = init.left ?? 0;
      this.top = init.top ?? 0;
      this.width = init.width ?? 0;
      this.height = init.height ?? 0;
      this.radius = init.radius ?? 0;
      this.visible = init.visible ?? false;
      this.volumeBtn = init.volumeBtn ?? 0;
      this.zoomBtn = init.zoomBtn ?? 0;
    }
  }
}
interface JsMsgRoot { type?: Object; data?: Object; name?: Object; }
interface JoinChannelData {
  appId: string; domain: string; secretKey: string; sdkType: string;
  channelId: string; uid: number; channelMode: string; channelKey: string;
  videoProfile: string; videoDynamicSubscribe: boolean;
}
interface MemberListData { list: MemberInfo[]; }
interface ViewCellListData { list: ViewCellData[]; }
interface MuteData { uid: number; mute: boolean; }
interface PushStreamData { uid: number; video: boolean; audio: boolean; userRole?: string; userName?: string; }
interface CancelStreamData { uid: number; }
interface VolumeData { value?: number; openVolumeGain?: boolean; }
interface LeaveChannelData { uid: number; channelId: string; action: string; }
interface LocalStatsObj {
  uid: number; audiosentSampleRate: number; audioSendBytesNow: number;
  audioSendBytes: number; videoSendResolutionWidth: number;
  videoSendResolutionHeight: number; videoSendFrameRate: number;
  videoSendBytesNow: number; videoSendBytes: number;
}
interface RemoteStatsObj {
  uid: number; endToEndDelay: number; audioTotalActiveTime: number;
  audioReceivePacketsLost: number; audioReceiveBytesNow: number; audioReceiveBytes: number;
  videoReceiveResolutionWidth: number; videoReceiveResolutionHeight: number;
  videoReceiveDecodeFrameRate: number; videoReceiveBytesNow: number; videoReceiveBytes: number;
  isAudio: boolean; isVideo: boolean;
}

// ===== 视频分辨率映射 =====
function getVideoConfig(profile: string): VideoEncodeType {
  const map: Record<string, VideoEncodeType> = {
    '120p': VideoEncodeType.VIDEO_ENCODE_120P, '180p': VideoEncodeType.VIDEO_ENCODE_180P,
    '240p': VideoEncodeType.VIDEO_ENCODE_240P, '360p': VideoEncodeType.VIDEO_ENCODE_360P,
    '480p': VideoEncodeType.VIDEO_ENCODE_480P, '720p': VideoEncodeType.VIDEO_ENCODE_720P,
    '1080p': VideoEncodeType.VIDEO_ENCODE_1080,
    '360p_7': VideoEncodeType.VIDEO_ENCODE_360P_7, '480p_4': VideoEncodeType.VIDEO_ENCODE_480P_4,
    '720p_3': VideoEncodeType.VIDEO_ENCODE_720P_3,
  };
  return map[profile] ?? VideoEncodeType.VIDEO_ENCODE_240P;
}

// ===== JS桥接对象（供WebView调用）=====
class NativeBridge {
  private handler: (msgId: string, val: string) => void = (_a: string, _b: string) => {};
  setHandler(h: (msgId: string, val: string) => void): void { this.handler = h; }
  _js2native(messageId: string, val: string): void { this.handler(messageId, val); }
}

// ===== InitParams 实现 =====
class ChannelInitParams extends InitParams {
  private _appId: string;
  private _rtcType: RtcType;
  private _domain: string;
  private _secretKey: string;
  constructor(appId: string, rtcType: RtcType, domain: string, secretKey: string) {
    super();
    this._appId = appId; this._rtcType = rtcType;
    this._domain = domain; this._secretKey = secretKey;
  }
  appId(): string { return this._appId; }
  rtcType(): RtcType { return this._rtcType; }
  domain(): string { return this._domain; }
  secretKey(): string { return this._secretKey; }
}

// ===== RTC 事件处理器 =====
class XdyRtcHandler implements IEngineEventHandler {
  private page: XdyClassPage;
  constructor(page: XdyClassPage) { this.page = page; }
  onWarning(warn: TipInfo): void { console.warn('[RTC] warn=' + warn.getCode()); }
  onError(error: TipInfo): void { this.page.handleRtcError(error); }
  onJoinChannelSuccess(channel: string, uid: UserUUID): void { this.page.handleJoinSuccess(channel, uid); }
  onLeaveChannel(): void { this.page.handleLeaveSuccess(); }
  onUserJoined(uid: UserUUID): void { this.page.handleUserJoined(uid); }
  onUserOffline(uid: UserUUID, reason: number): void { this.page.handleUserOffline(uid, reason); }
  onFirstRemoteAudioDecoded(uid: UserUUID): void { this.page.handleFirstRemoteAudio(uid); }
  onFirstRemoteVideoDecoded(uid: UserUUID): void { this.page.handleFirstRemoteVideo(uid); }
  onUserMuteAudio(uid: UserUUID, muted: boolean): void { this.page.handleUserMuteAudio(uid, muted); }
  onUserMuteVideo(uid: UserUUID, muted: boolean): void { this.page.handleUserMuteVideo(uid, muted); }
  onConnStateChange(state: ConnStateType): void { this.page.handleConnStateChange(state); }
  onAudioStats(l: LocalAudioStats | null, r: RemoteAudioStats | null): void { this.page.handleAudioStats(l, r); }
  onVideoStats(l: LocalVideoStats | null, r: RemoteVideoStats | null): void { this.page.handleVideoStats(l, r); }
}

@Component
struct VideoItemView {
  @ObjectLink pv: PlayerViewInfo;
  controller: XComponentController = new XComponentController();
  onSurfaceReady: (vid: string, surfaceId: string) => void = (_v: string, _s: string) => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      XComponent({
        id: 'xc_' + this.pv.vid,
        type: XComponentType.SURFACE,
        controller: this.controller
      })
        .onLoad(() => { 
          console.info('[XDY] XComponent onLoad fired for vid=' + this.pv.vid);
          this.onSurfaceReady(this.pv.vid, this.controller.getXComponentSurfaceId()); 
        })
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
      if (this.pv.visible && this.pv.userName.length > 0) {
        Text(this.pv.userName)
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor('#66000000')
          .padding({ left: 4, right: 4 })
          .position({ x: 2, y: 2 })
          .zIndex(1)
      }
    }
    .position({ x: this.pv.left, y: this.pv.top })
    .width(this.pv.width > 0 ? this.pv.width : 1)
    .height(this.pv.height > 0 ? this.pv.height : 1)
    .borderRadius(this.pv.radius)
    .clip(true)
    .backgroundColor(Color.Black)
    .opacity(this.pv.visible ? 1 : 0)
    .zIndex(this.pv.visible ? 10 : 0)
  }
}

// ===== 主页面组件 =====
@Entry
@Component
struct XdyClassPage {
  @State playerViews: PlayerViewInfo[] = [];

  private webviewCtrl: webview.WebviewController = new webview.WebviewController();
  private jsBridge: NativeBridge = new NativeBridge();
  private homeUrl: string = 'https://pclive.xuedianyun.com/xdyclass/?mobileWeb=true&appVersion=v5.5.5.20251226';
  private channelId: string = '';
  private selfUid: number = -1;
  private joinChanneled: boolean = false;
  private isOut: boolean = false;
  private rtcEngine: XrtcEngine | null = null;
  private rtcHandler: XdyRtcHandler | null = null;
  private memberMap: Map<number, MemberInfo> = new Map();
  private rtcModelMap: Map<number, RtcModelInfo> = new Map();
  private screenWidth: number = 640;
  private videoDynamicSubscribe: boolean = false;
  // 本地统计累积
  private localAudioBytes: number = 0;
  private localVideoBytes: number = 0;
  private localStatsAudioReady: boolean = false;
  private isExiting: boolean = false;
  private localStatsVideoReady: boolean = false;
  private localStats: LocalStatsObj = {
    uid: 0, audiosentSampleRate: 0, audioSendBytesNow: 0, audioSendBytes: 0,
    videoSendResolutionWidth: 0, videoSendResolutionHeight: 0,
    videoSendFrameRate: 0, videoSendBytesNow: 0, videoSendBytes: 0,
  };
  // 远端统计累积（按uid）
  private remoteStatsMap: Map<number, RemoteStatsObj> = new Map();

  aboutToAppear(): void {
    this.jsBridge.setHandler((msgId: string, val: string) => { this.onJs2Native(msgId, val); });
    try {
      const disp = display.getDefaultDisplaySync();
      this.screenWidth = px2vp(Math.max(disp.width, disp.height));
    } catch (e) {
      this.screenWidth = 640;
    }
    // 申请权限
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const atm = abilityAccessCtrl.createAtManager();
      atm.requestPermissionsFromUser(ctx, ['ohos.permission.CAMERA', 'ohos.permission.MICROPHONE'])
        .then(() => { console.info('[XDY] 权限申请完成'); })
        .catch((e: Error) => { console.warn('[XDY] 权限申请失败: ' + e.message); });
    } catch (e) {
      console.warn('[XDY] 权限申请异常');
    }
  }
  aboutToDisappear(): void {
    if (this.rtcEngine) {
      if (this.rtcHandler && this.rtcEngine) { this.rtcEngine.removeEventHandler(this.rtcHandler); }
      this.rtcEngine.leaveChannel();
      this.rtcEngine.destroy();
      this.rtcEngine = null;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // WebView 课堂内容层
      Web({ src: this.homeUrl, controller: this.webviewCtrl })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .javaScriptProxy({
          object: this.jsBridge,
          name: 'xdyAndroid',
          methodList: ['_js2native'],
          controller: this.webviewCtrl
        })
        .domStorageAccess(true)
        .fileAccess(true)
        .mixedMode(MixedMode.All)
        .overviewModeAccess(true)
        .metaViewport(true)
        .textZoomRatio(100)
        .textAutosizing(false)
        .zoomAccess(false)
        .mediaPlayGestureAccess(false)
        .cacheMode(CacheMode.None)
        .userAgent('Mozilla/5.0 (Linux; Android 10; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36 XdyAndroid/1.0')
        .onPermissionRequest((event) => {
          if (event && event.request) { event.request.grant(event.request.getAccessibleResource()); }
        })
        .onPageBegin(() => {
          // 尽早注入全局 js2native 函数，桥接到 xdyAndroid._js2native
          const script = 'if (typeof js2native === "undefined") { window.js2native = function(msgId, val) { if (window.xdyAndroid && window.xdyAndroid._js2native) { window.xdyAndroid._js2native(msgId, val); } }; }';
          this.webviewCtrl.runJavaScript(script).catch((_e: Error) => {});
        })
        .onLoadIntercept((event) => {
          if (!event) return false;
          const url: string = event.data.getRequestUrl();
          // 拦截管理后台跳转（H5退出时直接window.location.href，不经过type:1004消息）
          // Android 端通过 shouldOverrideUrlLoading 关闭 Activity，我们在此拦截并重定向到登录页
          if (url.indexOf('xdyui2.xuedianyun.com') >= 0) {
            console.info('[XDY] 拦截管理页跳转: ' + url);
            try {
              webview.WebCookieManager.clearAllCookiesSync();
              // 当前页面还在 pclive 域，可清除 pclive 的 localStorage
              this.webviewCtrl.runJavaScript('try{localStorage.clear();sessionStorage.clear();}catch(e){}')
                .then((_r: string) => {
                  try {
                    this.webviewCtrl.removeCache(true);
                    this.webviewCtrl.loadUrl(this.homeUrl);
                    console.info('[XDY] 已清除会话，重载登录页');
                  } catch (e2) {
                    console.warn('[XDY] loadUrl err: ' + String(e2));
                  }
                }).catch((_e: Error) => {
                  try { this.webviewCtrl.loadUrl(this.homeUrl); } catch (_e2) {}
                });
            } catch (e) {
              try { this.webviewCtrl.loadUrl(this.homeUrl); } catch (_e2) {}
            }
            return true; // 阻断跳转到管理页
          }
          return false;
        })
        .backgroundColor(Color.Black)
      // 视频浮层（XComponent叠加在WebView上）
      // 与安卓端一致：XComponent 始终保持配置尺寸（surfaceId 尺寸正确），通过 opacity=0 隐藏空闲槽位
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(this.playerViews, (pv: PlayerViewInfo) => {
          VideoItemView({
            pv: pv,
            onSurfaceReady: (vid: string, surfaceId: string) => { this.onSurfaceReady(vid, surfaceId); }
          })
        }, (pv: PlayerViewInfo) => pv.vid)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(10)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }

  // ===== JS Bridge 消息分发 =====
  onJs2Native(messageId: string, val: string): void {
    console.info('[XDY] onJs2Native: messageId=' + messageId + ', val=' + val);
    if (messageId !== 'nativeWebRtcAction') return;
    try {
      const jo = JSON.parse(val) as JsMsgRoot;
      const msgType: string = jo.type !== undefined && jo.type !== null ? String(jo.type) : '';
      const msgData: string = typeof jo.data === 'object' ? JSON.stringify(jo.data) : (jo.data !== undefined && jo.data !== null ? String(jo.data) : '');
      const msgName: string = jo.name !== undefined && jo.name !== null ? String(jo.name) : '';
      const iMsgType: number = parseInt(msgType);
      if (iMsgType > 1004 && !this.joinChanneled && iMsgType < 1009) return;
      switch (msgType) {
        case '1000': this.handleLoadWebView(msgData); break;
        case '1001': this.handleUserView(msgData); break;
        case '1002': this.handleUserList(msgData); break;
        case '1003': this.handleJoinChannel(msgData, msgName); break;
        case '1004': this.handleLeaveChannel(msgData); break;
        case '1005': this.handlePushStream(msgData); break;
        case '1006': this.handleMuteVideo(msgData); break;
        case '1007': this.handleMuteAudio(msgData); break;
        case '1008': this.handleCancelStream(msgData); break;
        case '1009': this.handleSysInfo(); break;
        case '1010': this.handleDeviceInfo(); break;
        case '1015': this.handleSwitchCamera(); break;
        case '1020': this.handleVolume(msgData); break;
        case '1051': this.handleWebDialog(msgData); break;
        case '1052': this.handleClassInfo(msgData); break;
        default: break;
      }
    } catch (e) {
      console.error('[XDY] js2native err: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // 1000 WebView加载
  handleLoadWebView(msgData: string): void {
    console.info('[XDY] handleLoadWebView: msgData=' + msgData);
    this.native2Js('2000', 0, '加载webview', '{"os":"android"}');
  }

  // 1001 用户视图布局
  handleUserView(data: string): void {
    try {
      const jo = JSON.parse(data) as ViewCellListData;
      const list: ViewCellData[] = jo.list ?? [];
      const sw: number = this.screenWidth;
      console.info('[XDY] handleUserView: screenWidthPx=' + sw + ', listCount=' + list.length);
      const views: PlayerViewInfo[] = [];
      for (const vc of list) {
        // 与Android端一致：创建所有类型的PlayerView，包括'showstage'、'invisible'、'zoom'
        // 使用与 Android 端一致的计算方式：maxWidth * percentage
        const leftPx: number = Math.ceil(sw * vc.left * 0.01);
        const topPx: number = Math.ceil(sw * vc.top * 0.01);
        const widthPx: number = Math.ceil(sw * vc.width * 0.01);
        const heightPx: number = Math.ceil(sw * vc.height * 0.01);
        const radiusPx: number = Math.ceil(sw * vc.radius * 0.01);

        const pv = new PlayerViewInfo();
        pv.vid = vc.id;
        pv.userId = 0;
        pv.userRole = vc.userRole;
        pv.userName = '';
        pv.isPlaying = false;
        pv.surfaceId = '';
        pv.audioMuted = false;
        pv.videoMuted = false;
        pv.channelId = '';
        pv.left = leftPx;
        pv.top = topPx;
        pv.width = widthPx;
        pv.height = heightPx;
        pv.radius = radiusPx;
        pv.visible = false;
        pv.volumeBtn = vc.volumeBtn;
        pv.zoomBtn = vc.zoomBtn;
        views.push(pv);
      }
      this.playerViews = views;
    } catch (e) {
      console.error('[XDY] handleUserView err: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // 1002 用户列表
  handleUserList(data: string): void {
    try {
      const jo = JSON.parse(data) as MemberListData;
      const list: MemberInfo[] = jo.list ?? [];
      for (const m of list) {
        this.memberMap.set(m.uid, m);
        
        // 如果有缓存的 rtcModel，说明首帧已到，但当时没有 memberInfo。现在有了，立即推流绑定。
        const rtcModel = this.rtcModelMap.get(m.uid);
        if (rtcModel && this.joinChanneled) {
          let found = false;
          for (const pv of this.playerViews) {
            if (pv.userId === m.uid) {
              found = true;
              break;
            }
          }
          if (!found) {
            const hasVideo = rtcModel.videoMute === 0;
            const hasAudio = rtcModel.audioMute === 0;
            if (hasVideo || hasAudio) {
              // 从 memberMap 获取 userRole 和 userName
              const userRole = m.userRole ?? 'normal';
              const userName = m.userName ?? '';
              this.pushStream(m.uid, hasVideo, hasAudio, this.channelId, userRole, userName);
            }
          }
        }
      }
    } catch (e) {
      console.error('[XDY] handleUserList err: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // 1003 加入频道
  handleJoinChannel(data: string, name: string): void {
    try {
      const jo = JSON.parse(data) as JoinChannelData;
      this.selfUid = jo.uid;
      
      // 增加上层回调（与 Android 保持完全一致）
      const joinData = '{"uid":' + this.selfUid + ',"type":"1003"}';
      const script = 'js2native("join",\'' + joinData + '\')';
      this.webviewCtrl.runJavaScript(script).catch((e: Error) => {});

      if (name === '加入频道') {
        this.doJoinChannel(jo.channelId, jo.uid, jo.appId, jo.domain, jo.secretKey,
          jo.sdkType, jo.channelMode, jo.channelKey, jo.videoProfile, jo.videoDynamicSubscribe);
      }
    } catch (e) {
      console.error('[XDY] handleJoinChannel err: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // 1004 离开频道
  handleLeaveChannel(data: string): void {
    try {
      const jo = JSON.parse(data) as LeaveChannelData;
      const action = jo.action ?? 'leave';
      const script = 'js2native("' + action + '",\'' + data + '\')';
      this.webviewCtrl.runJavaScript(script).catch(() => {});
    } catch (e) {
      console.warn('[XDY] handleLeaveChannel parse warn');
    }
    this.joinChanneled = false;
    this.isExiting = true;
    this.handelWebLeaveChannel();
    // 先通过 JS 清除 localStorage/sessionStorage（与 xdyclass 同域，可清除 session 状态）
    // 再清 cookie + cache + 重载登录页
    try {
      webview.WebCookieManager.clearAllCookiesSync();
      this.webviewCtrl.runJavaScript(
        'try{localStorage.clear();sessionStorage.clear();}catch(e){}'
      ).then((_r: string) => {
        try {
          this.webviewCtrl.removeCache(true);
          this.webviewCtrl.loadUrl(this.homeUrl);
          console.info('[XDY] 退出课堂，已清除 localStorage + cookie，重载登录页');
        } catch (e2) {
          console.warn('[XDY] loadUrl err: ' + (e2 instanceof Error ? e2.message : String(e2)));
        }
      }).catch((_e: Error) => {
        try {
          this.webviewCtrl.removeCache(true);
          this.webviewCtrl.loadUrl(this.homeUrl);
        } catch (e3) {}
      });
    } catch (e) {
      console.warn('[XDY] exit redirect err: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // 1005 推流
  handlePushStream(data: string): void {
    try {
      const jo = JSON.parse(data) as PushStreamData;
      // 优先使用消息中的 userRole，如果没有则从 memberMap 获取
      const userRole = jo.userRole || (this.memberMap.get(jo.uid)?.userRole ?? 'normal');
      console.info('[XDY] handlePushStream: uid=' + jo.uid + ', userRole=' + userRole + ', video=' + jo.video + ', audio=' + jo.audio);
      this.pushStream(jo.uid, jo.video, jo.audio, this.channelId, userRole, jo.userName);
    } catch (e) {
      console.error('[XDY] handlePushStream err: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // 1006 静音视频
  handleMuteVideo(data: string): void {
    try {
      const jo = JSON.parse(data) as MuteData;
      const uid: number = jo.uid; const mute: boolean = jo.mute;
      if (uid === this.selfUid && this.rtcEngine) {
        let success: number = -1;
        if (mute) {
          this.rtcEngine.muteLocalAudioStream(false);
          this.native2Js('2007', 0, '推流开关音频', '{"uid":' + uid + ',"mute":false}');
          success = this.rtcEngine.muteLocalVideoStream(true);
        } else {
          success = this.rtcEngine.muteLocalVideoStream(false);
        }
        this.native2Js('2006', success >= 0 ? 0 : 1, '推流开关视频', '{"uid":' + uid + ',"mute":' + (mute ? 'true' : 'false') + '}');
      }
      const mi = this.memberMap.get(uid);
      if (mi) { mi.videoMuted = mute; this.memberMap.set(uid, mi); }
      for (const pv of this.playerViews) {
        if (pv.userId === uid) {
          pv.videoMuted = mute;
        }
      }
    } catch (e) {
      console.error('[XDY] handleMuteVideo err: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // 1007 静音音频
  handleMuteAudio(data: string): void {
    try {
      const jo = JSON.parse(data) as MuteData;
      const uid: number = jo.uid; const mute: boolean = jo.mute;
      if (uid === this.selfUid && this.rtcEngine) {
        let success: number = -1;
        if (mute) {
          this.rtcEngine.muteLocalVideoStream(false);
          this.native2Js('2006', 0, '推流开关视频', '{"uid":' + uid + ',"mute":false}');
          success = this.rtcEngine.muteLocalAudioStream(true);
        } else {
          success = this.rtcEngine.muteLocalAudioStream(false);
        }
        this.native2Js('2007', success >= 0 ? 0 : 1, '推流开关音频', '{"uid":' + uid + ',"mute":' + (mute ? 'true' : 'false') + '}');
      }
      const mi = this.memberMap.get(uid);
      if (mi) { mi.audioMuted = mute; this.memberMap.set(uid, mi); }
      for (const pv of this.playerViews) {
        if (pv.userId === uid) {
          pv.audioMuted = mute;
        }
      }
    } catch (e) {
      console.error('[XDY] handleMuteAudio err: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // 1008 取消推流
  handleCancelStream(data: string): void {
    try {
      const jo = JSON.parse(data) as CancelStreamData;
      this.cancelStream(jo.uid, this.channelId);
    } catch (e) {
      console.error('[XDY] handleCancelStream err: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // 1009 系统信息
  handleSysInfo(): void {
    this.native2Js('2009', 0, '系统信息', '{"memoryUsage":100,"memory":2048,"volumeGain":0}');
  }

  // 1010 设备信息
  handleDeviceInfo(): void {
    try {
      const disp = display.getDefaultDisplaySync();
      const pw: number = disp.width;
      const ph: number = disp.height;
      // dpi 使用密度比率（Android 标准：densityDPI / 160），与 Android 端一致
      const dpiRatio: number = disp.densityDPI / 160;
      const mw: number = Math.max(pw, ph);
      const mh: number = Math.min(pw, ph);
      const info: string = '{"rtcSdk":{"agoraRtc":"4.3.2.17"},' +
        '"deviceSysName":"Android","deviceSysVersion":"10","deviceModelName":"HarmonyOS",' +
        '"deviceWidth":' + mw + ',"deviceWidth1":' + mw + ',"deviceWidth2":' + mw +
        ',"deviceWidth3":' + mw + ',"deviceWidth4":' + mw + ',"deviceWidth5":' + mw + ',' +
        '"deviceHeight":' + mh + ',"deviceHeight1":' + mh + ',"deviceHeight2":' + mh +
        ',"deviceHeight3":' + mh + ',"deviceHeight4":' + mh + ',"deviceHeight5":' + mh + ',' +
        '"dpi":' + dpiRatio + ',' +
        '"systemMaxVolume":7,"systemCurrentVolume":0,"musicMaxVolume":15,"musicCurrentVolume":2,' +
        '"appName":"学点云课堂","appVersion":"v1.0.0","sdkVersion":"v1.0.0","appBuild":1}';
      this.native2Js('2010', 0, '设备信息', info);
    } catch (e) {
      this.native2Js('2010', 0, '设备信息',
        '{"rtcSdk":{"agoraRtc":"4.3.2.17"},' +
        '"deviceSysName":"Android","deviceSysVersion":"10","deviceModelName":"HarmonyOS",' +
        '"deviceWidth":1280,"deviceWidth1":1280,"deviceWidth2":1280,"deviceWidth3":1280,"deviceWidth4":1280,"deviceWidth5":1280,' +
        '"deviceHeight":800,"deviceHeight1":800,"deviceHeight2":800,"deviceHeight3":800,"deviceHeight4":800,"deviceHeight5":800,' +
        '"dpi":2.5,' +
        '"systemMaxVolume":7,"systemCurrentVolume":0,"musicMaxVolume":15,"musicCurrentVolume":2,' +
        '"appName":"学点云课堂","appVersion":"v1.0.0","sdkVersion":"v1.0.0","appBuild":1}');
    }
  }

  // 1015 切换摄像头
  handleSwitchCamera(): void {
    if (!this.rtcEngine) return;
    const result: number = this.rtcEngine.switchCamera();
    this.native2Js('2015', result >= 0 ? 0 : 1, '切换摄像头', '{"label":"front"}');
  }

  // 1020 音量增益
  handleVolume(data: string): void {
    try {
      const jo = JSON.parse(data) as VolumeData;
      const value = jo.value ?? 0;
      if (this.rtcEngine) {
        let code = 0;
        if (value > 100) {
          code = this.rtcEngine.adjustPlaybackVolume(value);
          this.native2Js('2020', code, '开启声音增益', '{"uid":' + this.selfUid + '}');
        } else {
          code = this.rtcEngine.adjustPlaybackVolume(101);
          this.native2Js('2020', code, '关闭声音增益', '{"uid":' + this.selfUid + '}');
        }
      }
    } catch (e) {
      console.error('[XDY] handleVolume err');
    }
  }

  // 1051 web是否有弹窗
  handleWebDialog(msgData: string): void {
    const script = 'js2native("webDialog",\'' + msgData + '\')';
    this.webviewCtrl.runJavaScript(script).catch(() => {});
  }

  // 1052 课堂记录信息
  handleClassInfo(msgData: string): void {
    try {
      const jo = JSON.parse(msgData) as Record<string, string>;
      const action = jo['action'];
      if (action) {
        const script = 'js2native("' + action + '",\'' + msgData + '\')';
        this.webviewCtrl.runJavaScript(script).catch(() => {});
      }
    } catch (e) {
      console.warn('[XDY] handleClassInfo parse err');
    }
  }

  // 实际执行加入频道
  doJoinChannel(channelId: string, uid: number, appId: string, domain: string,
    secretKey: string, sdkType: string, channelMode: string,
    channelKey: string, videoProfile: string, dynSub: boolean): void {
    this.channelId = channelId;
    this.videoDynamicSubscribe = dynSub;
    let rtcType: RtcType = RtcType.Agora;
    if (sdkType === 'hrtc') { rtcType = RtcType.HRtc; }
    else if (sdkType === 'trtc') { rtcType = RtcType.TRtc; }
    else if (sdkType === 'yunxinrtc') { rtcType = RtcType.WRtc; }
    if (this.rtcEngine) {
      if (this.rtcHandler && this.rtcEngine) { this.rtcEngine.removeEventHandler(this.rtcHandler); }
      this.rtcEngine.destroy();
      this.rtcEngine = null;
    }
    // 必须在创建引擎前设置 Context
    try {
      const context = getContext(this) as common.UIAbilityContext;
      XrtcEngine.setContext(context);
      console.info('[XDY] XrtcEngine.setContext 成功');
    } catch (e) {
      console.error('[XDY] setContext 失败: ' + (e instanceof Error ? e.message : String(e)));
      return;
    }
    const params: ChannelInitParams = new ChannelInitParams(appId, rtcType, domain, secretKey);
    this.rtcEngine = XrtcEngine.createRtc(params);
    if (!this.rtcEngine) { console.error('[XDY] createRtc 失败'); return; }
    this.rtcHandler = new XdyRtcHandler(this);
    this.rtcEngine.addEventHandler(this.rtcHandler);
    let scenario: AudioScenarioType = AudioScenarioType.AUDIO_SCENARIO_DEFAULT;
    if (channelMode === 'GameStreaming') { scenario = AudioScenarioType.AUDIO_SCENARIO_MUSIC; }
    else if (channelMode === 'ChatRoom') { scenario = AudioScenarioType.AUDIO_SCENARIO_CHATROOM; }
    this.rtcEngine.setAudioProfileScenario(scenario);
    this.rtcEngine.configVideoEncoder(getVideoConfig(videoProfile));
    UserParam.getLocal().setUid(uid);
    const userParam: UserParam = new UserParam(uid);
    this.rtcEngine.joinChannel(userParam, channelKey, channelId);
  }

  // Native → JS 通知
  native2Js(type: string, code: number, name: string, dataJson: string): void {
    const msg: string = '{"type":"' + type + '","name":"' + name +
      '","code":' + code + ',"data":' + dataJson + '}';
    const escaped: string = msg.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
    const script: string = '_native2js("nativeWebRtcAction",\'' + escaped + '\')';
    try {
      this.webviewCtrl.runJavaScript(script)
        .then((_r: string) => {})
        .catch((e: Error) => { console.warn('[XDY] runJS catch: ' + e.message); });
    } catch (e) {
      console.error('[XDY] native2Js err: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // ===== 离开频道处理 =====
  handelWebLeaveChannel(): void {
    if (this.isOut) return;
    this.isOut = true;
    if (this.rtcEngine) {
      this.rtcEngine.muteLocalVideoStream(true);
      this.rtcEngine.muteLocalAudioStream(true);
      const pv = this.getPlayerViewByUid(this.selfUid);
      if (pv && pv.surfaceId) {
        const up: UserParam = new UserParam(this.selfUid);
        this.rtcEngine.setLocalVideo(pv.surfaceId, false, RenderMode.RENDER_MODE_HIDDEN, up);
      }
      if (this.rtcHandler && this.rtcEngine) {
        this.rtcEngine.removeEventHandler(this.rtcHandler);
      }
      this.rtcEngine.leaveChannel();
      this.rtcEngine.destroy();
      this.rtcEngine = null;
    }
    this.native2Js('2004', 0, '本地退出频道', '{"uid":' + this.selfUid + ',"action":"退出课堂"}');
    this.reset();
  }

  // ===== 推流绑定视频 =====
  pushStream(uid: number, video: boolean, audio: boolean, channelId: string, overrideRole?: string, overrideName?: string): PlayerViewInfo | null {
    const memberInfo = this.memberMap.get(uid);
    // 优先使用传入的角色和名称，其次使用 memberMap 中的
    const userRole: string = overrideRole ?? (memberInfo ? memberInfo.userRole : 'normal');
    const userName: string = overrideName ?? (memberInfo ? memberInfo.userName : '');
    let targetPv: PlayerViewInfo | null = null;

    if (uid === this.selfUid && this.rtcEngine) {
      this.rtcEngine.switchRole(RoleType.ANCHOR);
    }

    console.info('[XDY] pushStream: uid=' + uid + ', userRole=' + userRole + ', selfUid=' + this.selfUid + ', memberInfo=' + (memberInfo ? JSON.stringify(memberInfo) : 'null'));

    // 先检查是否已经绑定到某个视图
    for (const pv of this.playerViews) {
      if (pv.userId === uid && pv.surfaceId) {
        console.info('[XDY] pushStream: uid=' + uid + ' 已绑定到 vid=' + pv.vid);
        return pv;
      }
    }

    // 优先查找匹配角色的空闲视图
    // host -> host 视图
    // normal -> normal 视图（优先）或 showstage 视图
    // 注意：需要优先匹配 exact role，其次匹配兼容 role
    
    // 第一轮：优先找 exact match 的空闲视图
    for (let i = 0; i < this.playerViews.length; i++) {
      const pv = this.playerViews[i];
      console.info('[XDY] pushStream: checking vid=' + pv.vid + ', pv.userRole=' + pv.userRole + ', isPlaying=' + pv.isPlaying + ', userId=' + pv.userId + ', surfaceId=' + (pv.surfaceId ? 'yes' : 'no'));
      
      // 如果视图已被其他用户占用，跳过
      if (pv.isPlaying && pv.userId !== uid) continue;
      
      // 第一轮：只找 exact match
      if (pv.userRole !== userRole) continue;

      if (!pv.surfaceId) {
        // surfaceId尚未就绪，标记uid等待绑定
        pv.userId = uid;
        pv.userName = userName;
        pv.channelId = channelId;
        pv.visible = true;
        pv.isPlaying = true; // 标记为正在播放，等待surface就绪
        return pv;
      }

      const surfaceId: string = pv.surfaceId;
      if (this.rtcEngine) {
        const up: UserParam = new UserParam(uid);
        if (uid === this.selfUid) {
          this.rtcEngine.enableLocalVideo(video);
          this.rtcEngine.setLocalVideo(surfaceId, true, RenderMode.RENDER_MODE_HIDDEN, up);
          this.rtcEngine.muteLocalVideoStream(!video);
          this.rtcEngine.muteLocalAudioStream(!audio);
          const setupCode: number = 0; // 与Android一致，setLocalVideo始终成功返回0
          this.native2Js('2005', setupCode >= 0 ? 0 : 1, '推流开音视频',
            '{"uid":' + uid + ',"video":' + (video ? 'true' : 'false') +
              ',"audio":' + (audio ? 'true' : 'false') + ',"setupVideo":' + setupCode + '}');
        } else {
          this.rtcEngine.setRemoteVideo(surfaceId, true, RenderMode.RENDER_MODE_HIDDEN, up);
        }
      }
      pv.userId = uid;
      pv.userName = userName;
      pv.isPlaying = true;
      pv.audioMuted = !audio;
      pv.videoMuted = !video;
      pv.channelId = channelId;
      pv.visible = true;
      targetPv = pv;
      console.info('[XDY] pushStream: 绑定成功 uid=' + uid + ' -> vid=' + pv.vid + ', surfaceId=' + surfaceId);
      break;
    }
    
    // 第二轮：如果没有找到，找兼容的视图（normal 可以绑定到 showstage）
    if (!targetPv && userRole === 'normal') {
      console.info('[XDY] pushStream: 未找到 normal 视图，尝试绑定到 showstage 视图');
      for (let i = 0; i < this.playerViews.length; i++) {
        const pv = this.playerViews[i];
        
        // 如果视图已被其他用户占用，跳过
        if (pv.isPlaying && pv.userId !== uid) continue;
        
        // 第二轮：找兼容的 showstage 视图
        if (pv.userRole !== 'showstage') continue;

        if (!pv.surfaceId) {
          pv.userId = uid;
          pv.userName = userName;
          pv.channelId = channelId;
          pv.visible = true;
          pv.isPlaying = true; // 标记为正在播放，等待surface就绪
          return pv;
        }

        const surfaceId: string = pv.surfaceId;
        if (this.rtcEngine) {
          const up: UserParam = new UserParam(uid);
          if (uid === this.selfUid) {
            this.rtcEngine.enableLocalVideo(video);
            this.rtcEngine.setLocalVideo(surfaceId, true, RenderMode.RENDER_MODE_HIDDEN, up);
            this.rtcEngine.muteLocalVideoStream(!video);
            this.rtcEngine.muteLocalAudioStream(!audio);
            const setupCode: number = 0;
            this.native2Js('2005', setupCode >= 0 ? 0 : 1, '推流开音视频',
              '{"uid":' + uid + ',"video":' + (video ? 'true' : 'false') +
                ',"audio":' + (audio ? 'true' : 'false') + ',"setupVideo":' + setupCode + '}');
          } else {
            this.rtcEngine.setRemoteVideo(surfaceId, true, RenderMode.RENDER_MODE_HIDDEN, up);
          }
        }
        pv.userId = uid;
        pv.userName = userName;
        pv.isPlaying = true;
        pv.audioMuted = !audio;
        pv.videoMuted = !video;
        pv.channelId = channelId;
        pv.visible = true;
        targetPv = pv;
        console.info('[XDY] pushStream: 绑定成功 uid=' + uid + ' -> vid=' + pv.vid + ' (showstage兼容), surfaceId=' + surfaceId);
        break;
      }
    }
    if (!targetPv) {
      console.warn('[XDY] pushStream: 未找到合适视图 uid=' + uid + ', userRole=' + userRole);
    }
    return targetPv;
  }

  // ===== 取消推流 =====
  cancelStream(uid: number, _channelId: string): void {
    for (const pv of this.playerViews) {
      if (pv.userId === uid) {
        if (pv.surfaceId && this.rtcEngine) {
          const up: UserParam = new UserParam(uid);
          if (uid === this.selfUid) {
            this.rtcEngine.enableLocalVideo(false);
            this.rtcEngine.setLocalVideo(pv.surfaceId, false, RenderMode.RENDER_MODE_HIDDEN, up);
          } else {
            this.rtcEngine.setRemoteVideo(pv.surfaceId, false, RenderMode.RENDER_MODE_HIDDEN, up);
          }
        }
        pv.userId = 0;
        pv.userName = '';
        pv.isPlaying = false;
        pv.channelId = '';
        pv.visible = false;
      }
    }
    
    if (uid === this.selfUid) {
      if (this.rtcEngine) {
        this.rtcEngine.muteLocalAudioStream(true);
        this.rtcEngine.muteLocalVideoStream(true);
      }
      this.native2Js('2008', 0, '取消推流', '{"uid":' + uid + '}');
    }
  }

  // ===== RTC 事件回调（由 XdyRtcHandler 调用）=====
  handleJoinSuccess(channel: string, uid: UserUUID): void {
    this.joinChanneled = true;
    this.selfUid = uid.getUid();
    if (this.rtcEngine) {
      this.rtcEngine.setEnableSpeakerphone(true);
      this.rtcEngine.adjustPlaybackVolume(100);
    }
    const rtcTypeStr: string = String(XrtcEngine.getRtcType() ?? 'Agora');
    this.native2Js('2003', 0, '加入频道',
      '{"uid":' + this.selfUid + ',"rtcType":"' + rtcTypeStr + '"}');
    console.info('[XDY] 加入频道成功 channel=' + channel + ' uid=' + uid.getUid());
  }

  handleLeaveSuccess(): void {
    this.joinChanneled = false;
    this.cancelStream(this.selfUid, this.channelId);
    this.clearViews();
    this.native2Js('3003', 0, '本地已退出频道', '{"uid":' + this.selfUid + '}');
    this.reset();
    console.info('[XDY] 离开频道');
  }

  handleUserJoined(uid: UserUUID): void {
    console.info('[XDY] 远端用户加入 uid=' + uid.getUid());
  }

  handleUserOffline(uid: UserUUID, reason: number): void {
    const uidVal: number = uid.getUid();
    console.info('[XDY] 远端用户离线 uid=' + uidVal + ' reason=' + reason);
    if (uidVal === this.selfUid) return;
    const mi = this.memberMap.get(uidVal);
    if (mi) { mi.audioMuted = true; mi.videoMuted = true; this.memberMap.set(uidVal, mi); }
    this.rtcModelMap.delete(uidVal);
    this.native2Js('2004', 0, '远端退出频道', '{"uid":' + uidVal + '}');
    this.cancelStream(uidVal, this.channelId);
  }

  handleFirstRemoteVideo(uid: UserUUID): void {
    const uidVal: number = uid.getUid();
    if (uidVal === this.selfUid) return;
    console.info('[XDY] 远端首帧视频 uid=' + uidVal);
    let model = this.rtcModelMap.get(uidVal);
    const memberInfo = this.memberMap.get(uidVal);
    if (!memberInfo) {
      if (!model) {
        const m: RtcModelInfo = { uid: uidVal, audioMute: 0, videoMute: 0 };
        this.rtcModelMap.set(uidVal, m);
      } else {
        model.videoMute = 0; model.audioMute = 0;
      }
      return;
    }
    if (model) {
      model.videoMute = 0; model.audioMute = 0;
      const userRole = memberInfo.userRole ?? 'normal';
      const userName = memberInfo.userName ?? '';
      this.pushStream(uidVal, true, true, this.channelId, userRole, userName);
    } else {
      const m: RtcModelInfo = { uid: uidVal, audioMute: 0, videoMute: 0 };
      this.rtcModelMap.set(uidVal, m);
      const userRole = memberInfo.userRole ?? 'normal';
      const userName = memberInfo.userName ?? '';
      this.pushStream(uidVal, true, true, this.channelId, userRole, userName);
    }
  }

  handleFirstRemoteAudio(uid: UserUUID): void {
    const uidVal: number = uid.getUid();
    if (uidVal === this.selfUid) return;
    console.info('[XDY] 远端首帧音频 uid=' + uidVal);
    let model = this.rtcModelMap.get(uidVal);
    const memberInfo = this.memberMap.get(uidVal);
    if (!memberInfo) {
      if (!model) {
        const m: RtcModelInfo = { uid: uidVal, audioMute: 0, videoMute: 1 };
        this.rtcModelMap.set(uidVal, m);
      } else {
        model.audioMute = 0;
      }
      return;
    }
    if (model) {
      model.audioMute = 0;
      const userRole = memberInfo.userRole ?? 'normal';
      const userName = memberInfo.userName ?? '';
      this.pushStream(uidVal, model.videoMute === 0, true, this.channelId, userRole, userName);
    } else {
      const m: RtcModelInfo = { uid: uidVal, audioMute: 0, videoMute: 1 };
      this.rtcModelMap.set(uidVal, m);
      const userRole = memberInfo.userRole ?? 'normal';
      const userName = memberInfo.userName ?? '';
      this.pushStream(uidVal, false, true, this.channelId, userRole, userName);
    }
  }

  handleUserMuteAudio(uid: UserUUID, muted: boolean): void {
    const uidVal: number = uid.getUid();
    if (uidVal === this.selfUid) return;
    const model = this.rtcModelMap.get(uidVal);
    if (model) { model.audioMute = muted ? 1 : 0; }
    const mi = this.memberMap.get(uidVal);
    if (mi) { mi.audioMuted = muted; this.memberMap.set(uidVal, mi); }
  }

  handleUserMuteVideo(uid: UserUUID, muted: boolean): void {
    const uidVal: number = uid.getUid();
    if (uidVal === this.selfUid) return;
    const model = this.rtcModelMap.get(uidVal);
    if (model) { model.videoMute = muted ? 1 : 0; }
    const mi = this.memberMap.get(uidVal);
    if (mi) { mi.videoMuted = muted; this.memberMap.set(uidVal, mi); }
  }

  handleConnStateChange(state: ConnStateType): void {
    if (state === ConnStateType.DISCONNECTED) {
      this.native2Js('3003', 0, 'RTC断线', '{"message":"rtcEngine onConnectionLost"}');
    }
    console.info('[XDY] 连接状态变化: ' + state);
  }

  handleVideoStats(local: LocalVideoStats | null, remote: RemoteVideoStats | null): void {
    if (local) {
      this.localStats.videoSendResolutionWidth = local.getEncodedBitrate();
      this.localStats.videoSendResolutionHeight = local.getEncodedFrameHeight();
      this.localStats.videoSendFrameRate = local.getSentFrameRate();
      const now: number = local.getSentBitrate() * 2 / 8 * 1024;
      this.localVideoBytes += now;
      this.localStats.videoSendBytesNow = now;
      this.localStats.videoSendBytes = this.localVideoBytes;
      this.localStatsVideoReady = true;
      if (this.localStatsAudioReady) {
        this.localStatsAudioReady = false; this.localStatsVideoReady = false;
        this.localStats.uid = this.selfUid;
        this.native2Js('3001', 0, '推流视频数据', JSON.stringify(this.localStats));
      }
    }
    if (remote) {
      const rUid: number = remote.getUid();
      let rs = this.remoteStatsMap.get(rUid);
      if (!rs) {
        rs = {
          uid: rUid, endToEndDelay: 0, audioTotalActiveTime: 0,
          audioReceivePacketsLost: 0, audioReceiveBytesNow: 0, audioReceiveBytes: 0,
          videoReceiveResolutionWidth: 0, videoReceiveResolutionHeight: 0,
          videoReceiveDecodeFrameRate: 0, videoReceiveBytesNow: 0, videoReceiveBytes: 0,
          isAudio: false, isVideo: false,
        };
        this.remoteStatsMap.set(rUid, rs);
      }
      const vNow: number = remote.getReceivedBitrate() * 2 / 8 * 1024;
      rs.videoReceiveResolutionWidth = remote.getWidth();
      rs.videoReceiveResolutionHeight = remote.getHeight();
      rs.videoReceiveDecodeFrameRate = remote.getDecoderOutputFrameRate();
      rs.videoReceiveBytesNow = vNow;
      rs.videoReceiveBytes += vNow;
      rs.isVideo = true;
      if (rs.isAudio) {
        rs.isAudio = false; rs.isVideo = false;
        this.native2Js('3002', 0, '远端视频数据', JSON.stringify(rs));
      }
    }
  }

  handleAudioStats(local: LocalAudioStats | null, remote: RemoteAudioStats | null): void {
    if (local) {
      const now: number = local.getSentBitrate() * 2 / 8 * 1024;
      this.localAudioBytes += now;
      this.localStats.audiosentSampleRate = local.getSentSampleRate();
      this.localStats.audioSendBytesNow = now;
      this.localStats.audioSendBytes = this.localAudioBytes;
      this.localStatsAudioReady = true;
      if (this.localStatsVideoReady) {
        this.localStatsAudioReady = false; this.localStatsVideoReady = false;
        this.localStats.uid = this.selfUid;
        this.native2Js('3001', 0, '推流视频数据', JSON.stringify(this.localStats));
      }
    }
    if (remote) {
      const rUid: number = remote.getUid();
      let rs = this.remoteStatsMap.get(rUid);
      if (!rs) {
        rs = {
          uid: rUid, endToEndDelay: 0, audioTotalActiveTime: 0,
          audioReceivePacketsLost: 0, audioReceiveBytesNow: 0, audioReceiveBytes: 0,
          videoReceiveResolutionWidth: 0, videoReceiveResolutionHeight: 0,
          videoReceiveDecodeFrameRate: 0, videoReceiveBytesNow: 0, videoReceiveBytes: 0,
          isAudio: false, isVideo: false,
        };
        this.remoteStatsMap.set(rUid, rs);
      }
      const aNow: number = remote.getReceivedBitrate() * 2 / 8 * 1024;
      rs.endToEndDelay = remote.getNetworkTransportDelay();
      rs.audioTotalActiveTime = remote.getTotalActiveTime();
      rs.audioReceivePacketsLost = remote.getAudioLossRate();
      rs.audioReceiveBytesNow = aNow;
      rs.audioReceiveBytes += aNow;
      rs.isAudio = true;
      if (rs.isVideo) {
        rs.isAudio = false; rs.isVideo = false;
        this.native2Js('3002', 0, '远端视频数据', JSON.stringify(rs));
      }
    }
  }

  handleRtcError(error: TipInfo): void {
    this.native2Js('3003', 0, 'RTC错误',
      '{"uid":' + this.selfUid + ',"code":' + error.getCode() + ',"message":"rtcEngine onError"}');
    console.error('[XDY] RTC错误 code=' + error.getCode());
  }

  // ===== 辅助方法 =====
  onSurfaceReady(vid: string, surfaceId: string): void {
    console.info('[XDY] onSurfaceReady triggered for vid=' + vid + ', surfaceId=' + surfaceId);
    // 找到对应 playerView 存储 surfaceId
    const pv = this.playerViews.find((pv: PlayerViewInfo) => pv.vid === vid);
    if (!pv) return;
    
    pv.surfaceId = surfaceId;
    
    // 若已有待绑定的uid，立即绑定视频
    if (pv.userId > 0 && this.rtcEngine) {
      const up: UserParam = new UserParam(pv.userId);
      if (pv.userId === this.selfUid) {
        this.rtcEngine.setLocalVideo(surfaceId, true, RenderMode.RENDER_MODE_HIDDEN, up);
      } else {
        this.rtcEngine.setRemoteVideo(surfaceId, true, RenderMode.RENDER_MODE_HIDDEN, up);
      }
      pv.isPlaying = true;
      pv.visible = true;
    }
    console.info('[XDY] onSurfaceReady: 绑定视频完成 vid=' + vid + ', uid=' + pv.userId + ', surfaceId=' + surfaceId);
  }

  getPlayerViewByUid(uid: number): PlayerViewInfo | null {
    return this.playerViews.find((pv: PlayerViewInfo) => pv.userId === uid) ?? null;
  }

  reset(): void {
    this.isOut = false;
    this.joinChanneled = false;
    this.channelId = '';
    this.memberMap.clear();
    this.rtcModelMap.clear();
    this.remoteStatsMap.clear();
    this.localAudioBytes = 0;
    this.localVideoBytes = 0;
    this.localStatsAudioReady = false;
    this.localStatsVideoReady = false;
  }

  clearViews(): void {
    for (const pv of this.playerViews) {
      pv.userId = 0;
      pv.userName = '';
      pv.isPlaying = false;
      pv.audioMuted = false;
      pv.videoMuted = false;
      pv.channelId = '';
      pv.visible = false;
    }
  }
}
