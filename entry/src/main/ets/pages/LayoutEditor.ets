import type commonAbility from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import picker from '@ohos.file.picker';
import image from '@ohos.multimedia.image';
import router from '@ohos.router';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HidDebugState, RemoteDeviceItem } from '../services/AbsoluteTouchHidService';
import { hidService, layoutRepository, nativeInputRuntimeService } from '../services/AppSession';
import { InputLayout, LayoutControlItem } from '../services/LayoutRepository';
import { NativeInputRuntimeState } from '../services/NativeInputRuntimeService';

const BACKGROUND_DIRECTORY_NAME = 'layout-backgrounds';
const TOUCH_ACTION_DOWN = 0;
const TOUCH_ACTION_UP = 1;
const TOUCH_ACTION_MOVE = 2;
const TOUCH_ACTION_CANCEL = 3;
const CONTROL_CANVAS_UNITS = 1000;
const STICK_CONTROL_DEFAULT_SIZE = 120;
const KEYBOARD_CONTROL_DEFAULT_SIZE = 108;
const LOOK_CONTROL_DEFAULT_SIZE = 250;
const BUTTON_CONTROL_DEFAULT_SIZE = 76;
const CONTROL_DEFAULT_SIZE = BUTTON_CONTROL_DEFAULT_SIZE;
const CONTROL_MIN_SIZE = 56;
const CONTROL_MAX_SIZE = 320;
const ROUND_CONTROL_MIN_SIZE = 36;
const LOOK_CONTROL_ASPECT_RATIO = 1.2;
const LOOK_CONTROL_MIN_WIDTH = 72;
const LOOK_CONTROL_MIN_HEIGHT = 60;
const CONTROL_SWIPE_DEFAULT_WIDTH = 172;
const CONTROL_SWIPE_DEFAULT_HEIGHT = 52;
const CONTROL_SWIPE_MIN_LENGTH = 104;
const CONTROL_SWIPE_MAX_LENGTH = 360;
const CONTROL_SWIPE_MIN_THICKNESS = 40;
const CONTROL_SWIPE_MAX_THICKNESS = 112;
const CONTROL_SWIPE_HANDLE_SIZE = 24;
const CONTROL_RESIZE_STEP = 20;
const CONTROL_LABEL_GAP = 3;
const SWIPE_DIRECTION_GAP = 4;
const CONTROL_TYPE_STICK_MOVE = 'stick-move';
const CONTROL_TYPE_STICK_LOOK = 'stick-look';
const CONTROL_TYPE_KEYBOARD_MOVE = 'keyboard-move';
const CONTROL_TYPE_KEYBOARD_LOOK = 'keyboard-look';
const CONTROL_TYPE_BUTTON = 'button';
const CONTROL_TYPE_SWIPE = 'swipe';
const CONTROL_PINCH_MIN_SCALE = 0.6;
const CONTROL_PINCH_MAX_SCALE = 1.8;
const MENU_BUTTON_WIDTH = 84;
const MENU_BUTTON_HEIGHT = 52;
const MENU_EDGE_MARGIN = 16;
const MENU_PANEL_WIDTH = 296;
const MENU_PANEL_HEIGHT = 540;
const MENU_PANEL_OFFSET = 10;
const MENU_DRAG_THRESHOLD_PX = 8;
const PRIMARY_COLOR = '#1456F0';
const SUCCESS_COLOR = '#0D8A5F';
const WARNING_COLOR = '#B06A00';
const CARD_COLOR = '#F5F7FB';
const KEY_EVENT_DOWN = 0;
const KEY_EVENT_UP = 1;
const RAW_KEYCODE_DPAD_UP = 2012;
const RAW_KEYCODE_DPAD_DOWN = 2013;
const RAW_KEYCODE_DPAD_LEFT = 2014;
const RAW_KEYCODE_DPAD_RIGHT = 2015;
const RAW_KEYCODE_BUTTON_A = 2301;
const RAW_KEYCODE_BUTTON_B = 2302;
const RAW_KEYCODE_BUTTON_X = 2304;
const RAW_KEYCODE_BUTTON_Y = 2305;
const RAW_KEYCODE_BUTTON_L1 = 2307;
const RAW_KEYCODE_BUTTON_R1 = 2308;
const RAW_KEYCODE_BUTTON_L2 = 2309;
const RAW_KEYCODE_BUTTON_R2 = 2310;
const RAW_KEYCODE_BUTTON_SELECT = 2311;
const RAW_KEYCODE_BUTTON_START = 2312;
const RAW_KEYCODE_BUTTON_MODE = 2313;
const RAW_KEYCODE_BUTTON_L3 = 2314;
const RAW_KEYCODE_BUTTON_R3 = 2315;
const MOUSE_ACTION_MOVE = 1;
const MOUSE_ACTION_BUTTON_DOWN = 2;
const MOUSE_ACTION_AXIS_UPDATE = 5;
const BINDING_AXIS_THRESHOLD = 0.24;
const EXECUTION_MODE_EDIT = 'edit';
const EXECUTION_MODE_EXECUTE = 'execute';
const EXECUTION_STICK_DEADZONE = 0.18;
const EXECUTION_TOUCH_FEEDBACK_SIZE = 32;
const EXECUTION_TOUCH_FEEDBACK_TIMEOUT_MS = 260;
const HID_AXIS_MAX = 32767;
const CONTROL_COORDINATE_SPACE_LEGACY_CANVAS = 'background-v1';
const CONTROL_COORDINATE_SPACE_BACKGROUND = 'background-v2';
const DIRECTIONAL_BINDING_PART_COUNT = 4;
const DIRECTIONAL_BINDING_ORDER_LABELS: Array<string> = ['上', '左', '下', '右'];
const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'LayoutEditor';

function clampEditorValue(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

class ControlLibraryItem {
  label: string;
  controlType: string;
  actionType: string;
  defaultSize: number;

  constructor(label: string, controlType: string, actionType: string, defaultSize: number) {
    this.label = label;
    this.controlType = controlType;
    this.actionType = actionType;
    this.defaultSize = defaultSize;
  }
}

class BindingOption {
  label: string;
  code: string;

  constructor(label: string, code: string) {
    this.label = label;
    this.code = code;
  }
}

class CapturedBinding {
  code: string;
  label: string;
  sourceLabel: string;
  rawSource: string;
  rawCode: string;
  rawName: string;

  constructor(code: string, label: string, sourceLabel: string, rawSource: string = '', rawCode: string = '', rawName: string = '') {
    this.code = code;
    this.label = label;
    this.sourceLabel = sourceLabel;
    this.rawSource = rawSource;
    this.rawCode = rawCode;
    this.rawName = rawName;
  }
}

class ControlPayload {
  rotation: number = 0;
  bindingLabel: string = '';
  bindingSource: string = '';
  bindingRawSource: string = '';
  bindingRawCode: string = '';
  bindingRawName: string = '';
  directionalKeyCodes: string = '';
  directionalKeyLabels: string = '';
  coordinateSpace: string = '';
  swipeStartX: number = -1;
  swipeStartY: number = -1;
  swipeEndX: number = -1;
  swipeEndY: number = -1;
}

class EditorPoint {
  x: number;
  y: number;

  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }

  clone(): EditorPoint {
    return new EditorPoint(this.x, this.y);
  }
}

class SwipeHandlePositions {
  start: EditorPoint;
  end: EditorPoint;

  constructor(start: EditorPoint, end: EditorPoint) {
    this.start = start;
    this.end = end;
  }
}

class ExecutionTouchTarget {
  controlId: string;
  xUnits: number;
  yUnits: number;
  order: number;

  constructor(controlId: string, xUnits: number, yUnits: number, order: number) {
    this.controlId = controlId;
    this.xUnits = xUnits;
    this.yUnits = yUnits;
    this.order = order;
  }

  clone(): ExecutionTouchTarget {
    return new ExecutionTouchTarget(this.controlId, this.xUnits, this.yUnits, this.order);
  }
}

class CanvasFrame {
  x: number;
  y: number;
  width: number;
  height: number;

  constructor(x: number, y: number, width: number, height: number) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

const CONTROL_LIBRARY_ITEMS: Array<ControlLibraryItem> = [
  new ControlLibraryItem('摇杆移动', CONTROL_TYPE_STICK_MOVE, 'touch', STICK_CONTROL_DEFAULT_SIZE),
  new ControlLibraryItem('摇杆视角', CONTROL_TYPE_STICK_LOOK, 'touch', LOOK_CONTROL_DEFAULT_SIZE),
  new ControlLibraryItem('键盘移动', CONTROL_TYPE_KEYBOARD_MOVE, 'touch', KEYBOARD_CONTROL_DEFAULT_SIZE),
  new ControlLibraryItem('键盘视角', CONTROL_TYPE_KEYBOARD_LOOK, 'touch', LOOK_CONTROL_DEFAULT_SIZE),
  new ControlLibraryItem('按钮', CONTROL_TYPE_BUTTON, 'touch', BUTTON_CONTROL_DEFAULT_SIZE),
  new ControlLibraryItem('滑动', CONTROL_TYPE_SWIPE, 'swipe', CONTROL_SWIPE_DEFAULT_WIDTH),
];

const STICK_MOVE_BINDINGS: Array<BindingOption> = [
  new BindingOption('左摇杆', `gamepad-axis:left-thumbstick`),
  new BindingOption('右摇杆', `gamepad-axis:right-thumbstick`),
];

const STICK_LOOK_BINDINGS: Array<BindingOption> = [
  new BindingOption('右摇杆', `gamepad-axis:right-thumbstick`),
  new BindingOption('左摇杆', `gamepad-axis:left-thumbstick`),
];

const KEYBOARD_MOVE_BINDINGS: Array<BindingOption> = [
  new BindingOption('W / A / S / D', 'keys-wasd'),
  new BindingOption('方向键', 'keys-arrows'),
  new BindingOption('数字键盘 8 / 4 / 2 / 6', 'keys-numpad-move'),
];

const KEYBOARD_LOOK_BINDINGS: Array<BindingOption> = [
  new BindingOption('I / J / K / L', 'keys-ijkl'),
  new BindingOption('方向键', 'keys-arrows-look'),
  new BindingOption('数字键盘 8 / 4 / 2 / 6', 'keys-numpad-look'),
];

const BUTTON_BINDINGS: Array<BindingOption> = [
  new BindingOption('按钮A', `gamepad-button:${RAW_KEYCODE_BUTTON_A}`),
  new BindingOption('按钮B', `gamepad-button:${RAW_KEYCODE_BUTTON_B}`),
  new BindingOption('按钮X', `gamepad-button:${RAW_KEYCODE_BUTTON_X}`),
  new BindingOption('按钮Y', `gamepad-button:${RAW_KEYCODE_BUTTON_Y}`),
  new BindingOption('L1', `gamepad-button:${RAW_KEYCODE_BUTTON_L1}`),
  new BindingOption('R1', `gamepad-button:${RAW_KEYCODE_BUTTON_R1}`),
  new BindingOption('L2', `gamepad-button:${RAW_KEYCODE_BUTTON_L2}`),
  new BindingOption('R2', `gamepad-button:${RAW_KEYCODE_BUTTON_R2}`),
  new BindingOption('L3', `gamepad-button:${RAW_KEYCODE_BUTTON_L3}`),
  new BindingOption('R3', `gamepad-button:${RAW_KEYCODE_BUTTON_R3}`),
  new BindingOption('开始', `gamepad-button:${RAW_KEYCODE_BUTTON_START}`),
  new BindingOption('选择', `gamepad-button:${RAW_KEYCODE_BUTTON_SELECT}`),
  new BindingOption('方向上', `gamepad-button:${RAW_KEYCODE_DPAD_UP}`),
  new BindingOption('方向下', `gamepad-button:${RAW_KEYCODE_DPAD_DOWN}`),
  new BindingOption('方向左', `gamepad-button:${RAW_KEYCODE_DPAD_LEFT}`),
  new BindingOption('方向右', `gamepad-button:${RAW_KEYCODE_DPAD_RIGHT}`),
];

const SWIPE_BINDINGS: Array<BindingOption> = [
  new BindingOption('左摇杆', `gamepad-axis:left-thumbstick`),
  new BindingOption('右摇杆', `gamepad-axis:right-thumbstick`),
  new BindingOption('左扳机', `gamepad-axis:left-trigger`),
  new BindingOption('右扳机', `gamepad-axis:right-trigger`),
];

const ALL_BINDING_OPTIONS: Array<BindingOption> = [
  ...STICK_MOVE_BINDINGS,
  ...STICK_LOOK_BINDINGS,
  ...KEYBOARD_MOVE_BINDINGS,
  ...KEYBOARD_LOOK_BINDINGS,
  ...BUTTON_BINDINGS,
  ...SWIPE_BINDINGS,
];

@Component
struct LayoutSummaryRow {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop highlight: boolean = false;

  build() {
    Row() {
      Text(this.label)
        .layoutWeight(1)
        .fontSize(14)
        .fontColor('#1E2430')

      Text(this.value)
        .fontSize(13)
        .fontColor(this.highlight ? PRIMARY_COLOR : '#667085')
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }
}

@Entry
@Component
struct LayoutEditor {
  private hostContext = this.getUIContext().getHostContext() as commonAbility.UIAbilityContext;
  private draggingControlId: string = '';
  private dragStartWindowX: number = 0;
  private dragStartWindowY: number = 0;
  private dragStartControlX: number = 0;
  private dragStartControlY: number = 0;
  private dragStartSwipeStartPoint: EditorPoint = new EditorPoint(0, 0);
  private dragStartSwipeEndPoint: EditorPoint = new EditorPoint(0, 0);
  private pinchingControlId: string = '';
  private pinchStartControlWidth: number = 0;
  private pinchStartControlHeight: number = 0;
  private pinchStartControlX: number = 0;
  private pinchStartControlY: number = 0;
  private resizingSwipeControlId: string = '';
  private resizingSwipeHandle: string = '';
  private swipeResizeAnchorX: number = 0;
  private swipeResizeAnchorY: number = 0;
  private swipeResizeThickness: number = 0;
  private pendingDirectionalKeyCodes: Array<number> = [];
  private pendingDirectionalKeyLabels: Array<string> = [];
  private draggingMenuButton: boolean = false;
  private menuDragStartWindowX: number = 0;
  private menuDragStartWindowY: number = 0;
  private menuButtonDragStartX: number = 0;
  private menuButtonDragStartY: number = 0;
  private menuButtonMoved: boolean = false;
  private editorWindow: window.Window | null = null;
  private backgroundImageMetricsRequestId: number = 0;
  private executionTouchSequence: number = 0;
  private executionTargets: Array<ExecutionTouchTarget> = [];
  private executionFeedbackTimeoutId: number = -1;
  private dispatchedExecutionActive: boolean = false;
  private dispatchedExecutionControlId: string = '';
  private dispatchedExecutionXUnits: number = 0;
  private dispatchedExecutionYUnits: number = 0;
  @State connectedDeviceName: string = '未连接设备';
  @State connectedDeviceId: string = '';
  @State nativeInputState: NativeInputRuntimeState = nativeInputRuntimeService.getState();
  @State nativeInputDeviceCount: number = 0;
  @State nativeInputEventCount: number = 0;
  @State nativeInputLastEvent: string = '等待连接设备后启动原生输入监控';
  @State savedLayoutCount: number = 0;
  @State currentLayoutName: string = '默认布局';
  @State currentLayoutBackgroundImageUri: string = '';
  @State currentLayoutControlCount: number = 0;
  @State currentLayoutHasBackground: boolean = false;
  @State layoutControls: Array<LayoutControlItem> = [];
  @State selectedControlId: string = '';
  @State controlEditorMessage: string = '先导入被控游戏截图，再添加控件。';
  @State bindingCaptureState: string = 'idle';
  @State bindingCaptureHint: string = '选中控件后，未绑定控件会自动监听输入。';
  @State bindingCaptureTargetId: string = '';
  @State menuExpanded: boolean = false;
  @State controlLibraryExpanded: boolean = false;
  @State canvasWidthPx: number = 1;
  @State canvasHeightPx: number = 1;
  @State backgroundImageWidthPx: number = 0;
  @State backgroundImageHeightPx: number = 0;
  @State viewportWidthPx: number = 0;
  @State viewportHeightPx: number = 0;
  @State menuButtonX: number = MENU_EDGE_MARGIN;
  @State menuButtonY: number = MENU_EDGE_MARGIN;
  @State menuButtonInitialized: boolean = false;
  @State interactionMode: string = EXECUTION_MODE_EDIT;
  @State executionStatusText: string = '保存布局后进入执行模式。';
  @State executionActiveControlId: string = '';
  @State executionTouchFeedbackVisible: boolean = false;
  @State executionTouchFeedbackDimmed: boolean = false;
  @State executionTouchFeedbackXUnits: number = 0;
  @State executionTouchFeedbackYUnits: number = 0;

  aboutToAppear(): void {
    this.menuExpanded = false;
    this.controlLibraryExpanded = false;
    this.menuButtonInitialized = false;
    this.configureEditorWindow();
    this.initializeLayoutRepository();
    this.refreshConnectionSummary(hidService.getState(), hidService.getDevices());
    nativeInputRuntimeService.setListener((eventsJson: string) => {
      this.handleNativeInputEvents(eventsJson);
    });
    this.ensureNativeInputRuntime();
    hidService.setStateListener((state: HidDebugState, devices: Array<RemoteDeviceItem>) => {
      this.refreshConnectionSummary(state, devices);
      this.ensureNativeInputRuntime();
    });
  }

  aboutToDisappear(): void {
    hidService.setStateListener(null);
    nativeInputRuntimeService.setListener(null);
    nativeInputRuntimeService.stop();
    this.resetExecutionState(true);
    this.draggingControlId = '';
    this.pinchingControlId = '';
    this.resizingSwipeControlId = '';
    this.resetPendingDirectionalBinding();
    this.draggingMenuButton = false;
    this.restoreEditorWindow();
  }

  private async configureEditorWindow(): Promise<void> {
    try {
      const currentWindow = await window.getLastWindow(this.hostContext);
      this.editorWindow = currentWindow;
      await currentWindow.setPreferredOrientation(window.Orientation.LANDSCAPE);
      await currentWindow.setWindowLayoutFullScreen(true);
      await currentWindow.setWindowSystemBarEnable([]);
      await currentWindow.setSpecificSystemBarEnabled('navigationIndicator', false, false);
    } catch (error) {
      const errorObject = error as Object;
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'configure editor window failed: %{public}s', JSON.stringify(errorObject));
    }
  }

