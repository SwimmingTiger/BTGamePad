import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import type commonAbility from '@ohos.app.ability.common';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { access, common, connection, hid } from '@kit.ConnectivityKit';

const ABSOLUTE_TOUCH_REPORT_ID = 1;
const MOUSE_REPORT_ID = 2;
const ABSOLUTE_AXIS_MAX = 32767;
const BLUETOOTH_PERMISSION = 'ohos.permission.ACCESS_BLUETOOTH';
const UNKNOWN_RSSI = -127;
const CONNECT_VALIDATE_INTERVAL_MS = 600;
const CONNECT_VALIDATE_RETRY_COUNT = 10;
const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'AbsTouchHid';
const BUILD_MARKER = 'BTGAMEPAD_BUILD_20260501_1432';

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function toUnsignedByte(value: number): number {
  return value & 0xFF;
}

function toLittleEndianWord(value: number): number[] {
  const normalized = clamp(Math.round(value), 0, ABSOLUTE_AXIS_MAX);
  return [toUnsignedByte(normalized), toUnsignedByte(normalized >> 8)];
}

function toSignedLittleEndianWord(value: number): number[] {
  const normalized = clamp(Math.round(value), -ABSOLUTE_AXIS_MAX, ABSOLUTE_AXIS_MAX);
  const unsigned = normalized & 0xFFFF;
  return [toUnsignedByte(unsigned), toUnsignedByte(unsigned >> 8)];
}

function buildAbsoluteDigitizerDescriptor(): Uint8Array {
  return new Uint8Array([
    0x05, 0x0D,
    0x09, 0x04,
    0xA1, 0x01,
    0x85, ABSOLUTE_TOUCH_REPORT_ID,
    0x09, 0x22,
    0xA1, 0x02,
    0x09, 0x42,
    0x09, 0x32,
    0x15, 0x00,
    0x25, 0x01,
    0x75, 0x01,
    0x95, 0x02,
    0x81, 0x02,
    0x95, 0x06,
    0x81, 0x03,
    0x05, 0x01,
    0x09, 0x30,
    0x09, 0x31,
    0x16, 0x00, 0x00,
    0x26, 0xFF, 0x7F,
    0x75, 0x10,
    0x95, 0x02,
    0x81, 0x02,
    0xC0,
    0xC0,
  ]);
}

function buildMouseReportDescriptor(): Uint8Array {
  return new Uint8Array([
    0x05, 0x01,
    0x09, 0x02,
    0xA1, 0x01,
    0x85, MOUSE_REPORT_ID,
    0x09, 0x01,
    0xA1, 0x00,
    0x05, 0x09,
    0x19, 0x01,
    0x29, 0x03,
    0x15, 0x00,
    0x25, 0x01,
    0x75, 0x01,
    0x95, 0x03,
    0x81, 0x02,
    0x95, 0x01,
    0x75, 0x05,
    0x81, 0x03,
    0x05, 0x01,
    0x09, 0x30,
    0x09, 0x31,
    0x16, 0x01, 0x80,
    0x26, 0xFF, 0x7F,
    0x75, 0x10,
    0x95, 0x02,
    0x81, 0x06,
    0xC0,
    0xC0,
  ]);
}

function buildCombinedDescriptor(): Uint8Array {
  const digitizer = buildAbsoluteDigitizerDescriptor();
  const mouse = buildMouseReportDescriptor();
  const combined = new Uint8Array(digitizer.length + mouse.length);
  combined.set(digitizer, 0);
  combined.set(mouse, digitizer.length);
  return combined;
}

function formatBluetoothError(action: string, error: Object): string {
  const code = Reflect.get(error, 'code') as number | undefined;
  const message = Reflect.get(error, 'message') as string | undefined;

  if (code === 2903051) {
    return `${action} failed: another application already holds the HID device registration (2903051).`;
  }

  if (code === 2903050) {
    return `${action} failed: the app must stay in the foreground while registering HID (2903050).`;
  }

  if (code === 2903052) {
    return `${action} failed: HID device is not registered yet (2903052).`;
  }

  if (code === 2903053) {
    return `${action} failed: remote HID host is not connected yet (2903053).`;
  }

  if (code !== undefined) {
    return `${action} failed: ${message ?? 'bluetooth business error'} (${code}).`;
  }

  return `${action} failed: ${JSON.stringify(error)}`;
}

export class NormalizedStickInput {
  x: number;
  y: number;

  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

export class CalibrationConfig {
  centerX: number;
  centerY: number;
  radiusX: number;
  radiusY: number;
  deadzone: number;

  constructor(centerX: number, centerY: number, radiusX: number, radiusY: number, deadzone: number) {
    this.centerX = centerX;
    this.centerY = centerY;
    this.radiusX = radiusX;
    this.radiusY = radiusY;
    this.deadzone = deadzone;
  }
}

export class HidDebugState {
  registered: boolean = false;
  registering: boolean = false;
  connected: boolean = false;
  connecting: boolean = false;
  discovering: boolean = false;
  bluetoothEnabled: boolean = false;
  lastReportHex: string = '';
  descriptorHex: string = '';
  lastError: string = '';
  lastEvent: string = 'idle';
  lastConnectedDeviceId: string = '';
  connectingDeviceId: string = '';
  pairingDeviceId: string = '';
  pendingPinCode: string = '';

