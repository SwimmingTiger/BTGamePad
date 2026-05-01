const NativeMock: Record<string, Object> = {
  'add': (a: number, b: number) => {
    return a + b;
  },
  'getNativeInputBridgeVersion': () => {
    return 'mock-game-controller-bridge-v1';
  },
  'startNativeInputMonitoring': () => {
    return 0;
  },
  'stopNativeInputMonitoring': () => {
    return 0;
  },
  'pollNativeInputEvents': (_maxCount: number = 32) => {
    return '[]';
  },
  'getConnectedGamepadDevicesJson': () => {
    return '[]';
  },
  'getNativeInputBridgeStateJson': () => {
    return '{"monitoringStarted":false,"queuedEventCount":0,"lastErrorCode":0}';
  },
};

export default NativeMock;