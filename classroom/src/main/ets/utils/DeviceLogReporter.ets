import { deviceInfo, batteryInfo } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';
import { connection } from '@kit.NetworkKit';
import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { bundleManager } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';

// ===== 数据结构定义 =====
interface StaticInfo {
  deviceSysName: string;
  deviceSysVersion: string;
  deviceModelName: string;
  brand: string;
  deviceType: string;
  sdkApiVersion: number;
  totalRam: number;
  cpuCores: number;
  screenWidth: number;
  screenHeight: number;
  screenDensity: number;
  appVersion: string;
  appBuild: number;
}

interface DynamicInfo {
  batteryLevel: number;
  batteryStatus: number;
  networkType: string;
  memoryUsagePercent: number;
  isAppForeground: boolean;
}

interface LogEntry {
  timestamp: string;
  logType: string;
  platform: string;
  staticInfo?: StaticInfo;
  dynamicInfo?: DynamicInfo;
  eventType?: string;
}

interface CachedLogItem {
  timestamp: number;
  logJson: string;
}

const TAG = '[DeviceLogReporter]';
const PREF_NAME = 'device_log_reporter';
const PREF_STATIC_REPORTED = 'static_info_reported';
const PREF_CACHED_LOGS = 'cached_logs';
const MAX_CACHE_SIZE = 100;
const COLLECT_INTERVAL_MS = 30 * 1000;       // 30秒采集一次动态信息
const REPORT_INTERVAL_MS = 10 * 60 * 1000;   // 10分钟上报一次
const UPLOAD_URL = 'https://log.xuedianyun.com/h5/';

export class DeviceLogReporter {
  private static instance: DeviceLogReporter | null = null;
  private context: common.UIAbilityContext | null = null;
  private prefs: preferences.Preferences | null = null;
  private collectTimerId: number = -1;
  private reportTimerId: number = -1;
  private isRunning: boolean = false;
  private channelId: string = '';
  private uid: number = 0;
  private isAppForeground: boolean = true;
  private lastNetworkType: string = '';
  private lastBatteryLevel: number = 100;
  private dynamicBuffer: DynamicInfo[] = [];
  private netConn: connection.NetConnection | null = null;
  private cacheOpQueue: Promise<void> = Promise.resolve();

  private constructor() {}

  static getInstance(): DeviceLogReporter {
    if (!DeviceLogReporter.instance) {
      DeviceLogReporter.instance = new DeviceLogReporter();
    }
    return DeviceLogReporter.instance;
  }

  /**
   * 启动日志上报模块
   */
  async start(context: common.UIAbilityContext, channelId?: string, uid?: number): Promise<void> {
    if (this.isRunning) {
      return;
    }
    this.context = context;
    this.channelId = channelId ?? '';
    this.uid = uid ?? 0;
    this.isRunning = true;

    try {
      this.prefs = await preferences.getPreferences(context, PREF_NAME);
    } catch (e) {
      console.error(TAG + ' 初始化Preferences失败: ' + (e instanceof Error ? e.message : String(e)));
    }
    // 竞态保护：如果在 await 期间 stop() 已被调用，直接返回
    if (!this.isRunning) return;

    // 1. 静态信息首次上报
    await this.reportStaticInfoIfNeeded();
    // 竞态保护：如果在 await 期间 stop() 已被调用，直接返回
    if (!this.isRunning) return;

    // 2. 启动动态采集定时器 (30s)
    this.collectTimerId = setInterval(() => {
      this.collectDynamicInfo();
    }, COLLECT_INTERVAL_MS);

    // 3. 启动上报定时器 (10min)
    this.reportTimerId = setInterval(() => {
      this.flushDynamicLogs();
    }, REPORT_INTERVAL_MS);

    // 4. 注册网络状态监听
    this.registerNetworkListener();

    // 5. 首次采集
    this.collectDynamicInfo();

    console.info(TAG + ' 已启动');
  }

  /**
   * 停止日志上报模块
   */
  stop(): void {
    this.isRunning = false;
    if (this.collectTimerId !== -1) {
      clearInterval(this.collectTimerId);
      this.collectTimerId = -1;
    }
    if (this.reportTimerId !== -1) {
      clearInterval(this.reportTimerId);
      this.reportTimerId = -1;
    }
    if (this.netConn) {
      try {
        this.netConn.unregister(() => {});
      } catch (_e) {}
      this.netConn = null;
    }
    // 停止前 flush 一次
    this.flushDynamicLogs();
    console.info(TAG + ' 已停止');
  }

