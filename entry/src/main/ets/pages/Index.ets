import type commonAbility from '@ohos.app.ability.common';
import { AbsoluteTouchHidService, HidDebugState, RemoteDeviceItem } from '../services/AbsoluteTouchHidService';

const hidService = new AbsoluteTouchHidService();
const PRIMARY_COLOR = '#1456F0';
const SUCCESS_COLOR = '#0D8A5F';
const WARNING_COLOR = '#B06A00';
const CARD_COLOR = '#F5F7FB';

@Component
struct StatusChip {
  @Prop label: string = '';
  @Prop active: boolean = false;

  build() {
    Row() {
      Text(this.label)
        .layoutWeight(1)
        .fontSize(14)
        .fontColor('#1E2430')
        .textAlign(TextAlign.End)
        .padding({ right: 8 })

      Row() {
        Text(this.active ? '已完成' : '未完成')
          .fontSize(11)
          .fontColor('#FFFFFF')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.active ? SUCCESS_COLOR : WARNING_COLOR)
          .borderRadius(999)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)
      .padding({ left: 8 })
    }
    .width('100%')
  }
}

@Entry
@Component
struct Index {
  private hostContext = this.getUIContext().getHostContext() as commonAbility.UIAbilityContext;
  private lastShownError: string = '';
  @State debugState: HidDebugState = hidService.getState();
  @State devices: Array<RemoteDeviceItem> = hidService.getDevices();
  @State selectedDeviceId: string = hidService.getPendingRemoteAddress();
  @State isPreparing: boolean = false;

  aboutToAppear(): void {
    this.refreshFromService();
    hidService.setStateListener((state: HidDebugState, devices: Array<RemoteDeviceItem>) => {
      this.debugState = state;
      this.devices = this.cloneDevices(devices);
      this.selectedDeviceId = hidService.getPendingRemoteAddress();
    });
    this.enterDeviceSelectionStage();
  }

  aboutToDisappear(): void {
    hidService.setStateListener(null);
    hidService.destroy();
  }

  private refreshFromService(): void {
    const state = hidService.getState();
    const devices = hidService.getDevices();
    this.debugState = state;
    this.devices = this.cloneDevices(devices);
    this.selectedDeviceId = hidService.getPendingRemoteAddress();
  }

  private cloneDevices(devices: Array<RemoteDeviceItem>): Array<RemoteDeviceItem> {
    return devices.map((device: RemoteDeviceItem) => {
      return new RemoteDeviceItem(device.deviceId, device.name, device.bondState, device.rssi, device.isPaired, device.isSelected);
    });
  }

  private isBluetoothReady(): boolean {
    return this.debugState.bluetoothEnabled;
  }

  private isHidReady(): boolean {
    return this.debugState.registered || this.debugState.connected || this.debugState.connecting || this.debugState.lastConnectedDeviceId.length > 0;
  }

  private isDiscoveryReady(): boolean {
    return this.debugState.discovering || this.hasDiscoveryEvidence(this.devices);
  }

  private hasDiscoveryEvidence(devices: Array<RemoteDeviceItem>): boolean {
    return devices.some((device: RemoteDeviceItem) => !device.isPaired || !this.isOfflineSignal(device.rssi));
  }

  private getSelectedDevice(): RemoteDeviceItem | null {
    if (this.selectedDeviceId.length === 0) {
      return null;
    }

    for (const device of this.devices) {
      if (device.deviceId === this.selectedDeviceId) {
        return device;
      }
    }

    return null;
  }

  private getSelectedDeviceName(): string {
    const selectedDevice = this.getSelectedDevice();
    if (selectedDevice !== null) {
      return selectedDevice.name || '未命名设备';
    }
    if (this.selectedDeviceId.length > 0) {
      return '未知设备';
    }
    return '未选择设备';
  }

  private getDeviceRenderKey(device: RemoteDeviceItem): string {
    return `${device.deviceId}|${device.rssi}|${device.bondState}|${device.isPaired ? 1 : 0}|${device.isSelected ? 1 : 0}`;
  }

