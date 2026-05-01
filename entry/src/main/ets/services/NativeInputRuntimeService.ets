import { hilog } from '@kit.PerformanceAnalysisKit';
import { nativeInputBridge } from './NativeInputBridge';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'NativeInputRuntime';
const DEFAULT_POLL_EVENT_COUNT = 32;
const DEFAULT_POLL_INTERVAL_MS = 16;

export type NativeInputRuntimeListener = (eventsJson: string) => void;

export class NativeInputRuntimeState {
  monitoringStarted: boolean = false;
  queuedEventCount: number = 0;
  lastErrorCode: number = 0;
}

export class NativeInputRuntimeService {
  private listener: NativeInputRuntimeListener | null = null;
  private pollIntervalId: number = -1;

  setListener(listener: NativeInputRuntimeListener | null): void {
    this.listener = listener;
  }

  start(): number {
    if (this.pollIntervalId >= 0) {
      return 0;
    }

    const result = nativeInputBridge.startMonitoring();
    if (result !== 0) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to start native input monitoring, error=%{public}d', result);
      return result;
    }

    this.pollIntervalId = setInterval(() => {
      this.flushPendingEvents();
    }, DEFAULT_POLL_INTERVAL_MS);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Native input runtime started version=%{public}s', nativeInputBridge.getVersion());
    return result;
  }

  stop(): number {
    if (this.pollIntervalId >= 0) {
      clearInterval(this.pollIntervalId);
      this.pollIntervalId = -1;
    }

    const result = nativeInputBridge.stopMonitoring();
    if (result !== 0) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to stop native input monitoring, error=%{public}d', result);
      return result;
    }

    hilog.info(LOG_DOMAIN, LOG_TAG, 'Native input runtime stopped');
    return result;
  }

  pollOnce(maxCount: number = DEFAULT_POLL_EVENT_COUNT): string {
    return nativeInputBridge.pollEventsJson(maxCount);
  }

  getConnectedGamepadsJson(): string {
    return nativeInputBridge.getConnectedGamepadsJson();
  }

  getState(): NativeInputRuntimeState {
    const state = new NativeInputRuntimeState();
    try {
      const rawState = JSON.parse(nativeInputBridge.getStateJson()) as Object;
      state.monitoringStarted = this.getBooleanField(rawState, 'monitoringStarted');
      state.queuedEventCount = this.getNumberField(rawState, 'queuedEventCount');
      state.lastErrorCode = this.getNumberField(rawState, 'lastErrorCode');
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to parse native input bridge state: %{public}s', JSON.stringify(error));
    }
    return state;
  }

  private flushPendingEvents(): void {
    const eventsJson = nativeInputBridge.pollEventsJson(DEFAULT_POLL_EVENT_COUNT);
    if (eventsJson === '[]') {
      return;
    }

    this.listener?.(eventsJson);
  }

  private getBooleanField(target: Object, key: string): boolean {
    const value = Reflect.get(target, key) as boolean | undefined;
    return typeof value === 'boolean' ? value : false;
  }

  private getNumberField(target: Object, key: string): number {
    const value = Reflect.get(target, key) as number | undefined;
    return typeof value === 'number' ? value : 0;
  }
}

export const nativeInputRuntimeService = new NativeInputRuntimeService();