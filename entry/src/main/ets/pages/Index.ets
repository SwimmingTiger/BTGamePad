import type commonAbility from '@ohos.app.ability.common';
import { AbsoluteTouchHidService, CalibrationConfig, HidDebugState, NormalizedStickInput, RemoteDeviceItem } from '../services/AbsoluteTouchHidService';

const hidService = new AbsoluteTouchHidService();
const DEFAULT_CALIBRATION: CalibrationConfig = new CalibrationConfig(5500, 27500, 3500, 3500, 0.18);

@Entry
@Component
struct Index {
  private hostContext = this.getUIContext().getHostContext() as commonAbility.UIAbilityContext;
  @State remoteAddress: string = '';
  @State centerX: string = `${DEFAULT_CALIBRATION.centerX}`;
  @State centerY: string = `${DEFAULT_CALIBRATION.centerY}`;
  @State radiusX: string = `${DEFAULT_CALIBRATION.radiusX}`;
  @State radiusY: string = `${DEFAULT_CALIBRATION.radiusY}`;
  @State deadzone: string = `${DEFAULT_CALIBRATION.deadzone}`;
  @State stickX: string = '0';
  @State stickY: string = '0';
  @State debugState: HidDebugState = hidService.getState();
  @State devices: Array<RemoteDeviceItem> = hidService.getDevices();

  aboutToAppear(): void {
    this.refreshState();
    this.refreshDevices();
  }

  aboutToDisappear(): void {
    hidService.destroy();
  }

  private refreshState(): void {
    this.debugState = hidService.getState();
    this.remoteAddress = hidService.getPendingRemoteAddress();
  }

  private refreshDevices(): void {
    this.devices = hidService.getDevices();
  }

  private getCalibration(): CalibrationConfig {
    return new CalibrationConfig(
      this.toInt(this.centerX, DEFAULT_CALIBRATION.centerX),
      this.toInt(this.centerY, DEFAULT_CALIBRATION.centerY),
      this.toInt(this.radiusX, DEFAULT_CALIBRATION.radiusX),
      this.toInt(this.radiusY, DEFAULT_CALIBRATION.radiusY),
      this.toFloat(this.deadzone, DEFAULT_CALIBRATION.deadzone)
    );
  }

  private getStickInput(): NormalizedStickInput {
    return new NormalizedStickInput(this.toFloat(this.stickX, 0), this.toFloat(this.stickY, 0));
  }