  clone(): HidDebugState {
    const copy = new HidDebugState();
    copy.registered = this.registered;
    copy.registering = this.registering;
    copy.connected = this.connected;
    copy.connecting = this.connecting;
    copy.discovering = this.discovering;
    copy.bluetoothEnabled = this.bluetoothEnabled;
    copy.lastReportHex = this.lastReportHex;
    copy.descriptorHex = this.descriptorHex;
    copy.lastError = this.lastError;
    copy.lastEvent = this.lastEvent;
    copy.lastConnectedDeviceId = this.lastConnectedDeviceId;
    copy.connectingDeviceId = this.connectingDeviceId;
    copy.pairingDeviceId = this.pairingDeviceId;
    copy.pendingPinCode = this.pendingPinCode;
    return copy;
  }
}

export class RemoteDeviceItem {
  deviceId: string;
  name: string;
  bondState: string;
  rssi: number;
  isPaired: boolean;
  isSelected: boolean;

  constructor(deviceId: string, name: string, bondState: string, rssi: number, isPaired: boolean, isSelected: boolean) {
    this.deviceId = deviceId;
    this.name = name;
    this.bondState = bondState;
    this.rssi = rssi;
    this.isPaired = isPaired;
    this.isSelected = isSelected;
  }
}

class TouchMapping {
  active: boolean;
  x: number;
  y: number;

  constructor(active: boolean, x: number, y: number) {
    this.active = active;
    this.x = x;
    this.y = y;
  }
}

type HidStateListener = (state: HidDebugState, devices: Array<RemoteDeviceItem>) => void;

export class AbsoluteTouchHidService {
  private debugState: HidDebugState = new HidDebugState();
  private pendingRemoteAddress: string = '';
  private registerTimeoutId: number = -1;
  private connectValidationTimeoutId: number = -1;
  private pendingConnectDeviceId: string = '';
  private discoveredDevices: Map<string, RemoteDeviceItem> = new Map<string, RemoteDeviceItem>();
  private atManager = abilityAccessCtrl.createAtManager();
  private hidProfile: hid.HidDeviceProfile | null = null;
  private stateListener: HidStateListener | null = null;
  private readonly discoveryListener = (results: Array<connection.DiscoveryResult>): void => {
    this.debugState.discovering = true;
    results.forEach((result: connection.DiscoveryResult) => {
      const current = this.discoveredDevices.get(result.deviceId);
      const isSelected = current?.isSelected ?? this.pendingRemoteAddress === result.deviceId;
      const item = new RemoteDeviceItem(
        result.deviceId,
        result.deviceName || current?.name || 'Unknown Device',
        current?.bondState || this.toBondStateLabel(this.getSafePairState(result.deviceId)),
        result.rssi,
        current?.isPaired || this.getSafePairState(result.deviceId) === connection.BondState.BOND_STATE_BONDED,
        isSelected
      );
      this.discoveredDevices.set(result.deviceId, item);
      hilog.info(
        LOG_DOMAIN,
        LOG_TAG,
        'discovery update name=%{public}s deviceId=%{public}s rssi=%{public}d paired=%{public}d',
        result.deviceName || 'Unknown Device',
        result.deviceId,
        result.rssi,
        item.isPaired ? 1 : 0
      );
    });
    this.debugState.lastEvent = `discovery update: ${results.length}`;
    this.notifyStateChanged();
  };
  private readonly bondListener = (event: connection.BondStateParam): void => {
    const current = this.discoveredDevices.get(event.deviceId);
    const item = new RemoteDeviceItem(
      event.deviceId,
      current?.name || this.getSafeRemoteName(event.deviceId),
      this.toBondStateLabel(event.state),
      current?.rssi ?? UNKNOWN_RSSI,
      event.state === connection.BondState.BOND_STATE_BONDED,
      current?.isSelected ?? this.pendingRemoteAddress === event.deviceId
    );
    this.discoveredDevices.set(event.deviceId, item);
    if (event.state === connection.BondState.BOND_STATE_BONDING) {
      this.debugState.pairingDeviceId = event.deviceId;
      this.debugState.lastError = '';
      this.debugState.lastEvent = `pairing: ${event.deviceId}`;
    } else if (event.state === connection.BondState.BOND_STATE_BONDED) {
      this.debugState.pairingDeviceId = '';
      this.debugState.lastError = '';
      this.debugState.lastEvent = `bonded: ${event.deviceId}`;
      if (this.pendingConnectDeviceId === event.deviceId) {
        this.connect(event.deviceId);
      }
    } else if (this.debugState.pairingDeviceId === event.deviceId) {
      this.debugState.pairingDeviceId = '';
      this.debugState.lastEvent = `bond state: ${event.deviceId} -> ${item.bondState}`;
    }
    this.notifyStateChanged();
  };
  private readonly pinListener = (event: connection.PinRequiredParam): void => {
    this.debugState.pendingPinCode = event.pinCode;
    this.debugState.lastEvent = `pin required: ${event.deviceId}`;
    this.notifyStateChanged();
  };

