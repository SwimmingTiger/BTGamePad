import mouseFeedbackNative from 'libentry.so';
import socket from '@ohos.net.socket';
import { hilog } from '@kit.PerformanceAnalysisKit';
import display from '@ohos.display';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'MouseFeedbackPage';
const PRIMARY_COLOR = '#1456F0';

@Entry
@Component
struct Index {
  @State targetIp: string = '192.168.1.100';
  @State targetPort: number = 21345;
  @State sendRate: number = 120;
  @State running: boolean = false;
  @State statusText: string = '先点击「开始监听鼠标」，启动后自动发送。';
  @State statusColor: string = '#9CA3AF';
  @State mouseX: number = 0;
  @State mouseY: number = 0;
  @State errorText: string = '';
  @State monitorStarted: boolean = false;
  @State sentCount: number = 0;
  @State screenW: number = 1920;
  @State screenH: number = 1080;
  private udpSocket: socket.UDPSocket | null = null;
  private sendIntervalId: number = -1;
  private lastX: number = 0;
  private lastY: number = 0;
  private lastSentX: number = 0;
  private lastSentY: number = 0;
  private firstSendDone: boolean = false;
  private lastSendTime: number = 0; // ms 时间戳
  private hasPrevSample: boolean = false;
  private prevSampleX: number = 0;
  private prevSampleY: number = 0;
  private stableSentForCurrentValue: boolean = false;

  aboutToAppear(): void {
    // Get screen resolution for coordinate normalization
    try {
      const defaultDisplay = display.getDefaultDisplaySync();
      this.screenW = defaultDisplay.width;
      this.screenH = defaultDisplay.height;
    } catch (e) {
      // use defaults
    }
  }

  aboutToDisappear(): void {
    this.stopSending();
    this.stopMonitor();
  }

  startMonitor(): void {
    this.doStartMonitor();
  }

  private doStartMonitor(): void {
    // Start screen capture first to activate CUSTOM_SCREEN_RECORDING permission
    try {
      mouseFeedbackNative.startScreenCapture();
    } catch (e) {
      let msg = '';
      const msgProp = Reflect.get(e as Object, 'message') as string | undefined;
      msg = msgProp !== undefined && msgProp !== null ? msgProp : String(e);
      this.errorText = `录屏激活失败: ${msg}`;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Screen capture start failed: %{public}s', msg);
      return;
    }

    try {
      mouseFeedbackNative.startMouseMonitor((x: number, y: number) => {
        this.lastX = x;
        this.lastY = y;
        this.mouseX = x;
        this.mouseY = y;
      });
      this.monitorStarted = true;
      this.errorText = '';
      this.sentCount = 0;
      this.statusText = '监听已启动，自动发送中…';
      this.statusColor = '#34D399';
      // Auto-start sending
      this.startSending();
    } catch (e) {
      let msg = '';
      const msgProp = Reflect.get(e as Object, 'message') as string | undefined;
      msg = msgProp !== undefined && msgProp !== null ? msgProp : String(e);
      this.errorText = `启动监听失败: ${msg}`;
      this.monitorStarted = false;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to start monitor: %{public}s', msg);
    }
  }

  stopMonitor(): void {
    try {
      mouseFeedbackNative.stopMouseMonitor();
    } catch (e) {
      // ignore
    }
    try {
      mouseFeedbackNative.stopScreenCapture();
    } catch (e) {
      // ignore
    }
    this.monitorStarted = false;
  }

  async startSending(): Promise<void> {
    if (this.running) {
      return;
    }

    // Validate target
    if (this.targetIp.trim().length === 0 || this.targetPort <= 0 || this.targetPort > 65535) {
      this.errorText = '请输入有效的 IP 地址和端口';
      return;
    }

    // Create UDP socket
    try {
      this.udpSocket = socket.constructUDPSocketInstance();
      await this.udpSocket.bind({
        address: '0.0.0.0',
        port: 0,
        family: 1,
      });
    } catch (e) {
      let msg = '';
      const msgProp = Reflect.get(e as Object, 'message') as string | undefined;
      msg = msgProp !== undefined && msgProp !== null ? msgProp : String(e);
      this.errorText = `UDP 绑定失败: ${msg}`;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'UDP bind failed: %{public}s', msg);
      return;
    }

    this.running = true;
    this.sentCount = 0;
    this.statusText = '正在发送…';
    this.statusColor = '#34D399';
    this.errorText = '';
    this.firstSendDone = false;
    this.lastSentX = 0;
    this.lastSentY = 0;
    this.lastSendTime = 0;
    this.hasPrevSample = false;
    this.prevSampleX = 0;
    this.prevSampleY = 0;
    this.stableSentForCurrentValue = false;

    const intervalMs = Math.max(1, Math.round(1000 / this.sendRate));
    const ip = this.targetIp.trim();
    const port = this.targetPort;
    const sW = Math.max(this.screenW, 1);
    const sH = Math.max(this.screenH, 1);