  private async enterDeviceSelectionStage(): Promise<void> {
    if (this.isPreparing) {
      return;
    }

    this.isPreparing = true;
    try {
      const ready = await hidService.prepareForDeviceSelection(this.hostContext);
      this.refreshFromService();
      if (!ready) {
        await this.showPreparationError(this.debugState.lastError || '蓝牙准备失败，请稍后重试。');
      } else {
        this.lastShownError = '';
      }
    } finally {
      this.isPreparing = false;
    }
  }

  private async showPreparationError(message: string): Promise<void> {
    if (message.length === 0 || message === this.lastShownError) {
      return;
    }

    this.lastShownError = message;
    try {
      await this.getUIContext().getPromptAction().showDialog({
        title: '设备准备失败',
        message,
        buttons: [
          {
            text: '知道了',
            color: PRIMARY_COLOR,
          },
        ],
      });
    } catch (_) {
    }
  }

  private async showActionError(title: string, message: string): Promise<void> {
    if (message.length === 0) {
      return;
    }

    try {
      await this.getUIContext().getPromptAction().showDialog({
        title,
        message,
        buttons: [
          {
            text: '知道了',
            color: PRIMARY_COLOR,
          },
        ],
      });
    } catch (_) {
    }
  }

  private async showSignalDetails(device: RemoteDeviceItem): Promise<void> {
    const message = this.isOfflineSignal(device.rssi)
      ? `设备名称：${device.name}\n虚拟MAC地址：${device.deviceId}\n当前没有实时 RSSI，图标显示为离线。\n原始 RSSI：${device.rssi}`
      : `设备名称：${device.name}\n虚拟MAC地址：${device.deviceId}\n原始 RSSI：${device.rssi}\n信号档位：${this.getSignalLevel(device.rssi)} 格`;
    await this.showActionError('信号详情', message);
  }

  private async showPairDetails(device: RemoteDeviceItem): Promise<void> {
    const connectedText = this.isDeviceConnected(device)
      ? '已连接'
      : (this.isDeviceConnecting(device) ? '连接中' : (this.isDevicePairing(device) ? '配对中' : '未连接'));
    const message = `设备名称：${device.name}\n虚拟MAC地址：${device.deviceId}\n配对状态：${device.bondState}\n是否已配对：${device.isPaired ? '是' : '否'}\n当前连接状态：${connectedText}`;
    await this.showActionError('配对详情', message);
  }

  private async showVirtualMacDetails(device: RemoteDeviceItem): Promise<void> {
    await this.showActionError(
      '虚拟MAC地址说明',
      `设备名称：${device.name}\n虚拟MAC地址：${device.deviceId}\n\n这里显示的是 HarmonyOS 提供给应用使用的虚拟MAC地址，用于设备发现、配对和连接流程中的设备标识。\n\n它不是设备真实的蓝牙MAC地址，请不要把它当成厂商出厂的物理蓝牙地址。`
    );
  }

  private async connectDevice(deviceId: string): Promise<void> {
    const started = await hidService.connectWithPairing(deviceId);
    this.refreshFromService();
    if (!started) {
      const message = hidService.consumeLastError();
      if (message.length > 0) {
        await this.showActionError('连接失败', message);
      }
    }
  }

  private async disconnectDevice(deviceId: string): Promise<void> {
    hidService.cancelDeviceConnection(deviceId);
    this.refreshFromService();
    const message = hidService.consumeLastError();
    if (message.length > 0) {
      await this.showActionError('断开失败', message);
    }
  }

  private getSetupStatusTitle(): string {
    if (this.isPreparing || this.debugState.registering) {
      return '正在准备设备选择';
    }
    if (this.isReadyForSelection()) {
      return '设备选择已就绪';
    }
    return '需要重新准备';
  }

  private getSetupStatusDescription(): string {
    if (this.isPreparing || this.debugState.registering) {
      return '正在自动打开蓝牙、注册 HID，并搜索可用设备。';
    }
    if (this.isReadyForSelection()) {
      return '现在可以直接选择、配对并连接目标设备。';
    }
    return '自动准备没有完成，可以点击“重新准备”再次执行完整流程。';
  }

