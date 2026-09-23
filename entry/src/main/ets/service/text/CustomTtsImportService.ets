import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { CustomTtsImportResult } from '../../model/CustomTtsConfig';
import { CustomTtsConfigParser } from './CustomTtsConfigParser';

export class CustomTtsImportService {
  static async pick(context: common.Context): Promise<CustomTtsImportResult> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 5;
    options.fileSuffixFilters = ['JSON|.json'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    const result = new CustomTtsImportResult();
    for (const uri of uris.slice(0, 5)) {
      try {
        const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
        try {
          const size = (await fileIo.stat(file.fd)).size;
          if (size <= 0 || size > 1024 * 1024) throw new Error('Invalid TTS file size');
          const buffer = new ArrayBuffer(size);
          const read = await fileIo.read(file.fd, buffer);
          if (read !== size) throw new Error('Incomplete TTS file');
          const raw = util.TextDecoder.create('utf-8', { fatal: true }).decodeWithStream(new Uint8Array(buffer));
          result.configs.push(...CustomTtsConfigParser.parse(raw));
        } finally { await fileIo.close(file); }
      } catch (_error) { result.failedFiles++; }
    }
    return result;
  }
}
