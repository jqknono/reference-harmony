/**
 * 启动参数存储模块
 * 用于在 EntryAbility 和 Index 页面之间传递启动参数
 * 避免使用 globalThis（ArkTS 不支持）
 */

export interface LaunchParams {
  launchAction: string;
  recentDocId: string;
}

let storedParams: LaunchParams | undefined = undefined;

/**
 * 保存启动参数
 */
export function saveLaunchParams(params: LaunchParams | undefined): void {
  storedParams = params;
}

/**
 * 查看启动参数（不清除）
 */
export function peekLaunchParams(): LaunchParams | undefined {
  return storedParams;
}

/**
 * 获取并清除启动参数
 */
export function takeLaunchParams(): LaunchParams | undefined {
  const params = storedParams;
  storedParams = undefined;
  return params;
}

