/**
 * 在线 Markdown 链接相关数据模型
 */

export interface OnlineMdLink {
  id: string;
  url: string;
  name: string;
  addedTime: number;
}

export interface OnlineMdLinkList {
  links: Array<OnlineMdLink>;
}

export function generateOnlineMdId(): string {
  return `online_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
}


