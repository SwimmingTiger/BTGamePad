import socket from '@ohos.net.socket';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'MouseFeedback';
const MOUSE_FEEDBACK_DEFAULT_PORT = 21345;

export type MouseFeedbackPositionCallback = (x: number, y: number) => void;
export type MouseFeedbackStatusCallback = (active: boolean, error: string) => void;

export class MouseFeedbackService {
  private udpSocket: socket.UDPSocket | null = null;
  private listenPort: number = MOUSE_FEEDBACK_DEFAULT_PORT;
  private listening: boolean = false;
  private positionCallback: MouseFeedbackPositionCallback | null = null;
  private statusCallback: MouseFeedbackStatusCallback | null = null;
  private receivedCount: number = 0;

  setPositionCallback(callback: MouseFeedbackPositionCallback | null): void {
    this.positionCallback = callback;
  }

  setStatusCallback(callback: MouseFeedbackStatusCallback | null): void {
    this.statusCallback = callback;
  }

  isActive(): boolean {
    return this.listening;
  }

  getPort(): number {
    return this.listenPort;
  }

  getReceivedCount(): number {
    return this.receivedCount;
  }

  async start(port: number): Promise<boolean> {
    if (this.listening) {
      await this.stop();
    }

    this.listenPort = port > 0 ? port : MOUSE_FEEDBACK_DEFAULT_PORT;
    this.receivedCount = 0;

    try {
      this.udpSocket = socket.constructUDPSocketInstance();

      await this.udpSocket.bind({
        address: '0.0.0.0',
        port: this.listenPort,
        family: 1,
      });

      this.udpSocket.on('message', (value: socket.SocketMessageInfo) => {
        this.handleMessage(value);
      });

      this.udpSocket.on('error', (error: Object) => {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'UDP socket error: %{public}s', JSON.stringify(error));
        this.listening = false;
        this.statusCallback?.(false, `UDP 错误: ${JSON.stringify(error)}`);
      });

      this.udpSocket.on('close', () => {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'UDP socket closed');
        this.listening = false;
        this.statusCallback?.(false, '');
      });

      this.listening = true;
      this.statusCallback?.(true, '');
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Mouse feedback listening on port %{public}d', this.listenPort);
      return true;
    } catch (e) {
      const message = this.formatSocketError(e as Object);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to start mouse feedback: %{public}s', message);
      this.listening = false;
      this.statusCallback?.(false, message);
      await this.releaseSocket();
      return false;
    }
  }

  async stop(): Promise<void> {
    this.listening = false;
    await this.releaseSocket();
    this.statusCallback?.(false, '');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Mouse feedback stopped');
  }

  private handleMessage(value: socket.SocketMessageInfo): void {
    const data = value.message;
    if (!(data instanceof ArrayBuffer)) {
      return;
    }

    if ((data as ArrayBuffer).byteLength < 8) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Mouse feedback packet too short: %{public}d bytes', (data as ArrayBuffer).byteLength);
      return;
    }

    const view = new DataView(data as ArrayBuffer);
    const x = view.getFloat32(0, true);
    const y = view.getFloat32(4, true);

    if (x < 0 || x > 1 || y < 0 || y > 1) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Mouse feedback invalid coords: (%.4f, %.4f)', x, y);
      return;
    }

    this.receivedCount++;
    this.positionCallback?.(x, y);
  }

  private async releaseSocket(): Promise<void> {
    const sock = this.udpSocket;
    this.udpSocket = null;
    if (sock === null) {
      return;
    }

    try {
      sock.off('message');
      sock.off('error');
      sock.off('close');
      await sock.close();
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Error releasing UDP socket: %{public}s', JSON.stringify(e));
    }
  }

  private formatSocketError(error: Object): string {
    const code = Reflect.get(error, 'code') as number | undefined;
    const message = Reflect.get(error, 'message') as string | undefined;

    if (code === 2300004) {
      return '端口已被占用，请更换端口号。';
    }
    if (code !== undefined) {
      return `创建 UDP 监听失败 (${code}): ${message ?? '未知错误'}`;
    }
    return `创建 UDP 监听失败: ${message ?? JSON.stringify(error)}`;
  }
}

export const mouseFeedbackService = new MouseFeedbackService();
