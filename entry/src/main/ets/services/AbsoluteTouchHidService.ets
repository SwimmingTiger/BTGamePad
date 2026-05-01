import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import type commonAbility from '@ohos.app.ability.common';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { access, common, connection, hid } from '@kit.ConnectivityKit';

const ABSOLUTE_TOUCH_REPORT_ID = 1;
const ABSOLUTE_AXIS_MAX = 32767;
const BLUETOOTH_PERMISSION = 'ohos.permission.ACCESS_BLUETOOTH';
const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'AbsTouchHid';

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
  discovering: boolean = false;
  bluetoothEnabled: boolean = false;
  lastReportHex: string = '';
  descriptorHex: string = '';
  lastError: string = '';
  lastEvent: string = 'idle';
  lastConnectedDeviceId: string = '';
  pendingPinCode: string = '';

  clone(): HidDebugState {
    const copy = new HidDebugState();
    copy.registered = this.registered;
    copy.registering = this.registering;
    copy.connected = this.connected;
    copy.discovering = this.discovering;
    copy.bluetoothEnabled = this.bluetoothEnabled;
    copy.lastReportHex = this.lastReportHex;
    copy.descriptorHex = this.descriptorHex;
    copy.lastError = this.lastError;
    copy.lastEvent = this.lastEvent;
    copy.lastConnectedDeviceId = this.lastConnectedDeviceId;
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

export class AbsoluteTouchHidService {
  private debugState: HidDebugState = new HidDebugState();
  private pendingRemoteAddress: string = '';
  private registerTimeoutId: number = -1;
  private discoveredDevices: Map<string, RemoteDeviceItem> = new Map<string, RemoteDeviceItem>();
  private atManager = abilityAccessCtrl.createAtManager();
  private hidProfile: hid.HidDeviceProfile | null = null;
  private readonly discoveryListener = (results: Array<connection.DiscoveryResult>): void => {
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
    });
    this.debugState.lastEvent = `discovery update: ${results.length}`;
  };
  private readonly bondListener = (event: connection.BondStateParam): void => {
    const item = this.discoveredDevices.get(event.deviceId) ?? new RemoteDeviceItem(event.deviceId, this.getSafeRemoteName(event.deviceId), '', 0, false, this.pendingRemoteAddress === event.deviceId);
    item.bondState = this.toBondStateLabel(event.state);
    item.isPaired = event.state === connection.BondState.BOND_STATE_BONDED;
    this.discoveredDevices.set(event.deviceId, item);
    this.debugState.lastEvent = `bond state: ${event.deviceId} -> ${item.bondState}`;
  };
  private readonly pinListener = (event: connection.PinRequiredParam): void => {
    this.debugState.pendingPinCode = event.pinCode;
    this.debugState.lastEvent = `pin required: ${event.deviceId}`;
  };

  constructor() {
    this.debugState.descriptorHex = this.toHex(buildAbsoluteDigitizerDescriptor());
    this.debugState.lastEvent = 'absolute descriptor prepared';
    this.debugState.bluetoothEnabled = this.getBluetoothEnabledSafe();
    this.attachBluetoothListeners();
    this.initializeHidProfile();
    this.refreshPairedDevices();
  }

  getState(): HidDebugState {
    return this.debugState.clone();
  }

  register(onStateChange?: (state: HidDebugState) => void): void {
    if (this.hidProfile === null) {
      this.setError('HID device profile is unavailable on this device.');
      onStateChange?.(this.getState());
      return;
    }

    this.clearRegisterTimeout();
    this.debugState.registering = true;
    this.debugState.lastError = '';
    this.debugState.lastEvent = 'registering hid';
    onStateChange?.(this.getState());

    this.registerTimeoutId = setTimeout(() => {
      this.registerTimeoutId = -1;
      if (this.debugState.registered || !this.debugState.registering) {
        return;
      }
      this.debugState.registering = false;
      this.setError('register hid failed: no callback or exception returned from the Bluetooth stack within 1500ms. Check hdc.log for system business errors such as 2903051.');
      onStateChange?.(this.getState());
    }, 1500);

    try {
      this.hidProfile.registerHidDevice(this.buildSdp(), this.buildQos(), this.buildQos(), (registered: boolean) => {
        this.clearRegisterTimeout();
        this.debugState.registering = false;
        this.debugState.registered = registered;
        if (registered) {
          this.debugState.lastEvent = 'hid registered';
        } else {
          this.setError('register hid rejected: the Bluetooth stack returned false without a business error detail.');
        }
        onStateChange?.(this.getState());
      });
    } catch (error) {
      this.clearRegisterTimeout();
      this.debugState.registering = false;
      this.setError(formatBluetoothError('register hid', error as Object));
      onStateChange?.(this.getState());
    }
  }

  unregister(): void {
    if (this.hidProfile === null) {
      return;
    }

    try {
      this.clearRegisterTimeout();
      this.debugState.registering = false;
      this.hidProfile.unregisterHidDevice();
      this.debugState.registered = false;
      this.debugState.connected = false;
      this.debugState.lastEvent = 'hid unregistered';
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
      this.hidProfile.connect({
        address: deviceId,
        addressType,
      });
      this.debugState.connected = true;
      this.debugState.lastConnectedDeviceId = deviceId;
      this.debugState.lastEvent = `hid connect requested: ${deviceId}`;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'connect failed: %{public}s', JSON.stringify(error));
      this.setError(formatBluetoothError('connect hid host', error as Object));
    }
  }

  disconnect(): void {
    if (this.hidProfile === null) {
      return;
    }

    try {
      this.hidProfile.disconnect();
      this.debugState.connected = false;
      this.debugState.lastEvent = 'hid disconnect requested';
    } catch (error) {
      this.setError(formatBluetoothError('disconnect hid host', error as Object));
    }
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
      hilog.info(LOG_DOMAIN, LOG_TAG, 'sendReport completed reportId=%{public}d', ABSOLUTE_TOUCH_REPORT_ID);
      this.debugState.lastEvent = active ? `touch report sent: ${x},${y}` : 'touch release report sent';
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'sendReport failed: %{public}s', JSON.stringify(error));
      this.setError(formatBluetoothError('send hid report', error as Object));
    }
  }

  releaseTouch(): void {
    this.sendTouch(false, 0, 0);
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
      clamp(calibration.centerY - normalizedY * calibration.radiusY, 0, ABSOLUTE_AXIS_MAX)
    );
  }

  private buildAbsoluteTouchReport(active: boolean, x: number, y: number): Uint8Array {
    const flags = active ? 0x03 : 0x00;
    const xBytes = toLittleEndianWord(x);
    const yBytes = toLittleEndianWord(y);
    return new Uint8Array([flags, xBytes[0], xBytes[1], yBytes[0], yBytes[1]]);
  }

  private toHex(report: Uint8Array): string {
    return Array.from(report)
      .map((value: number) => value.toString(16).padStart(2, '0'))
      .join(' ');
  }

  private setError(message: string): void {
    this.debugState.lastError = message;
    this.debugState.lastEvent = 'error';
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
    return Array.from(this.discoveredDevices.values()).map((item: RemoteDeviceItem) => {
      return new RemoteDeviceItem(item.deviceId, item.name, item.bondState, item.rssi, item.isPaired, item.isSelected);
    });
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
    } catch (error) {
      this.setError(formatBluetoothError('enable bluetooth', error as Object));
    }
  }

  startDiscovery(): void {
    try {
      connection.startBluetoothDiscovery();
      this.debugState.discovering = true;
      this.debugState.lastEvent = 'bluetooth discovery started';
    } catch (error) {
      this.setError(formatBluetoothError('start bluetooth discovery', error as Object));
    }
  }

  stopDiscovery(): void {
    try {
      connection.stopBluetoothDiscovery();
      this.debugState.discovering = false;
      this.debugState.lastEvent = 'bluetooth discovery stopped';
    } catch (error) {
      this.setError(formatBluetoothError('stop bluetooth discovery', error as Object));
    }
  }

  async pairDevice(deviceId: string): Promise<void> {
    try {
      await connection.pairDevice(deviceId);
      this.pendingRemoteAddress = deviceId;
      this.debugState.lastEvent = `pair requested: ${deviceId}`;
      this.refreshPairedDevices();
    } catch (error) {
      this.setError(formatBluetoothError('pair device', error as Object));
    }
  }

  selectDevice(deviceId: string): void {
    this.pendingRemoteAddress = deviceId;
    this.discoveredDevices.forEach((item: RemoteDeviceItem) => {
      item.isSelected = item.deviceId === deviceId;
    });
    this.debugState.lastEvent = `device selected: ${deviceId}`;
  }

  destroy(): void {
    try {
      connection.off('discoveryResult', this.discoveryListener);
      connection.off('bondStateChange', this.bondListener);
      connection.off('pinRequired', this.pinListener);
      access.off('stateChange');
    } catch (_) {
    }
  }

  private initializeHidProfile(): void {
    try {
      this.hidProfile = hid.createHidDeviceProfile();
    } catch (error) {
      this.setError(formatBluetoothError('create hid profile', error as Object));
      this.hidProfile = null;
    }
  }

  private buildSdp(): hid.HidDeviceSdp {
    return {
      name: 'BtGamePad Touch',
      description: 'Absolute touch digitizer for remote joystick',
      provider: 'BtGamePad',
      subclass: hid.Subclass.SUBCLASS_DIGITIZER_TABLET,
      descriptors: buildAbsoluteDigitizerDescriptor(),
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
          existing?.rssi || 0,
          true,
          this.pendingRemoteAddress === deviceId
        );
        this.discoveredDevices.set(deviceId, item);
      });
    } catch (error) {
      this.setError(formatBluetoothError('load paired devices', error as Object));
    }
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