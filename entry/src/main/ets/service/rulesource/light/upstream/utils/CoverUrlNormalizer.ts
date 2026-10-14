export class CoverUrlNormalizer {
  static normalize(raw: string): string {
    const value = (raw || '').trim();
    if (!value) {
      return '';
    }
    return value;
  }

  static prefer(primary: string, fallback: string): string {
    const preferred = CoverUrlNormalizer.normalize(primary);
    if (preferred) {
      return preferred;
    }
    return CoverUrlNormalizer.normalize(fallback);
  }

  static downloadCandidates(raw: string): string[] {
    const value = (raw || '').trim();
    if (!value) {
      return [];
    }
    const normalized = CoverUrlNormalizer.normalize(value);
    if (normalized && normalized !== value) {
      return [normalized, value];
    }
    return [value];
  }
}
