import type commonAbility from '@ohos.app.ability.common';
import { hilog } from '@kit.PerformanceAnalysisKit';
import preferences from '@ohos.data.preferences';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'LayoutRepository';
const DEFAULT_LAYOUT_ID = 'default-layout';
const SNAPSHOT_KEY = 'layout_snapshot';
const STORE_OPTIONS: preferences.Options = {
  name: 'input_layouts',
};

export class LayoutControlItem {
  id: string;
  label: string;
  inputKind: string;
  inputCode: string;
  actionType: string;
  x: number;
  y: number;
  width: number;
  height: number;
  payloadJson: string;

  constructor(id: string, label: string, inputKind: string, inputCode: string, actionType: string,
    x: number, y: number, width: number, height: number, payloadJson: string) {
    this.id = id;
    this.label = label;
    this.inputKind = inputKind;
    this.inputCode = inputCode;
    this.actionType = actionType;
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
    this.payloadJson = payloadJson;
  }

  clone(): LayoutControlItem {
    return new LayoutControlItem(
      this.id,
      this.label,
      this.inputKind,
      this.inputCode,
      this.actionType,
      this.x,
      this.y,
      this.width,
      this.height,
      this.payloadJson
    );
  }
}

export class InputLayout {
  id: string;
  name: string;
  backgroundImageUri: string;
  controls: Array<LayoutControlItem>;
  updatedAt: number;

  constructor(id: string, name: string, backgroundImageUri: string, controls: Array<LayoutControlItem>, updatedAt: number) {
    this.id = id;
    this.name = name;
    this.backgroundImageUri = backgroundImageUri;
    this.controls = controls;
    this.updatedAt = updatedAt;
  }

  clone(): InputLayout {
    return new InputLayout(
      this.id,
      this.name,
      this.backgroundImageUri,
      this.controls.map((control: LayoutControlItem) => control.clone()),
      this.updatedAt
    );
  }
}

export class LayoutRepositorySnapshot {
  currentLayoutId: string;
  layouts: Array<InputLayout>;

  constructor(currentLayoutId: string, layouts: Array<InputLayout>) {
    this.currentLayoutId = currentLayoutId;
    this.layouts = layouts;
  }

  clone(): LayoutRepositorySnapshot {
    return new LayoutRepositorySnapshot(
      this.currentLayoutId,
      this.layouts.map((layout: InputLayout) => layout.clone())
    );
  }
}

export class LayoutRepository {
  private store: preferences.Preferences | null = null;
  private context: commonAbility.UIAbilityContext | null = null;
  private initializationPromise: Promise<void> | null = null;
  private snapshot: LayoutRepositorySnapshot = this.ensureSnapshotConsistency(new LayoutRepositorySnapshot('', []));

  async initialize(context: commonAbility.UIAbilityContext): Promise<void> {
    this.context = context;
    if (this.store !== null) {
      return;
    }

    if (this.initializationPromise !== null) {
      await this.initializationPromise;
      return;
    }

    this.initializationPromise = this.initializeInternal(context);
    try {
      await this.initializationPromise;
    } finally {
      this.initializationPromise = null;
    }
  }

  listLayouts(): Array<InputLayout> {
    return this.snapshot.layouts.map((layout: InputLayout) => layout.clone());
  }

  getCurrentLayout(): InputLayout | null {
    for (const layout of this.snapshot.layouts) {
      if (layout.id === this.snapshot.currentLayoutId) {
        return layout.clone();
      }
    }
    return null;
  }

  createEmptyLayout(name: string = '新布局'): InputLayout {
    return new InputLayout(this.createLayoutId(), name, '', [], Date.now());
  }

