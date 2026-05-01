export interface NativeInputModule {
	add(a: number, b: number): number;
	getNativeInputBridgeVersion(): string;
	startNativeInputMonitoring(): number;
	stopNativeInputMonitoring(): number;
	pollNativeInputEvents(maxCount?: number): string;
	getConnectedGamepadDevicesJson(): string;
	getNativeInputBridgeStateJson(): string;
}

declare const nativeInputModule: NativeInputModule;

export default nativeInputModule;