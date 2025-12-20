export function normalizeHttpUrl(raw: string): string | undefined {
  const s = (raw ?? '').trim();
  if (!s) return undefined;

  const lower = s.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) return s;

  if (lower.startsWith('www.')) {
    return `https://${s}`;
  }

  // domain.tld[/...]
  const domainLike = /^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}(\/.*)?$/i;
  if (domainLike.test(s)) {
    return `https://${s}`;
  }

  return undefined;
}

interface OpenLinkHost {
  openLink(link: string): Promise<void>;
}

export function openExternalLink(hostContext: object | undefined, rawUrl: string): void {
  const url = normalizeHttpUrl(rawUrl);
  if (!hostContext || !url) return;

  Promise.resolve()
    .then((): Promise<void> => (hostContext as OpenLinkHost).openLink(url))
    .then(
      (): void => undefined,
      (): void => undefined,
    );
}
