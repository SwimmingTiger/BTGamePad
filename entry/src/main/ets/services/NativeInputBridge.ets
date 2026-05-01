import nativeInputModule from 'libentry.so';

export class NativeInputBridge {
  getVersion(): string {
    return nativeInputModule.getNativeInputBridgeVersion();
  }

  startMonitoring(): number {
    return nativeInputModule.startNativeInputMonitoring();
  }

  stopMonitoring(): number {
    return nativeInputModule.stopNativeInputMonitoring();
  }

  pollEventsJson(maxCount: number = 32): string {
    return nativeInputModule.pollNativeInputEvents(maxCount);
  }

  getConnectedGamepadsJson(): string {
    return nativeInputModule.getConnectedGamepadDevicesJson();
  }

  getStateJson(): string {
    return nativeInputModule.getNativeInputBridgeStateJson();
  }
}

export const nativeInputBridge = new NativeInputBridge();