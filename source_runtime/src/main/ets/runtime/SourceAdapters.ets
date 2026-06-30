export interface SourceFetchAdapter {
  fetchText(url: string): Promise<string>;
}