  private isReadyForSelection(): boolean {
    return this.isBluetoothReady() && this.isHidReady() && this.isDiscoveryReady();
  }

  private hasSelectedDevice(): boolean {
    return this.getSelectedDevice() !== null;
  }

  private showSelectedDeviceVirtualMac(): void {
    const selectedDevice = this.getSelectedDevice();
    if (selectedDevice !== null) {
      this.showVirtualMacDetails(selectedDevice);
    }
  }

  @Builder
  private buildCurrentSelectionRow() {
    Row() {
      Text('连接设备')
        .layoutWeight(1)
        .fontSize(14)
        .fontColor('#1E2430')
        .textAlign(TextAlign.End)
        .padding({ right: 8 })

      Text(this.getSelectedDeviceName())
        .layoutWeight(1)
        .fontSize(13)
        .fontColor(this.hasSelectedDevice() ? PRIMARY_COLOR : '#667085')
        .textAlign(TextAlign.Start)
        .padding({ left: 8 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .onClick(() => {
      this.showSelectedDeviceVirtualMac();
    })
  }

  private isDeviceConnected(device: RemoteDeviceItem): boolean {
    return this.debugState.connected && this.debugState.lastConnectedDeviceId === device.deviceId;
  }

  private isDeviceConnecting(device: RemoteDeviceItem): boolean {
    return this.debugState.connecting && this.debugState.connectingDeviceId === device.deviceId;
  }

  private isDevicePairing(device: RemoteDeviceItem): boolean {
    return this.debugState.pairingDeviceId === device.deviceId;
  }

  private isOfflineSignal(rssi: number): boolean {
    return rssi >= 0 || rssi <= -100;
  }

  private getSignalLevel(rssi: number): number {
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

  @Builder
  private buildSignalBadge(rssi: number) {
    if (this.isOfflineSignal(rssi)) {
      Row({ space: 0 }) {
        Stack() {
          Column()
            .width(16)
            .height(16)
            .borderRadius(8)
            .backgroundColor('#FEE4E2')
          Column()
            .width(12)
            .height(2)
            .backgroundColor('#F04438')
            .rotate({ angle: -45 })
        }
      }
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .backgroundColor('#FFF1F3')
      .borderRadius(999)
    } else {
      Row({ space: 2 }) {
        Column()
          .width(4)
          .height(6)
          .borderRadius(2)
          .backgroundColor(this.getSignalLevel(rssi) >= 1 ? PRIMARY_COLOR : '#D0D5DD')
        Column()
          .width(4)
          .height(9)
          .borderRadius(2)
          .backgroundColor(this.getSignalLevel(rssi) >= 2 ? PRIMARY_COLOR : '#D0D5DD')
        Column()
          .width(4)
          .height(12)
          .borderRadius(2)
          .backgroundColor(this.getSignalLevel(rssi) >= 3 ? PRIMARY_COLOR : '#D0D5DD')
        Column()
          .width(4)
          .height(15)
          .borderRadius(2)
          .backgroundColor(this.getSignalLevel(rssi) >= 4 ? PRIMARY_COLOR : '#D0D5DD')
      }
      .alignItems(VerticalAlign.Bottom)
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .backgroundColor('#EEF4FF')
      .borderRadius(999)
    }
  }

  @Builder
  private buildDeviceCard(device: RemoteDeviceItem) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text(device.name || '未命名设备')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .onClick(() => {
            this.showVirtualMacDetails(device);
          })

        Row({ space: 8 }) {
          Row() {
            this.buildSignalBadge(device.rssi)
          }
          .onClick(() => {
            this.showSignalDetails(device);
          })

          Text(device.isPaired ? '已配对' : '未配对')
            .fontSize(12)
            .fontColor(device.isPaired ? SUCCESS_COLOR : WARNING_COLOR)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor(device.isPaired ? '#E7F8F0' : '#FFF4E5')
            .borderRadius(999)
            .onClick(() => {
              this.showPairDetails(device);
            })
        }
      }
      .alignItems(VerticalAlign.Top)

      Button(this.isDevicePairing(device) ? '配对中' : (this.isDeviceConnecting(device) ? '连接中' : (this.isDeviceConnected(device) ? '断开' : '连接')))
        .width('100%')
        .enabled(this.isReadyForSelection())
        .backgroundColor((this.isDevicePairing(device) || this.isDeviceConnecting(device) || this.isDeviceConnected(device)) ? '#F04438' : PRIMARY_COLOR)
        .fontColor('#FFFFFF')
        .onClick(() => {
          if (this.isDevicePairing(device) || this.isDeviceConnecting(device) || this.isDeviceConnected(device)) {
            this.disconnectDevice(device.deviceId);
            return;
          }
          this.connectDevice(device.deviceId);
        })
    }
    .padding(18)
    .backgroundColor((this.isDevicePairing(device) || this.isDeviceConnecting(device) || this.isDeviceConnected(device)) ? '#EAF1FF' : (device.isSelected ? '#F5F8FF' : '#FFFFFF'))
    .borderRadius(20)
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Column({ space: 10 }) {
          Text('选择要连接的蓝牙设备')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#101828')
            .width('100%')
            .textAlign(TextAlign.Start)

          Text('进入此页面后，应用会自动打开蓝牙、注册 HID，并开始发现附近设备。')
            .fontSize(15)
            .fontColor('#667085')
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)

        Column({ space: 14 }) {
          Text(this.getSetupStatusTitle())
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#101828')
            .width('100%')

          Text(this.getSetupStatusDescription())
            .fontSize(14)
            .fontColor('#667085')
            .width('100%')

          Column({ space: 10 }) {
            StatusChip({ label: '打开蓝牙', active: this.isBluetoothReady() })
            StatusChip({ label: '注册HID', active: this.isHidReady() })
            StatusChip({ label: '启用设备发现', active: this.isDiscoveryReady() })
            this.buildCurrentSelectionRow()
          }
          .width('100%')

          Row({ space: 12 }) {
            Button(this.isPreparing ? '正在准备...' : '重新准备')
              .layoutWeight(1)
              .enabled(!this.isPreparing)
              .backgroundColor(PRIMARY_COLOR)
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.enterDeviceSelectionStage();
              })

            Button(this.debugState.discovering ? '停止搜索' : '重新搜索')
              .layoutWeight(1)
              .enabled(!this.isPreparing)
              .backgroundColor('#E8EEF9')
              .fontColor('#1D4ED8')
              .onClick(() => {
                if (this.debugState.discovering) {
                  hidService.stopDiscovery();
                } else {
                  hidService.startDiscovery();
                }
                this.refreshFromService();
              })
          }
        }
        .padding(20)
        .backgroundColor(CARD_COLOR)
        .borderRadius(24)

        Column({ space: 14 }) {
          Text('附近设备')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#101828')
            .width('100%')

          if (this.devices.length > 0) {
            Column({ space: 12 }) {
              ForEach(this.devices, (device: RemoteDeviceItem) => {
                this.buildDeviceCard(device)
              }, (device: RemoteDeviceItem) => this.getDeviceRenderKey(device))
            }
          } else {
            Column({ space: 8 }) {
              Text(this.isPreparing ? '正在搜索附近设备，请稍候。' : '还没有发现设备，可以点击“重新准备”或“重新搜索”。')
                .fontSize(14)
                .fontColor('#667085')
                .width('100%')
              Text('如果目标设备已配对，也会直接出现在列表中。')
                .fontSize(12)
                .fontColor('#98A2B3')
                .width('100%')
            }
            .padding(18)
            .backgroundColor('#FFFFFF')
            .borderRadius(20)
          }
        }
        .padding(20)
        .backgroundColor(CARD_COLOR)
        .borderRadius(24)
      }
      .padding(20)
      .width('100%')
    }
    .backgroundColor('#EEF3FB')
    .height('100%')
  }
}