  private toInt(value: string, fallback: number): number {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  private toFloat(value: string, fallback: number): number {
    const parsed = Number.parseFloat(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  private sendMappedTouch(): void {
    const mapping = hidService.mapStickToTouch(this.getStickInput(), this.getCalibration());
    hidService.sendTouch(mapping.active, mapping.x, mapping.y);
    this.refreshState();
  }

  private sendCenterTouch(): void {
    const calibration = this.getCalibration();
    hidService.sendTouch(true, calibration.centerX, calibration.centerY);
    this.refreshState();
  }

  private async ensureBluetoothReady(): Promise<boolean> {
    const granted = await hidService.ensureBluetoothPermission(this.hostContext);
    this.refreshState();
    if (!granted) {
      return false;
    }

    await hidService.enableBluetoothIfNeeded();
    this.refreshState();
    return true;
  }

  private async startDiscoveryFlow(): Promise<void> {
    const ready = await this.ensureBluetoothReady();
    if (!ready) {
      return;
    }

    hidService.startDiscovery();
    this.refreshState();
    this.refreshDevices();
  }

  private async pairSelectedDevice(deviceId: string): Promise<void> {
    const ready = await this.ensureBluetoothReady();
    if (!ready) {
      return;
    }

    await hidService.pairDevice(deviceId);
    this.refreshState();
    this.refreshDevices();
  }

  @Builder
  private buildDeviceItem(device: RemoteDeviceItem) {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Text(device.name || 'Unknown Device')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          Text(device.deviceId)
            .fontSize(12)
            .fontColor('#666666')
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(device.bondState)
          .fontSize(12)
          .fontColor(device.isPaired ? '#0A7F32' : '#A65B00')
      }

      Row({ space: 10 }) {
        Button(device.isSelected ? 'Selected' : 'Select')
          .layoutWeight(1)
          .enabled(!device.isSelected)
          .onClick(() => {
            hidService.selectDevice(device.deviceId);
            this.refreshState();
            this.refreshDevices();
          })
        Button(device.isPaired ? 'Paired' : 'Pair')
          .layoutWeight(1)
          .enabled(!device.isPaired)
          .onClick(() => {
            this.pairSelectedDevice(device.deviceId);
          })
        Button('Connect')
          .layoutWeight(1)
          .onClick(() => {
            hidService.selectDevice(device.deviceId);
            hidService.connect(device.deviceId);
            this.refreshState();
            this.refreshDevices();
          })
      }
    }
    .padding(14)
    .backgroundColor(device.isSelected ? '#E9F5FF' : '#F4F6F8')
    .borderRadius(14)
  }

  @Builder
  private buildField(label: string, value: string, onChange: (value: string) => void) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
      TextInput({ text: value })
        .type(InputType.Number)
        .onChange(onChange)
    }
    .alignItems(HorizontalAlign.Start)
    .width('48%')
  }

  @Builder
  private buildStatusLine(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#666666')
        .width('36%')
      Text(value)
        .fontSize(14)
        .fontColor('#111111')
        .width('64%')
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Text('BtGamePad Absolute Touch HID')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text('第一阶段先验证 absolute digitizer/touch 描述符是否能驱动远程鸿蒙设备的左下角虚拟摇杆。')
          .fontSize(14)
          .fontColor('#666666')
          .width('100%')

        Column({ space: 10 }) {
          Text('Remote Host Address')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          TextInput({ text: this.remoteAddress, placeholder: 'AA:BB:CC:DD:EE:FF' })
            .onChange((value: string) => {
              this.remoteAddress = value;
            })
        }
        .padding(16)
        .backgroundColor('#F4F6F8')
        .borderRadius(16)

        Column({ space: 12 }) {
          Text('Calibration')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          Row({ space: 12 }) {
            this.buildField('Center X', this.centerX, (value: string) => {
              this.centerX = value;
            })
            this.buildField('Center Y', this.centerY, (value: string) => {
              this.centerY = value;
            })
          }
          Row({ space: 12 }) {
            this.buildField('Radius X', this.radiusX, (value: string) => {
              this.radiusX = value;
            })
            this.buildField('Radius Y', this.radiusY, (value: string) => {
              this.radiusY = value;
            })
          }
          Row({ space: 12 }) {
            this.buildField('Deadzone', this.deadzone, (value: string) => {
              this.deadzone = value;
            })
            this.buildField('Stick X', this.stickX, (value: string) => {
              this.stickX = value;
            })
          }
          Row({ space: 12 }) {
            this.buildField('Stick Y', this.stickY, (value: string) => {
              this.stickY = value;
            })
          }
        }
        .padding(16)
        .backgroundColor('#F4F6F8')
        .borderRadius(16)

        Column({ space: 10 }) {
          Row({ space: 10 }) {
            Button('Enable Bluetooth')
              .layoutWeight(1)
              .onClick(() => {
                this.ensureBluetoothReady();
              })
            Button(this.debugState.discovering ? 'Stop Discovery' : 'Start Discovery')
              .layoutWeight(1)
              .onClick(() => {
                if (this.debugState.discovering) {
                  hidService.stopDiscovery();
                  this.refreshState();
                } else {
                  this.startDiscoveryFlow();
                }
              })
          }

          Row({ space: 10 }) {
            Button('Register HID')
              .layoutWeight(1)
              .onClick(() => {
                this.ensureBluetoothReady().then((ready: boolean) => {
                  if (!ready) {
                    return;
                  }
                  hidService.register(() => {
                    this.refreshState();
                  });
                  this.refreshState();
                });
              })
            Button('Unregister')
              .layoutWeight(1)
              .onClick(() => {
                hidService.unregister();
                this.refreshState();
              })
          }

          Row({ space: 10 }) {
            Button('Connect Host')
              .layoutWeight(1)
              .onClick(() => {
                hidService.connect(this.remoteAddress);
                this.refreshState();
              })
            Button('Disconnect')
              .layoutWeight(1)
              .onClick(() => {
                hidService.disconnect();
                this.refreshState();
              })
          }

          Row({ space: 10 }) {
            Button('Send Mapped Touch')
              .layoutWeight(1)
              .onClick(() => {
                this.sendMappedTouch();
              })
            Button('Tap Center')
              .layoutWeight(1)
              .onClick(() => {
                this.sendCenterTouch();
              })
          }

          Row({ space: 10 }) {
            Button('Release')
              .layoutWeight(1)
              .onClick(() => {
                hidService.releaseTouch();
                this.refreshState();
              })
            Text('`Send Mapped Touch` 会受 Stick X/Y 和 Deadzone 影响；`Tap Center` 会直接发送按下触点用于联调。')
              .fontSize(12)
              .fontColor('#666666')
              .layoutWeight(1)
          }
        }

        Column({ space: 10 }) {
          Text('Discovered Devices')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          if (this.devices.length > 0) {
            Column({ space: 10 }) {
              ForEach(this.devices, (device: RemoteDeviceItem) => {
                this.buildDeviceItem(device)
              }, (device: RemoteDeviceItem) => device.deviceId)
            }
          } else {
            Text('No devices yet. Start discovery to search for the remote host.')
              .fontSize(14)
              .fontColor('#666666')
              .width('100%')
          }
        }
        .padding(16)
        .backgroundColor('#F4F6F8')
        .borderRadius(16)

        Column({ space: 8 }) {
          Text('State')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          this.buildStatusLine('Bluetooth On', `${this.debugState.bluetoothEnabled}`)
          this.buildStatusLine('Discovering', `${this.debugState.discovering}`)
          this.buildStatusLine('Registering', `${this.debugState.registering}`)
          this.buildStatusLine('Registered', `${this.debugState.registered}`)
          this.buildStatusLine('Connected', `${this.debugState.connected}`)
          this.buildStatusLine('Connected Device', this.debugState.lastConnectedDeviceId || '-')
          this.buildStatusLine('Pending PIN', this.debugState.pendingPinCode || '-')
          this.buildStatusLine('Last Event', this.debugState.lastEvent)
          this.buildStatusLine('Descriptor', this.debugState.descriptorHex || '-')
          this.buildStatusLine('Last Report', this.debugState.lastReportHex || '-')
          this.buildStatusLine('Last Error', this.debugState.lastError || '-')
        }
        .padding(16)
        .backgroundColor('#F4F6F8')
        .borderRadius(16)
      }
      .padding(20)
      .width('100%')
    }
    .height('100%')
  }
}
