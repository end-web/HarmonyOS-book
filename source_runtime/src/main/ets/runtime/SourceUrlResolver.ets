export class SourceUrlResolver {
  private static readonly REPOSITORY_SOURCE_PATHS: string[] = [
    'shuyuan',
    'shuyuan.json',
    'sy.json',
    'source.json',
    'sources.json',
    'bookSource.json',
    'bookSources.json',
    'book-source.json',
  ];

  static resolveCandidates(inputUrl: string): string[] {
    const trimmed = inputUrl.trim();
    if (!trimmed) return [];
    const candidates: string[] = [];
    SourceUrlResolver.pushUnique(candidates, trimmed);

    for (const url of SourceUrlResolver.resolveGithubUrl(trimmed)) {
      SourceUrlResolver.pushUnique(candidates, url);
    }

    const rawMirrorFallback = SourceUrlResolver.resolveRawGitMirror(trimmed);
    if (rawMirrorFallback) {
      SourceUrlResolver.pushUnique(candidates, rawMirrorFallback);
    }

    return candidates;
  }

  private static resolveGithubUrl(url: string): string[] {
    const normalized = SourceUrlResolver.stripHash(url);
    const blob = SourceUrlResolver.resolveGithubBlob(normalized);
    if (blob) return [blob];
    return SourceUrlResolver.resolveGithubRepository(normalized);
  }

  private static resolveGithubBlob(url: string): string {
    const match = url.match(/^https?:\/\/github\.com\/([^\/]+)\/([^\/?#]+)\/(?:blob|raw)\/([^\/?#]+)\/(.+)$/);
    if (!match) return '';
    const owner = match[1];
    const repo = match[2].replace(/\.git$/, '');
    const branch = match[3];
    const path = match[4].replace(/[?#].*$/, '');
    if (!owner || !repo || !branch || !path) return '';
    return `https://raw.githubusercontent.com/${owner}/${repo}/${branch}/${path}`;
  }

  private static resolveGithubRepository(url: string): string[] {
    const match = url.match(/^https?:\/\/github\.com\/([^\/]+)\/([^\/?#]+)(?:[\/?#].*)?$/);
    if (!match) return [];
    const owner = match[1];
    const repo = match[2].replace(/\.git$/, '');
    if (!owner || !repo) return [];

    const branches: string[] = ['master', 'main'];
    const candidates: string[] = [];
    for (const branch of branches) {
      for (const path of SourceUrlResolver.REPOSITORY_SOURCE_PATHS) {
        candidates.push(`https://raw.githubusercontent.com/${owner}/${repo}/${branch}/${path}`);
      }
    }
    return candidates;
  }

  private static resolveRawGitMirror(url: string): string {
    const match = url.match(/^https?:\/\/raw\.gitmirror\.com\/([^\/]+)\/([^\/]+)\/([^\/]+)\/(.+)$/);
    if (!match) return '';
    return `https://raw.githubusercontent.com/${match[1]}/${match[2]}/${match[3]}/${match[4]}`;
  }

  private static stripHash(url: string): string {
    const idx = url.indexOf('#');
    return idx >= 0 ? url.substring(0, idx) : url;
  }

  private static pushUnique(list: string[], value: string): void {
    if (!value || list.includes(value)) return;
    list.push(value);
  }
}