  private restoreEditorWindow(): void {
    const currentWindow = this.editorWindow;
    this.editorWindow = null;
    if (currentWindow === null) {
      return;
    }

    void (async () => {
      try {
        await currentWindow.setSpecificSystemBarEnabled('navigationIndicator', true, false);
      } catch (_) {
      }

      try {
        await currentWindow.setWindowSystemBarEnable(['status', 'navigation']);
      } catch (_) {
      }

      try {
        await currentWindow.setWindowLayoutFullScreen(false);
        await currentWindow.setPreferredOrientation(window.Orientation.PORTRAIT);
      } catch (error) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'restore editor window failed: %{public}s', JSON.stringify(error as Object));
      }
    })();
  }

  private async initializeLayoutRepository(): Promise<void> {
    try {
      await layoutRepository.initialize(this.hostContext);
      this.refreshLayoutSummary();
    } catch (_) {
      this.savedLayoutCount = 0;
      this.currentLayoutName = '布局仓库初始化失败';
      this.currentLayoutBackgroundImageUri = '';
      this.currentLayoutControlCount = 0;
      this.currentLayoutHasBackground = false;
      this.resetBackgroundImageMetrics();
    }
  }

  private ensureNativeInputRuntime(): void {
    const hidState = hidService.getState();
    if (hidState.connected) {
      nativeInputRuntimeService.start();
    } else {
      nativeInputRuntimeService.stop();
      if (this.nativeInputEventCount === 0) {
        this.nativeInputLastEvent = '等待连接设备后启动原生输入监控';
      }
    }
    this.refreshNativeInputState();
  }

  private refreshNativeInputState(): void {
    this.nativeInputState = nativeInputRuntimeService.getState();
    this.nativeInputDeviceCount = this.parseJsonArray(nativeInputRuntimeService.getConnectedGamepadsJson()).length;
  }

  private refreshLayoutSummary(): void {
    const layouts = layoutRepository.listLayouts();
    const currentLayout = layoutRepository.getCurrentLayout();
    this.savedLayoutCount = layouts.length;
    if (currentLayout === null) {
      this.currentLayoutName = '未选择布局';
      this.currentLayoutBackgroundImageUri = '';
      this.currentLayoutControlCount = 0;
      this.currentLayoutHasBackground = false;
      this.resetBackgroundImageMetrics();
      this.layoutControls = [];
      this.selectedControlId = '';
      this.updateControlEditorMessage();
      return;
    }

    this.applyLayout(currentLayout);
  }

  private applyLayout(layout: InputLayout): void {
    this.currentLayoutName = layout.name;
    this.currentLayoutBackgroundImageUri = layout.backgroundImageUri;
    this.currentLayoutHasBackground = layout.backgroundImageUri.length > 0;
    this.layoutControls = layout.controls.map((control: LayoutControlItem) => this.normalizeEditorControl(control));
    this.currentLayoutControlCount = this.layoutControls.length;
    if (this.currentLayoutHasBackground) {
      void this.syncBackgroundImageMetrics(layout.backgroundImageUri);
    } else {
      this.resetBackgroundImageMetrics();
    }
    this.syncSelectedControl();
    this.updateControlEditorMessage();
  }

  private normalizeEditorControl(control: LayoutControlItem): LayoutControlItem {
    let normalizedControl = control.clone();
    normalizedControl.inputKind = this.normalizeControlType(normalizedControl.inputKind, normalizedControl.inputCode);
    normalizedControl.inputCode = normalizedControl.inputCode.trim();
    normalizedControl.actionType = this.getActionTypeForControlType(normalizedControl.inputKind);
    if (normalizedControl.label.trim().length === 0) {
      normalizedControl.label = this.getControlTypeLabel(normalizedControl.inputKind);
    }
    return this.normalizeControlGeometry(normalizedControl);
  }

  private normalizeControlGeometry(control: LayoutControlItem): LayoutControlItem {
    let normalizedControl = control.clone();
    if (this.isRoundControlType(normalizedControl.inputKind)) {
      const nextSize = Math.max(normalizedControl.width, this.toRoundControlWidthUnits(normalizedControl.height));
      const size = clampEditorValue(
        nextSize > 0 ? nextSize : CONTROL_DEFAULT_SIZE,
        ROUND_CONTROL_MIN_SIZE,
        CONTROL_MAX_SIZE
      );
      normalizedControl.width = size;
      normalizedControl.height = this.toRoundControlHeightUnits(size);
    } else if (this.isLookControlType(normalizedControl.inputKind)) {
      const nextWidth = Math.max(normalizedControl.width, normalizedControl.height);
      normalizedControl.width = clampEditorValue(
        nextWidth > 0 ? nextWidth : LOOK_CONTROL_DEFAULT_SIZE,
        LOOK_CONTROL_MIN_WIDTH,
        CONTROL_MAX_SIZE
      );
      normalizedControl.height = clampEditorValue(
        Math.round(normalizedControl.width / LOOK_CONTROL_ASPECT_RATIO),
        LOOK_CONTROL_MIN_HEIGHT,
        CONTROL_MAX_SIZE
      );
    } else if (normalizedControl.inputKind === CONTROL_TYPE_SWIPE) {
      const nextHeight = normalizedControl.height <= 0 ? CONTROL_SWIPE_DEFAULT_HEIGHT : normalizedControl.height;
      normalizedControl.height = clampEditorValue(nextHeight, CONTROL_SWIPE_MIN_THICKNESS, CONTROL_SWIPE_MAX_THICKNESS);
      normalizedControl = this.normalizeSwipeGeometry(normalizedControl);
    } else {
      normalizedControl.width = clampEditorValue(normalizedControl.width, CONTROL_MIN_SIZE, CONTROL_MAX_SIZE);
      normalizedControl.height = clampEditorValue(normalizedControl.height, CONTROL_MIN_SIZE, CONTROL_MAX_SIZE);
    }

    normalizedControl.x = Math.round(normalizedControl.x);
    normalizedControl.y = Math.round(normalizedControl.y);
    return normalizedControl;
  }

  private isMoveControlType(controlType: string): boolean {
    return controlType === CONTROL_TYPE_STICK_MOVE || controlType === CONTROL_TYPE_KEYBOARD_MOVE;
  }

  private isLookControlType(controlType: string): boolean {
    return controlType === CONTROL_TYPE_STICK_LOOK || controlType === CONTROL_TYPE_KEYBOARD_LOOK;
  }

  private isRoundControlType(controlType: string): boolean {
    return this.isMoveControlType(controlType) || controlType === CONTROL_TYPE_BUTTON;
  }

  private parseControlPayload(control: LayoutControlItem): ControlPayload {
    const payload = new ControlPayload();
    if (control.payloadJson.trim().length === 0) {
      return payload;
    }

    try {
      const rawPayload = JSON.parse(control.payloadJson) as Object;
      payload.rotation = this.getPayloadNumberField(rawPayload, 'rotation', 0);
      payload.bindingLabel = this.getPayloadStringField(rawPayload, 'bindingLabel');
      payload.bindingSource = this.getPayloadStringField(rawPayload, 'bindingSource');
      payload.bindingRawSource = this.getPayloadStringField(rawPayload, 'bindingRawSource');
      payload.bindingRawCode = this.getPayloadStringField(rawPayload, 'bindingRawCode');
      payload.bindingRawName = this.getPayloadStringField(rawPayload, 'bindingRawName');
      payload.directionalKeyCodes = this.getPayloadStringField(rawPayload, 'directionalKeyCodes');
      payload.directionalKeyLabels = this.getPayloadStringField(rawPayload, 'directionalKeyLabels');
      payload.coordinateSpace = this.getPayloadStringField(rawPayload, 'coordinateSpace');
      payload.swipeStartX = this.getPayloadNumberField(rawPayload, 'swipeStartX', -1);
      payload.swipeStartY = this.getPayloadNumberField(rawPayload, 'swipeStartY', -1);
      payload.swipeEndX = this.getPayloadNumberField(rawPayload, 'swipeEndX', -1);
      payload.swipeEndY = this.getPayloadNumberField(rawPayload, 'swipeEndY', -1);
      return payload;
    } catch (_) {
      return payload;
    }
  }

  private getPayloadNumberField(payload: Object, key: string, defaultValue: number): number {
    const value = Reflect.get(payload, key) as number | string | undefined;
    if (typeof value === 'number') {
      return Number.isFinite(value) ? value : defaultValue;
    }
    if (typeof value === 'string') {
      const parsed = Number.parseFloat(value);
      return Number.isFinite(parsed) ? parsed : defaultValue;
    }
    return defaultValue;
  }

  private getPayloadStringField(payload: Object, key: string): string {
    const value = Reflect.get(payload, key) as string | undefined;
    return typeof value === 'string' ? value : '';
  }

  private withControlPayload(control: LayoutControlItem, mutator: (payload: ControlPayload) => void): LayoutControlItem {
    const nextControl = control.clone();
    const payload = this.parseControlPayload(nextControl);
    mutator(payload);
    nextControl.payloadJson = JSON.stringify(payload);
    return nextControl;
  }

  private getControlCoordinateSpace(control: LayoutControlItem): string {
    const payload = this.parseControlPayload(control);
    return this.getPayloadStringField(payload, 'coordinateSpace');
  }

  private isControlUsingCurrentCoordinateSpace(control: LayoutControlItem): boolean {
    const coordinateSpace = this.getControlCoordinateSpace(control);
    if (coordinateSpace === CONTROL_COORDINATE_SPACE_LEGACY_CANVAS || coordinateSpace.length === 0) {
      return false;
    }
    return coordinateSpace === CONTROL_COORDINATE_SPACE_BACKGROUND;
  }

  private resetBackgroundImageMetrics(): void {
    this.backgroundImageWidthPx = 0;
    this.backgroundImageHeightPx = 0;
  }

  private getBackgroundWidthToHeightRatio(): number {
    if (!this.hasBackgroundImageMetrics()) {
      return 1;
    }
    return this.backgroundImageWidthPx / Math.max(this.backgroundImageHeightPx, 1);
  }

  private toRoundControlHeightUnits(widthUnits: number): number {
    return clampEditorValue(
      Math.round(widthUnits * this.getBackgroundWidthToHeightRatio()),
      ROUND_CONTROL_MIN_SIZE,
      CONTROL_CANVAS_UNITS
    );
  }

  private toRoundControlWidthUnits(heightUnits: number): number {
    return clampEditorValue(
      Math.round(heightUnits / Math.max(this.getBackgroundWidthToHeightRatio(), 0.0001)),
      ROUND_CONTROL_MIN_SIZE,
      CONTROL_CANVAS_UNITS
    );
  }

  private refreshRoundControlGeometryForCurrentBackground(): void {
    if (!this.currentLayoutHasBackground || !this.hasBackgroundImageMetrics() || this.layoutControls.length === 0) {
      return;
    }

    let changed = false;
    const nextControls = this.layoutControls.map((control: LayoutControlItem) => {
      if (!this.isRoundControlType(control.inputKind)) {
        return control.clone();
      }

      const normalizedControl = this.normalizeControlGeometry(control);
      if (normalizedControl.x !== control.x || normalizedControl.y !== control.y || normalizedControl.width !== control.width ||
        normalizedControl.height !== control.height) {
        changed = true;
      }
      return normalizedControl;
    });

    if (!changed) {
      return;
    }

    this.layoutControls = nextControls;
    this.currentLayoutControlCount = nextControls.length;
    this.updateControlEditorMessage();
  }

  private hasBackgroundImageMetrics(): boolean {
    return this.backgroundImageWidthPx > 0 && this.backgroundImageHeightPx > 0;
  }

  private isBackgroundCoordinateFrameReady(): boolean {
    return !this.currentLayoutHasBackground || this.hasBackgroundImageMetrics();
  }

  private getBackgroundContentFrame(): CanvasFrame {
    const canvasWidth = Math.max(this.canvasWidthPx, 1);
    const canvasHeight = Math.max(this.canvasHeightPx, 1);
    if (!this.currentLayoutHasBackground || !this.hasBackgroundImageMetrics()) {
      return new CanvasFrame(0, 0, canvasWidth, canvasHeight);
    }

    const scale = Math.min(canvasWidth / this.backgroundImageWidthPx, canvasHeight / this.backgroundImageHeightPx);
    const width = Math.max(1, this.backgroundImageWidthPx * scale);
    const height = Math.max(1, this.backgroundImageHeightPx * scale);
    return new CanvasFrame((canvasWidth - width) / 2, (canvasHeight - height) / 2, width, height);
  }

  private toLegacyCanvasXValue(units: number): number {
    return clampEditorValue(units, 0, CONTROL_CANVAS_UNITS) / CONTROL_CANVAS_UNITS * Math.max(this.canvasWidthPx, 1);
  }

  private toLegacyCanvasYValue(units: number): number {
    return clampEditorValue(units, 0, CONTROL_CANVAS_UNITS) / CONTROL_CANVAS_UNITS * Math.max(this.canvasHeightPx, 1);
  }

  private toLegacyCanvasWidthValue(units: number): number {
    return clampEditorValue(units, 0, CONTROL_CANVAS_UNITS) / CONTROL_CANVAS_UNITS * Math.max(this.canvasWidthPx, 1);
  }

  private toLegacyCanvasHeightValue(units: number): number {
    return clampEditorValue(units, 0, CONTROL_CANVAS_UNITS) / CONTROL_CANVAS_UNITS * Math.max(this.canvasHeightPx, 1);
  }

  private toBackgroundXUnitsFromCanvasPixels(canvasX: number): number {
    const frame = this.getBackgroundContentFrame();
    return Math.round((canvasX - frame.x) / Math.max(frame.width, 1) * CONTROL_CANVAS_UNITS);
  }

  private toBackgroundYUnitsFromCanvasPixels(canvasY: number): number {
    const frame = this.getBackgroundContentFrame();
    return Math.round((canvasY - frame.y) / Math.max(frame.height, 1) * CONTROL_CANVAS_UNITS);
  }

  private rebaseLegacyScreenXUnits(units: number): number {
    const canvasX = units / CONTROL_CANVAS_UNITS * Math.max(this.canvasWidthPx, 1);
    return this.toBackgroundXUnitsFromCanvasPixels(canvasX);
  }

  private rebaseLegacyScreenYUnits(units: number): number {
    const canvasY = units / CONTROL_CANVAS_UNITS * Math.max(this.canvasHeightPx, 1);
    return this.toBackgroundYUnitsFromCanvasPixels(canvasY);
  }

  private rebaseControlToCurrentCoordinateSpace(control: LayoutControlItem): LayoutControlItem {
    let nextControl = control.clone();
    nextControl.x = this.rebaseLegacyScreenXUnits(control.x);
    nextControl.y = this.rebaseLegacyScreenYUnits(control.y);
    nextControl = this.withControlPayload(nextControl, (payload: ControlPayload) => {
      if (payload.swipeStartX >= 0) {
        payload.swipeStartX = this.rebaseLegacyScreenXUnits(payload.swipeStartX);
      }
      if (payload.swipeStartY >= 0) {
        payload.swipeStartY = this.rebaseLegacyScreenYUnits(payload.swipeStartY);
      }
      if (payload.swipeEndX >= 0) {
        payload.swipeEndX = this.rebaseLegacyScreenXUnits(payload.swipeEndX);
      }
      if (payload.swipeEndY >= 0) {
        payload.swipeEndY = this.rebaseLegacyScreenYUnits(payload.swipeEndY);
      }
      payload.coordinateSpace = CONTROL_COORDINATE_SPACE_BACKGROUND;
    });
    return this.normalizeControlGeometry(nextControl);
  }

  private rebaseCurrentLayoutCoordinatesIfNeeded(): void {
    if (!this.currentLayoutHasBackground || !this.hasBackgroundImageMetrics() || this.layoutControls.length === 0) {
      return;
    }

    let changed = false;
    const nextControls = this.layoutControls.map((control: LayoutControlItem) => {
      if (this.isControlUsingCurrentCoordinateSpace(control)) {
        return control.clone();
      }

      changed = true;
      return this.rebaseControlToCurrentCoordinateSpace(control);
    });

    if (!changed) {
      return;
    }

    this.layoutControls = nextControls.map((control: LayoutControlItem) => control.clone());
    this.currentLayoutControlCount = this.layoutControls.length;
    const nextSelectedControlId = this.selectedControlId;
    void this.persistRebasedCurrentLayout(nextControls, nextSelectedControlId);
  }

  private async persistRebasedCurrentLayout(controls: Array<LayoutControlItem>, nextSelectedControlId: string): Promise<void> {
    const currentLayout = layoutRepository.getCurrentLayout();
    if (currentLayout === null) {
      return;
    }

    try {
      const updatedLayout = currentLayout.clone();
      updatedLayout.controls = controls.map((control: LayoutControlItem) => control.clone());
      updatedLayout.updatedAt = Date.now();
      await layoutRepository.saveLayout(updatedLayout);
      this.applyLayout(updatedLayout);
      this.selectedControlId = nextSelectedControlId;
      this.syncSelectedControl();
      this.refreshLayoutSummary();
      this.updateControlEditorMessage();
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'rebase screenshot-origin coordinates failed: %{public}s', JSON.stringify(error as Object));
    }
  }

  private async syncBackgroundImageMetrics(backgroundUri: string): Promise<void> {
    const normalizedUri = backgroundUri.trim();
    const requestId = this.backgroundImageMetricsRequestId + 1;
    this.backgroundImageMetricsRequestId = requestId;
    if (normalizedUri.length === 0) {
      this.resetBackgroundImageMetrics();
      return;
    }

    let imageSource: image.ImageSource | null = null;
    let backgroundFile: fs.File | null = null;
    try {
      backgroundFile = await fs.open(normalizedUri, fs.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(backgroundFile.fd);
      const imageInfo = await imageSource.getImageInfo();
      if (requestId !== this.backgroundImageMetricsRequestId || normalizedUri !== this.currentLayoutBackgroundImageUri) {
        return;
      }

      this.backgroundImageWidthPx = Math.max(imageInfo.size.width, 0);
      this.backgroundImageHeightPx = Math.max(imageInfo.size.height, 0);
      this.rebaseCurrentLayoutCoordinatesIfNeeded();
      this.refreshRoundControlGeometryForCurrentBackground();
      this.updateControlEditorMessage();
    } catch (error) {
      if (requestId === this.backgroundImageMetricsRequestId) {
        this.resetBackgroundImageMetrics();
      }
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'read background image metrics failed: %{public}s', JSON.stringify(error as Object));
    } finally {
      if (imageSource !== null) {
        try {
          await imageSource.release();
        } catch (_) {
        }
      }
      if (backgroundFile !== null) {
        try {
          await fs.close(backgroundFile);
        } catch (_) {
        }
      }
    }
  }

  private normalizeRotationAngle(angle: number): number {
    let nextAngle = angle % 360;
    if (nextAngle > 180) {
      nextAngle -= 360;
    }
    if (nextAngle < -180) {
      nextAngle += 360;
    }
    return Math.round(nextAngle * 10) / 10;
  }

  private getControlRotationAngle(control: LayoutControlItem): number {
    const payload = this.parseControlPayload(control);
    return this.normalizeRotationAngle(this.getPayloadNumberField(payload, 'rotation', 0));
  }

  private setControlRotationAngle(control: LayoutControlItem, angle: number): LayoutControlItem {
    return this.withControlPayload(control, (payload: ControlPayload) => {
      payload.rotation = this.normalizeRotationAngle(angle);
    });
  }

  private hasSwipeHandlePositions(control: LayoutControlItem): boolean {
    const payload = this.parseControlPayload(control);
    return payload.swipeStartX >= 0 && payload.swipeStartY >= 0 && payload.swipeEndX >= 0 && payload.swipeEndY >= 0;
  }

  private createSwipeHandlePositions(startX: number, startY: number, endX: number, endY: number): SwipeHandlePositions {
    return new SwipeHandlePositions(new EditorPoint(startX, startY), new EditorPoint(endX, endY));
  }

  private getSwipeHandlePositionsFromGeometry(control: LayoutControlItem): SwipeHandlePositions {
    const centerX = this.getControlCenterX(control);
    const centerY = this.getControlCenterY(control);
    const radians = this.getControlRotationAngle(control) * Math.PI / 180;
    const handleOffset = Math.max(0, control.width / 2 - CONTROL_SWIPE_HANDLE_SIZE / 2);
    const deltaX = Math.cos(radians) * handleOffset;
    const deltaY = Math.sin(radians) * handleOffset;
    return this.createSwipeHandlePositions(centerX - deltaX, centerY - deltaY, centerX + deltaX, centerY + deltaY);
  }

  private getSwipeHandlePositions(control: LayoutControlItem): SwipeHandlePositions {
    if (this.hasSwipeHandlePositions(control)) {
      const payload = this.parseControlPayload(control);
      return this.createSwipeHandlePositions(payload.swipeStartX, payload.swipeStartY, payload.swipeEndX, payload.swipeEndY);
    }
    return this.getSwipeHandlePositionsFromGeometry(control);
  }

  private getSwipeHandleDistance(positions: SwipeHandlePositions): number {
    const deltaX = positions.end.x - positions.start.x;
    const deltaY = positions.end.y - positions.start.y;
    return Math.sqrt(deltaX * deltaX + deltaY * deltaY);
  }

  private clampSwipeMovingPointWithFixedHandle(fixedPoint: EditorPoint, movingPoint: EditorPoint, fixedHandle: string,
    thickness: number): EditorPoint {
    const minDistance = CONTROL_SWIPE_MIN_LENGTH - CONTROL_SWIPE_HANDLE_SIZE;
    const maxDistance = CONTROL_SWIPE_MAX_LENGTH - CONTROL_SWIPE_HANDLE_SIZE;
    let nextMovingPoint = movingPoint.clone();
    for (let attempt = 0; attempt < 4; attempt += 1) {
      let deltaX = nextMovingPoint.x - fixedPoint.x;
      let deltaY = nextMovingPoint.y - fixedPoint.y;
      let distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
      if (distance < 1) {
        nextMovingPoint = fixedHandle === 'start'
          ? new EditorPoint(fixedPoint.x + minDistance, fixedPoint.y)
          : new EditorPoint(fixedPoint.x - minDistance, fixedPoint.y);
        deltaX = nextMovingPoint.x - fixedPoint.x;
        deltaY = nextMovingPoint.y - fixedPoint.y;
        distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
      }

      const targetDistance = clampEditorValue(Math.round(distance), minDistance, maxDistance);
      if (Math.abs(targetDistance - distance) > 0.01) {
        const scale = targetDistance / distance;
        nextMovingPoint = new EditorPoint(fixedPoint.x + deltaX * scale, fixedPoint.y + deltaY * scale);
        deltaX = nextMovingPoint.x - fixedPoint.x;
        deltaY = nextMovingPoint.y - fixedPoint.y;
        distance = targetDistance;
      }

      const totalWidth = distance + CONTROL_SWIPE_HANDLE_SIZE;
      const centerX = (fixedPoint.x + nextMovingPoint.x) / 2;
      const centerY = (fixedPoint.y + nextMovingPoint.y) / 2;
      const left = centerX - totalWidth / 2;
      const top = centerY - thickness / 2;
      let shiftX = 0;
      let shiftY = 0;
      if (left < 0) {
        shiftX = -left;
      } else if (left + totalWidth > CONTROL_CANVAS_UNITS) {
        shiftX = CONTROL_CANVAS_UNITS - (left + totalWidth);
      }
      if (top < 0) {
        shiftY = -top;
      } else if (top + thickness > CONTROL_CANVAS_UNITS) {
        shiftY = CONTROL_CANVAS_UNITS - (top + thickness);
      }
      if (shiftX === 0 && shiftY === 0) {
        break;
      }

      nextMovingPoint = new EditorPoint(
        clampEditorValue(nextMovingPoint.x + shiftX * 2, 0, CONTROL_CANVAS_UNITS),
        clampEditorValue(nextMovingPoint.y + shiftY * 2, 0, CONTROL_CANVAS_UNITS)
      );
    }
    return nextMovingPoint;
  }

  private clampSwipeHandlePositions(positions: SwipeHandlePositions, thickness: number, fixedHandle: string = ''): SwipeHandlePositions {
    let start = positions.start.clone();
    let end = positions.end.clone();
    if (fixedHandle === 'start' || fixedHandle === 'end') {
      const fixedPoint = fixedHandle === 'start' ? start.clone() : end.clone();
      const adjustedMovingPoint = fixedHandle === 'start'
        ? this.clampSwipeMovingPointWithFixedHandle(fixedPoint, end.clone(), fixedHandle, thickness)
        : this.clampSwipeMovingPointWithFixedHandle(fixedPoint, start.clone(), fixedHandle, thickness);
      return fixedHandle === 'start'
        ? new SwipeHandlePositions(fixedPoint, adjustedMovingPoint)
        : new SwipeHandlePositions(adjustedMovingPoint, fixedPoint);
    }

    let deltaX = end.x - start.x;
    let deltaY = end.y - start.y;
    let distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    const minDistance = CONTROL_SWIPE_MIN_LENGTH - CONTROL_SWIPE_HANDLE_SIZE;
    const maxDistance = CONTROL_SWIPE_MAX_LENGTH - CONTROL_SWIPE_HANDLE_SIZE;
    if (distance < 1) {
      end = new EditorPoint(start.x + minDistance, start.y);
      deltaX = minDistance;
      deltaY = 0;
      distance = minDistance;
    }

    const targetDistance = clampEditorValue(Math.round(distance), minDistance, maxDistance);
    if (Math.abs(targetDistance - distance) > 0.01) {
      const centerX = (start.x + end.x) / 2;
      const centerY = (start.y + end.y) / 2;
      const scale = targetDistance / distance;
      const halfDeltaX = deltaX * scale / 2;
      const halfDeltaY = deltaY * scale / 2;
      start = new EditorPoint(centerX - halfDeltaX, centerY - halfDeltaY);
      end = new EditorPoint(centerX + halfDeltaX, centerY + halfDeltaY);
      deltaX = end.x - start.x;
      deltaY = end.y - start.y;
      distance = targetDistance;
    }

    const totalWidth = distance + CONTROL_SWIPE_HANDLE_SIZE;
    const centerX = (start.x + end.x) / 2;
    const centerY = (start.y + end.y) / 2;
    const left = centerX - totalWidth / 2;
    const top = centerY - thickness / 2;
    let shiftX = 0;
    let shiftY = 0;
    if (left < 0) {
      shiftX = -left;
    } else if (left + totalWidth > CONTROL_CANVAS_UNITS) {
      shiftX = CONTROL_CANVAS_UNITS - (left + totalWidth);
    }
    if (top < 0) {
      shiftY = -top;
    } else if (top + thickness > CONTROL_CANVAS_UNITS) {
      shiftY = CONTROL_CANVAS_UNITS - (top + thickness);
    }
    if (shiftX !== 0 || shiftY !== 0) {
      start = new EditorPoint(start.x + shiftX, start.y + shiftY);
      end = new EditorPoint(end.x + shiftX, end.y + shiftY);
    }
    return new SwipeHandlePositions(start, end);
  }

  private writeSwipeHandlePositions(control: LayoutControlItem, positions: SwipeHandlePositions): LayoutControlItem {
    return this.withControlPayload(control, (payload: ControlPayload) => {
      payload.swipeStartX = Math.round(positions.start.x);
      payload.swipeStartY = Math.round(positions.start.y);
      payload.swipeEndX = Math.round(positions.end.x);
      payload.swipeEndY = Math.round(positions.end.y);
    });
  }

  private applySwipeHandlePositions(control: LayoutControlItem, positions: SwipeHandlePositions, fixedHandle: string = ''): LayoutControlItem {
    const thickness = clampEditorValue(control.height <= 0 ? CONTROL_SWIPE_DEFAULT_HEIGHT : control.height,
      CONTROL_SWIPE_MIN_THICKNESS, CONTROL_SWIPE_MAX_THICKNESS);
    const normalizedPositions = this.clampSwipeHandlePositions(positions, thickness, fixedHandle);
    const deltaX = normalizedPositions.end.x - normalizedPositions.start.x;
    const deltaY = normalizedPositions.end.y - normalizedPositions.start.y;
    const distance = this.getSwipeHandleDistance(normalizedPositions);
    let nextControl = control.clone();
    nextControl.width = Math.round(distance + CONTROL_SWIPE_HANDLE_SIZE);
    nextControl.height = thickness;
    const centerX = (normalizedPositions.start.x + normalizedPositions.end.x) / 2;
    const centerY = (normalizedPositions.start.y + normalizedPositions.end.y) / 2;
    nextControl.x = Math.round(centerX - nextControl.width / 2);
    nextControl.y = Math.round(centerY - nextControl.height / 2);
    nextControl = this.setControlRotationAngle(nextControl, Math.atan2(deltaY, deltaX) * 180 / Math.PI);
    nextControl = this.writeSwipeHandlePositions(nextControl, normalizedPositions);
    return nextControl;
  }

  private normalizeSwipeGeometry(control: LayoutControlItem): LayoutControlItem {
    return this.applySwipeHandlePositions(control, this.getSwipeHandlePositions(control));
  }

  private getStoredBindingLabel(control: LayoutControlItem): string {
    const payload = this.parseControlPayload(control);
    return this.formatBindingDisplayName(this.getPayloadStringField(payload, 'bindingLabel'));
  }

  private hasControlBinding(control: LayoutControlItem): boolean {
    return control.inputCode.trim().length > 0 || this.getStoredBindingLabel(control).length > 0;
  }

  private getUnboundBindingHint(control: LayoutControlItem): string {
    switch (control.inputKind) {
      case CONTROL_TYPE_BUTTON:
        return '未绑定，按下按键绑定。';
      case CONTROL_TYPE_STICK_MOVE:
      case CONTROL_TYPE_STICK_LOOK:
        return '未绑定，晃动摇杆绑定。';
      case CONTROL_TYPE_KEYBOARD_MOVE:
      case CONTROL_TYPE_KEYBOARD_LOOK:
        return '未绑定，连按四键绑定。';
      case CONTROL_TYPE_SWIPE:
        return '未绑定，推动摇杆或扳机绑定。';
      default:
        return '未绑定，输入操作完成绑定。';
    }
  }

  private isDirectionalKeyboardControlType(controlType: string): boolean {
    return controlType === CONTROL_TYPE_KEYBOARD_MOVE || controlType === CONTROL_TYPE_KEYBOARD_LOOK;
  }

  private resetPendingDirectionalBinding(): void {
    this.pendingDirectionalKeyCodes = [];
    this.pendingDirectionalKeyLabels = [];
  }

  private hasPendingDirectionalKeyCode(keyCode: number): boolean {
    return this.pendingDirectionalKeyCodes.some((recordedKeyCode: number) => recordedKeyCode === keyCode);
  }

  private getDirectionalBindingToken(keyText: string, keyCode: number): string {
    const formattedKeyText = this.formatBindingDisplayName(keyText);
    if (formattedKeyText.length > 0) {
      return formattedKeyText;
    }
    return `${keyCode}`;
  }

  private normalizeDirectionalDisplayToken(rawToken: string): string {
    const trimmedToken = rawToken.trim();
    switch (trimmedToken) {
      case '方向上':
        return '方向上';
      case '方向下':
        return '方向下';
      case '方向左':
        return '方向左';
      case '方向右':
        return '方向右';
      default:
        break;
    }

    const normalizedToken = trimmedToken.replace(/[_\s-]+/g, '').toUpperCase();
    switch (normalizedToken) {
      case 'UP':
      case 'ARROWUP':
      case 'DPADUP':
        return '方向上';
      case 'DOWN':
      case 'ARROWDOWN':
      case 'DPADDOWN':
        return '方向下';
      case 'LEFT':
      case 'ARROWLEFT':
      case 'DPADLEFT':
        return '方向左';
      case 'RIGHT':
      case 'ARROWRIGHT':
      case 'DPADRIGHT':
        return '方向右';
      default:
        return '';
    }
  }

  private buildDirectionalBindingLabel(keyLabels: Array<string>): string {
    return DIRECTIONAL_BINDING_ORDER_LABELS.map((directionLabel: string, index: number) => {
      const keyLabel = index < keyLabels.length ? keyLabels[index] : '?';
      return `${directionLabel}:${keyLabel}`;
    }).join(' ');
  }

  private updateDirectionalBindingHint(control: LayoutControlItem): void {
    if (!this.isDirectionalKeyboardControlType(control.inputKind)) {
      return;
    }

    if (this.pendingDirectionalKeyLabels.length === 0) {
      this.bindingCaptureHint = '未绑定，连按四键绑定（依次上、左、下、右）。';
      return;
    }

    const capturedLabels = DIRECTIONAL_BINDING_ORDER_LABELS.slice(0, this.pendingDirectionalKeyLabels.length)
      .map((directionLabel: string, index: number) => `${directionLabel}:${this.pendingDirectionalKeyLabels[index]}`)
      .join(' ');
    const remainingLabels = DIRECTIONAL_BINDING_ORDER_LABELS.slice(this.pendingDirectionalKeyLabels.length).join('、');
    if (remainingLabels.length > 0) {
      this.bindingCaptureHint = `已记录 ${capturedLabels}，继续按 ${remainingLabels}。`;
      return;
    }
    this.bindingCaptureHint = `已记录 ${capturedLabels}，正在完成绑定。`;
  }

  private stripBindingNamePrefixes(rawName: string): string {
    let normalizedName = rawName.trim().replace(/-/g, '_').toUpperCase();
    const prefixes = ['KEYCODE_BUTTON_', 'KEYCODE_GAMEPAD_', 'KEYCODE_', 'GAMEPAD_BUTTON_', 'GAMEPAD_', 'BUTTON_'];
    let updated = true;
    while (updated) {
      updated = false;
      for (const prefix of prefixes) {
        if (normalizedName.startsWith(prefix)) {
          normalizedName = normalizedName.substring(prefix.length);
          updated = true;
        }
      }
    }
    return normalizedName;
  }

  private toCompactBindingToken(token: string): string {
    const normalizedToken = token.trim().replace(/[_\s-]+/g, '').toUpperCase();
    switch (normalizedToken) {
      case 'LEFTSHOULDER':
      case 'L1':
        return 'L1';
      case 'RIGHTSHOULDER':
      case 'R1':
        return 'R1';
      case 'LEFTTRIGGER':
      case 'L2':
        return 'L2';
      case 'RIGHTTRIGGER':
      case 'R2':
        return 'R2';
      case 'LEFTSTICK':
      case 'LEFTTHUMBSTICK':
      case 'THUMBL':
      case 'L3':
        return 'L3';
      case 'RIGHTSTICK':
      case 'RIGHTTHUMBSTICK':
      case 'THUMBR':
      case 'R3':
        return 'R3';
      case 'DPADUP':
        return 'UP';
      case 'DPADDOWN':
        return 'DOWN';
      case 'DPADLEFT':
        return 'LEFT';
      case 'DPADRIGHT':
        return 'RIGHT';
      case 'MENU':
      case 'START':
        return 'START';
      case 'SELECT':
      case 'BACK':
        return 'SELECT';
      default:
        return token;
    }
  }

  private formatBindingDisplayToken(rawToken: string): string {
    const trimmedToken = rawToken.trim();
    if (trimmedToken.length === 0) {
      return '';
    }
    const directionalLabel = this.normalizeDirectionalDisplayToken(trimmedToken);
    if (directionalLabel.length > 0) {
      return directionalLabel;
    }
    if (/.*[\u4E00-\u9FFF].*/.test(trimmedToken)) {
      return trimmedToken;
    }

    const compactToken = this.toCompactBindingToken(this.stripBindingNamePrefixes(trimmedToken));
    const compactDirectionalLabel = this.normalizeDirectionalDisplayToken(compactToken);
    if (compactDirectionalLabel.length > 0) {
      return compactDirectionalLabel;
    }
    if (/^[A-Z0-9]+$/.test(compactToken)) {
      return compactToken;
    }
    return compactToken.replace(/_/g, ' ');
  }

  private formatBindingDisplayName(rawName: string): string {
    const trimmedName = rawName.trim();
    if (trimmedName.length === 0) {
      return '';
    }

    const normalizedTokens = trimmedName.split(/\s+/)
      .map((token: string) => this.formatBindingDisplayToken(token))
      .filter((token: string) => token.length > 0);
    return normalizedTokens.join(' ');
  }

  private buildRawBindingCode(rawSource: string, rawCode: string): string {
    const normalizedSource = rawSource.trim();
    const normalizedCode = rawCode.trim();
    if (normalizedSource.length === 0 || normalizedCode.length === 0) {
      return '';
    }
    return `${normalizedSource}:${normalizedCode}`;
  }

  private parseRawCodeNumber(rawCode: string): number {
    const parsedCode = Number.parseInt(rawCode.trim(), 10);
    return Number.isNaN(parsedCode) ? -1 : parsedCode;
  }

  private getGamepadButtonDisplayLabelByRawCode(rawCode: string): string {
    switch (this.parseRawCodeNumber(rawCode)) {
      case RAW_KEYCODE_BUTTON_A:
        return '按钮A';
      case RAW_KEYCODE_BUTTON_B:
        return '按钮B';
      case RAW_KEYCODE_BUTTON_X:
        return '按钮X';
      case RAW_KEYCODE_BUTTON_Y:
        return '按钮Y';
      case RAW_KEYCODE_BUTTON_L1:
        return 'L1';
      case RAW_KEYCODE_BUTTON_R1:
        return 'R1';
      case RAW_KEYCODE_BUTTON_L2:
        return 'L2';
      case RAW_KEYCODE_BUTTON_R2:
        return 'R2';
      case RAW_KEYCODE_BUTTON_SELECT:
        return 'SELECT';
      case RAW_KEYCODE_BUTTON_START:
        return 'START';
      case RAW_KEYCODE_BUTTON_MODE:
        return 'MODE';
      case RAW_KEYCODE_BUTTON_L3:
        return 'L3';
      case RAW_KEYCODE_BUTTON_R3:
        return 'R3';
      case RAW_KEYCODE_DPAD_UP:
        return '方向上';
      case RAW_KEYCODE_DPAD_DOWN:
        return '方向下';
      case RAW_KEYCODE_DPAD_LEFT:
        return '方向左';
      case RAW_KEYCODE_DPAD_RIGHT:
        return '方向右';
      default:
        return '';
    }
  }

  private getGamepadButtonDisplayLabel(rawCode: string, rawName: string): string {
    const labelFromCode = this.getGamepadButtonDisplayLabelByRawCode(rawCode);
    if (labelFromCode.length > 0) {
      return labelFromCode;
    }

    const labelFromName = this.formatBindingDisplayName(rawName);
    if (labelFromName.length > 0) {
      return labelFromName;
    }

    const normalizedCode = rawCode.trim();
    return normalizedCode.length > 0 ? `按钮 ${normalizedCode}` : '按钮';
  }

  private getKeyEventButtonDisplayLabel(keyCode: number, keyText: string): string {
    const labelFromCode = this.getGamepadButtonDisplayLabelByRawCode(`${keyCode}`);
    if (labelFromCode.length > 0) {
      return labelFromCode;
    }

    const labelFromText = this.formatBindingDisplayName(keyText);
    if (labelFromText.length > 0) {
      return labelFromText;
    }
    return `按键 ${keyCode}`;
  }

  private getGamepadAxisDisplayLabel(rawCode: string): string {
    switch (rawCode.trim().toLowerCase()) {
      case 'left-thumbstick':
        return '左摇杆';
      case 'right-thumbstick':
        return '右摇杆';
      case 'left-trigger':
        return '左扳机';
      case 'right-trigger':
        return '右扳机';
      case 'left-stick:x':
        return '左摇杆 X 轴';
      case 'left-stick:y':
        return '左摇杆 Y 轴';
      case 'right-stick:x':
        return '右摇杆 X 轴';
      case 'right-stick:y':
        return '右摇杆 Y 轴';
      default:
        return '';
    }
  }

  private normalizeControlType(inputKind: string, _inputCode: string): string {
    switch (inputKind) {
      case CONTROL_TYPE_STICK_MOVE:
      case CONTROL_TYPE_STICK_LOOK:
      case CONTROL_TYPE_KEYBOARD_MOVE:
      case CONTROL_TYPE_KEYBOARD_LOOK:
      case CONTROL_TYPE_BUTTON:
      case CONTROL_TYPE_SWIPE:
        return inputKind;
      default:
        return CONTROL_TYPE_BUTTON;
    }
  }

  private getActionTypeForControlType(controlType: string): string {
    return controlType === CONTROL_TYPE_SWIPE ? 'swipe' : 'touch';
  }

  private getControlTypeLabel(controlType: string): string {
    switch (controlType) {
      case CONTROL_TYPE_STICK_MOVE:
        return '摇杆移动';
      case CONTROL_TYPE_STICK_LOOK:
        return '摇杆视角';
      case CONTROL_TYPE_KEYBOARD_MOVE:
        return '键盘移动';
      case CONTROL_TYPE_KEYBOARD_LOOK:
        return '键盘视角';
      case CONTROL_TYPE_BUTTON:
        return '按钮';
      case CONTROL_TYPE_SWIPE:
        return '滑动';
      default:
        return '控件';
    }
  }

  private getBindingOptionsForControlType(controlType: string): Array<BindingOption> {
    switch (controlType) {
      case CONTROL_TYPE_STICK_MOVE:
        return STICK_MOVE_BINDINGS;
      case CONTROL_TYPE_STICK_LOOK:
        return STICK_LOOK_BINDINGS;
      case CONTROL_TYPE_KEYBOARD_MOVE:
        return KEYBOARD_MOVE_BINDINGS;
      case CONTROL_TYPE_KEYBOARD_LOOK:
        return KEYBOARD_LOOK_BINDINGS;
      case CONTROL_TYPE_BUTTON:
        return BUTTON_BINDINGS;
      case CONTROL_TYPE_SWIPE:
        return SWIPE_BINDINGS;
      default:
        return BUTTON_BINDINGS;
    }
  }

  private getBindingLabel(bindingCode: string): string {
    if (bindingCode.length === 0) {
      return '未绑定';
    }

    for (const option of ALL_BINDING_OPTIONS) {
      if (option.code === bindingCode) {
        return option.label;
      }
    }

    if (bindingCode.startsWith('gamepad-button:')) {
      const rawCode = bindingCode.substring('gamepad-button:'.length);
      const displayLabel = this.getGamepadButtonDisplayLabelByRawCode(rawCode);
      return displayLabel.length > 0 ? displayLabel : `按钮 ${rawCode}`;
    }
    if (bindingCode.startsWith('gamepad-axis:')) {
      const rawCode = bindingCode.substring('gamepad-axis:'.length);
      const displayLabel = this.getGamepadAxisDisplayLabel(rawCode);
      return displayLabel.length > 0 ? displayLabel : this.formatBindingDisplayName(rawCode);
    }
    if (bindingCode.startsWith('key-event:')) {
      const rawCode = bindingCode.substring('key-event:'.length);
      const displayLabel = this.getGamepadButtonDisplayLabelByRawCode(rawCode);
      return displayLabel.length > 0 ? displayLabel : `键盘 ${rawCode}`;
    }
    if (bindingCode.startsWith('mouse-button:')) {
      const rawCode = bindingCode.substring('mouse-button:'.length);
      const buttonCode = this.parseRawCodeNumber(rawCode);
      return buttonCode >= 0 ? `鼠标${this.getMouseButtonLabel(buttonCode)}` : `鼠标${rawCode}`;
    }
    return this.formatBindingDisplayName(bindingCode);
  }

  private getControlBindingLabel(control: LayoutControlItem): string {
    const storedBindingLabel = this.getStoredBindingLabel(control);
    if (storedBindingLabel.length > 0) {
      return storedBindingLabel;
    }
    return this.getBindingLabel(control.inputCode.trim());
  }

  private getControlBindingCaptionText(control: LayoutControlItem): string {
    if (control.id === this.selectedControlId && this.isBindingCaptureListening() && !this.hasControlBinding(control)) {
      return this.bindingCaptureHint;
    }
    return this.getControlBindingLabel(control);
  }

  private getSelectedBindingOptions(): Array<BindingOption> {
    const selectedControl = this.getSelectedControl();
    if (selectedControl === null) {
      return [];
    }
    return this.getBindingOptionsForControlType(selectedControl.inputKind);
  }

  private async bindSelectedControl(bindingCode: string, bindingLabel: string, sourceLabel: string,
    rawSource: string = '', rawCode: string = '', rawName: string = ''): Promise<void> {
    const selectedControl = this.getSelectedControl();
    const currentLayout = layoutRepository.getCurrentLayout();
    if (selectedControl === null || currentLayout === null) {
      return;
    }

    const formattedBindingLabel = this.formatBindingDisplayName(bindingLabel);
    const formattedSourceLabel = this.formatBindingDisplayName(sourceLabel);

    let boundControl = selectedControl.clone();
    boundControl.inputKind = this.normalizeControlType(boundControl.inputKind, boundControl.inputCode);
    boundControl.inputCode = bindingCode;
    boundControl.actionType = this.getActionTypeForControlType(boundControl.inputKind);
    boundControl = this.withControlPayload(boundControl, (payload: ControlPayload) => {
      payload.bindingLabel = formattedBindingLabel;
      payload.bindingSource = formattedSourceLabel;
      payload.bindingRawSource = rawSource.trim();
      payload.bindingRawCode = rawCode.trim();
      payload.bindingRawName = rawName.trim();
      payload.directionalKeyCodes = '';
      payload.directionalKeyLabels = '';
    });
    await this.replaceSelectedControl(currentLayout, boundControl);
    this.resetPendingDirectionalBinding();
    this.bindingCaptureState = 'bound';
    this.bindingCaptureTargetId = boundControl.id;
    this.bindingCaptureHint = `已绑定 ${formattedBindingLabel}，来源 ${formattedSourceLabel}；当前已锁定，如需重绑请先清除绑定。`;
    this.updateControlEditorMessage();
  }

  private async bindSelectedDirectionalKeys(keyCodes: Array<number>, keyLabels: Array<string>): Promise<void> {
    const selectedControl = this.getSelectedControl();
    const currentLayout = layoutRepository.getCurrentLayout();
    if (selectedControl === null || currentLayout === null || !this.isDirectionalKeyboardControlType(selectedControl.inputKind)) {
      return;
    }

    const bindingCode = selectedControl.inputKind === CONTROL_TYPE_KEYBOARD_MOVE ? 'keys-directional-move' : 'keys-directional-look';
    const bindingLabel = this.buildDirectionalBindingLabel(keyLabels);
    let boundControl = selectedControl.clone();
    boundControl.inputKind = this.normalizeControlType(boundControl.inputKind, boundControl.inputCode);
    boundControl.inputCode = bindingCode;
    boundControl.actionType = this.getActionTypeForControlType(boundControl.inputKind);
    boundControl = this.withControlPayload(boundControl, (payload: ControlPayload) => {
      payload.bindingLabel = bindingLabel;
      payload.bindingSource = '键盘';
      payload.bindingRawSource = 'key-event';
      payload.bindingRawCode = keyCodes.join(',');
      payload.bindingRawName = keyLabels.join('|');
      payload.directionalKeyCodes = keyCodes.join(',');
      payload.directionalKeyLabels = keyLabels.join(',');
    });
    await this.replaceSelectedControl(currentLayout, boundControl);
    this.resetPendingDirectionalBinding();
    this.bindingCaptureState = 'bound';
    this.bindingCaptureTargetId = boundControl.id;
    this.bindingCaptureHint = `已完成四向绑定 ${bindingLabel}；当前已锁定，如需重绑请先清除绑定。`;
    this.updateControlEditorMessage();
  }

  private async clearSelectedBinding(): Promise<void> {
    const selectedControl = this.getSelectedControl();
    const currentLayout = layoutRepository.getCurrentLayout();
    if (selectedControl === null || currentLayout === null) {
      return;
    }

    let clearedControl = selectedControl.clone();
    clearedControl.inputKind = this.normalizeControlType(clearedControl.inputKind, clearedControl.inputCode);
    clearedControl.inputCode = '';
    clearedControl.actionType = this.getActionTypeForControlType(clearedControl.inputKind);
    clearedControl = this.withControlPayload(clearedControl, (payload: ControlPayload) => {
      payload.bindingLabel = '';
      payload.bindingSource = '';
      payload.bindingRawSource = '';
      payload.bindingRawCode = '';
      payload.bindingRawName = '';
      payload.directionalKeyCodes = '';
      payload.directionalKeyLabels = '';
    });
    await this.replaceSelectedControl(currentLayout, clearedControl);
    this.syncBindingCaptureWithSelectedControl();
    this.updateControlEditorMessage();
  }

  private syncSelectedControl(): void {
    if (this.layoutControls.length === 0) {
      this.selectedControlId = '';
      this.bindingCaptureState = 'idle';
      this.bindingCaptureTargetId = '';
      this.bindingCaptureHint = '选中控件后，未绑定控件会自动监听输入。';
      return;
    }

    const hasSelectedControl = this.layoutControls.some((control: LayoutControlItem) => control.id === this.selectedControlId);
    if (!hasSelectedControl) {
      this.selectedControlId = this.layoutControls[0].id;
    }

    this.syncBindingCaptureWithSelectedControl();
  }

  private updateControlEditorMessage(): void {
    if (this.isExecutionMode()) {
      this.controlEditorMessage = '执行模式已锁定布局编辑，画布上的控件仅用于显示当前映射区域。';
      return;
    }

    if (this.currentLayoutHasBackground && !this.hasBackgroundImageMetrics()) {
      this.controlEditorMessage = '正在读取截图尺寸，完成后再添加或调整控件，坐标会以截图左上角为原点。';
      return;
    }

    if (!this.currentLayoutHasBackground) {
      this.controlEditorMessage = '先导入被控游戏截图，再添加控件。';
      return;
    }

    if (this.layoutControls.length === 0) {
      this.controlEditorMessage = '当前布局还没有控件，可以先添加一种控件类型。';
      return;
    }

    const selectedControl = this.getSelectedControl();
    if (selectedControl === null) {
      this.controlEditorMessage = '请选择一个控件；未绑定控件会自动监听，已绑定控件默认锁定。';
      return;
    }

    const gestureHint = selectedControl.inputKind === CONTROL_TYPE_SWIPE
      ? '拖动两端圆点可拉伸并改变角度，双指捏合可整体缩放。'
      : '单指拖动位置，双指捏合缩放。';
    this.controlEditorMessage = `当前选中 ${selectedControl.label}，位置 ${Math.round(selectedControl.x / 10)}%, ${Math.round(selectedControl.y / 10)}%（以截图左上角为原点），尺寸 ${Math.round(selectedControl.width / 10)}% x ${Math.round(selectedControl.height / 10)}%。${gestureHint}`;
  }

  private getSelectedControl(): LayoutControlItem | null {
    for (const control of this.layoutControls) {
      if (control.id === this.selectedControlId) {
        return control.clone();
      }
    }
    return null;
  }

  private isExecutionMode(): boolean {
    return this.interactionMode === EXECUTION_MODE_EXECUTE;
  }

  private getBoundControlCount(): number {
    let boundCount = 0;
    for (const control of this.layoutControls) {
      if (this.hasControlBinding(control)) {
        boundCount += 1;
      }
    }
    return boundCount;
  }

  private getExecutionModeLabel(): string {
    return this.isExecutionMode() ? '执行模式' : '编辑模式';
  }

  private getExecutionModeAccentColor(): string {
    return this.isExecutionMode() ? SUCCESS_COLOR : PRIMARY_COLOR;
  }

  private getExecutionModeDescription(): string {
    if (this.isExecutionMode()) {
      return '当前为单点触控执行，最后激活的控件优先发送。';
    }
    return '可拖动、缩放和绑定控件；保存后进入执行模式。';
  }

  private clearExecutionFeedbackTimeout(): void {
    if (this.executionFeedbackTimeoutId < 0) {
      return;
    }

    clearTimeout(this.executionFeedbackTimeoutId);
    this.executionFeedbackTimeoutId = -1;
  }

  private hideExecutionTouchFeedback(): void {
    this.clearExecutionFeedbackTimeout();
    this.executionTouchFeedbackVisible = false;
    this.executionTouchFeedbackDimmed = false;
  }

  private updateExecutionTouchFeedback(active: boolean, xUnits: number, yUnits: number): void {
    this.clearExecutionFeedbackTimeout();
    this.executionTouchFeedbackXUnits = clampEditorValue(Math.round(xUnits), 0, CONTROL_CANVAS_UNITS);
    this.executionTouchFeedbackYUnits = clampEditorValue(Math.round(yUnits), 0, CONTROL_CANVAS_UNITS);
    this.executionTouchFeedbackVisible = true;
    this.executionTouchFeedbackDimmed = !active;
    if (active) {
      return;
    }

    this.executionFeedbackTimeoutId = setTimeout(() => {
      this.executionTouchFeedbackVisible = false;
      this.executionTouchFeedbackDimmed = false;
      this.executionFeedbackTimeoutId = -1;
    }, EXECUTION_TOUCH_FEEDBACK_TIMEOUT_MS);
  }

  private resetExecutionState(releaseTouch: boolean): void {
    this.clearExecutionFeedbackTimeout();
    if (releaseTouch && this.dispatchedExecutionActive && hidService.getState().connected) {
      hidService.releaseTouch();
    }
    this.executionTouchSequence = 0;
    this.executionTargets = [];
    this.executionActiveControlId = '';
    this.dispatchedExecutionActive = false;
    this.dispatchedExecutionControlId = '';
    this.dispatchedExecutionXUnits = 0;
    this.dispatchedExecutionYUnits = 0;
    this.hideExecutionTouchFeedback();
  }

  private enterExecutionMode(): void {
    this.resetExecutionState(false);
    this.interactionMode = EXECUTION_MODE_EXECUTE;
    this.menuExpanded = false;
    this.selectedControlId = '';
    this.bindingCaptureState = 'idle';
    this.bindingCaptureTargetId = '';
    this.bindingCaptureHint = '执行模式已启动，若需调整布局请先返回编辑模式。';
    this.executionStatusText = `已加载 ${this.getBoundControlCount()} 个已绑定控件，等待输入。`;
    this.updateControlEditorMessage();
  }

  private exitExecutionMode(): void {
    this.resetExecutionState(true);
    this.interactionMode = EXECUTION_MODE_EDIT;
    this.executionStatusText = '已返回编辑模式。';
    this.syncSelectedControl();
    this.updateControlEditorMessage();
  }

  private async saveLayoutAndEnterExecutionMode(): Promise<void> {
    if (this.getBoundControlCount() === 0) {
      await this.showActionError('无法执行', '当前布局还没有已绑定控件，至少完成一个按键或摇杆绑定后再保存执行。');
      return;
    }

    if (!hidService.getState().connected) {
      await this.showActionError('无法执行', '蓝牙 HID 设备当前未连接，暂时不能进入执行模式。');
      return;
    }

    const currentLayout = layoutRepository.getCurrentLayout();
    if (currentLayout === null) {
      await this.showActionError('保存失败', '当前没有可执行的布局。');
      return;
    }

    try {
      const updatedLayout = currentLayout.clone();
      updatedLayout.controls = this.layoutControls.map((control: LayoutControlItem) => control.clone());
      updatedLayout.updatedAt = Date.now();
      await layoutRepository.saveLayout(updatedLayout);
      this.applyLayout(updatedLayout);
      this.refreshLayoutSummary();
      this.enterExecutionMode();
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'save layout before execution failed: %{public}s', JSON.stringify(error as Object));
      await this.showActionError('保存失败', '布局保存失败，暂时无法进入执行模式。');
    }
  }

  private getExecutionControlHeight(control: LayoutControlItem): number {
    return this.getControlLogicalHeightUnits(control);
  }

  private getControlLogicalHeightUnits(control: LayoutControlItem): number {
    if (this.isRoundControlType(control.inputKind)) {
      return this.toRoundControlHeightUnits(control.width);
    }
    return control.height;
  }

  private getRoundControlBodyFrame(control: LayoutControlItem): CanvasFrame {
    const diameter = this.getControlBodyWidthValue(control);
    return new CanvasFrame(this.toCanvasXValue(control.x), this.toCanvasYValue(control.y), diameter, diameter);
  }

  private getRoundControlCenterXUnits(control: LayoutControlItem): number {
    const frame = this.getRoundControlBodyFrame(control);
    return this.toBackgroundXUnitsFromCanvasPixels(frame.x + frame.width / 2);
  }

  private getRoundControlCenterYUnits(control: LayoutControlItem): number {
    const frame = this.getRoundControlBodyFrame(control);
    return this.toBackgroundYUnitsFromCanvasPixels(frame.y + frame.height / 2);
  }

  private getRoundControlRadiusXUnits(control: LayoutControlItem): number {
    const frame = this.getRoundControlBodyFrame(control);
    const centerXUnits = this.getRoundControlCenterXUnits(control);
    return Math.max(1, this.toBackgroundXUnitsFromCanvasPixels(frame.x + frame.width) - centerXUnits);
  }

  private getRoundControlRadiusYUnits(control: LayoutControlItem): number {
    const frame = this.getRoundControlBodyFrame(control);
    const centerYUnits = this.getRoundControlCenterYUnits(control);
    return Math.max(1, this.toBackgroundYUnitsFromCanvasPixels(frame.y + frame.height) - centerYUnits);
  }

  private upsertExecutionTarget(controlId: string, xUnits: number, yUnits: number): void {
    const normalizedX = clampEditorValue(Math.round(xUnits), 0, CONTROL_CANVAS_UNITS);
    const normalizedY = clampEditorValue(Math.round(yUnits), 0, CONTROL_CANVAS_UNITS);
    const nextTargets: Array<ExecutionTouchTarget> = [];
    let replaced = false;
    for (const target of this.executionTargets) {
      if (target.controlId === controlId) {
        nextTargets.push(new ExecutionTouchTarget(controlId, normalizedX, normalizedY, target.order));
        replaced = true;
        continue;
      }
      nextTargets.push(target.clone());
    }

    if (!replaced) {
      this.executionTouchSequence += 1;
      nextTargets.push(new ExecutionTouchTarget(controlId, normalizedX, normalizedY, this.executionTouchSequence));
    }
    this.executionTargets = nextTargets;
  }

  private removeExecutionTarget(controlId: string): void {
    this.executionTargets = this.executionTargets
      .filter((target: ExecutionTouchTarget) => target.controlId !== controlId)
      .map((target: ExecutionTouchTarget) => target.clone());
  }

  private getTopExecutionTarget(): ExecutionTouchTarget | null {
    let topTarget: ExecutionTouchTarget | null = null;
    for (const target of this.executionTargets) {
      if (topTarget === null || target.order > topTarget.order) {
        topTarget = target;
      }
    }
    return topTarget === null ? null : topTarget.clone();
  }

  private toHidAxisValue(units: number): number {
    return clampEditorValue(Math.round(units / CONTROL_CANVAS_UNITS * HID_AXIS_MAX), 0, HID_AXIS_MAX);
  }

  private buildStickExecutionTarget(control: LayoutControlItem, horizontalValue: number, verticalValue: number): ExecutionTouchTarget | null {
    const magnitude = Math.sqrt(horizontalValue * horizontalValue + verticalValue * verticalValue);
    if (magnitude < EXECUTION_STICK_DEADZONE) {
      return null;
    }

    const scaledMagnitude = clampEditorValue((magnitude - EXECUTION_STICK_DEADZONE) / (1 - EXECUTION_STICK_DEADZONE), 0, 1);
    const normalizedX = horizontalValue / Math.max(magnitude, 0.0001) * scaledMagnitude;
    const normalizedY = verticalValue / Math.max(magnitude, 0.0001) * scaledMagnitude;
    const centerXUnits = this.isRoundControlType(control.inputKind) ? this.getRoundControlCenterXUnits(control) : this.getControlCenterX(control);
    const centerYUnits = this.isRoundControlType(control.inputKind) ? this.getRoundControlCenterYUnits(control) : this.getControlCenterY(control);
    const radiusX = this.isRoundControlType(control.inputKind) ? this.getRoundControlRadiusXUnits(control) : Math.max(control.width / 2, 1);
    const radiusY = this.isRoundControlType(control.inputKind) ? this.getRoundControlRadiusYUnits(control) : Math.max(this.getExecutionControlHeight(control) / 2, 1);
    const xUnits = clampEditorValue(Math.round(centerXUnits + normalizedX * radiusX), 0, CONTROL_CANVAS_UNITS);
    const yUnits = clampEditorValue(Math.round(centerYUnits + normalizedY * radiusY), 0, CONTROL_CANVAS_UNITS);
    return new ExecutionTouchTarget(control.id, xUnits, yUnits, 0);
  }

  private updateButtonExecutionTargets(bindingCode: string, active: boolean): void {
    for (const control of this.layoutControls) {
      if (control.inputCode !== bindingCode || control.inputKind !== CONTROL_TYPE_BUTTON) {
        continue;
      }

      if (!active) {
        this.removeExecutionTarget(control.id);
        continue;
      }

      this.upsertExecutionTarget(control.id, this.getRoundControlCenterXUnits(control), this.getRoundControlCenterYUnits(control));
    }
  }

  private updateStickExecutionTargets(bindingCode: string, horizontalValue: number, verticalValue: number): void {
    for (const control of this.layoutControls) {
      if (control.inputCode !== bindingCode) {
        continue;
      }
      if (control.inputKind !== CONTROL_TYPE_STICK_MOVE && control.inputKind !== CONTROL_TYPE_STICK_LOOK) {
        continue;
      }

      const nextTarget = this.buildStickExecutionTarget(control, horizontalValue, verticalValue);
      if (nextTarget === null) {
        this.removeExecutionTarget(control.id);
        continue;
      }

      this.upsertExecutionTarget(control.id, nextTarget.xUnits, nextTarget.yUnits);
    }
  }

  private handleGamepadButtonExecutionEvent(event: Object): void {
    const rawCodeValue = this.getNumberField(event, 'code');
    if (rawCodeValue <= 0) {
      return;
    }

    const bindingCode = this.buildRawBindingCode('gamepad-button', `${rawCodeValue}`);
    if (bindingCode.length === 0) {
      return;
    }

    const action = this.getStringField(event, 'action');
    if (action === 'down') {
      this.updateButtonExecutionTargets(bindingCode, true);
      this.executionStatusText = `触发 ${this.getBindingLabel(bindingCode)}。`;
      return;
    }
    if (action === 'up' || action === 'cancel') {
      this.updateButtonExecutionTargets(bindingCode, false);
    }
  }

  private handleGamepadAxisExecutionEvent(event: Object): void {
    const source = this.getStringField(event, 'source');
    if (source !== 'left-thumbstick' && source !== 'right-thumbstick') {
      return;
    }

    let horizontalValue = this.getNumberField(event, source === 'left-thumbstick' ? 'x' : 'z');
    let verticalValue = this.getNumberField(event, source === 'left-thumbstick' ? 'y' : 'rz');
    if (source === 'right-thumbstick' && Math.abs(horizontalValue) < BINDING_AXIS_THRESHOLD && Math.abs(verticalValue) < BINDING_AXIS_THRESHOLD) {
      horizontalValue = this.getNumberField(event, 'x');
      verticalValue = this.getNumberField(event, 'y');
    }

    const bindingCode = this.buildRawBindingCode('gamepad-axis', source);
    if (bindingCode.length === 0) {
      return;
    }

    this.updateStickExecutionTargets(bindingCode, horizontalValue, verticalValue);
    if (Math.sqrt(horizontalValue * horizontalValue + verticalValue * verticalValue) >= EXECUTION_STICK_DEADZONE) {
      this.executionStatusText = `正在执行 ${this.getBindingLabel(bindingCode)}。`;
    }
  }

  private reconcileExecutionOutput(): void {
    const nextTarget = this.getTopExecutionTarget();
    if (nextTarget === null) {
      if (!this.dispatchedExecutionActive) {
        return;
      }

      if (hidService.getState().connected) {
        hidService.releaseTouch();
      }
      this.updateExecutionTouchFeedback(false, this.dispatchedExecutionXUnits, this.dispatchedExecutionYUnits);
      this.executionActiveControlId = '';
      this.dispatchedExecutionActive = false;
      this.dispatchedExecutionControlId = '';
      this.executionStatusText = '等待输入。';
      return;
    }

    if (hidService.getState().connected) {
      if (this.dispatchedExecutionActive && this.dispatchedExecutionControlId !== nextTarget.controlId) {
        hidService.releaseTouch();
      }
      hidService.sendTouch(true, this.toHidAxisValue(nextTarget.xUnits), this.toHidAxisValue(nextTarget.yUnits));
    }

    this.executionActiveControlId = nextTarget.controlId;
    this.dispatchedExecutionActive = true;
    this.dispatchedExecutionControlId = nextTarget.controlId;
    this.dispatchedExecutionXUnits = nextTarget.xUnits;
    this.dispatchedExecutionYUnits = nextTarget.yUnits;
    this.updateExecutionTouchFeedback(true, nextTarget.xUnits, nextTarget.yUnits);
  }

  private handleExecutionEvents(events: Array<Object>): void {
    if (!this.isExecutionMode()) {
      return;
    }

    for (const event of events) {
      const eventKind = this.getStringField(event, 'kind');
      if (eventKind === 'gamepad-button') {
        this.handleGamepadButtonExecutionEvent(event);
        continue;
      }
      if (eventKind === 'gamepad-axis') {
        this.handleGamepadAxisExecutionEvent(event);
      }
    }

    this.reconcileExecutionOutput();
  }

  private handleExecutionKeyEvent(event: Object): boolean {
    if (!this.isExecutionMode()) {
      return false;
    }

    const keyCode = this.readKeyEventCode(event);
    if (keyCode < 0) {
      return false;
    }

    const bindingCode = this.buildRawBindingCode('key-event', `${keyCode}`);
    if (bindingCode.length === 0) {
      return false;
    }

    const eventType = this.readKeyEventType(event);
    if (eventType === KEY_EVENT_DOWN) {
      this.updateButtonExecutionTargets(bindingCode, true);
      this.executionStatusText = `触发 ${this.getBindingLabel(bindingCode)}。`;
      this.reconcileExecutionOutput();
      return true;
    }

    if (eventType === KEY_EVENT_UP) {
      this.updateButtonExecutionTargets(bindingCode, false);
      this.reconcileExecutionOutput();
      return true;
    }

    return false;
  }

  private hasSelectedControl(): boolean {
    return this.getSelectedControl() !== null;
  }

  private hasSelectedControlBinding(): boolean {
    const selectedControl = this.getSelectedControl();
    return selectedControl !== null && this.hasControlBinding(selectedControl);
  }

  private selectControl(controlId: string): void {
    this.selectedControlId = controlId;
    this.syncBindingCaptureWithSelectedControl();
    this.updateControlEditorMessage();
  }

  private syncBindingCaptureWithSelectedControl(): void {
    const control = this.findLocalControl(this.selectedControlId);
    if (control === null) {
      this.resetPendingDirectionalBinding();
      this.bindingCaptureState = 'idle';
      this.bindingCaptureTargetId = '';
      this.bindingCaptureHint = '选中控件后，未绑定控件会自动监听输入。';
      return;
    }

    this.resetPendingDirectionalBinding();
    this.bindingCaptureTargetId = control.id;
    if (this.hasControlBinding(control)) {
      this.bindingCaptureState = 'bound';
      this.bindingCaptureHint = `当前已锁定；如需重绑，请先清除绑定。`;
      return;
    }

    this.bindingCaptureState = 'listening';
    if (this.isDirectionalKeyboardControlType(control.inputKind)) {
      this.updateDirectionalBindingHint(control);
      return;
    }
    this.bindingCaptureHint = this.getUnboundBindingHint(control);
  }

  private isBindingCaptureListening(): boolean {
    return this.bindingCaptureState === 'listening' && this.bindingCaptureTargetId === this.selectedControlId;
  }

  private async addControlFromLibrary(libraryItem: ControlLibraryItem): Promise<void> {
    if (!this.currentLayoutHasBackground) {
      await this.showActionError('无法添加控件', '请先为当前布局导入被控游戏截图，再开始布置控件。');
      return;
    }

    if (!this.hasBackgroundImageMetrics()) {
      await this.showActionError('无法添加控件', '截图尺寸还在读取中，请稍后再试。坐标需要以截图左上角为原点保存。');
      return;
    }

    const currentLayout = layoutRepository.getCurrentLayout();
    if (currentLayout === null) {
      await this.showActionError('无法添加控件', '当前没有可编辑的布局。');
      return;
    }

    const nextIndex = this.getNextControlIndexForType(libraryItem.controlType, currentLayout.controls);
    const defaultSize = libraryItem.defaultSize;
    const controlWidth = libraryItem.controlType === CONTROL_TYPE_SWIPE ? CONTROL_SWIPE_DEFAULT_WIDTH : defaultSize;
    const controlHeight = libraryItem.controlType === CONTROL_TYPE_SWIPE ? CONTROL_SWIPE_DEFAULT_HEIGHT : defaultSize;
    const control = this.normalizeControlGeometry(new LayoutControlItem(
      `control-${Date.now()}`,
      `${libraryItem.label} ${nextIndex}`,
      libraryItem.controlType,
      '',
      libraryItem.actionType,
      Math.round((CONTROL_CANVAS_UNITS - controlWidth) / 2),
      Math.round((CONTROL_CANVAS_UNITS - controlHeight) / 2),
      controlWidth,
      controlHeight,
      libraryItem.controlType === CONTROL_TYPE_SWIPE
        ? JSON.stringify({ rotation: 0, coordinateSpace: CONTROL_COORDINATE_SPACE_BACKGROUND })
        : JSON.stringify({ coordinateSpace: CONTROL_COORDINATE_SPACE_BACKGROUND })
    ));

    const updatedLayout = currentLayout.clone();
    updatedLayout.controls.push(control);
    updatedLayout.updatedAt = Date.now();
    this.controlLibraryExpanded = false;
    this.menuExpanded = true;
    await this.persistLayout(updatedLayout, control.id);
  }

  private getNextControlIndexForType(controlType: string, controls: Array<LayoutControlItem>): number {
    let sameTypeCount = 0;
    for (const control of controls) {
      if (this.normalizeControlType(control.inputKind, control.inputCode) === controlType) {
        sameTypeCount += 1;
      }
    }
    return sameTypeCount + 1;
  }

  private async removeSelectedControl(): Promise<void> {
    const selectedControl = this.getSelectedControl();
    const currentLayout = layoutRepository.getCurrentLayout();
    if (selectedControl === null || currentLayout === null) {
      return;
    }

    const nextControls = currentLayout.controls.filter((control: LayoutControlItem) => control.id !== selectedControl.id)
      .map((control: LayoutControlItem) => control.clone());
    const updatedLayout = currentLayout.clone();
    updatedLayout.controls = nextControls;
    updatedLayout.updatedAt = Date.now();
    const nextSelectedControlId = nextControls.length > 0 ? nextControls[0].id : '';
    await this.persistLayout(updatedLayout, nextSelectedControlId);
  }

  private handleControlTouch(controlId: string, event: Object): void {
    if (this.isExecutionMode()) {
      return;
    }

    if (!this.isBackgroundCoordinateFrameReady()) {
      this.updateControlEditorMessage();
      return;
    }

    if (this.resizingSwipeControlId.length > 0 || this.pinchingControlId.length > 0) {
      return;
    }

    const action = this.readTouchAction(event);
    if (action === TOUCH_ACTION_DOWN) {
      this.startControlDrag(controlId, event);
    }
  }

  private handleCanvasTouch(event: Object): void {
    if (this.isExecutionMode()) {
      return;
    }

    if (!this.isBackgroundCoordinateFrameReady()) {
      this.updateControlEditorMessage();
      return;
    }

    if (this.draggingMenuButton) {
      return;
    }

    const action = this.readTouchAction(event);
    if (action === TOUCH_ACTION_DOWN) {
      if (this.draggingControlId.length === 0 && this.resizingSwipeControlId.length === 0 && this.pinchingControlId.length === 0 &&
        this.selectedControlId.length > 0) {
        this.startControlDrag(this.selectedControlId, event);
      }
      return;
    }

    if (this.draggingControlId.length === 0) {
      if (this.resizingSwipeControlId.length === 0) {
        return;
      }
    }
    if (action === TOUCH_ACTION_MOVE) {
      if (this.resizingSwipeControlId.length > 0) {
        this.updateSwipeHandleDrag(this.resizingSwipeControlId, event);
        return;
      }
      this.updateControlDrag(this.draggingControlId, event);
      return;
    }

    if (action === TOUCH_ACTION_UP || action === TOUCH_ACTION_CANCEL) {
      if (this.resizingSwipeControlId.length > 0) {
        this.finishSwipeHandleDrag(this.resizingSwipeControlId);
        return;
      }
      this.finishControlDrag(this.draggingControlId);
    }
  }

  private startControlDrag(controlId: string, event: Object): void {
    const selectedControl = this.findLocalControl(controlId);
    if (selectedControl === null) {
      return;
    }

    this.selectControl(controlId);
    this.controlLibraryExpanded = false;
    this.draggingControlId = controlId;
    this.dragStartWindowX = this.readTouchWindowX(event);
    this.dragStartWindowY = this.readTouchWindowY(event);
    this.dragStartControlX = selectedControl.x;
    this.dragStartControlY = selectedControl.y;
    if (selectedControl.inputKind === CONTROL_TYPE_SWIPE) {
      const positions = this.getSwipeHandlePositions(selectedControl);
      this.dragStartSwipeStartPoint = positions.start.clone();
      this.dragStartSwipeEndPoint = positions.end.clone();
    }
  }

  private updateControlDrag(controlId: string, event: Object): void {
    if (this.draggingControlId !== controlId) {
      return;
    }

    const draggingControl = this.findLocalControl(controlId);
    if (draggingControl === null) {
      return;
    }

    const currentWindowX = this.readTouchWindowX(event);
    const currentWindowY = this.readTouchWindowY(event);
    const backgroundFrame = this.getBackgroundContentFrame();
    const deltaXUnits = (currentWindowX - this.dragStartWindowX) / Math.max(backgroundFrame.width, 1) * CONTROL_CANVAS_UNITS;
    const deltaYUnits = (currentWindowY - this.dragStartWindowY) / Math.max(backgroundFrame.height, 1) * CONTROL_CANVAS_UNITS;
    if (draggingControl.inputKind === CONTROL_TYPE_SWIPE) {
      const nextPositions = new SwipeHandlePositions(
        new EditorPoint(this.dragStartSwipeStartPoint.x + deltaXUnits, this.dragStartSwipeStartPoint.y + deltaYUnits),
        new EditorPoint(this.dragStartSwipeEndPoint.x + deltaXUnits, this.dragStartSwipeEndPoint.y + deltaYUnits)
      );
      let nextSwipeControl = draggingControl.clone();
      nextSwipeControl = this.applySwipeHandlePositions(nextSwipeControl, nextPositions);
      this.updateLocalControl(nextSwipeControl, false);
      return;
    }

    const nextControl = draggingControl.clone();
    nextControl.x = Math.round(this.dragStartControlX + deltaXUnits);
    nextControl.y = Math.round(this.dragStartControlY + deltaYUnits);
    this.updateLocalControl(nextControl);
  }

  private finishControlDrag(controlId: string): void {
    if (this.draggingControlId !== controlId) {
      return;
    }

    this.draggingControlId = '';
    this.persistCurrentLayoutControls();
  }

  private async persistCurrentLayoutControls(): Promise<void> {
    const currentLayout = layoutRepository.getCurrentLayout();
    if (currentLayout === null) {
      return;
    }

    const updatedLayout = currentLayout.clone();
    updatedLayout.controls = this.layoutControls.map((control: LayoutControlItem) => control.clone());
    updatedLayout.updatedAt = Date.now();
    await this.persistLayout(updatedLayout, this.selectedControlId);
  }

  private findLocalControl(controlId: string): LayoutControlItem | null {
    for (const control of this.layoutControls) {
      if (control.id === controlId) {
        return control.clone();
      }
    }
    return null;
  }

  private updateLocalControl(nextControl: LayoutControlItem, normalizeGeometry: boolean = true): void {
    const normalizedControl = normalizeGeometry ? this.normalizeControlGeometry(nextControl) : nextControl.clone();
    this.layoutControls = this.layoutControls.map((control: LayoutControlItem) => {
      if (control.id === normalizedControl.id) {
        return normalizedControl.clone();
      }
      return control.clone();
    });
    this.updateControlEditorMessage();
  }

  private readGestureScale(event: Object): number {
    const scale = Reflect.get(event, 'scale') as number | undefined;
    return typeof scale === 'number' && Number.isFinite(scale) ? scale : 1;
  }

  private startControlPinch(controlId: string): void {
    const control = this.findLocalControl(controlId);
    if (control === null) {
      return;
    }

    this.selectControl(controlId);
    this.draggingControlId = '';
    this.resizingSwipeControlId = '';
    this.pinchingControlId = controlId;
    this.pinchStartControlWidth = control.width;
    this.pinchStartControlHeight = control.height;
    this.pinchStartControlX = control.x;
    this.pinchStartControlY = control.y;
  }

  private startSelectedControlPinch(): void {
    if (this.isExecutionMode() || this.selectedControlId.length === 0 || this.resizingSwipeControlId.length > 0 || this.draggingMenuButton) {
      return;
    }
    if (!this.isBackgroundCoordinateFrameReady()) {
      this.updateControlEditorMessage();
      return;
    }
    this.startControlPinch(this.selectedControlId);
  }

  private updateControlPinch(controlId: string, event: Object): void {
    if (this.pinchingControlId !== controlId) {
      return;
    }

    const control = this.findLocalControl(controlId);
    if (control === null) {
      return;
    }

    const scale = clampEditorValue(this.readGestureScale(event), CONTROL_PINCH_MIN_SCALE, CONTROL_PINCH_MAX_SCALE);
    let nextControl = control.clone();
    nextControl.width = Math.round(this.pinchStartControlWidth * scale);
    nextControl.height = Math.round(this.pinchStartControlHeight * scale);
    nextControl.x = Math.round(this.pinchStartControlX + (this.pinchStartControlWidth - nextControl.width) / 2);
    nextControl.y = Math.round(this.pinchStartControlY + (this.pinchStartControlHeight - nextControl.height) / 2);
    nextControl = this.normalizeControlGeometry(nextControl);
    this.updateLocalControl(nextControl, false);
  }

  private finishControlPinch(controlId: string): void {
    if (this.pinchingControlId !== controlId) {
      return;
    }

    this.pinchingControlId = '';
    this.persistCurrentLayoutControls();
  }

  private updateSelectedControlPinch(event: Object): void {
    if (this.pinchingControlId.length === 0) {
      return;
    }
    this.updateControlPinch(this.pinchingControlId, event);
  }

  private finishSelectedControlPinch(): void {
    if (this.pinchingControlId.length === 0) {
      return;
    }
    this.finishControlPinch(this.pinchingControlId);
  }

  private getControlCenterX(control: LayoutControlItem): number {
    return control.x + control.width / 2;
  }

  private getControlCenterY(control: LayoutControlItem): number {
    return control.y + this.getControlLogicalHeightUnits(control) / 2;
  }

  private startSwipeHandleDrag(controlId: string, handle: string): void {
    if (!this.isBackgroundCoordinateFrameReady()) {
      this.updateControlEditorMessage();
      return;
    }

    const control = this.findLocalControl(controlId);
    if (control === null) {
      return;
    }

    this.selectControl(controlId);
    this.draggingControlId = '';
    this.pinchingControlId = '';
    this.resizingSwipeControlId = controlId;
    this.resizingSwipeHandle = handle;
    this.swipeResizeThickness = control.height;
    const positions = this.getSwipeHandlePositions(control);
    if (handle === 'start') {
      this.swipeResizeAnchorX = positions.end.x;
      this.swipeResizeAnchorY = positions.end.y;
      return;
    }

    this.swipeResizeAnchorX = positions.start.x;
    this.swipeResizeAnchorY = positions.start.y;
  }

  private updateSwipeHandleDrag(controlId: string, event: Object): void {
    if (this.resizingSwipeControlId !== controlId) {
      return;
    }

    const control = this.findLocalControl(controlId);
    if (control === null) {
      return;
    }

    const movingX = this.toCanvasUnitX(this.readTouchWindowX(event));
    const movingY = this.toCanvasUnitY(this.readTouchWindowY(event));
    const deltaX = movingX - this.swipeResizeAnchorX;
    const deltaY = movingY - this.swipeResizeAnchorY;
    const rawDistance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    if (rawDistance < 1) {
      return;
    }

    const nextHandleDistance = clampEditorValue(Math.round(rawDistance), CONTROL_SWIPE_MIN_LENGTH - CONTROL_SWIPE_HANDLE_SIZE,
      CONTROL_SWIPE_MAX_LENGTH - CONTROL_SWIPE_HANDLE_SIZE);
    const moveRatio = nextHandleDistance / rawDistance;
    const movingHandleX = this.swipeResizeAnchorX + deltaX * moveRatio;
    const movingHandleY = this.swipeResizeAnchorY + deltaY * moveRatio;
    const nextPositions = this.resizingSwipeHandle === 'start'
      ? new SwipeHandlePositions(new EditorPoint(movingHandleX, movingHandleY), new EditorPoint(this.swipeResizeAnchorX, this.swipeResizeAnchorY))
      : new SwipeHandlePositions(new EditorPoint(this.swipeResizeAnchorX, this.swipeResizeAnchorY), new EditorPoint(movingHandleX, movingHandleY));
    const fixedHandle = this.resizingSwipeHandle === 'start' ? 'end' : 'start';
    let nextControl = control.clone();
    nextControl.height = clampEditorValue(this.swipeResizeThickness, CONTROL_SWIPE_MIN_THICKNESS, CONTROL_SWIPE_MAX_THICKNESS);
    nextControl = this.applySwipeHandlePositions(nextControl, nextPositions, fixedHandle);
    this.updateLocalControl(nextControl, false);
  }

  private finishSwipeHandleDrag(controlId: string): void {
    if (this.resizingSwipeControlId !== controlId) {
      return;
    }

    this.resizingSwipeControlId = '';
    this.resizingSwipeHandle = '';
    this.persistCurrentLayoutControls();
  }

  private updateCanvasSize(area: Object): void {
    const width = this.readAreaNumber(area, 'width');
    const height = this.readAreaNumber(area, 'height');
    if (width > 0) {
      this.canvasWidthPx = width;
    }
    if (height > 0) {
      this.canvasHeightPx = height;
    }
  }

  private updateViewportSize(area: Object): void {
    const width = this.readAreaNumber(area, 'width');
    const height = this.readAreaNumber(area, 'height');
    if (width > 0) {
      this.viewportWidthPx = width;
    }
    if (height > 0) {
      this.viewportHeightPx = height;
    }

    if (width <= 0 || height <= 0) {
      return;
    }

    if (!this.menuButtonInitialized) {
      this.menuButtonX = this.getClampedMenuButtonX(MENU_EDGE_MARGIN);
      this.menuButtonY = this.getClampedMenuButtonY(MENU_EDGE_MARGIN);
      this.menuButtonInitialized = true;
      return;
    }

    this.menuButtonX = this.getClampedMenuButtonX(this.menuButtonX);
    this.menuButtonY = this.getClampedMenuButtonY(this.menuButtonY);
  }

  private getClampedMenuButtonX(value: number): number {
    const maxValue = Math.max(MENU_EDGE_MARGIN, this.viewportWidthPx - MENU_BUTTON_WIDTH - MENU_EDGE_MARGIN);
    return clampEditorValue(Math.round(value), MENU_EDGE_MARGIN, maxValue);
  }

  private getClampedMenuButtonY(value: number): number {
    const maxValue = Math.max(MENU_EDGE_MARGIN, this.viewportHeightPx - MENU_BUTTON_HEIGHT - MENU_EDGE_MARGIN);
    return clampEditorValue(Math.round(value), MENU_EDGE_MARGIN, maxValue);
  }

  private handleMenuButtonTouch(event: Object): void {
    const action = this.readTouchAction(event);
    if (action === TOUCH_ACTION_DOWN) {
      this.draggingMenuButton = true;
      this.menuButtonMoved = false;
      this.menuDragStartWindowX = this.readTouchWindowX(event);
      this.menuDragStartWindowY = this.readTouchWindowY(event);
      this.menuButtonDragStartX = this.menuButtonX;
      this.menuButtonDragStartY = this.menuButtonY;
      return;
    }

    if (action === TOUCH_ACTION_MOVE && this.draggingMenuButton) {
      const deltaX = this.readTouchWindowX(event) - this.menuDragStartWindowX;
      const deltaY = this.readTouchWindowY(event) - this.menuDragStartWindowY;
      if (Math.abs(deltaX) >= MENU_DRAG_THRESHOLD_PX || Math.abs(deltaY) >= MENU_DRAG_THRESHOLD_PX) {
        this.menuButtonMoved = true;
      }
      this.menuButtonX = this.getClampedMenuButtonX(this.menuButtonDragStartX + deltaX);
      this.menuButtonY = this.getClampedMenuButtonY(this.menuButtonDragStartY + deltaY);
      return;
    }

    if ((action === TOUCH_ACTION_UP || action === TOUCH_ACTION_CANCEL) && this.draggingMenuButton) {
      const shouldToggleMenu = !this.menuButtonMoved;
      this.draggingMenuButton = false;
      this.menuButtonMoved = false;
      if (shouldToggleMenu) {
        this.menuExpanded = !this.menuExpanded;
      }
    }
  }

  private getMenuPanelHeight(): number {
    if (this.viewportHeightPx <= 0) {
      return MENU_PANEL_HEIGHT;
    }
    const nextHeight = Math.round(this.viewportHeightPx * 0.72);
    return clampEditorValue(nextHeight, 280, MENU_PANEL_HEIGHT);
  }

  private getMenuPanelX(): number {
    const rawX = this.menuButtonX + MENU_BUTTON_WIDTH - MENU_PANEL_WIDTH;
    const maxValue = Math.max(MENU_EDGE_MARGIN, this.viewportWidthPx - MENU_PANEL_WIDTH - MENU_EDGE_MARGIN);
    return clampEditorValue(rawX, MENU_EDGE_MARGIN, maxValue);
  }

  private getMenuPanelY(): number {
    const desiredY = this.menuButtonY + MENU_BUTTON_HEIGHT + MENU_PANEL_OFFSET;
    const maxValue = Math.max(MENU_EDGE_MARGIN, this.viewportHeightPx - this.getMenuPanelHeight() - MENU_EDGE_MARGIN);
    return clampEditorValue(desiredY, MENU_EDGE_MARGIN, maxValue);
  }

  private readAreaNumber(area: Object, key: string): number {
    const value = Reflect.get(area, key) as string | number | undefined;
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = Number.parseFloat(value);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return 0;
  }

  private readTouchAction(event: Object): number {
    const actionValue = Reflect.get(event, 'type') as number | undefined;
    if (typeof actionValue === 'number') {
      return actionValue;
    }

    const fallbackActionValue = Reflect.get(event, 'action') as number | undefined;
    if (typeof fallbackActionValue !== 'number') {
      return TOUCH_ACTION_CANCEL;
    }

    switch (fallbackActionValue) {
      case 0:
        return TOUCH_ACTION_CANCEL;
      case 1:
        return TOUCH_ACTION_DOWN;
      case 2:
        return TOUCH_ACTION_MOVE;
      case 3:
        return TOUCH_ACTION_UP;
      default:
        return TOUCH_ACTION_CANCEL;
    }
  }

  private readPrimaryTouch(event: Object): Object | null {
    const directTouch = Reflect.get(event, 'touch') as Object | undefined;
    if (directTouch !== undefined) {
      return directTouch;
    }

    const touches = Reflect.get(event, 'touches') as Array<Object> | undefined;
    if (Array.isArray(touches) && touches.length > 0) {
      return touches[0];
    }

    const changedTouches = Reflect.get(event, 'changedTouches') as Array<Object> | undefined;
    if (Array.isArray(changedTouches) && changedTouches.length > 0) {
      return changedTouches[0];
    }

    return null;
  }

  private readTouchWindowX(event: Object): number {
    const touchObject = this.readPrimaryTouch(event);
    if (touchObject !== null) {
      const windowX = Reflect.get(touchObject, 'windowX') as number | undefined;
      if (typeof windowX === 'number') {
        return windowX;
      }

      const screenX = Reflect.get(touchObject, 'screenX') as number | undefined;
      if (typeof screenX === 'number') {
        return screenX;
      }
    }

    const windowX = Reflect.get(event, 'windowX') as number | undefined;
    if (typeof windowX === 'number') {
      return windowX;
    }

    const screenX = Reflect.get(event, 'screenX') as number | undefined;
    return typeof screenX === 'number' ? screenX : 0;
  }

  private readTouchWindowY(event: Object): number {
    const touchObject = this.readPrimaryTouch(event);
    if (touchObject !== null) {
      const windowY = Reflect.get(touchObject, 'windowY') as number | undefined;
      if (typeof windowY === 'number') {
        return windowY;
      }

      const screenY = Reflect.get(touchObject, 'screenY') as number | undefined;
      if (typeof screenY === 'number') {
        return screenY;
      }
    }

    const windowY = Reflect.get(event, 'windowY') as number | undefined;
    if (typeof windowY === 'number') {
      return windowY;
    }

    const screenY = Reflect.get(event, 'screenY') as number | undefined;
    return typeof screenY === 'number' ? screenY : 0;
  }

  private toCanvasUnitX(windowX: number): number {
    return this.toBackgroundXUnitsFromCanvasPixels(windowX);
  }

  private toCanvasUnitY(windowY: number): number {
    return this.toBackgroundYUnitsFromCanvasPixels(windowY);
  }

  private async replaceSelectedControl(currentLayout: InputLayout, nextControl: LayoutControlItem): Promise<void> {
    const updatedLayout = currentLayout.clone();
    updatedLayout.controls = currentLayout.controls.map((control: LayoutControlItem) => {
      if (control.id === nextControl.id) {
        return nextControl.clone();
      }
      return control.clone();
    });
    updatedLayout.updatedAt = Date.now();
    await this.persistLayout(updatedLayout, nextControl.id);
  }

  private async persistLayout(layout: InputLayout, nextSelectedControlId: string): Promise<void> {
    try {
      await layoutRepository.saveLayout(layout);
      this.applyLayout(layout);
      this.selectedControlId = nextSelectedControlId;
      this.syncSelectedControl();
      this.refreshLayoutSummary();
      this.updateControlEditorMessage();
    } catch (error) {
      const errorObject = error as Object;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'persist layout failed: %{public}s', JSON.stringify(errorObject));
      await this.showActionError('保存失败', '布局更新没有保存成功，请稍后重试。');
    }
  }

  private async importBackgroundImage(): Promise<void> {
    const currentLayout = layoutRepository.getCurrentLayout();
    if (currentLayout === null) {
      await this.showActionError('导入失败', '当前没有可用布局，暂时无法设置被控游戏截图。');
      return;
    }

    try {
      const documentPicker = new picker.DocumentViewPicker(this.hostContext);
      const selectedUris = await documentPicker.select({
        fileSuffixFilters: ['图片|.png,.jpg,.jpeg,.webp,.bmp'],
        maxSelectNumber: 1,
      });
      if (selectedUris.length === 0) {
        return;
      }

      const previousBackgroundUri = currentLayout.backgroundImageUri;
      const backgroundUri = await this.copyBackgroundIntoSandbox(currentLayout.id, selectedUris[0]);
      const updatedLayout = currentLayout.clone();
      updatedLayout.backgroundImageUri = backgroundUri;
      updatedLayout.updatedAt = Date.now();
      await layoutRepository.saveLayout(updatedLayout);
      this.applyLayout(updatedLayout);
      this.refreshLayoutSummary();
      if (previousBackgroundUri !== backgroundUri) {
        await this.deleteManagedBackgroundImage(previousBackgroundUri);
      }
    } catch (error) {
      const errorObject = error as Object;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'import background failed: %{public}s', JSON.stringify(errorObject));
      await this.showActionError('导入失败', '无法导入被控游戏截图，请确认已选择图片文件。');
    }
  }

  private async clearBackgroundImage(): Promise<void> {
    const currentLayout = layoutRepository.getCurrentLayout();
    if (currentLayout === null || currentLayout.backgroundImageUri.length === 0) {
      return;
    }

    try {
      const previousBackgroundUri = currentLayout.backgroundImageUri;
      const updatedLayout = currentLayout.clone();
      updatedLayout.backgroundImageUri = '';
      updatedLayout.updatedAt = Date.now();
      await layoutRepository.saveLayout(updatedLayout);
      this.applyLayout(updatedLayout);
      this.refreshLayoutSummary();
      await this.deleteManagedBackgroundImage(previousBackgroundUri);
    } catch (error) {
      const errorObject = error as Object;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'clear background failed: %{public}s', JSON.stringify(errorObject));
      await this.showActionError('清除失败', '当前被控游戏截图无法清除，请稍后重试。');
    }
  }

  private async copyBackgroundIntoSandbox(layoutId: string, sourceUri: string): Promise<string> {
    const directoryPath = this.getManagedBackgroundDirectoryPath();
    try {
      await fs.mkdir(directoryPath, true);
    } catch (_) {
    }

    try {
      const extension = this.getUriExtension(sourceUri);
      const destinationPath = `${directoryPath}/${layoutId}-${Date.now()}${extension}`;
      const destinationUri = fileUri.getUriFromPath(destinationPath);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'copy background target, filesDir=%{public}s directory=%{public}s path=%{public}s uri=%{public}s',
        this.hostContext.filesDir, directoryPath, destinationPath, destinationUri);
      await fs.copy(sourceUri, destinationUri);
      return destinationUri;
    } catch (error) {
      const errorObject = error as Object;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'copy background into sandbox failed: %{public}s', JSON.stringify(errorObject));
      throw new Error('Failed to copy background image into sandbox.');
    }
  }

  private getUriExtension(uri: string): string {
    const normalizedUri = uri.split('?')[0];
    const lastSlashIndex = normalizedUri.lastIndexOf('/');
    const fileName = lastSlashIndex >= 0 ? normalizedUri.substring(lastSlashIndex + 1) : normalizedUri;
    const lastDotIndex = fileName.lastIndexOf('.');
    if (lastDotIndex < 0) {
      return '.png';
    }

    const extension = fileName.substring(lastDotIndex).toLowerCase();
    return extension.length > 0 ? extension : '.png';
  }

  private getManagedBackgroundDirectoryPath(): string {
    return this.normalizeManagedBackgroundAbsolutePath(`${this.hostContext.filesDir}/${BACKGROUND_DIRECTORY_NAME}`);
  }

  private normalizeManagedBackgroundAbsolutePath(path: string): string {
    const normalizedPath = path.trim();
    if (normalizedPath.length === 0) {
      return '';
    }

    if (normalizedPath.startsWith('/data/')) {
      return normalizedPath;
    }

    const dataIndex = normalizedPath.indexOf('data/');
    if (dataIndex >= 0) {
      return `/${normalizedPath.substring(dataIndex)}`;
    }

    return normalizedPath;
  }

  private getManagedBackgroundImagePath(uri: string): string {
    const normalizedUri = uri.trim();
    if (normalizedUri.length === 0) {
      return '';
    }

    try {
      const imagePath = new fileUri.FileUri(normalizedUri).path;
      const directoryPath = this.getManagedBackgroundDirectoryPath();
      return imagePath.startsWith(`${directoryPath}/`) ? imagePath : '';
    } catch (_) {
      return '';
    }
  }

  private async deleteManagedBackgroundImage(uri: string): Promise<void> {
    const imagePath = this.getManagedBackgroundImagePath(uri);
    if (imagePath.length === 0) {
      return;
    }

    try {
      if (!(await fs.access(imagePath))) {
        return;
      }
      await fs.unlink(imagePath);
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'delete managed background failed: %{public}s', JSON.stringify(error as Object));
    }
  }

  private async showActionError(title: string, message: string): Promise<void> {
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

  private handleNativeInputEvents(eventsJson: string): void {
    const events = this.parseJsonArray(eventsJson);
    if (events.length === 0) {
      return;
    }

    this.nativeInputEventCount += events.length;
    const lastEventKind = this.getStringField(events[events.length - 1], 'kind');
    const eventLabel = this.toNativeInputEventLabel(lastEventKind);
    this.nativeInputLastEvent = `最近收到 ${events.length} 条${eventLabel}，累计 ${this.nativeInputEventCount} 条。`;
    this.refreshNativeInputState();
    if (this.isExecutionMode()) {
      this.handleExecutionEvents(events);
      return;
    }
    void this.captureBindingFromNativeEvents(events);
  }

  private async captureBindingFromNativeEvents(events: Array<Object>): Promise<void> {
    if (!this.isBindingCaptureListening()) {
      return;
    }

    const selectedControl = this.getSelectedControl();
    if (selectedControl === null) {
      return;
    }

    for (const event of events) {
      const binding = this.tryBuildBindingFromNativeEvent(selectedControl, event);
      if (binding !== null) {
        await this.bindSelectedControl(binding.code, binding.label, binding.sourceLabel,
          binding.rawSource, binding.rawCode, binding.rawName);
        return;
      }
    }
  }

  private tryBuildBindingFromNativeEvent(control: LayoutControlItem, event: Object): CapturedBinding | null {
    const eventKind = this.getStringField(event, 'kind');
    if (eventKind === 'gamepad-button') {
      return this.tryBuildButtonBinding(control, event);
    }
    if (eventKind === 'gamepad-axis') {
      return this.tryBuildAxisBinding(control, event);
    }
    return null;
  }

  private tryBuildButtonBinding(control: LayoutControlItem, event: Object): CapturedBinding | null {
    if (control.inputKind !== CONTROL_TYPE_BUTTON) {
      return null;
    }

    const action = this.getStringField(event, 'action');
    if (action !== 'down') {
      return null;
    }

    const rawCodeValue = this.getNumberField(event, 'code');
    if (rawCodeValue <= 0) {
      return null;
    }

    const rawCode = `${rawCodeValue}`;
    const codeName = this.getStringField(event, 'codeName');
    const bindingCode = this.buildRawBindingCode('gamepad-button', rawCode);
    if (bindingCode.length === 0) {
      return null;
    }
    return new CapturedBinding(bindingCode, this.getGamepadButtonDisplayLabel(rawCode, codeName), '手柄按钮', 'gamepad-button', rawCode, codeName);
  }

  private tryBuildAxisBinding(control: LayoutControlItem, event: Object): CapturedBinding | null {
    const source = this.getStringField(event, 'source');
    if (control.inputKind === CONTROL_TYPE_STICK_MOVE || control.inputKind === CONTROL_TYPE_STICK_LOOK) {
      if (source === 'left-thumbstick') {
        return new CapturedBinding(this.buildRawBindingCode('gamepad-axis', source), '左摇杆', '摇杆', 'gamepad-axis', source, source);
      }
      if (source === 'right-thumbstick') {
        return new CapturedBinding(this.buildRawBindingCode('gamepad-axis', source), '右摇杆', '摇杆', 'gamepad-axis', source, source);
      }
      return null;
    }

    if (control.inputKind !== CONTROL_TYPE_SWIPE) {
      return null;
    }

    if (source === 'left-trigger') {
      const value = Math.abs(this.getNumberField(event, 'brake'));
      if (value < BINDING_AXIS_THRESHOLD) {
        return null;
      }
      return new CapturedBinding(this.buildRawBindingCode('gamepad-axis', source), '左扳机', '线性扳机', 'gamepad-axis', source, source);
    }
    if (source === 'right-trigger') {
      const value = Math.abs(this.getNumberField(event, 'gas'));
      if (value < BINDING_AXIS_THRESHOLD) {
        return null;
      }
      return new CapturedBinding(this.buildRawBindingCode('gamepad-axis', source), '右扳机', '线性扳机', 'gamepad-axis', source, source);
    }
    if (source === 'left-thumbstick') {
      return this.buildStickAxisBinding('left-stick', this.getNumberField(event, 'x'), this.getNumberField(event, 'y'));
    }
    if (source === 'right-thumbstick') {
      let horizontal = this.getNumberField(event, 'z');
      let vertical = this.getNumberField(event, 'rz');
      if (Math.abs(horizontal) < BINDING_AXIS_THRESHOLD && Math.abs(vertical) < BINDING_AXIS_THRESHOLD) {
        horizontal = this.getNumberField(event, 'x');
        vertical = this.getNumberField(event, 'y');
      }
      return this.buildStickAxisBinding('right-stick', horizontal, vertical);
    }
    return null;
  }

  private buildStickAxisBinding(stickName: string, horizontalValue: number, verticalValue: number): CapturedBinding | null {
    if (Math.abs(horizontalValue) < BINDING_AXIS_THRESHOLD && Math.abs(verticalValue) < BINDING_AXIS_THRESHOLD) {
      return null;
    }

    if (Math.abs(horizontalValue) >= Math.abs(verticalValue)) {
      const rawCode = `${stickName}:x`;
      if (stickName === 'left-stick') {
        return new CapturedBinding(this.buildRawBindingCode('gamepad-axis', rawCode), '左摇杆 X 轴', '摇杆轴', 'gamepad-axis', rawCode, rawCode);
      }
      return new CapturedBinding(this.buildRawBindingCode('gamepad-axis', rawCode), '右摇杆 X 轴', '摇杆轴', 'gamepad-axis', rawCode, rawCode);
    }

    const rawCode = `${stickName}:y`;
    if (stickName === 'left-stick') {
      return new CapturedBinding(this.buildRawBindingCode('gamepad-axis', rawCode), '左摇杆 Y 轴', '摇杆轴', 'gamepad-axis', rawCode, rawCode);
    }
    return new CapturedBinding(this.buildRawBindingCode('gamepad-axis', rawCode), '右摇杆 Y 轴', '摇杆轴', 'gamepad-axis', rawCode, rawCode);
  }

  private readKeyEventType(event: Object): number {
    const type = Reflect.get(event, 'type') as number | undefined;
    return typeof type === 'number' ? type : -1;
  }

  private readKeyEventCode(event: Object): number {
    const keyCode = Reflect.get(event, 'keyCode') as number | undefined;
    return typeof keyCode === 'number' ? keyCode : -1;
  }

  private readKeyEventText(event: Object): string {
    const keyText = Reflect.get(event, 'keyText') as string | undefined;
    return typeof keyText === 'string' ? keyText : '';
  }

  private handleKeyBindingEvent(event: Object): boolean {
    if (!this.isBindingCaptureListening()) {
      return false;
    }
    if (this.readKeyEventType(event) !== KEY_EVENT_DOWN) {
      return false;
    }

    const selectedControl = this.getSelectedControl();
    if (selectedControl === null) {
      return false;
    }
    if (selectedControl.inputKind !== CONTROL_TYPE_BUTTON && selectedControl.inputKind !== CONTROL_TYPE_KEYBOARD_MOVE &&
      selectedControl.inputKind !== CONTROL_TYPE_KEYBOARD_LOOK) {
      return false;
    }

    const keyCode = this.readKeyEventCode(event);
    if (keyCode < 0) {
      return false;
    }

    const keyText = this.readKeyEventText(event).trim();
    if (this.isDirectionalKeyboardControlType(selectedControl.inputKind)) {
      if (this.hasPendingDirectionalKeyCode(keyCode)) {
        return true;
      }

      this.pendingDirectionalKeyCodes = [...this.pendingDirectionalKeyCodes, keyCode];
      this.pendingDirectionalKeyLabels = [...this.pendingDirectionalKeyLabels, this.getDirectionalBindingToken(keyText, keyCode)];
      if (this.pendingDirectionalKeyCodes.length < DIRECTIONAL_BINDING_PART_COUNT) {
        this.updateDirectionalBindingHint(selectedControl);
        this.updateControlEditorMessage();
        return true;
      }

      const capturedKeyCodes = [...this.pendingDirectionalKeyCodes];
      const capturedKeyLabels = [...this.pendingDirectionalKeyLabels];
      void this.bindSelectedDirectionalKeys(capturedKeyCodes, capturedKeyLabels);
      return true;
    }

    if (selectedControl.inputKind === CONTROL_TYPE_BUTTON) {
      const rawCode = `${keyCode}`;
      const bindingCode = this.buildRawBindingCode('key-event', rawCode);
      if (bindingCode.length === 0) {
        return false;
      }
      void this.bindSelectedControl(bindingCode, this.getKeyEventButtonDisplayLabel(keyCode, keyText), '按键', 'key-event', rawCode, keyText);
      return true;
    }

    const rawCode = `${keyCode}`;
    const bindingCode = this.buildRawBindingCode('key-event', rawCode);
    if (bindingCode.length === 0) {
      return false;
    }
    const bindingLabel = keyText.length > 0 ? this.formatBindingDisplayName(keyText) : `按键 ${keyCode}`;
    void this.bindSelectedControl(bindingCode, bindingLabel, '键盘', 'key-event', rawCode, keyText);
    return true;
  }

  private readMouseAction(event: Object): number {
    const action = Reflect.get(event, 'action') as number | undefined;
    return typeof action === 'number' ? action : -1;
  }

  private readMouseButton(event: Object): number {
    const button = Reflect.get(event, 'button') as number | undefined;
    return typeof button === 'number' ? button : -1;
  }

  private readMouseRawDeltaX(event: Object): number {
    const delta = Reflect.get(event, 'rawDeltaX') as number | undefined;
    return typeof delta === 'number' ? delta : 0;
  }

  private readMouseRawDeltaY(event: Object): number {
    const delta = Reflect.get(event, 'rawDeltaY') as number | undefined;
    return typeof delta === 'number' ? delta : 0;
  }

  private getMouseButtonLabel(button: number): string {
    switch (button) {
      case 0:
        return '左键';
      case 1:
        return '中键';
      case 2:
        return '右键';
      case 3:
        return '侧键';
      case 4:
        return '扩展键';
      default:
        return `按钮 ${button}`;
    }
  }

  private handleMouseBindingEvent(event: Object): void {
    if (!this.isBindingCaptureListening()) {
      return;
    }

    const selectedControl = this.getSelectedControl();
    if (selectedControl === null) {
      return;
    }

    const action = this.readMouseAction(event);
    if (action === MOUSE_ACTION_BUTTON_DOWN && selectedControl.inputKind === CONTROL_TYPE_BUTTON) {
      const button = this.readMouseButton(event);
      if (button >= 0) {
        const rawCode = `${button}`;
        const bindingCode = this.buildRawBindingCode('mouse-button', rawCode);
        if (bindingCode.length > 0) {
          void this.bindSelectedControl(bindingCode, `鼠标${this.getMouseButtonLabel(button)}`, '鼠标按钮', 'mouse-button', rawCode);
        }
      }
      return;
    }
  }

  private parseJsonArray(jsonText: string): Array<Object> {
    try {
      const value = JSON.parse(jsonText) as Array<Object>;
      return Array.isArray(value) ? value : [];
    } catch (_) {
      return [];
    }
  }

  private getStringField(target: Object, key: string): string {
    const value = Reflect.get(target, key) as string | undefined;
    return typeof value === 'string' ? value : '';
  }

  private getNumberField(target: Object, key: string): number {
    const value = Reflect.get(target, key) as number | undefined;
    return typeof value === 'number' ? value : 0;
  }

  private toNativeInputEventLabel(kind: string): string {
    switch (kind) {
      case 'gamepad-button':
        return '按钮输入';
      case 'gamepad-axis':
        return '摇杆/轴输入';
      case 'device-status':
        return '设备状态变化';
      default:
        return '输入事件';
    }
  }

  private refreshConnectionSummary(state: HidDebugState, devices: Array<RemoteDeviceItem>): void {
    if (!state.connected || state.lastConnectedDeviceId.length === 0) {
      this.connectedDeviceName = '未连接设备';
      this.connectedDeviceId = '';
      if (this.isExecutionMode()) {
        this.resetExecutionState(false);
        this.executionStatusText = '设备已断开，执行已暂停。';
      }
      return;
    }

    this.connectedDeviceId = state.lastConnectedDeviceId;
    this.connectedDeviceName = this.findDeviceName(state.lastConnectedDeviceId, devices);
    if (this.isExecutionMode() && this.executionStatusText === '设备已断开，执行已暂停。') {
      this.executionStatusText = `已重新连接 ${this.connectedDeviceName}，等待输入。`;
    }
  }

  private findDeviceName(deviceId: string, devices: Array<RemoteDeviceItem>): string {
    for (const device of devices) {
      if (device.deviceId === deviceId) {
        return device.name || '未命名设备';
      }
    }
    return '已连接设备';
  }

  private getConnectionDescription(): string {
    return '当前页面会把被控游戏截图尽量铺满画布，操作集中在左上角浮层菜单。';
  }

  private getNativeInputDescription(): string {
    if (this.nativeInputState.monitoringStarted) {
      return '原生输入桥已经就绪，未绑定控件会直接监听这里的手柄输入。';
    }

    if (this.nativeInputState.lastErrorCode !== 0) {
      return `原生输入监控尚未启动，最近错误码为 ${this.nativeInputState.lastErrorCode}。`;
    }

    return '原生输入监控会跟随连接状态启动，手柄绑定依赖这里的实时事件。';
  }

  private getNativeInputMetricsText(): string {
    return `已识别手柄 ${this.nativeInputDeviceCount} 个，队列待取 ${this.nativeInputState.queuedEventCount} 条，累计事件 ${this.nativeInputEventCount} 条。`;
  }

  private getLayoutRepositoryDescription(): string {
    return '先把泛型控件放到画布中央；未绑定控件会自动监听，已绑定控件默认锁定。';
  }

  private getLayoutRepositoryMetricsText(): string {
    return `当前布局：${this.currentLayoutName}，控件 ${this.currentLayoutControlCount}，已保存布局 ${this.savedLayoutCount} 个。`;
  }

  private getBackgroundDescription(): string {
    if (this.currentLayoutBackgroundImageUri.length > 0) {
      return '被控游戏截图已导入，画布会尽量按全屏展示。';
    }

    return '当前布局还未设置被控游戏截图，请先导入截图再摆放控件。';
  }

  private getSelectedControlTypeLabel(): string {
    const selectedControl = this.getSelectedControl();
    if (selectedControl === null) {
      return '未选中';
    }
    return this.getControlTypeLabel(selectedControl.inputKind);
  }

  private getSelectedControlBindingText(): string {
    const selectedControl = this.getSelectedControl();
    if (selectedControl === null) {
      return '未绑定';
    }
    return this.getControlBindingLabel(selectedControl);
  }

  private toPercent(units: number): string {
    return `${clampEditorValue(units, 0, CONTROL_CANVAS_UNITS) / 10}%`;
  }

  private toCanvasXValue(units: number): number {
    const frame = this.getBackgroundContentFrame();
    return frame.x + units / CONTROL_CANVAS_UNITS * Math.max(frame.width, 1);
  }

  private toCanvasYValue(units: number): number {
    const frame = this.getBackgroundContentFrame();
    return frame.y + units / CONTROL_CANVAS_UNITS * Math.max(frame.height, 1);
  }

  private toCanvasWidthValue(units: number): number {
    const frame = this.getBackgroundContentFrame();
    return clampEditorValue(units, 0, CONTROL_CANVAS_UNITS) / CONTROL_CANVAS_UNITS * Math.max(frame.width, 1);
  }

  private toCanvasHeightValue(units: number): number {
    const frame = this.getBackgroundContentFrame();
    return clampEditorValue(units, 0, CONTROL_CANVAS_UNITS) / CONTROL_CANVAS_UNITS * Math.max(frame.height, 1);
  }

  private getControlBodyWidthValue(control: LayoutControlItem): number {
    if (this.isRoundControlType(control.inputKind)) {
      return this.toCanvasWidthValue(control.width);
    }
    return this.toCanvasWidthValue(control.width);
  }

  private getControlBodyHeightValue(control: LayoutControlItem): number {
    if (this.isRoundControlType(control.inputKind)) {
      return this.toCanvasWidthValue(control.width);
    }
    return this.toCanvasHeightValue(control.height);
  }

  private getBindingCaptionWidthUnits(control: LayoutControlItem): number {
    if (this.isRoundControlType(control.inputKind)) {
      return Math.max(control.width, 132);
    }
    if (control.inputKind === CONTROL_TYPE_SWIPE) {
      return Math.max(control.width, 220);
    }
    return control.width;
  }

  private getBindingCaptionWidthValue(control: LayoutControlItem): number {
    return this.toCanvasWidthValue(this.getBindingCaptionWidthUnits(control));
  }

  private getControlOverlayWidthValue(control: LayoutControlItem): number {
    return Math.max(this.getControlBodyWidthValue(control), this.getBindingCaptionWidthValue(control));
  }

  private getControlOverlayXValue(control: LayoutControlItem): number {
    const bodyWidth = this.getControlBodyWidthValue(control);
    const overlayWidth = this.getControlOverlayWidthValue(control);
    return this.toCanvasXValue(control.x) - Math.max(0, (overlayWidth - bodyWidth) / 2);
  }

  private getControlRenderKey(control: LayoutControlItem): string {
    const selectedFlag = !this.isExecutionMode() && this.selectedControlId === control.id ? 'selected' : 'idle';
    const executingFlag = this.executionActiveControlId === control.id ? 'executing' : 'rest';
    return `${control.id}:${control.x}:${control.y}:${control.width}:${control.height}:${control.inputCode}:${control.payloadJson}:${selectedFlag}:${executingFlag}:${this.interactionMode}`;
  }

  private isControlExecuting(control: LayoutControlItem): boolean {
    return this.isExecutionMode() && this.executionActiveControlId === control.id;
  }

  private isControlSelected(control: LayoutControlItem): boolean {
    return !this.isExecutionMode() && this.selectedControlId === control.id;
  }

  private isControlHighlighted(control: LayoutControlItem): boolean {
    return this.isControlSelected(control) || this.isControlExecuting(control);
  }

  private getControlBorderColor(control: LayoutControlItem): string {
    if (this.isControlExecuting(control)) {
      return '#34D399';
    }
    if (this.isControlSelected(control)) {
      return '#FFFFFF';
    }
    return 'rgba(255,255,255,0.35)';
  }

  private getControlBorderWidth(control: LayoutControlItem): number {
    return this.isControlHighlighted(control) ? 2 : 1;
  }

  private getControlBodyBorderRadius(control: LayoutControlItem): number {
    if (this.isRoundControlType(control.inputKind) || control.inputKind === CONTROL_TYPE_SWIPE) {
      return 999;
    }
    if (this.isLookControlType(control.inputKind)) {
      return 20;
    }
    return 18;
  }

  private getControlSurfaceColor(control: LayoutControlItem): string {
    if (this.isControlExecuting(control)) {
      return 'rgba(13, 138, 95, 0.78)';
    }
    if (this.isControlSelected(control)) {
      return 'rgba(20, 86, 240, 0.82)';
    }
    if (this.isRoundControlType(control.inputKind)) {
      return 'rgba(15, 23, 42, 0.70)';
    }
    if (control.inputKind === CONTROL_TYPE_SWIPE) {
      return 'rgba(8, 47, 73, 0.74)';
    }
    return 'rgba(16, 24, 40, 0.60)';
  }

  private getRoundGlyphSize(control: LayoutControlItem): number {
    if (control.width <= 72) {
      return 24;
    }
    if (control.width <= 96) {
      return 30;
    }
    return 40;
  }

  private getMoveGlyphArrowSize(control: LayoutControlItem): number {
    return this.getRoundGlyphSize(control) <= 24 ? 10 : 12;
  }

  private getMoveGlyphCenterSize(control: LayoutControlItem): number {
    return Math.max(8, Math.round(this.getRoundGlyphSize(control) * 0.3));
  }

  private getMoveGlyphHalfGap(control: LayoutControlItem): number {
    return Math.round((this.getRoundGlyphSize(control) - this.getMoveGlyphCenterSize(control)) / 2);
  }

  private getLookGlyphHeight(control: LayoutControlItem): number {
    return Math.max(20, Math.round(this.getRoundGlyphSize(control) * 0.8));
  }

  private getLookCameraBodyWidth(control: LayoutControlItem): number {
    return Math.max(18, Math.round(this.getRoundGlyphSize(control) * 0.7));
  }

  private getLookCameraBodyHeight(control: LayoutControlItem): number {
    return Math.max(14, Math.round(this.getLookGlyphHeight(control) * 0.55));
  }

  private getLookLensSize(control: LayoutControlItem): number {
    return Math.max(8, Math.round(this.getLookCameraBodyHeight(control) * 0.55));
  }

  private getLookTopBarWidth(control: LayoutControlItem): number {
    return Math.max(8, Math.round(this.getLookCameraBodyWidth(control) * 0.45));
  }

  private getLookTopBarHeight(control: LayoutControlItem): number {
    return Math.max(4, Math.round(this.getLookCameraBodyHeight(control) * 0.2));
  }

  private getControlNameFontSize(control: LayoutControlItem): number {
    if (control.width <= 72) {
      return 10;
    }
    if (control.width <= 96) {
      return 11;
    }
    return 12;
  }

  private getBindingLabelFontSize(control: LayoutControlItem): number {
    if (control.width <= 80) {
      return 9;
    }
    return 10;
  }

  private getSwipeDirectionArrowFontSize(control: LayoutControlItem): number {
    return control.width <= 140 ? 11 : 13;
  }

  private getSwipeDirectionOffsetValue(control: LayoutControlItem): number {
    return this.getSwipeDirectionArrowFontSize(control) + SWIPE_DIRECTION_GAP;
  }

  @Builder
  private buildSwipeDirectionIndicator(control: LayoutControlItem) {
    Text('→')
      .width(this.getControlBodyWidthValue(control) - CONTROL_SWIPE_HANDLE_SIZE)
      .fontSize(this.getSwipeDirectionArrowFontSize(control))
      .fontWeight(FontWeight.Bold)
      .fontColor('rgba(253,230,138,0.92)')
      .textAlign(TextAlign.Center)
  }

  @Builder
  private buildBindingCaption(control: LayoutControlItem) {
    Text(this.getControlBindingCaptionText(control))
      .width(this.getBindingCaptionWidthValue(control))
      .fontSize(this.getBindingLabelFontSize(control))
      .fontColor('#EAECF0')
      .textAlign(TextAlign.Center)
      .lineHeight(this.getBindingLabelFontSize(control) + 4)
  }

  @Builder
  private buildMoveGlyph(control: LayoutControlItem) {
    Stack() {
      Text('↑')
        .fontSize(this.getMoveGlyphArrowSize(control))
        .fontWeight(FontWeight.Bold)
        .fontColor('#F8FAFC')
        .position({ x: this.getMoveGlyphHalfGap(control), y: 0 })

      Text('↓')
        .fontSize(this.getMoveGlyphArrowSize(control))
        .fontWeight(FontWeight.Bold)
        .fontColor('#F8FAFC')
        .position({ x: this.getMoveGlyphHalfGap(control), y: this.getRoundGlyphSize(control) - this.getMoveGlyphArrowSize(control) })

      Text('←')
        .fontSize(this.getMoveGlyphArrowSize(control))
        .fontWeight(FontWeight.Bold)
        .fontColor('#F8FAFC')
        .position({ x: 0, y: this.getMoveGlyphHalfGap(control) - 1 })

      Text('→')
        .fontSize(this.getMoveGlyphArrowSize(control))
        .fontWeight(FontWeight.Bold)
        .fontColor('#F8FAFC')
        .position({ x: this.getRoundGlyphSize(control) - this.getMoveGlyphArrowSize(control), y: this.getMoveGlyphHalfGap(control) - 1 })

      Column()
        .width(this.getMoveGlyphCenterSize(control))
        .height(this.getMoveGlyphCenterSize(control))
        .backgroundColor('rgba(255,255,255,0.18)')
        .borderRadius(this.getMoveGlyphCenterSize(control))
        .position({ x: this.getMoveGlyphHalfGap(control), y: this.getMoveGlyphHalfGap(control) })
    }
    .width(this.getRoundGlyphSize(control))
    .height(this.getRoundGlyphSize(control))
  }

  @Builder
  private buildLookGlyph(control: LayoutControlItem) {
    Stack() {
      Column()
        .width(this.getLookTopBarWidth(control))
        .height(this.getLookTopBarHeight(control))
        .backgroundColor('rgba(255,255,255,0.82)')
        .borderRadius(2)
        .position({ x: Math.round((this.getRoundGlyphSize(control) - this.getLookTopBarWidth(control)) / 2), y: 2 })

      Row() {
        Column()
          .width(this.getLookLensSize(control))
          .height(this.getLookLensSize(control))
          .borderRadius(this.getLookLensSize(control))
          .border({ width: 2, color: '#F8FAFC' })
      }
      .width(this.getLookCameraBodyWidth(control))
      .height(this.getLookCameraBodyHeight(control))
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .border({ width: 2, color: '#F8FAFC' })
      .borderRadius(6)
      .position({ x: Math.round((this.getRoundGlyphSize(control) - this.getLookCameraBodyWidth(control)) / 2),
        y: Math.max(6, Math.round(this.getLookGlyphHeight(control) * 0.25)) })
    }
    .width(this.getRoundGlyphSize(control))
    .height(this.getLookGlyphHeight(control))
  }

  @Builder
  private buildSwipeHandle(controlId: string, handle: string) {
    Column()
      .width(CONTROL_SWIPE_HANDLE_SIZE)
      .height(CONTROL_SWIPE_HANDLE_SIZE)
      .backgroundColor(handle === 'start' ? '#E2E8F0' : '#FDE68A')
      .borderRadius(CONTROL_SWIPE_HANDLE_SIZE)
      .border({ width: 2, color: 'rgba(15, 23, 42, 0.72)' })
      .onTouch((event) => {
        const action = this.readTouchAction(event as Object);
        if (action === TOUCH_ACTION_DOWN) {
          this.startSwipeHandleDrag(controlId, handle);
        }
      })
  }

  @Builder
  private buildSwipeOverlay(control: LayoutControlItem) {
    Column({ space: CONTROL_LABEL_GAP }) {
      Stack() {
        Column({ space: SWIPE_DIRECTION_GAP }) {
          this.buildSwipeDirectionIndicator(control)

          Row({ space: 8 }) {
            this.buildSwipeHandle(control.id, 'start')

            Column()
              .layoutWeight(1)
              .height('100%')
              .backgroundColor(this.getControlSurfaceColor(control))
              .borderRadius(999)
              .border({
                width: this.getControlBorderWidth(control),
                color: this.getControlBorderColor(control),
              })

            this.buildSwipeHandle(control.id, 'end')
          }
          .width(this.getControlBodyWidthValue(control))
          .height(this.getControlBodyHeightValue(control))
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
        }
        .rotate({ angle: this.getControlRotationAngle(control), x: 0, y: 0, z: 1, centerX: '50%', centerY: '50%' })
      }
      .width(this.getControlBodyWidthValue(control))
      .height(this.getControlBodyHeightValue(control) + this.getSwipeDirectionOffsetValue(control))
      .onTouch((event) => {
        this.handleControlTouch(control.id, event as Object);
      })

      Text(control.label)
        .width(this.getBindingCaptionWidthValue(control))
        .fontSize(this.getControlNameFontSize(control))
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      this.buildBindingCaption(control)
    }
    .width(this.getControlOverlayWidthValue(control))
    .alignItems(HorizontalAlign.Center)
    .position({
      x: this.getControlOverlayXValue(control),
      y: this.toCanvasYValue(control.y) - this.getSwipeDirectionOffsetValue(control),
    })
  }

  @Builder
  private buildStandardOverlay(control: LayoutControlItem) {
    Column({ space: CONTROL_LABEL_GAP }) {
      Stack() {
        Column({ space: control.width <= 72 ? 4 : 8 }) {
          if (this.isMoveControlType(control.inputKind)) {
            this.buildMoveGlyph(control)
          } else if (this.isLookControlType(control.inputKind)) {
            this.buildLookGlyph(control)
          }

          Text(control.label)
            .fontSize(this.getControlNameFontSize(control))
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .padding(8)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width(this.getControlBodyWidthValue(control))
      .height(this.getControlBodyHeightValue(control))
      .backgroundColor(this.getControlSurfaceColor(control))
      .borderRadius(this.getControlBodyBorderRadius(control))
      .border({
        width: this.getControlBorderWidth(control),
        color: this.getControlBorderColor(control),
      })
      .onTouch((event) => {
        this.handleControlTouch(control.id, event as Object);
      })

      this.buildBindingCaption(control)
    }
    .width(this.getControlOverlayWidthValue(control))
    .alignItems(HorizontalAlign.Center)
    .position({
      x: this.getControlOverlayXValue(control),
      y: this.toCanvasYValue(control.y),
    })
  }

  @Builder
  private buildControlOverlay(control: LayoutControlItem) {
    if (control.inputKind === CONTROL_TYPE_SWIPE) {
      this.buildSwipeOverlay(control)
    } else {
      this.buildStandardOverlay(control)
    }
  }

  @Builder
  private buildControlLibraryItem(libraryItem: ControlLibraryItem) {
    Button(libraryItem.label)
      .width('100%')
      .backgroundColor('rgba(255, 255, 255, 0.12)')
      .fontColor('#FFFFFF')
      .onClick(() => {
        this.addControlFromLibrary(libraryItem);
      })
  }

  @Builder
  private buildCanvasLayer() {
    Stack() {
      if (this.currentLayoutHasBackground) {
        Image(this.currentLayoutBackgroundImageUri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
      } else {
        Column({ space: 14 }) {
          Text('导入被控游戏截图后开始布置控件')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F8FAFC')

          Text('截图用于辅助定位控件位置。\n请对运行游戏的设备进行全屏截图，不要调整截图分辨率。\n导入截图后，点击左上角按钮开始添加控件。')
            .fontSize(14)
            .fontColor('#CBD5E1')
            .textAlign(TextAlign.Center)

          Button('导入被控游戏截图')
            .backgroundColor(PRIMARY_COLOR)
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.importBackgroundImage();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding(24)
      }

      if (this.currentLayoutHasBackground) {
        ForEach(this.layoutControls, (control: LayoutControlItem) => {
          this.buildControlOverlay(control)
        }, (control: LayoutControlItem) => this.getControlRenderKey(control))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#07111F')
    .onTouch((event) => {
      this.handleCanvasTouch(event as Object);
    })
    .parallelGesture(
      PinchGesture({ fingers: 2, distance: 4 })
        .onActionStart(() => {
          this.startSelectedControlPinch();
        })
        .onActionUpdate((event) => {
          this.updateSelectedControlPinch(event as Object);
        })
        .onActionEnd(() => {
          this.finishSelectedControlPinch();
        })
    )
    .onAreaChange((_, newValue) => {
      this.updateCanvasSize(newValue as Object);
    })
  }

  @Builder
  private buildControlLibraryPanel() {
    Column({ space: 10 }) {
      Text('添加控件')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('100%')

      Text('控件默认位于画布中央，可自行拖动到想要的位置。在屏幕空白处滑动也可以调整控件位置。')
        .fontSize(12)
        .fontColor('#CBD5E1')
        .width('100%')

      Text('在屏幕任意位置双指捏合可调整控件大小。滑动控件还能拖动两端圆点拉伸和转向。')
        .fontSize(12)
        .fontColor('#CBD5E1')
        .width('100%')

      Text('选中控件后按下键盘或手柄按键即可进行按键绑定。绑定后如需重新绑定，请点击菜单中的清除绑定按钮。')
        .fontSize(12)
        .fontColor('#CBD5E1')
        .width('100%')

      ForEach(CONTROL_LIBRARY_ITEMS, (libraryItem: ControlLibraryItem) => {
        this.buildControlLibraryItem(libraryItem)
      }, (libraryItem: ControlLibraryItem) => libraryItem.controlType)
    }
    .width('100%')
  }

  @Builder
  private buildSelectedControlPanel() {
    Column({ space: 12 }) {
      Text('当前控件')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('100%')

      Row({ space: 12 }) {
        Button('清除绑定')
          .layoutWeight(1)
          .enabled(this.hasSelectedControlBinding())
          .backgroundColor('rgba(255, 255, 255, 0.14)')
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.clearSelectedBinding();
          })

        Button('删除选中')
          .layoutWeight(1)
          .enabled(this.hasSelectedControl())
          .backgroundColor('#FEE4E2')
          .fontColor('#B42318')
          .onClick(() => {
            this.removeSelectedControl();
          })
      }

      Text(this.controlEditorMessage)
        .fontSize(12)
        .fontColor('#E2E8F0')
        .width('100%')

      Text(`类型：${this.getSelectedControlTypeLabel()} · 绑定：${this.getSelectedControlBindingText()}`)
        .fontSize(12)
        .fontColor('#CBD5E1')
        .width('100%')

      Text(this.bindingCaptureHint)
        .fontSize(12)
        .fontColor(this.isBindingCaptureListening() ? '#FDE68A' : '#CBD5E1')
        .width('100%')

    }
    .width('100%')
  }

  @Builder
  private buildFloatingMenuPanel() {
    Column({ space: 12 }) {
      Scroll() {
        Column({ space: 12 }) {
          if (!this.isExecutionMode() && this.hasSelectedControl()) {
            Column({ space: 10 }) {
              this.buildSelectedControlPanel()
            }
            .width('100%')
            .padding(14)
            .backgroundColor('rgba(255, 255, 255, 0.08)')
            .borderRadius(20)
          }

          if (!this.isExecutionMode()) {
            Column({ space: 10 }) {
              this.buildControlLibraryPanel()
            }
            .width('100%')
            .padding(14)
            .backgroundColor('rgba(255, 255, 255, 0.08)')
            .borderRadius(20)
          }

          Column({ space: 8 }) {
            Text(this.currentLayoutName)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .width('100%')

            Text(`${this.getExecutionModeLabel()} · 已绑定 ${this.getBoundControlCount()} 个控件`)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.getExecutionModeAccentColor())
              .width('100%')

            Text(`${this.connectedDeviceName} · ${this.currentLayoutHasBackground ? '已导入截图' : '未导入截图'}`)
              .fontSize(12)
              .fontColor('#CBD5E1')
              .width('100%')

            Text(this.getExecutionModeDescription())
              .fontSize(12)
              .fontColor('#CBD5E1')
              .width('100%')

            Text(this.executionStatusText)
              .fontSize(12)
              .fontColor(this.isExecutionMode() ? '#D1FAE5' : '#BFDBFE')
              .width('100%')

            Text(this.getLayoutRepositoryMetricsText())
              .fontSize(12)
              .fontColor('#CBD5E1')
              .width('100%')

            Text(this.getBackgroundDescription())
              .fontSize(12)
              .fontColor('#94A3B8')
              .width('100%')

            Text(this.getNativeInputMetricsText())
              .fontSize(11)
              .fontColor('#94A3B8')
              .width('100%')
          }
          .width('100%')
          .padding(14)
          .backgroundColor('rgba(255, 255, 255, 0.08)')
          .borderRadius(20)

          Row({ space: 8 }) {
            Button(this.isExecutionMode() ? '返回编辑' : '保存并执行')
              .layoutWeight(1)
              .enabled(this.isExecutionMode() || this.getBoundControlCount() > 0)
              .backgroundColor(this.isExecutionMode() ? 'rgba(255, 255, 255, 0.12)' : SUCCESS_COLOR)
              .fontColor('#FFFFFF')
              .onClick(() => {
                if (this.isExecutionMode()) {
                  this.exitExecutionMode();
                  return;
                }
                this.saveLayoutAndEnterExecutionMode();
              })

            Button('返回设备页')
              .layoutWeight(1)
              .backgroundColor('rgba(255, 255, 255, 0.12)')
              .fontColor('#FFFFFF')
              .onClick(() => {
                router.back();
              })
          }
          .width('100%')

          Row({ space: 8 }) {
            Button(this.currentLayoutHasBackground ? '更换被控游戏截图' : '导入被控游戏截图')
              .width('100%')
              .enabled(!this.isExecutionMode())
              .backgroundColor(PRIMARY_COLOR)
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.importBackgroundImage();
              })
          }
          .width('100%')

          Button('清除被控游戏截图')
            .width('100%')
            .enabled(this.currentLayoutHasBackground && !this.isExecutionMode())
            .backgroundColor('rgba(127, 29, 29, 0.84)')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.clearBackgroundImage();
            })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width(MENU_PANEL_WIDTH)
    .height(this.getMenuPanelHeight())
    .padding(14)
    .backgroundColor('rgba(2, 6, 23, 0.88)')
    .borderRadius(24)
    .position({
      x: this.getMenuPanelX(),
      y: this.getMenuPanelY(),
    })
  }

  @Builder
  private buildFloatingMenuButton() {
    Column({ space: 5 }) {
      Row() {}
        .width(22)
        .height(2)
        .backgroundColor('#FFFFFF')
        .borderRadius(99)

      Row() {}
        .width(22)
        .height(2)
        .backgroundColor('#FFFFFF')
        .borderRadius(99)

      Row() {}
        .width(22)
        .height(2)
        .backgroundColor('#FFFFFF')
        .borderRadius(99)
    }
    .width(MENU_BUTTON_WIDTH)
    .height(MENU_BUTTON_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(15, 23, 42, 0.88)')
    .borderRadius(22)
    .border({
      width: 1,
      color: 'rgba(255,255,255,0.20)',
    })
    .position({
      x: this.menuButtonX,
      y: this.menuButtonY,
    })
    .onTouch((event) => {
      this.handleMenuButtonTouch(event as Object);
    })
  }

  @Builder
  private buildExecutionTouchFeedback() {
    Stack() {
      Column()
        .width(EXECUTION_TOUCH_FEEDBACK_SIZE)
        .height(EXECUTION_TOUCH_FEEDBACK_SIZE)
        .backgroundColor(this.executionTouchFeedbackDimmed ? 'rgba(52, 211, 153, 0.12)' : 'rgba(52, 211, 153, 0.28)')
        .borderRadius(EXECUTION_TOUCH_FEEDBACK_SIZE)
        .border({
          width: 2,
          color: this.executionTouchFeedbackDimmed ? 'rgba(52, 211, 153, 0.42)' : 'rgba(110, 231, 183, 0.96)',
        })

      Column()
        .width(10)
        .height(10)
        .backgroundColor(this.executionTouchFeedbackDimmed ? 'rgba(110, 231, 183, 0.64)' : '#ECFDF5')
        .borderRadius(10)
    }
    .width(EXECUTION_TOUCH_FEEDBACK_SIZE)
    .height(EXECUTION_TOUCH_FEEDBACK_SIZE)
    .position({
      x: this.toCanvasXValue(this.executionTouchFeedbackXUnits) - EXECUTION_TOUCH_FEEDBACK_SIZE / 2,
      y: this.toCanvasYValue(this.executionTouchFeedbackYUnits) - EXECUTION_TOUCH_FEEDBACK_SIZE / 2,
    })
  }

  build() {
    Stack() {
      this.buildCanvasLayer()

      if (this.executionTouchFeedbackVisible) {
        this.buildExecutionTouchFeedback()
      }

      if (this.menuExpanded) {
        this.buildFloatingMenuPanel()
      }

      this.buildFloatingMenuButton()
    }
    .backgroundColor('#07111F')
    .height('100%')
    .width('100%')
    .onAreaChange((_, newValue) => {
      this.updateViewportSize(newValue as Object);
    })
    .focusable(true)
    .onKeyEvent((event) => {
      return this.handleExecutionKeyEvent(event as Object) || this.handleKeyBindingEvent(event as Object);
    })
    .onMouse((event) => {
      this.handleMouseBindingEvent(event as Object);
    })
  }
}