import { AbsoluteTouchHidService } from './AbsoluteTouchHidService';
import { layoutRepository } from './LayoutRepository';
import { nativeInputRuntimeService } from './NativeInputRuntimeService';

export const hidService = new AbsoluteTouchHidService();
export { nativeInputRuntimeService, layoutRepository };