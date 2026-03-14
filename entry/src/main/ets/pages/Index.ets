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
interface PlayerViewInfo {
  vid: string; userId: number; userRole: string; userName: string;
  isPlaying: boolean; surfaceId: string; audioMuted: boolean; videoMuted: boolean;
  channelId: string; left: number; top: number; width: number; height: number;
  radius: number; visible: boolean; volumeBtn: number; zoomBtn: number;
}
interface JsMsgRoot { type: string; data: string; name: string; }
interface JoinChannelData {
  appId: string; domain: string; secretKey: string; sdkType: string;
  channelId: string; uid: number; channelMode: string; channelKey: string;
  videoProfile: string; videoDynamicSubscribe: boolean;
}
interface MemberListData { list: MemberInfo[]; }
interface ViewCellListData { list: ViewCellData[]; }
interface MuteData { uid: number; mute: boolean; }
interface PushStreamData { uid: number; video: boolean; audio: boolean; }
interface CancelStreamData { uid: number; }
interface VolumeData { volumeGain: number; }
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

// ===== 主页面组件 =====
@Entry
@Component
struct XdyClassPage {
  @State playerViews: PlayerViewInfo[] = [];

  private webviewCtrl: webview.WebviewController = new webview.WebviewController();
  private jsBridge: NativeBridge = new NativeBridge();
  private xControllers: Map<string, XComponentController> = new Map();
  private homeUrl: string = 'https://pclive.xuedianyun.com/xdyclass/';
  private channelId: string = '';
  private selfUid: number = -1;
  private joinChanneled: boolean = false;
  private isOut: boolean = false;
  private rtcEngine: XrtcEngine | null = null;
  private rtcHandler: XdyRtcHandler | null = null;
  private memberMap: Map<number, MemberInfo> = new Map();
  private rtcModelMap: Map<number, RtcModelInfo> = new Map();
  private screenMaxDim: number = 360;
  private videoDynamicSubscribe: boolean = false;
  // 本地统计累积
  private localAudioBytes: number = 0;
  private localVideoBytes: number = 0;
  private localStatsAudioReady: boolean = false;
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
      this.screenMaxDim = px2vp(Math.max(disp.width, disp.height));
    } catch (e) {
      this.screenMaxDim = 360;
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
        .onPermissionRequest((event) => {
          if (event && event.request) { event.request.grant(event.request.getAccessibleResource()); }
        })
        .backgroundColor(Color.Black)
      // 视频浮层（XComponent叠加在WebView上）
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(this.playerViews, (pv: PlayerViewInfo) => {
          if (pv.visible) {
            Stack({ alignContent: Alignment.TopStart }) {
              XComponent({
                id: 'xc_' + pv.vid,
                type: XComponentType.SURFACE,
                controller: this.getController(pv.vid)
              })
                .onLoad(() => { this.onSurfaceReady(pv.vid); })
                .width('100%')
                .height('100%')
                .backgroundColor(Color.Black)
              if (pv.userName.length > 0) {
                Text(pv.userName)
                  .fontSize(10)
                  .fontColor(Color.White)
                  .backgroundColor('#66000000')
                  .padding({ left: 4, right: 4 })
                  .position({ x: 2, y: 2 })
                  .zIndex(1)
              }
            }
            .position({ x: pv.left, y: pv.top })
            .width(pv.width)
            .height(pv.height)
            .borderRadius(pv.radius)
            .clip(true)
            .backgroundColor(Color.Black)
          }
        }, (pv: PlayerViewInfo) => pv.vid)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }

  // ===== JS Bridge 消息分发 =====
  onJs2Native(messageId: string, val: string): void {
    if (messageId !== 'nativeWebRtcAction') return;
    try {
      const jo = JSON.parse(val) as JsMsgRoot;
      const msgType: string = jo.type ?? '';
      const msgData: string = jo.data ?? '';
      const msgName: string = jo.name ?? '';
      const iMsgType: number = parseInt(msgType);
      if (iMsgType > 1004 && !this.joinChanneled && iMsgType < 1009) return;
      switch (msgType) {
        case '1000': this.handleLoadWebView(); break;
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
        default: break;
      }
    } catch (e) {
      console.error('[XDY] js2native err: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // 1000 WebView加载
  handleLoadWebView(): void {
    this.native2Js('2000', 0, '加载webview', '{"os":"harmony"}');
  }

  // 1001 用户视图布局
  handleUserView(data: string): void {
    try {
      const jo = JSON.parse(data) as ViewCellListData;
      const list: ViewCellData[] = jo.list ?? [];
      const maxDim: number = this.screenMaxDim;
      const newViews: PlayerViewInfo[] = [];
      for (const vc of list) {
        if (vc.userRole === 'showstage' || vc.userRole === 'invisible' || vc.userRole === 'zoom') {
          continue;
        }
        const pv: PlayerViewInfo = {
          vid: vc.id,
          userId: 0, userRole: vc.userRole, userName: '',
          isPlaying: false, surfaceId: '', audioMuted: false, videoMuted: false,
          channelId: '',
          left: Math.ceil(maxDim * vc.left * 0.01),
          top: Math.ceil(maxDim * vc.top * 0.01),
          width: Math.ceil(maxDim * vc.width * 0.01),
          height: Math.ceil(maxDim * vc.height * 0.01),
          radius: Math.ceil(maxDim * vc.radius * 0.01),
          visible: false, volumeBtn: vc.volumeBtn, zoomBtn: vc.zoomBtn,
        };
        newViews.push(pv);
      }
      this.playerViews = newViews;
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
      const _jo = JSON.parse(data) as LeaveChannelData;
    } catch (e) {
      console.warn('[XDY] handleLeaveChannel parse warn');
    }
    this.joinChanneled = false;
    this.handelWebLeaveChannel();
  }

  // 1005 推流
  handlePushStream(data: string): void {
    try {
      const jo = JSON.parse(data) as PushStreamData;
      this.pushStream(jo.uid, jo.video, jo.audio, this.channelId);
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
      this.playerViews = this.playerViews.map((pv: PlayerViewInfo) =>
      pv.userId === uid ? {
        vid: pv.vid,
        userId: pv.userId,
        userRole: pv.userRole,
        userName: pv.userName,
        isPlaying: pv.isPlaying,
        surfaceId: pv.surfaceId,
        audioMuted: pv.audioMuted,
        videoMuted: mute,
        channelId: pv.channelId,
        left: pv.left,
        top: pv.top,
        width: pv.width,
        height: pv.height,
        radius: pv.radius,
        visible: pv.visible,
        volumeBtn: pv.volumeBtn,
        zoomBtn: pv.zoomBtn
      } : pv);
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
      this.playerViews = this.playerViews.map((pv: PlayerViewInfo) =>
      pv.userId === uid ? {
        vid: pv.vid,
        userId: pv.userId,
        userRole: pv.userRole,
        userName: pv.userName,
        isPlaying: pv.isPlaying,
        surfaceId: pv.surfaceId,
        audioMuted: mute,
        videoMuted: pv.videoMuted,
        channelId: pv.channelId,
        left: pv.left,
        top: pv.top,
        width: pv.width,
        height: pv.height,
        radius: pv.radius,
        visible: pv.visible,
        volumeBtn: pv.volumeBtn,
        zoomBtn: pv.zoomBtn
      } : pv);
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
    this.native2Js('2009', 0, '系统信息', '{"os":"harmony","platform":"HarmonyOS","volumeGain":100}');
  }

  // 1010 设备信息
  handleDeviceInfo(): void {
    this.native2Js('2010', 0, '设备信息', '{"os":"harmony","platform":"HarmonyOS"}');
  }

  // 1015 切换摄像头
  handleSwitchCamera(): void {
    if (!this.rtcEngine) return;
    const result: number = this.rtcEngine.switchCamera();
    this.native2Js('2015', result >= 0 ? 0 : 1, '切换摄像头', '{"label":"front"}');
  }

  // 1020 音量控制
  handleVolume(data: string): void {
    try {
      const jo = JSON.parse(data) as VolumeData;
      const vol: number = jo.volumeGain ?? 100;
      if (this.rtcEngine) { this.rtcEngine.adjustPlaybackVolume(vol); }
    } catch (e) {
      console.error('[XDY] handleVolume err: ' + (e instanceof Error ? e.message : String(e)));
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
      this.native2Js('2004', 0, '本地退出频道', '{"uid":' + this.selfUid + ',"action":"退出课堂"}');
    }
    this.reset();
  }

  // ===== 推流绑定视频 =====
  pushStream(uid: number, video: boolean, audio: boolean, channelId: string): PlayerViewInfo | null {
    const memberInfo = this.memberMap.get(uid);
    const userRole: string = memberInfo ? memberInfo.userRole : 'normal';
    const userName: string = memberInfo ? memberInfo.userName : '';
    let targetPv: PlayerViewInfo | null = null;

    if (uid === this.selfUid && this.rtcEngine) {
      this.rtcEngine.switchRole(RoleType.ANCHOR);
    }

    const newViews = this.playerViews.slice();
    for (let i = 0; i < newViews.length; i++) {
      const pv = newViews[i];
      if (pv.userRole !== userRole && userRole !== 'normal') continue;
      if (userRole === 'host' && pv.userRole !== 'host') continue;
      if (pv.isPlaying && pv.userId !== uid) continue;

      if (!pv.surfaceId) {
        // surfaceId尚未就绪，标记uid等待绑定
        newViews[i] = {
          vid: pv.vid, userRole: pv.userRole, userId: uid, userName: userName,
          isPlaying: pv.isPlaying, surfaceId: pv.surfaceId, audioMuted: pv.audioMuted,
          videoMuted: pv.videoMuted, channelId: channelId, left: pv.left, top: pv.top,
          width: pv.width, height: pv.height, radius: pv.radius, visible: true,
          volumeBtn: pv.volumeBtn, zoomBtn: pv.zoomBtn
        };
        this.playerViews = newViews;
        return newViews[i];
      }

      const surfaceId: string = pv.surfaceId;
      if (this.rtcEngine) {
        const up: UserParam = new UserParam(uid);
        if (uid === this.selfUid) {
          this.rtcEngine.enableLocalVideo(video);
          this.rtcEngine.setLocalVideo(surfaceId, true, RenderMode.RENDER_MODE_HIDDEN, up);
          this.rtcEngine.muteLocalVideoStream(!video);
          this.rtcEngine.muteLocalAudioStream(!audio);
          const setupCode: number = video ? 0 : -1;
          this.native2Js('2005', setupCode >= 0 ? 0 : 1, '推流开音视频',
            '{"uid":' + uid + ',"video":' + (video ? 'true' : 'false') +
              ',"audio":' + (audio ? 'true' : 'false') + ',"setupVideo":' + setupCode + '}');
        } else {
          this.rtcEngine.setRemoteVideo(surfaceId, true, RenderMode.RENDER_MODE_HIDDEN, up);
        }
      }
      newViews[i] = {
        vid: pv.vid, userRole: pv.userRole, userId: uid, userName: userName,
        isPlaying: true, surfaceId: pv.surfaceId, audioMuted: !audio,
        videoMuted: !video, channelId: channelId, left: pv.left, top: pv.top,
        width: pv.width, height: pv.height, radius: pv.radius, visible: true,
        volumeBtn: pv.volumeBtn, zoomBtn: pv.zoomBtn
      };
      targetPv = newViews[i];
      break;
    }
    this.playerViews = newViews;
    return targetPv;
  }

  // ===== 取消推流 =====
  cancelStream(uid: number, _channelId: string): void {
    const newViews = this.playerViews.map((pv: PlayerViewInfo) => {
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
        return {
          vid: pv.vid, userRole: pv.userRole, userId: 0, userName: '',
          isPlaying: false, surfaceId: pv.surfaceId, audioMuted: pv.audioMuted,
          videoMuted: pv.videoMuted, channelId: '', left: pv.left, top: pv.top,
          width: pv.width, height: pv.height, radius: pv.radius, visible: false,
          volumeBtn: pv.volumeBtn, zoomBtn: pv.zoomBtn
        };
      }
      return pv;
    });
    this.playerViews = newViews;
    const success: number = 0;
    this.native2Js('2008', success, '取消推流', '{"uid":' + uid + '}');
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
      this.pushStream(uidVal, true, true, this.channelId);
    } else {
      const m: RtcModelInfo = { uid: uidVal, audioMute: 0, videoMute: 0 };
      this.rtcModelMap.set(uidVal, m);
      this.pushStream(uidVal, true, true, this.channelId);
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
      this.pushStream(uidVal, model.videoMute === 0, true, this.channelId);
    } else {
      const m: RtcModelInfo = { uid: uidVal, audioMute: 0, videoMute: 1 };
      this.rtcModelMap.set(uidVal, m);
      this.pushStream(uidVal, false, true, this.channelId);
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
  getController(vid: string): XComponentController {
    if (!this.xControllers.has(vid)) {
      this.xControllers.set(vid, new XComponentController());
    }
    return this.xControllers.get(vid) as XComponentController;
  }

  onSurfaceReady(vid: string): void {
    const ctrl = this.xControllers.get(vid);
    if (!ctrl) return;
    const surfaceId: string = ctrl.getXComponentSurfaceId();
    // 找到对应 playerView 存储 surfaceId
    const idx = this.playerViews.findIndex((pv: PlayerViewInfo) => pv.vid === vid);
    if (idx < 0) return;
    const pv = this.playerViews[idx];
    const newViews = [...this.playerViews];
    newViews[idx] = {
      vid: pv.vid, userRole: pv.userRole, userId: pv.userId, userName: pv.userName,
      isPlaying: pv.isPlaying, surfaceId: surfaceId, audioMuted: pv.audioMuted,
      videoMuted: pv.videoMuted, channelId: pv.channelId, left: pv.left, top: pv.top,
      width: pv.width, height: pv.height, radius: pv.radius, visible: pv.visible,
      volumeBtn: pv.volumeBtn, zoomBtn: pv.zoomBtn
    };
    this.playerViews = newViews;
    // 若已有待绑定的uid，立即绑定视频
    if (pv.userId > 0 && this.rtcEngine) {
      const up: UserParam = new UserParam(pv.userId);
      if (pv.userId === this.selfUid) {
        this.rtcEngine.setLocalVideo(surfaceId, true, RenderMode.RENDER_MODE_HIDDEN, up);
      } else {
        this.rtcEngine.setRemoteVideo(surfaceId, true, RenderMode.RENDER_MODE_HIDDEN, up);
      }
      const newViews2 = [...this.playerViews];
      const src = newViews[idx];
      newViews2[idx] = {
        vid: src.vid, userRole: src.userRole, userId: src.userId, userName: src.userName,
        isPlaying: true, surfaceId: src.surfaceId, audioMuted: src.audioMuted,
        videoMuted: src.videoMuted, channelId: src.channelId, left: src.left, top: src.top,
        width: src.width, height: src.height, radius: src.radius, visible: true,
        volumeBtn: src.volumeBtn, zoomBtn: src.zoomBtn
      };
      this.playerViews = newViews2;
    }
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
    const updated: PlayerViewInfo[] = [];
    for (const pv of this.playerViews) {
      updated.push({
        vid: pv.vid, userRole: pv.userRole, userId: 0, userName: '',
        isPlaying: false, surfaceId: pv.surfaceId, audioMuted: false,
        videoMuted: false, channelId: '', left: pv.left, top: pv.top,
        width: pv.width, height: pv.height, radius: pv.radius, visible: false,
        volumeBtn: pv.volumeBtn, zoomBtn: pv.zoomBtn
      });
    }
    this.playerViews = updated;
  }
}
