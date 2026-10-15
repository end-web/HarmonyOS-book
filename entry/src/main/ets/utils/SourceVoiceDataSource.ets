import { LocalRuleVoice } from '../service/rulesource/LocalRuleRuntimeTypes';

/** Source-provided voice ids are stable list keys and the values passed back to rules. */
export class SourceVoiceDataSource implements IDataSource {
  private voices: LocalRuleVoice[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.voices.length; }
  getData(index: number): LocalRuleVoice { return this.voices[index]; }

  setVoices(voices: LocalRuleVoice[], variables?: Record<string, string>): void {
    const ids = new Set<string>();
    const declaredTones = variables?.['tones'];
    const supported = new Set<string>((declaredTones ?? '').split(',').map((id: string): string => id.trim())
      .filter((id: string): boolean => id.length > 0));
    const hasRealEdition = (variables?.['real'] ?? '').split(',').some((id: string): boolean => id.trim().length > 0);
    this.voices = voices.filter((voice: LocalRuleVoice): boolean => {
      if (!voice.id || !voice.name || ids.has(voice.id)) return false;
      // Missing per-book metadata keeps the source's declared choices; an explicit list restricts them.
      // A related real edition uses the source's original-voice id even when absent from synthetic tones.
      if (declaredTones !== undefined && !supported.has(voice.id) && !(voice.id === '0' && hasRealEdition)) return false;
      ids.add(voice.id);
      return true;
    });
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
}