  async saveLayout(layout: InputLayout): Promise<void> {
    await this.ensureReady();
    const normalizedLayout = this.normalizeLayout(layout);
    const nextLayouts = this.snapshot.layouts.map((item: InputLayout) => item.clone());
    let replaced = false;
    for (let index = 0; index < nextLayouts.length; index++) {
      if (nextLayouts[index].id === normalizedLayout.id) {
        nextLayouts[index] = normalizedLayout;
        replaced = true;
        break;
      }
    }

    if (!replaced) {
      nextLayouts.push(normalizedLayout);
    }

    this.snapshot = this.ensureSnapshotConsistency(new LayoutRepositorySnapshot(this.snapshot.currentLayoutId, nextLayouts));
    await this.persistSnapshot();
  }

  async setCurrentLayout(layoutId: string): Promise<boolean> {
    await this.ensureReady();
    if (layoutId.trim().length === 0) {
      return false;
    }

    for (const layout of this.snapshot.layouts) {
      if (layout.id === layoutId) {
        this.snapshot = new LayoutRepositorySnapshot(layoutId, this.snapshot.layouts.map((item: InputLayout) => item.clone()));
        await this.persistSnapshot();
        return true;
      }
    }

    return false;
  }

  async deleteLayout(layoutId: string): Promise<boolean> {
    await this.ensureReady();
    const remainingLayouts = this.snapshot.layouts
      .filter((layout: InputLayout) => layout.id !== layoutId)
      .map((layout: InputLayout) => layout.clone());

    if (remainingLayouts.length === this.snapshot.layouts.length) {
      return false;
    }

    const nextCurrentLayoutId = this.snapshot.currentLayoutId === layoutId ? '' : this.snapshot.currentLayoutId;
    this.snapshot = this.ensureSnapshotConsistency(new LayoutRepositorySnapshot(nextCurrentLayoutId, remainingLayouts));
    await this.persistSnapshot();
    return true;
  }