  constructor() {
    this.debugState.descriptorHex = this.toHex(buildCombinedDescriptor());
    this.debugState.lastEvent = 'combined descriptor prepared';
    this.debugState.bluetoothEnabled = this.getBluetoothEnabledSafe();
    hilog.info(LOG_DOMAIN, LOG_TAG, 'service initialized build marker=%{public}s', BUILD_MARKER);
    this.attachBluetoothListeners();
    this.initializeHidProfile();
    this.refreshPairedDevices();
    this.notifyStateChanged();
  }

  getState(): HidDebugState {
    return this.buildDerivedState();
  }

  setStateListener(listener: HidStateListener | null): void {
    this.stateListener = listener;
    this.notifyStateChanged();
  }

  async register(onStateChange?: (state: HidDebugState) => void): Promise<boolean> {
    if (this.hidProfile === null) {
      this.setError('HID device profile is unavailable on this device.');
      onStateChange?.(this.getState());
      return false;
    }

    return await new Promise<boolean>((resolve: (value: boolean) => void) => {
      let settled = false;
      const finish = (value: boolean): void => {
        if (settled) {
          return;
        }
        settled = true;
        onStateChange?.(this.getState());
        this.notifyStateChanged();
        resolve(value);
      };

      this.clearRegisterTimeout();
      this.debugState.registering = true;
      this.debugState.lastError = '';
      this.debugState.lastEvent = 'registering hid';
      onStateChange?.(this.getState());
      this.notifyStateChanged();

      this.registerTimeoutId = setTimeout(() => {
        this.registerTimeoutId = -1;
        if (!this.debugState.registering) {
          return;
        }
        this.debugState.registering = false;
        if (this.debugState.registered) {
          this.debugState.lastError = '';
          this.debugState.lastEvent = 'hid register callback timeout, keeping accepted state';
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'register callback timeout, keeping accepted HID registration state');
          finish(true);
          return;
        }
        this.setError('register hid failed: no callback or exception returned from the Bluetooth stack within 1500ms. Check hdc.log for system business errors such as 2903051.');
        finish(false);
      }, 1500);

      try {
        this.hidProfile?.registerHidDevice(this.buildSdp(), this.buildQos(), this.buildQos(), (registered: boolean) => {
          this.clearRegisterTimeout();
          this.debugState.registering = false;
          this.debugState.registered = registered;
          if (registered) {
            this.debugState.lastEvent = 'hid registered';
            hilog.info(LOG_DOMAIN, LOG_TAG, 'register callback confirmed hid registered');
          } else {
            this.setError('register hid rejected: the Bluetooth stack returned false without a business error detail.');
          }
          finish(registered);
        });
        this.debugState.registered = true;
        this.debugState.lastEvent = 'hid register request accepted';
        hilog.info(LOG_DOMAIN, LOG_TAG, 'register request accepted by SDK, waiting for register callback');
        onStateChange?.(this.getState());
        this.notifyStateChanged();
      } catch (error) {
        this.clearRegisterTimeout();
        this.debugState.registering = false;
        this.applyRegistrationStateFromError(error as Object);
        this.setError(formatBluetoothError('register hid', error as Object));
        finish(false);
      }
    });
  }

  async prepareForDeviceSelection(context: commonAbility.UIAbilityContext, onStateChange?: (state: HidDebugState) => void): Promise<boolean> {
    const granted = await this.ensureBluetoothPermission(context);
    onStateChange?.(this.getState());
    this.notifyStateChanged();
    if (!granted) {
      return false;
    }

    const prepared = await this.prepareDeviceSelectionAttempt(onStateChange);
    if (prepared) {
      return true;
    }

    const firstError = this.debugState.lastError || 'prepare device selection failed for an unknown reason.';
    this.debugState.lastEvent = 'prepare failed, retrying without disabling bluetooth';
    onStateChange?.(this.getState());
    this.notifyStateChanged();

    const retryReady = await this.recoverPreparationWithoutDisablingBluetooth(onStateChange);
    if (!retryReady) {
      if (this.debugState.lastError.length === 0) {
        this.setError(`prepare device selection failed, and retry preparation also failed. Initial error: ${firstError}`);
      } else {
        this.setError(`prepare device selection failed. Initial error: ${firstError} Retry error: ${this.debugState.lastError}`);
      }
      return false;
    }

    const recovered = await this.prepareDeviceSelectionAttempt(onStateChange);
    if (recovered) {
      this.debugState.lastError = '';
      this.debugState.lastEvent = 'device selection ready after retry';
      onStateChange?.(this.getState());
      this.notifyStateChanged();
      return true;
    }

    const retryError = this.debugState.lastError || 'retry failed for an unknown reason.';
    this.setError(`prepare device selection failed. Initial error: ${firstError} Retry error: ${retryError}`);
    return false;
  }

