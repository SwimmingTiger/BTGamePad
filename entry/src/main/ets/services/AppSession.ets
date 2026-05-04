import { AbsoluteTouchHidService } from './AbsoluteTouchHidService';
import { layoutRepository } from './LayoutRepository';
import { mouseFeedbackService } from './MouseFeedbackService';
import { nativeInputRuntimeService } from './NativeInputRuntimeService';

export const hidService = new AbsoluteTouchHidService();
export { nativeInputRuntimeService, layoutRepository, mouseFeedbackService };