  private async initializeInternal(context: commonAbility.UIAbilityContext): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, STORE_OPTIONS);
      const rawSnapshot = this.store.getSync(SNAPSHOT_KEY, '') as string | undefined;
      if (typeof rawSnapshot === 'string' && rawSnapshot.length > 0) {
        this.snapshot = this.ensureSnapshotConsistency(this.parseSnapshot(rawSnapshot));
      } else {
        this.snapshot = this.ensureSnapshotConsistency(new LayoutRepositorySnapshot('', []));
      }

      await this.persistSnapshot();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'layout repository ready, layoutCount=%{public}d currentLayout=%{public}s',
        this.snapshot.layouts.length, this.snapshot.currentLayoutId);
    } catch (error) {
      const errorObject = error as Object;
      this.store = null;
      this.snapshot = this.ensureSnapshotConsistency(new LayoutRepositorySnapshot('', []));
      hilog.error(LOG_DOMAIN, LOG_TAG, 'failed to initialize layout repository: %{public}s', JSON.stringify(errorObject));
      throw new Error('Failed to initialize layout repository.');
    }
  }

  private async ensureReady(): Promise<void> {
    if (this.store !== null) {
      return;
    }

    if (this.context === null) {
      throw new Error('Layout repository has not been initialized.');
    }

    await this.initialize(this.context);
  }

  private async persistSnapshot(): Promise<void> {
    if (this.store === null) {
      return;
    }

    try {
      await this.store.put(SNAPSHOT_KEY, this.serializeSnapshot(this.snapshot));
      await this.store.flush();
    } catch (error) {
      const errorObject = error as Object;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'failed to persist layout snapshot: %{public}s', JSON.stringify(errorObject));
      throw new Error('Failed to persist layout snapshot.');
    }
  }

  private parseSnapshot(snapshotJson: string): LayoutRepositorySnapshot {
    try {
      return this.snapshotFromObject(JSON.parse(snapshotJson) as Object);
    } catch (_) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'failed to parse layout snapshot, fallback to default layout');
      return new LayoutRepositorySnapshot('', []);
    }
  }

  private snapshotFromObject(target: Object): LayoutRepositorySnapshot {
    const currentLayoutId = this.getStringField(target, 'currentLayoutId');
    const layoutObjects = this.getObjectArrayField(target, 'layouts');
    const layouts = layoutObjects.map((layoutObject: Object) => this.layoutFromObject(layoutObject));
    return new LayoutRepositorySnapshot(currentLayoutId, layouts);
  }

  private layoutFromObject(target: Object): InputLayout {
    const controlObjects = this.getObjectArrayField(target, 'controls');
    const controls = controlObjects.map((controlObject: Object) => this.controlFromObject(controlObject));
    return this.normalizeLayout(new InputLayout(
      this.getStringField(target, 'id'),
      this.getStringField(target, 'name'),
      this.getStringField(target, 'backgroundImageUri'),
      controls,
      this.getNumberField(target, 'updatedAt')
    ));
  }

  private controlFromObject(target: Object): LayoutControlItem {
    return this.normalizeControl(new LayoutControlItem(
      this.getStringField(target, 'id'),
      this.getStringField(target, 'label'),
      this.getStringField(target, 'inputKind'),
      this.getStringField(target, 'inputCode'),
      this.getStringField(target, 'actionType'),
      this.getNumberField(target, 'x'),
      this.getNumberField(target, 'y'),
      this.getNumberField(target, 'width'),
      this.getNumberField(target, 'height'),
      this.getStringField(target, 'payloadJson')
    ));
  }

  private ensureSnapshotConsistency(snapshot: LayoutRepositorySnapshot): LayoutRepositorySnapshot {
    const normalizedLayouts = snapshot.layouts.map((layout: InputLayout) => this.normalizeLayout(layout));
    if (normalizedLayouts.length === 0) {
      normalizedLayouts.push(this.createDefaultLayout());
    }

    let currentLayoutId = snapshot.currentLayoutId;
    const hasCurrentLayout = normalizedLayouts.some((layout: InputLayout) => layout.id === currentLayoutId);
    if (!hasCurrentLayout) {
      currentLayoutId = normalizedLayouts[0].id;
    }

    return new LayoutRepositorySnapshot(currentLayoutId, normalizedLayouts);
  }

  private normalizeLayout(layout: InputLayout): InputLayout {
    const layoutId = layout.id.trim().length > 0 ? layout.id.trim() : this.createLayoutId();
    const layoutName = layout.name.trim().length > 0 ? layout.name.trim() : '未命名布局';
    return new InputLayout(
      layoutId,
      layoutName,
      layout.backgroundImageUri,
      layout.controls.map((control: LayoutControlItem) => this.normalizeControl(control)),
      layout.updatedAt > 0 ? layout.updatedAt : Date.now()
    );
  }

  private normalizeControl(control: LayoutControlItem): LayoutControlItem {
    const controlId = control.id.trim().length > 0 ? control.id.trim() : `control-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
    const controlLabel = control.label.trim().length > 0 ? control.label.trim() : '未命名控件';
    return new LayoutControlItem(
      controlId,
      controlLabel,
      control.inputKind,
      control.inputCode,
      control.actionType,
      control.x,
      control.y,
      control.width,
      control.height,
      control.payloadJson
    );
  }

  private createDefaultLayout(): InputLayout {
    return new InputLayout(DEFAULT_LAYOUT_ID, '默认布局', '', [], Date.now());
  }

  private createLayoutId(): string {
    return `layout-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
  }

  private serializeSnapshot(snapshot: LayoutRepositorySnapshot): string {
    return JSON.stringify(snapshot.clone());
  }

  private getStringField(target: Object, key: string): string {
    const value = Reflect.get(target, key) as string | undefined;
    return typeof value === 'string' ? value : '';
  }

  private getNumberField(target: Object, key: string): number {
    const value = Reflect.get(target, key) as number | undefined;
    return typeof value === 'number' ? value : 0;
  }

  private getObjectArrayField(target: Object, key: string): Array<Object> {
    const value = Reflect.get(target, key) as Array<Object> | undefined;
    return Array.isArray(value) ? value : [];
  }
}

export const layoutRepository = new LayoutRepository();