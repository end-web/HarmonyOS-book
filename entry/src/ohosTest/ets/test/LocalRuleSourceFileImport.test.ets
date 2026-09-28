import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleSourceFileImporter } from '../../../main/ets/service/rulesource/LocalRuleSourceFileImporter';
import { LocalRuleSourceRepository } from '../../../main/ets/service/rulesource/LocalRuleSourceRepository';

class ImportFileFixture {
  bookSourceName: string = 'File import regression';
  bookSourceUrl: string = '';
  bookSourceComment: string = '';
  enabled: boolean = false;
}

export default function localRuleSourceFileImportTest() {
  describe('LocalRuleSourceFileImport', () => {
    it('imports_large_json_with_real_file_io_taskpool_and_database', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const context = delegator.getAppContext().createModuleContext('entry');
      await LocalRuleSourceRepository.init(context);
      const prefix = `file-import-${Date.now()}`;
      const first = new ImportFileFixture();
      first.bookSourceUrl = `https://${prefix}-first.invalid`;
      first.bookSourceComment = '跨块读取'.repeat(16000);
      const second = new ImportFileFixture();
      second.bookSourceUrl = `https://${prefix}-second.invalid`;
      const paths: string[] = [0, 1, 2].map((index: number) => `${context.cacheDir}/${prefix}-${index}.json`);
      const bodies: string[] = [JSON.stringify(first).padEnd(3 * 1024 * 1024, ' '), '{', JSON.stringify(second)];
      try {
        for (let index = 0; index < paths.length; index++) {
          const file = await fileIo.open(paths[index], fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
          try { await fileIo.write(file.fd, bodies[index]); } finally { await fileIo.close(file); }
        }
        const uris = paths.map((path: string) => fileUri.getUriFromPath(path));
        const report = await LocalRuleSourceFileImporter.importFiles(uris, (_current: number, _total: number) => {});
        delegator.printSync(`[SourceFileImportTest] imported=${report.imported}, skipped=${report.skippedFiles}, ` +
          `invalid=${report.invalidFiles}, read=${report.readFailedFiles}, write=${report.writeFailedFiles}\n`);
        expect(report.imported).assertEqual(2);
        expect(report.skippedFiles).assertEqual(1);
        expect(report.invalidFiles).assertEqual(1);
        const saved = await LocalRuleSourceRepository.get(first.bookSourceUrl);
        expect(saved?.bookSourceComment).assertEqual(first.bookSourceComment);
        const listed = await LocalRuleSourceRepository.list();
        expect(listed.some((source) => source.bookSourceUrl === first.bookSourceUrl)).assertTrue();
        expect(listed.some((source) => source.bookSourceUrl === second.bookSourceUrl)).assertTrue();
      } finally {
        await LocalRuleSourceRepository.remove(first.bookSourceUrl);
        await LocalRuleSourceRepository.remove(second.bookSourceUrl);
        for (const path of paths) {
          try { await fileIo.unlink(path); } catch (_error) { /* 仅清理本次创建的测试文件。 */ }
        }
      }
    });
  });
}