    this.sendIntervalId = setInterval(() => {

      const normX = (this.lastX / sW);
      const normY = (this.lastY / sH);

      const now = Date.now();
      let shouldSend = false;

      // 100ms兜底：无论是否变化都发送一次
      if (this.firstSendDone && now - this.lastSendTime >= 100) {
        shouldSend = true;
      }

      if (!this.hasPrevSample) {
        this.hasPrevSample = true;
        this.prevSampleX = normX;
        this.prevSampleY = normY;
      } else {
        const changedFromPrev = Math.abs(normX - this.prevSampleX) >= 0.0001 || Math.abs(normY - this.prevSampleY) >= 0.0001;

        if (changedFromPrev) {
          // 数值变化：进入“等待稳定”状态
          this.prevSampleX = normX;
          this.prevSampleY = normY;
          this.stableSentForCurrentValue = false;
        } else if (!this.stableSentForCurrentValue) {
          // 当前值与上一个值相同，且本轮稳定值尚未发送
          shouldSend = true;
          this.stableSentForCurrentValue = true;
        }
      }

      if (!this.firstSendDone) {
        // 启动后首次始终发送
        shouldSend = true;
      }

      if (!shouldSend) {
        return;
      }

      const buf = new ArrayBuffer(8);
      const view = new DataView(buf);
      view.setFloat32(0, normX, true);
      view.setFloat32(4, normY, true);

      try {
        this.udpSocket?.send({
          data: buf,
          address: {
            address: ip,
            port: port,
            family: 1,
          },
        });
        this.sentCount++;
        this.lastSentX = normX;
        this.lastSentY = normY;
        this.firstSendDone = true;
        this.lastSendTime = now;
      } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'UDP send failed: %{public}s', JSON.stringify(e));
      }
    }, intervalMs);
  }

  stopSending(): void {
    this.running = false;
    this.statusText = '已停止';
    this.statusColor = '#9CA3AF';

    if (this.sendIntervalId >= 0) {
      clearInterval(this.sendIntervalId);
      this.sendIntervalId = -1;
    }

    if (this.udpSocket !== null) {
      try {
        this.udpSocket.close();
      } catch (e) {
        // ignore
      }
      this.udpSocket = null;
    }
  }

  build() {
    Column({ space: 16 }) {
      // Title
      Text('鼠标位置反馈')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(PRIMARY_COLOR)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 32 })

      Text('在被控 HarmonyOS 设备上实时获取鼠标位置，通过 UDP 发送给 BtGamePad App。')
        .fontSize(13)
        .fontColor('#9CA3AF')
        .width('100%')
        .textAlign(TextAlign.Center)

      // Target config
      Column({ space: 10 }) {
        Text('目标地址')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .width('100%')

        Row({ space: 8 }) {
          TextInput({ text: this.targetIp, placeholder: 'IP 地址' })
            .layoutWeight(2)
            .height(42)
            .fontSize(14)
            .borderRadius(10)
            .backgroundColor('#F5F7FB')
            .onChange((value: string) => {
              this.targetIp = value;
            })

          TextInput({ text: `${this.targetPort}`, placeholder: '端口' })
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .type(InputType.Number)
            .borderRadius(10)
            .backgroundColor('#F5F7FB')
            .onChange((value: string) => {
              const p = Number.parseInt(value, 10);
              if (!Number.isNaN(p) && p > 0 && p <= 65535) {
                this.targetPort = p;
              }
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)

      // Rate config
      Column({ space: 10 }) {
        Row() {
          Text('发送频率')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)

          Blank()

          Text(`${this.sendRate} Hz`)
            .fontSize(14)
            .fontColor(PRIMARY_COLOR)
        }
        .width('100%')

        Slider({
          style: SliderStyle.OutSet,
          value: this.sendRate,
          min: 1,
          max: 360, // 允许最高360Hz
          step: 1,
        })
          .width('100%')
          .blockColor(PRIMARY_COLOR)
          .trackColor('#C8CDD5')
          .selectedColor(PRIMARY_COLOR)
          .onChange((value: number) => {
            this.sendRate = Math.round(value);
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)

      // Mouse position display
      Column({ space: 8 }) {
        Text('当前鼠标位置')
          .fontSize(12)
          .fontColor('#9CA3AF')

        Text(`${this.mouseX}, ${this.mouseY}`)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY_COLOR)
          .fontFamily('monospace')

        if (this.sentCount > 0) {
          Text(`已发送 ${this.sentCount}`)
            .fontSize(10)
            .fontColor('#9CA3AF')
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
      .alignItems(HorizontalAlign.Center)

      // Status
      Row({ space: 8 }) {
        Circle({ width: 10, height: 10 })
          .fill(this.statusColor)

        Text(this.errorText.length > 0 ? this.errorText : this.statusText)
          .fontSize(13)
          .fontColor(this.errorText.length > 0 ? '#F87171' : this.statusColor)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // Start monitoring button (must be pressed first)
      if (!this.monitorStarted) {
        Button('开始监听鼠标')
          .width('100%')
          .height(48)
          .fontSize(16)
          .backgroundColor(PRIMARY_COLOR)
          .fontColor('#FFFFFF')
          .borderRadius(12)
          .onClick(() => {
            this.startMonitor();
          })
      } else {
        Button('停止')
          .width('100%')
          .height(48)
          .fontSize(16)
          .backgroundColor('#EF4444')
          .fontColor('#FFFFFF')
          .borderRadius(12)
          .onClick(() => {
            this.stopSending();
            this.stopMonitor();
            this.errorText = '';
          })
      }

      Text(`协议: 8 字节 LE (int32 x, int32 y) · 需要 INPUT_MONITORING 权限`)
        .fontSize(10)
        .fontColor('#B0B7C3')
        .width('100%')
        .textAlign(TextAlign.Center)

      Text(`版本: ${mouseFeedbackNative.getVersion()}`)
        .fontSize(10)
        .fontColor('#C8CDD5')
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
    .backgroundColor('#F0F2F5')
  }
}