  unregister(): void {
    if (this.hidProfile === null) {
      return;
    }

    try {
      this.clearRegisterTimeout();
      this.cancelPendingConnectionState();
      this.debugState.registering = false;
      this.hidProfile.unregisterHidDevice();
      this.debugState.registered = false;
      this.debugState.connected = false;
      this.debugState.lastConnectedDeviceId = '';
      this.debugState.lastEvent = 'hid unregistered';
      this.notifyStateChanged();
    } catch (error) {
      this.setError(formatBluetoothError('unregister hid', error as Object));
    }
  }

  connect(deviceId: string): void {
    if (deviceId.trim().length === 0) {
      this.setError('Remote host address is required before connect.');
      return;
    }

    this.pendingRemoteAddress = deviceId;
    if (this.hidProfile === null) {
      this.setError('HID device profile is unavailable on this device.');
      return;
    }

    try {
      const addressType = this.getAddressType(deviceId);
      hilog.info(
        LOG_DOMAIN,
        LOG_TAG,
        'connect requested to %{public}s addressType=%{public}d',
        deviceId,
        addressType
      );
      this.clearConnectValidation();
      this.pendingConnectDeviceId = deviceId;
      this.debugState.connecting = true;
      this.debugState.connectingDeviceId = deviceId;
      this.debugState.connected = false;
      this.debugState.lastConnectedDeviceId = '';
      this.debugState.lastError = '';
      this.hidProfile.connect({
        address: deviceId,
        addressType,
      });
      this.debugState.lastEvent = `connecting: ${deviceId}`;
      this.scheduleConnectValidation(deviceId, CONNECT_VALIDATE_RETRY_COUNT);
      this.notifyStateChanged();
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'connect failed: %{public}s', JSON.stringify(error));
      this.cancelPendingConnectionState();
      this.applyRegistrationStateFromError(error as Object);
      this.setError(formatBluetoothError('connect hid host', error as Object));
    }
  }

  disconnect(): void {
    this.cancelPendingConnectionState();
    if (this.hidProfile === null) {
      return;
    }

    try {
      this.hidProfile.disconnect();
      this.debugState.connected = false;
      this.debugState.lastConnectedDeviceId = '';
      this.debugState.lastError = '';
      this.debugState.lastEvent = 'hid disconnect requested';
      this.notifyStateChanged();
    } catch (error) {
      this.applyRegistrationStateFromError(error as Object);
      this.setError(formatBluetoothError('disconnect hid host', error as Object));
    }
  }

  cancelDeviceConnection(deviceId: string): void {
    if (this.pendingConnectDeviceId === deviceId || this.debugState.connectingDeviceId === deviceId || this.debugState.pairingDeviceId === deviceId || this.debugState.lastConnectedDeviceId === deviceId) {
      this.disconnect();
      this.debugState.lastEvent = `connection flow canceled: ${deviceId}`;
      this.notifyStateChanged();
    }
  }

  consumeLastError(): string {
    const message = this.debugState.lastError;
    this.debugState.lastError = '';
    this.notifyStateChanged();
    return message;
  }

  sendTouch(active: boolean, x: number, y: number): void {
    const report = this.buildAbsoluteTouchReport(active, x, y);
    this.debugState.lastReportHex = this.toHex(report);
    hilog.info(
      LOG_DOMAIN,
      LOG_TAG,
      'sendTouch active=%{public}d x=%{public}d y=%{public}d report=%{public}s registered=%{public}d connected=%{public}d',
      active ? 1 : 0,
      x,
      y,
      this.debugState.lastReportHex,
      this.debugState.registered ? 1 : 0,
      this.debugState.connected ? 1 : 0
    );
    if (this.hidProfile === null) {
      this.debugState.lastEvent = active ? `touch report prepared: ${x},${y}` : 'touch release report prepared';
      hilog.error(LOG_DOMAIN, LOG_TAG, 'sendTouch aborted: hidProfile is null');
      this.setError('HID device profile is unavailable on this device.');
      return;
    }

    try {
      this.hidProfile.sendReport(ABSOLUTE_TOUCH_REPORT_ID, report);
      this.debugState.registered = true;
      this.debugState.registering = false;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'sendReport completed reportId=%{public}d', ABSOLUTE_TOUCH_REPORT_ID);
      this.debugState.lastEvent = active ? `touch report sent: ${x},${y}` : 'touch release report sent';
      this.notifyStateChanged();
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'sendReport failed: %{public}s', JSON.stringify(error));
      this.applyRegistrationStateFromError(error as Object);
      this.setError(formatBluetoothError('send hid report', error as Object));
    }
  }

  releaseTouch(): void {
    this.sendTouch(false, 0, 0);
  }

  sendMouseButton(buttonPressed: boolean, x: number, y: number): void {
    const report = this.buildMouseButtonReport(buttonPressed, x, y);
    this.debugState.lastReportHex = this.toHex(report);
    hilog.info(
      LOG_DOMAIN,
      LOG_TAG,
      'sendMouseButton pressed=%{public}d x=%{public}d y=%{public}d report=%{public}s',
      buttonPressed ? 1 : 0,
      x,
      y,
      this.debugState.lastReportHex
    );
    if (this.hidProfile === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'sendMouseButton aborted: hidProfile is null');
      return;
    }

    try {
      this.hidProfile.sendReport(MOUSE_REPORT_ID, report);
      this.debugState.registered = true;
      this.debugState.registering = false;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'sendMouseReport completed reportId=%{public}d', MOUSE_REPORT_ID);
      this.debugState.lastEvent = buttonPressed ? `mouse button down: ${x},${y}` : 'mouse button up';
      this.notifyStateChanged();
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'sendMouseReport failed: %{public}s', JSON.stringify(error));
      this.applyRegistrationStateFromError(error as Object);
      this.setError(formatBluetoothError('send mouse hid report', error as Object));
    }
  }

  releaseMouseButton(): void {
    this.sendMouseButton(false, 0, 0);
  }

  sendMouseMove(dx: number, dy: number): void {
    const report = this.buildMouseMoveReport(dx, dy);
    this.debugState.lastReportHex = this.toHex(report);
    hilog.info(
      LOG_DOMAIN,
      LOG_TAG,
      'sendMouseMove dx=%{public}d dy=%{public}d report=%{public}s',
      dx,
      dy,
      this.debugState.lastReportHex
    );
    if (this.hidProfile === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'sendMouseMove aborted: hidProfile is null');
      return;
    }

    try {
      this.hidProfile.sendReport(MOUSE_REPORT_ID, report);
      this.debugState.registered = true;
      this.debugState.registering = false;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'sendMouseMove completed reportId=%{public}d', MOUSE_REPORT_ID);
      this.debugState.lastEvent = `mouse move: ${dx},${dy}`;
      this.notifyStateChanged();
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'sendMouseMove failed: %{public}s', JSON.stringify(error));
      this.applyRegistrationStateFromError(error as Object);
      this.setError(formatBluetoothError('send mouse move report', error as Object));
    }
  }

  mapStickToTouch(input: NormalizedStickInput, calibration: CalibrationConfig): TouchMapping {
    const magnitude = Math.sqrt(input.x * input.x + input.y * input.y);
    if (magnitude < calibration.deadzone) {
      return new TouchMapping(false, calibration.centerX, calibration.centerY);
    }

    const scaledMagnitude = clamp((magnitude - calibration.deadzone) / (1 - calibration.deadzone), 0, 1);
    const normalizedX = clamp(input.x / Math.max(magnitude, 0.0001), -1, 1) * scaledMagnitude;
    const normalizedY = clamp(input.y / Math.max(magnitude, 0.0001), -1, 1) * scaledMagnitude;

    return new TouchMapping(
      true,
      clamp(calibration.centerX + normalizedX * calibration.radiusX, 0, ABSOLUTE_AXIS_MAX),
      clamp(calibration.centerY + normalizedY * calibration.radiusY, 0, ABSOLUTE_AXIS_MAX)
    );
  }

  private buildAbsoluteTouchReport(active: boolean, x: number, y: number): Uint8Array {
    const flags = active ? 0x03 : 0x00;
    const xBytes = toLittleEndianWord(x);
    const yBytes = toLittleEndianWord(y);
    return new Uint8Array([flags, xBytes[0], xBytes[1], yBytes[0], yBytes[1]]);
  }

  private buildMouseButtonReport(buttonPressed: boolean, x: number, y: number): Uint8Array {
    const buttons = buttonPressed ? 0x01 : 0x00;
    const xBytes = toLittleEndianWord(x);
    const yBytes = toLittleEndianWord(y);
    return new Uint8Array([buttons, xBytes[0], xBytes[1], yBytes[0], yBytes[1]]);
  }

  private buildMouseMoveReport(dx: number, dy: number): Uint8Array {
    const xBytes = toSignedLittleEndianWord(dx);
    const yBytes = toSignedLittleEndianWord(dy);
    return new Uint8Array([0x00, xBytes[0], xBytes[1], yBytes[0], yBytes[1]]);
  }

  private toHex(report: Uint8Array): string {
    return Array.from(report)
      .map((value: number) => value.toString(16).padStart(2, '0'))
      .join(' ');
  }

  private setError(message: string): void {
    this.debugState.lastError = message;
    this.debugState.lastEvent = 'error';
    this.notifyStateChanged();
  }

  private applyRegistrationStateFromError(error: Object): void {
    const code = Reflect.get(error, 'code') as number | undefined;
    if (code === 2903053) {
      this.debugState.registered = true;
      this.debugState.registering = false;
      return;
    }

    if (code === 2903052 || code === 2903051 || code === 2903050) {
      this.debugState.registered = false;
      this.debugState.registering = false;
      if (code === 2903052) {
        this.debugState.connected = false;
        this.debugState.connecting = false;
        this.debugState.connectingDeviceId = '';
        this.debugState.lastConnectedDeviceId = '';
      }
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'hid registration state cleared by business error=%{public}d', code);
    }
  }

  private clearRegisterTimeout(): void {
    if (this.registerTimeoutId >= 0) {
      clearTimeout(this.registerTimeoutId);
      this.registerTimeoutId = -1;
    }
  }

  getPendingRemoteAddress(): string {
    return this.pendingRemoteAddress;
  }

  getDevices(): Array<RemoteDeviceItem> {
    const devices = Array.from(this.discoveredDevices.values())
      .sort((left: RemoteDeviceItem, right: RemoteDeviceItem) => {
        const leftRank = this.getSignalSortRank(left.rssi);
        const rightRank = this.getSignalSortRank(right.rssi);

        if (leftRank !== rightRank) {
          return rightRank - leftRank;
        }
        if (leftRank > 0 && left.rssi !== right.rssi) {
          return right.rssi - left.rssi;
        }
        return left.name.localeCompare(right.name);
      })
      .map((item: RemoteDeviceItem) => {
        return new RemoteDeviceItem(item.deviceId, item.name, item.bondState, item.rssi, item.isPaired, item.isSelected);
      });

    const summary = devices
      .slice(0, 8)
      .map((item: RemoteDeviceItem) => `${item.name}|${item.deviceId}|rssi=${item.rssi}|rank=${this.getSignalSortRank(item.rssi)}`)
      .join('; ');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'device order snapshot: %{public}s', summary || 'empty');
    return devices;
  }

  async ensureBluetoothPermission(context: commonAbility.UIAbilityContext): Promise<boolean> {
    try {
      const grantStatus = this.atManager.verifyAccessTokenSync(context.applicationInfo.accessTokenId, BLUETOOTH_PERMISSION);
      if (grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      }

      const result = await this.atManager.requestPermissionsFromUser(context, [BLUETOOTH_PERMISSION]);
      const granted = result.authResults.length > 0 && result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      if (!granted) {
        this.setError('Bluetooth permission was denied by the user.');
      }
      this.notifyStateChanged();
      return granted;
    } catch (error) {
      this.setError(`request bluetooth permission failed: ${JSON.stringify(error)}`);
      return false;
    }
  }

  async enableBluetoothIfNeeded(): Promise<void> {
    this.debugState.bluetoothEnabled = this.getBluetoothEnabledSafe();
    if (this.debugState.bluetoothEnabled) {
      return;
    }

    try {
      await access.enableBluetoothAsync();
      this.debugState.bluetoothEnabled = true;
      this.debugState.lastEvent = 'bluetooth enabled';
      this.notifyStateChanged();
    } catch (error) {
      this.setError(formatBluetoothError('enable bluetooth', error as Object));
    }
  }

  startDiscovery(): void {
    if (this.debugState.discovering) {
      this.debugState.lastEvent = 'bluetooth discovery already active';
      this.notifyStateChanged();
      return;
    }

    try {
      connection.startBluetoothDiscovery();
      this.debugState.discovering = true;
      this.debugState.lastEvent = 'bluetooth discovery started';
      this.notifyStateChanged();
    } catch (error) {
      this.setError(formatBluetoothError('start bluetooth discovery', error as Object));
    }
  }

  stopDiscovery(): void {
    try {
      connection.stopBluetoothDiscovery();
      this.debugState.discovering = false;
      this.debugState.lastEvent = 'bluetooth discovery stopped';
      this.notifyStateChanged();
    } catch (error) {
      this.setError(formatBluetoothError('stop bluetooth discovery', error as Object));
    }
  }

  async pairDevice(deviceId: string): Promise<void> {
    this.debugState.lastError = '';
    try {
      await connection.pairDevice(deviceId);
      this.pendingRemoteAddress = deviceId;
      this.debugState.pairingDeviceId = deviceId;
      this.debugState.lastEvent = `pair requested: ${deviceId}`;
      this.refreshPairedDevices();
      this.notifyStateChanged();
    } catch (error) {
      if (this.getSafePairState(deviceId) === connection.BondState.BOND_STATE_BONDING) {
        this.debugState.pairingDeviceId = deviceId;
        this.debugState.lastError = '';
        this.debugState.lastEvent = `pairing: ${deviceId}`;
        this.notifyStateChanged();
        return;
      }
      this.setError(formatBluetoothError('pair device', error as Object));
    }
  }

  async connectWithPairing(deviceId: string): Promise<boolean> {
    this.selectDevice(deviceId);
    this.pendingConnectDeviceId = deviceId;
    this.debugState.lastError = '';

    const pairState = this.getSafePairState(deviceId);
    if (pairState === connection.BondState.BOND_STATE_BONDING) {
      this.debugState.pairingDeviceId = deviceId;
      this.debugState.lastEvent = `pairing: ${deviceId}`;
      this.notifyStateChanged();
      return true;
    }

    if (pairState !== connection.BondState.BOND_STATE_BONDED) {
      await this.pairDevice(deviceId);
      const updatedPairState = this.getSafePairState(deviceId);
      if (updatedPairState === connection.BondState.BOND_STATE_BONDING) {
        this.debugState.pairingDeviceId = deviceId;
        this.debugState.lastError = '';
        this.debugState.lastEvent = `pairing: ${deviceId}`;
        this.notifyStateChanged();
        return true;
      }
      if (updatedPairState !== connection.BondState.BOND_STATE_BONDED) {
        if (this.debugState.lastError.length === 0) {
          this.setError(`connect failed: device is still not paired after pairing attempt: ${deviceId}`);
        }
        this.pendingConnectDeviceId = '';
        return false;
      }
    }

    this.connect(deviceId);
    return true;
  }

  forgetPairedDevice(deviceId: string): boolean {
    this.selectDevice(deviceId);
    if (this.getSafePairState(deviceId) !== connection.BondState.BOND_STATE_BONDED) {
      this.setError('forget paired device failed: this device is not paired.');
      return false;
    }

    this.setError('forget paired device is not available: the HarmonyOS public Bluetooth SDK in this app does not expose an unpair API. Remove the device in system Bluetooth settings instead.');
    return false;
  }

  selectDevice(deviceId: string): void {
    this.pendingRemoteAddress = deviceId;
    const entries = Array.from(this.discoveredDevices.entries());
    entries.forEach((entry: [string, RemoteDeviceItem]) => {
      const entryDeviceId = entry[0];
      const item = entry[1];
      this.discoveredDevices.set(entryDeviceId, new RemoteDeviceItem(
        item.deviceId,
        item.name,
        item.bondState,
        item.rssi,
        item.isPaired,
        item.deviceId === deviceId
      ));
    });
    this.debugState.lastEvent = `device selected: ${deviceId}`;
    this.notifyStateChanged();
  }

  destroy(): void {
    try {
      this.clearConnectValidation();
      connection.off('discoveryResult', this.discoveryListener);
      connection.off('bondStateChange', this.bondListener);
      connection.off('pinRequired', this.pinListener);
      access.off('stateChange');
      this.stateListener = null;
    } catch (_) {
    }
  }

  private initializeHidProfile(): void {
    try {
      this.hidProfile = hid.createHidDeviceProfile();
      this.notifyStateChanged();
    } catch (error) {
      this.setError(formatBluetoothError('create hid profile', error as Object));
      this.hidProfile = null;
    }
  }

  private buildSdp(): hid.HidDeviceSdp {
    return {
      name: 'Bluetooth Gaming Mouse',
      description: 'Bluetooth Gaming Mouse',
      provider: 'BluetoothGamingMouse',
      subclass: hid.Subclass.SUBCLASS_COMBO,
      descriptors: buildCombinedDescriptor(),
    };
  }

  private buildQos(): hid.HidDeviceQos {
    return {
      serviceType: hid.ServiceType.SERVICE_BEST_EFFORT,
      tokenRate: 0,
      tokenBucketSize: 0,
      peakBandwidth: 0,
      latency: 1000,
      delayVariation: 1000,
    };
  }

  private attachBluetoothListeners(): void {
    try {
      connection.on('discoveryResult', this.discoveryListener);
      connection.on('bondStateChange', this.bondListener);
      connection.on('pinRequired', this.pinListener);
      access.on('stateChange', (state: access.BluetoothState) => {
        this.debugState.bluetoothEnabled = state === access.BluetoothState.STATE_ON;
        this.notifyStateChanged();
      });
    } catch (error) {
      this.setError(formatBluetoothError('attach bluetooth listeners', error as Object));
    }
  }

  private refreshPairedDevices(): void {
    try {
      const pairedDeviceIds = connection.getPairedDevices();
      pairedDeviceIds.forEach((deviceId: string) => {
        const existing = this.discoveredDevices.get(deviceId);
        const item = new RemoteDeviceItem(
          deviceId,
          existing?.name || this.getSafeRemoteName(deviceId),
          this.toBondStateLabel(connection.BondState.BOND_STATE_BONDED),
          existing?.rssi ?? UNKNOWN_RSSI,
          true,
          existing?.isSelected ?? this.pendingRemoteAddress === deviceId
        );
        this.discoveredDevices.set(deviceId, item);
      });
      this.notifyStateChanged();
    } catch (error) {
      this.setError(formatBluetoothError('load paired devices', error as Object));
    }
  }

  private notifyStateChanged(): void {
    this.stateListener?.(this.buildDerivedState(), this.getDevices());
  }

  private buildDerivedState(): HidDebugState {
    const state = this.debugState.clone();
    if (state.connected || state.connecting || state.lastConnectedDeviceId.length > 0) {
      state.registered = true;
      state.registering = false;
    }

    const hasLiveDiscoveryResult = Array.from(this.discoveredDevices.values())
      .some((device: RemoteDeviceItem) => device.rssi < 0 && device.rssi > -100);
    if (hasLiveDiscoveryResult) {
      state.discovering = true;
    }

    return state;
  }

  private clearConnectValidation(): void {
    if (this.connectValidationTimeoutId >= 0) {
      clearTimeout(this.connectValidationTimeoutId);
      this.connectValidationTimeoutId = -1;
    }
  }

  private cancelPendingConnectionState(): void {
    this.clearConnectValidation();
    this.pendingConnectDeviceId = '';
    this.debugState.connecting = false;
    this.debugState.connectingDeviceId = '';
    this.debugState.pairingDeviceId = '';
  }

  private scheduleConnectValidation(deviceId: string, remainingAttempts: number): void {
    this.clearConnectValidation();
    this.connectValidationTimeoutId = setTimeout(() => {
      this.connectValidationTimeoutId = -1;
      this.validateConnectedDevice(deviceId, remainingAttempts);
    }, CONNECT_VALIDATE_INTERVAL_MS);
  }

  private validateConnectedDevice(deviceId: string, remainingAttempts: number): void {
    if (this.pendingConnectDeviceId !== deviceId || this.hidProfile === null) {
      return;
    }

    try {
      this.hidProfile.sendReport(ABSOLUTE_TOUCH_REPORT_ID, this.buildAbsoluteTouchReport(false, 0, 0));
      this.pendingConnectDeviceId = '';
      this.debugState.registered = true;
      this.debugState.registering = false;
      this.debugState.connecting = false;
      this.debugState.connectingDeviceId = '';
      this.debugState.connected = true;
      this.debugState.lastConnectedDeviceId = deviceId;
      this.debugState.lastError = '';
      this.debugState.lastEvent = `hid connected: ${deviceId}`;
      this.notifyStateChanged();
    } catch (error) {
      const code = Reflect.get(error as Object, 'code') as number | undefined;
      if (code === 2903053 && remainingAttempts > 1) {
        this.debugState.registered = true;
        this.debugState.registering = false;
        this.debugState.connecting = true;
        this.debugState.connectingDeviceId = deviceId;
        this.debugState.lastEvent = `connecting: ${deviceId}`;
        this.notifyStateChanged();
        this.scheduleConnectValidation(deviceId, remainingAttempts - 1);
        return;
      }

      this.cancelPendingConnectionState();
      this.debugState.connected = false;
      this.debugState.lastConnectedDeviceId = '';
      this.applyRegistrationStateFromError(error as Object);
      this.setError(formatBluetoothError('connect hid host', error as Object));
    }
  }

  private async prepareDeviceSelectionAttempt(onStateChange?: (state: HidDebugState) => void): Promise<boolean> {
    this.debugState.lastError = '';
    this.debugState.lastEvent = 'preparing device selection';
    this.debugState.bluetoothEnabled = this.getBluetoothEnabledSafe();
    this.refreshPairedDevices();
    onStateChange?.(this.getState());
    this.notifyStateChanged();

    await this.enableBluetoothIfNeeded();
    onStateChange?.(this.getState());
    if (!this.debugState.bluetoothEnabled) {
      if (this.debugState.lastError.length === 0) {
        this.setError('prepare device selection failed: bluetooth could not be enabled.');
      }
      return false;
    }

    if (!this.debugState.registered) {
      const registered = await this.register(onStateChange);
      if (!registered) {
        return false;
      }
    }

    this.startDiscovery();
    onStateChange?.(this.getState());
    this.refreshPairedDevices();
    if (!this.debugState.discovering) {
      if (this.debugState.lastError.length === 0) {
        this.setError('prepare device selection failed: bluetooth discovery could not be started.');
      }
      return false;
    }

    this.debugState.lastError = '';
    this.debugState.lastEvent = 'device selection ready';
    onStateChange?.(this.getState());
    this.notifyStateChanged();
    return true;
  }

  private async recoverPreparationWithoutDisablingBluetooth(onStateChange?: (state: HidDebugState) => void): Promise<boolean> {
    this.debugState.lastError = '';
    this.debugState.lastEvent = 'retrying preparation without disabling bluetooth';
    onStateChange?.(this.getState());
    this.notifyStateChanged();

    await this.enableBluetoothIfNeeded();
    onStateChange?.(this.getState());
    if (!this.debugState.bluetoothEnabled) {
      if (this.debugState.lastError.length === 0) {
        this.setError('retry failed: bluetooth could not be enabled.');
      }
      return false;
    }

    if (this.hidProfile === null) {
      this.initializeHidProfile();
    }
    return this.hidProfile !== null;
  }

  private getBluetoothEnabledSafe(): boolean {
    try {
      return access.getState() === access.BluetoothState.STATE_ON;
    } catch (_) {
      return false;
    }
  }

  private getSafeRemoteName(deviceId: string): string {
    try {
      return connection.getRemoteDeviceName(deviceId, false);
    } catch (_) {
      return 'Unknown Device';
    }
  }

  private getAddressType(deviceId: string): common.BluetoothAddressType {
    try {
      return access.isValidRandomDeviceId(deviceId)
        ? common.BluetoothAddressType.VIRTUAL
        : common.BluetoothAddressType.REAL;
    } catch (_) {
      return common.BluetoothAddressType.REAL;
    }
  }

  private getSafePairState(deviceId: string): connection.BondState {
    try {
      return connection.getPairState(deviceId);
    } catch (_) {
      return connection.BondState.BOND_STATE_INVALID;
    }
  }

  private getSignalSortRank(rssi: number): number {
    if (rssi >= 0 || rssi <= -100) {
      return 0;
    }
    if (rssi >= -55) {
      return 4;
    }
    if (rssi >= -68) {
      return 3;
    }
    if (rssi >= -78) {
      return 2;
    }
    if (rssi >= -88) {
      return 1;
    }
    return 0;
  }

  private toBondStateLabel(state: connection.BondState): string {
    if (state === connection.BondState.BOND_STATE_BONDED) {
      return 'bonded';
    }
    if (state === connection.BondState.BOND_STATE_BONDING) {
      return 'bonding';
    }
    return 'not bonded';
  }
}