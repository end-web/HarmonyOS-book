import { describe, expect, it } from 'vitest';
import { parseAudioSourceContent, parseSourceImport } from '../src/source-import.js';

describe('audio source import', () => {
  it('keeps only valid audio source records', async () => {
    const source = {
      bookSourceName: 'Audio test',
      bookSourceUrl: 'https://audio.example.com',
      bookSourceType: 1,
      searchUrl: 'https://audio.example.com/search?q={{key}}'
    };
    const result = await parseSourceImport({ content: JSON.stringify([source]), enabled: true, testKeyword: 'demo' });
    expect(result.sources).toHaveLength(1);
    expect(result.sources[0]?.bookSourceType).toBe(1);
    expect(result.request.enabled).toBe(true);
  });

  it('rejects text sources and private network rules', async () => {
    await expect(parseSourceImport({ content: JSON.stringify({
      bookSourceName: 'Text', bookSourceUrl: 'https://text.example.com', bookSourceType: 0
    }) })).rejects.toThrow('ONLY_AUDIO_SOURCE_ALLOWED');
    await expect(parseSourceImport({ content: JSON.stringify({
      bookSourceName: 'Private', bookSourceUrl: 'https://audio.example.com', bookSourceType: 1,
      searchUrl: 'http://127.0.0.1/search'
    }) })).rejects.toThrow('SOURCE_PRIVATE_NETWORK_DENIED');
  });

  it('keeps audio entries when a catalog contains mixed source types', () => {
    const result = parseAudioSourceContent(JSON.stringify([
      { bookSourceName: 'Text', bookSourceUrl: 'https://text.example.com', bookSourceType: 0 },
      { bookSourceName: 'Audio', bookSourceUrl: 'https://audio.example.com', bookSourceType: 1 }
    ]));
    expect(result.sources).toHaveLength(1);
    expect(result.rejected).toBe(1);
    expect(result.sources[0]?.bookSourceName).toBe('Audio');
  });
});
