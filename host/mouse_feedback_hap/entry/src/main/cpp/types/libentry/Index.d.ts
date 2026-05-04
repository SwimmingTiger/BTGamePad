export interface MouseFeedbackNative {
  startMouseMonitor(callback: Function): boolean;
  stopMouseMonitor(): boolean;
  isMonitorRunning(): boolean;
  startScreenCapture(): boolean;
  stopScreenCapture(): boolean;
  getVersion(): string;
}

declare const mouseFeedbackNative: MouseFeedbackNative;

export default mouseFeedbackNative;