  /** 更新频道和用户信息 */
  updateSession(channelId: string, uid: number): void {
    const hadSession = this.channelId.length > 0 && this.uid > 0;
    this.channelId = channelId;
    this.uid = uid;
    // 首次获得会话时触发补报（对齐 Android DeviceMonitor.notifyUserLogin 行为）
    // 必须确保 prefs 已就绪，否则 start() 恢复后会自动重试
    if (!hadSession && channelId.length > 0 && uid > 0) {
      if (this.prefs !== null) {
        console.info(TAG + ' 首次获得会话(channelId=' + channelId + ', uid=' + uid + ')，触发补报');
        this.reportStaticInfoIfNeeded();
        this.retryCachedLogs();
      } else {
        console.info(TAG + ' 首次获得会话但 prefs 未就绪，等待 start() 完成后自动补报');
      }
    }
  }

  /** 通知前后台切换 */
  notifyForegroundState(isForeground: boolean): void {
    const changed = this.isAppForeground !== isForeground;
    this.isAppForeground = isForeground;
    if (changed) {
      this.reportEvent(isForeground ? 'app_foreground' : 'app_background');
    }
  }

  // ===== 静态信息 =====
  private async reportStaticInfoIfNeeded(): Promise<void> {
    try {
      if (this.prefs) {
        const reported = await this.prefs.get(PREF_STATIC_REPORTED, false);
        if (reported === true) {
          console.info(TAG + ' 静态信息已上报过，跳过');
          return;
        }
      }
      const staticInfo = this.collectStaticInfo();
      const ts = this.formatTimestamp(Date.now());
      const logEntry: LogEntry = {
        timestamp: ts,
        logType: 'device_info',
        platform: 'harmony',
        staticInfo: staticInfo
      };
      const logJson = JSON.stringify(logEntry);
      const success = await this.uploadLog(logJson, ts);
      if (success && this.prefs) {
        await this.prefs.put(PREF_STATIC_REPORTED, true);
        await this.prefs.flush();
        console.info(TAG + ' 静态信息上报成功并已标记');
      } else if (!success) {
        await this.cacheLog(logJson);
        console.warn(TAG + ' 静态信息上报失败，已写入缓存等待补报');
      }
    } catch (e) {
      console.error(TAG + ' 静态信息上报失败: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  private collectStaticInfo(): StaticInfo {
    let screenW = 0, screenH = 0, screenDensity = 0;
    try {
      const disp = display.getDefaultDisplaySync();
      screenW = disp.width;
      screenH = disp.height;
      screenDensity = disp.densityDPI;
    } catch (_e) {}

    let appVer = 'unknown', appBld = 0;
    try {
      const bi = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      appVer = 'v' + (bi.versionName ?? '1.0.0');
      appBld = bi.versionCode ?? 0;
    } catch (_e) {}

    return {
      deviceSysName: 'HarmonyOS',
      deviceSysVersion: deviceInfo.osFullName ?? 'unknown',
      deviceModelName: deviceInfo.productModel ?? 'unknown',
      brand: deviceInfo.brand ?? 'unknown',
      deviceType: deviceInfo.deviceType ?? 'unknown',
      sdkApiVersion: deviceInfo.sdkApiVersion ?? 0,
      totalRam: 0,   // HarmonyOS 无公开 API
      cpuCores: 0,   // HarmonyOS 无公开 API
      screenWidth: screenW,
      screenHeight: screenH,
      screenDensity: screenDensity,
      appVersion: appVer,
      appBuild: appBld
    };
  }

  // ===== 动态信息 =====
  private collectDynamicInfo(): void {
    try {
      const dynInfo = this.getDynamicSnapshot();
      this.dynamicBuffer.push(dynInfo);

      // 检查异常事件
      if (dynInfo.batteryLevel < 20 && this.lastBatteryLevel >= 20) {
        this.reportEvent('battery_low', dynInfo);
      }
      this.lastBatteryLevel = dynInfo.batteryLevel;

      if (this.lastNetworkType !== '' && dynInfo.networkType !== this.lastNetworkType) {
        this.reportEvent('network_changed', dynInfo);
      }
      this.lastNetworkType = dynInfo.networkType;
    } catch (e) {
      console.error(TAG + ' 动态采集失败: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  private getDynamicSnapshot(): DynamicInfo {
    let battery = 0, chargeStatus = 0;
    try {
      battery = batteryInfo.batterySOC;
      chargeStatus = batteryInfo.chargingStatus;
    } catch (_e) {}

    const netType = this.getNetworkTypeSync();

    let memPercent = 0;
    // HarmonyOS 暂无公开的内存使用API，使用默认值

    return {
      batteryLevel: battery,
      batteryStatus: chargeStatus,
      networkType: netType,
      memoryUsagePercent: memPercent,
      isAppForeground: this.isAppForeground
    };
  }

  private getNetworkTypeSync(): string {
    try {
      const hasNet = connection.hasDefaultNetSync();
      if (!hasNet) {
        return 'none';
      }
      const netHandle = connection.getDefaultNetSync();
      const caps = connection.getNetCapabilitiesSync(netHandle);
      if (caps && caps.bearerTypes) {
        if (caps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) {
          return 'wifi';
        } else if (caps.bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR)) {
          return 'cellular';
        } else if (caps.bearerTypes.includes(connection.NetBearType.BEARER_ETHERNET)) {
          return 'ethernet';
        }
      }
      return 'unknown';
    } catch (_e) {
      return 'unknown';
    }
  }

  private async flushDynamicLogs(): Promise<void> {
    if (this.dynamicBuffer.length === 0) {
      return;
    }
    const buffered = this.dynamicBuffer.slice();
    this.dynamicBuffer = [];

    // 取最后一条作为代表性快照上报
    const latest = buffered[buffered.length - 1];
    const ts = this.formatTimestamp(Date.now());
    const logEntry: LogEntry = {
      timestamp: ts,
      logType: 'device_info',
      platform: 'harmony',
      dynamicInfo: latest
    };
    const success = await this.uploadLog(JSON.stringify(logEntry), ts);
    if (!success) {
      await this.cacheLog(JSON.stringify(logEntry));
    }
  }

  // ===== 异常事件即时上报 =====
  private async reportEvent(eventType: string, dynInfo?: DynamicInfo): Promise<void> {
    try {
      const ts = this.formatTimestamp(Date.now());
      const logEntry: LogEntry = {
        timestamp: ts,
        logType: 'event',
        platform: 'harmony',
        dynamicInfo: dynInfo ?? this.getDynamicSnapshot(),
        eventType: eventType
      };
      const logJson = JSON.stringify(logEntry);
      const success = await this.uploadLog(logJson, ts);
      if (!success) {
        await this.cacheLog(logJson);
      }
      console.info(TAG + ' 事件上报: ' + eventType + ', 成功=' + success);
    } catch (e) {
      console.error(TAG + ' 事件上报异常: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // ===== 网络监听 =====
  private registerNetworkListener(): void {
    try {
      this.netConn = connection.createNetConnection();
      this.netConn.register(() => {});

      this.netConn.on('netAvailable', () => {
        console.info(TAG + ' 网络恢复，尝试补报缓存');
        this.retryCachedLogs();
      });

      this.netConn.on('netLost', () => {
        console.info(TAG + ' 网络断开');
      });
    } catch (e) {
      console.error(TAG + ' 注册网络监听失败: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // ===== 上报 =====
  private async uploadLog(logJson: string, originalTimestamp?: string): Promise<boolean> {
    // 守卫：未设置会话信息时跳过，保留缓存等待补报（对齐Android DeviceMonitor行为）
    if (this.uid <= 0 || this.channelId.length === 0) {
      console.info(TAG + ' 跳过上报: uid=' + this.uid + ', channelId=' + this.channelId + ' 未就绪，保留缓存');
      return false;
    }

    try {
      const nodeId = (deviceInfo.productModel ?? 'HarmonyOS').replace(/ /g, '_');

      // 手动构建 form-urlencoded body（不用 Object 避免 ArkTS 序列化差异）
      const body = 'classId=' + encodeURIComponent(this.channelId) +
        '&type=1' +
        '&userId=' + encodeURIComponent(this.uid.toString()) +
        '&nodeId=' + encodeURIComponent(nodeId) +
        '&data=' + encodeURIComponent(logJson) +
        (originalTimestamp ? '&timestamp=' + encodeURIComponent(originalTimestamp) : '');

      console.info(TAG + ' 开始上报: classId=' + this.channelId + ', userId=' + this.uid +
        ', data长度=' + logJson.length + ', body长度=' + body.length);

      const httpRequest = http.createHttp();
      const response = await httpRequest.request(UPLOAD_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'
        },
        extraData: body
      });

      const code = response.responseCode;
      let respBody = '';
      try {
        if (typeof response.result === 'string') {
          respBody = response.result as string;
        } else if (typeof response.result === 'object') {
          respBody = JSON.stringify(response.result);
        }
      } catch (_re) {
        respBody = '(无法读取响应体)';
      }

      httpRequest.destroy();

      if (code >= 200 && code < 300) {
        console.info(TAG + ' 上报成功: code=' + code + ', body=' + respBody);
        return true;
      }
      console.warn(TAG + ' 上报失败: code=' + code + ', body=' + respBody);
      return false;
    } catch (e) {
      // ArkTS BusinessError 不一定是 Error 子类，用括号记法安全取值
      const err = e as Record<string, Object>;
      const errCode = err['code'] ?? '?';
      const errMsg = err['message'] ?? '?';
      console.error(TAG + ' 上报网络异常: code=' + errCode + ', message=' + errMsg);
      return false;
    }
  }

  // ===== 离线缓存 =====
  private enqueueCacheOp(op: () => Promise<void>): void {
    this.cacheOpQueue = this.cacheOpQueue.then(op).catch((e: Error) => {
      console.error(TAG + ' cache op error: ' + (e instanceof Error ? e.message : String(e)));
    });
  }

  private async cacheLog(logJson: string): Promise<void> {
    return new Promise<void>((resolve) => {
      this.enqueueCacheOp(async () => {
        await this.doCacheLog(logJson);
        resolve();
      });
    });
  }

  private async doCacheLog(logJson: string): Promise<void> {
    if (!this.prefs) {
      console.error(TAG + ' Preferences未就绪，缓存失败（数据丢失!），logJson前100字符: ' +
        (logJson.length > 100 ? logJson.substring(0, 100) + '...' : logJson));
      return;
    }
    try {
      const raw = await this.prefs.get(PREF_CACHED_LOGS, '[]');
      let cached: CachedLogItem[] = JSON.parse(raw as string) as CachedLogItem[];
      cached.push({ timestamp: Date.now(), logJson: logJson });

      // 超过上限删除最旧的
      if (cached.length > MAX_CACHE_SIZE) {
        cached = cached.slice(cached.length - MAX_CACHE_SIZE);
      }
      await this.prefs.put(PREF_CACHED_LOGS, JSON.stringify(cached));
      await this.prefs.flush();
      console.info(TAG + ' 日志已缓存，当前缓存数: ' + cached.length);
    } catch (e) {
      console.error(TAG + ' 缓存日志失败: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  private async retryCachedLogs(): Promise<void> {
    this.enqueueCacheOp(async () => {
      await this.doRetryCachedLogs();
    });
  }

  private async doRetryCachedLogs(): Promise<void> {
    if (!this.prefs) {
      return;
    }
    try {
      const raw = await this.prefs.get(PREF_CACHED_LOGS, '[]');
      const cached: CachedLogItem[] = JSON.parse(raw as string) as CachedLogItem[];
      if (cached.length === 0) {
        return;
      }
      console.info(TAG + ' 开始补报缓存日志，共 ' + cached.length + ' 条');
      const failed: CachedLogItem[] = [];
      for (const item of cached) {
        const ok = await this.uploadLog(item.logJson);
        if (!ok) {
          failed.push(item);
        }
      }
      await this.prefs.put(PREF_CACHED_LOGS, JSON.stringify(failed));
      await this.prefs.flush();
      console.info(TAG + ' 补报完成，剩余失败: ' + failed.length);
    } catch (e) {
      console.error(TAG + ' 补报缓存失败: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // ===== 工具 =====
  private formatTimestamp(ms: number): string {
    const d = new Date(ms);
    const pad = (n: number): string => n < 10 ? '0' + n : n.toString();
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' +
      pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
  }
}
