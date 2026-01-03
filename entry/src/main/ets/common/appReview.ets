import { commentManager } from '@kit.AppGalleryKit';
import type { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG: string = 'AppReview';

export type AppReviewResult = 'in_app' | 'store' | 'failed';

function asUiAbilityContext(hostContext: object | undefined): common.UIAbilityContext | undefined {
  return hostContext as common.UIAbilityContext | undefined;
}

function buildWriteReviewWant(bundleName: string): Want {
  // DeepLink: open AppGallery app detail page, then directly go to "write review".
  return {
    action: 'ohos.want.action.appdetail',
    uri: `store://appgallery.huawei.com/app/detail?id=${encodeURIComponent(bundleName)}&action=write-review`,
  };
}

export async function requestAppReview(hostContext: object | undefined, bundleName: string): Promise<AppReviewResult> {
  const ctx = asUiAbilityContext(hostContext);
  const id = (bundleName ?? '').trim();
  if (!ctx || !id) return 'failed';

  // Preferred: HarmonyOS 6 AppGalleryKit in-app comment dialog.
  try {
    await commentManager.showCommentDialog(ctx);
    return 'in_app';
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'showCommentDialog failed: %{public}s', JSON.stringify(e));
  }

  // Fallback: open AppGallery detail page and navigate to "write review".
  try {
    const want: Want = buildWriteReviewWant(id);
    await ctx.startAbility(want);
    return 'store';
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'startAbility(AppGallery detail) failed: %{public}s', JSON.stringify(e));
    return 'failed';
  }
}
