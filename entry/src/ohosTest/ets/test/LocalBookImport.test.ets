import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { describe, expect, it } from '@ohos/hypium';
import { LocalBookImportService, LocalImportFile } from '../../../main/ets/service/LocalBookImportService';

const EPUB_FIXTURE: string = 'UEsDBBQAAAAAAG97MV1vYassFAAAABQAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi9lcHViK3ppcFBLAwQUAAAAAABvezFdHgvXyd0AAADdAAAAFgAAAE1FVEEtSU5GL2NvbnRhaW5lci54bWw8P3htbCB2ZXJzaW9uPSIxLjAiPz48Y29udGFpbmVyIHZlcnNpb249IjEuMCIgeG1sbnM9InVybjpvYXNpczpuYW1lczp0YzpvcGVuZG9jdW1lbnQ6eG1sbnM6Y29udGFpbmVyIj48cm9vdGZpbGVzPjxyb290ZmlsZSBmdWxsLXBhdGg9Ik9FQlBTL2NvbnRlbnQub3BmIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi9vZWJwcy1wYWNrYWdlK3htbCIvPjwvcm9vdGZpbGVzPjwvY29udGFpbmVyPlBLAwQUAAAAAABvezFdLoordYICAACCAgAAEQAAAE9FQlBTL2NvbnRlbnQub3BmPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz48cGFja2FnZSB2ZXJzaW9uPSIyLjAiIHVuaXF1ZS1pZGVudGlmaWVyPSJpZCIgeG1sbnM9Imh0dHA6Ly93d3cuaWRwZi5vcmcvMjAwNy9vcGYiPjxtZXRhZGF0YSB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iPjxkYzp0aXRsZT7nroDlkKxFUFVC6aqM6K+BPC9kYzp0aXRsZT48ZGM6Y3JlYXRvcj7mnKzlnLDmtYvor5U8L2RjOmNyZWF0b3I+PGRjOmxhbmd1YWdlPnpoLUNOPC9kYzpsYW5ndWFnZT48ZGM6aWRlbnRpZmllciBpZD0iaWQiPmhzZGEtZml4dHVyZTwvZGM6aWRlbnRpZmllcj48L21ldGFkYXRhPjxtYW5pZmVzdD48aXRlbSBpZD0ibmN4IiBocmVmPSJ0b2MubmN4IiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94LWR0Ym5jeCt4bWwiLz48aXRlbSBpZD0iYzEiIGhyZWY9ImMxLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iYzIiIGhyZWY9ImMyLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48L21hbmlmZXN0PjxzcGluZSB0b2M9Im5jeCI+PGl0ZW1yZWYgaWRyZWY9ImMxIi8+PGl0ZW1yZWYgaWRyZWY9ImMyIi8+PC9zcGluZT48L3BhY2thZ2U+UEsDBBQAAAAAAG97MV0g58jN2AEAANgBAAANAAAAT0VCUFMvdG9jLm5jeDw/eG1sIHZlcnNpb249IjEuMCIgZW5jb2Rpbmc9InV0Zi04Ij8+PG5jeCB4bWxucz0iaHR0cDovL3d3dy5kYWlzeS5vcmcvejM5ODYvMjAwNS9uY3gvIiB2ZXJzaW9uPSIyMDA1LTEiPjxoZWFkPjxtZXRhIG5hbWU9ImR0Yjp1aWQiIGNvbnRlbnQ9ImhzZGEtZml4dHVyZSIvPjwvaGVhZD48ZG9jVGl0bGU+PHRleHQ+566A5ZCsRVBVQumqjOivgTwvdGV4dD48L2RvY1RpdGxlPjxuYXZNYXA+PG5hdlBvaW50IGlkPSJuMSIgcGxheU9yZGVyPSIxIj48bmF2TGFiZWw+PHRleHQ+56ys5LiA56ugIOa1i+ivlTwvdGV4dD48L25hdkxhYmVsPjxjb250ZW50IHNyYz0iYzEueGh0bWwiLz48L25hdlBvaW50PjxuYXZQb2ludCBpZD0ibjIiIHBsYXlPcmRlcj0iMiI+PG5hdkxhYmVsPjx0ZXh0PuesrOS6jOeroCDlrozmiJA8L3RleHQ+PC9uYXZMYWJlbD48Y29udGVudCBzcmM9ImMyLnhodG1sIi8+PC9uYXZQb2ludD48L25hdk1hcD48L25jeD5QSwMEFAAAAAAAb3sxXVbtGtXBAAAAwQAAAA4AAABPRUJQUy9jMS54aHRtbDw/eG1sIHZlcnNpb249IjEuMCIgZW5jb2Rpbmc9InV0Zi04Ij8+PGh0bWwgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkveGh0bWwiPjxoZWFkPjx0aXRsZT7nrKwx56ugPC90aXRsZT48L2hlYWQ+PGJvZHk+PGgxPuesrDHnq6A8L2gxPjxwPui/meaYryBFUFVCIOWvvOWFpemqjOivgeesrDHnq6DjgII8L3A+PC9ib2R5PjwvaHRtbD5QSwMEFAAAAAAAb3sxXfy7oxDBAAAAwQAAAA4AAABPRUJQUy9jMi54aHRtbDw/eG1sIHZlcnNpb249IjEuMCIgZW5jb2Rpbmc9InV0Zi04Ij8+PGh0bWwgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkveGh0bWwiPjxoZWFkPjx0aXRsZT7nrKwy56ugPC90aXRsZT48L2hlYWQ+PGJvZHk+PGgxPuesrDLnq6A8L2gxPjxwPui/meaYryBFUFVCIOWvvOWFpemqjOivgeesrDLnq6DjgII8L3A+PC9ib2R5PjwvaHRtbD5QSwECFAAUAAAAAABvezFdb2GrLBQAAAAUAAAACAAAAAAAAAAAAAAAgAEAAAAAbWltZXR5cGVQSwECFAAUAAAAAABvezFdHgvXyd0AAADdAAAAFgAAAAAAAAAAAAAAgAE6AAAATUVUQS1JTkYvY29udGFpbmVyLnhtbFBLAQIUABQAAAAAAG97MV0uiit1ggIAAIICAAARAAAAAAAAAAAAAACAAUsBAABPRUJQUy9jb250ZW50Lm9wZlBLAQIUABQAAAAAAG97MV0g58jN2AEAANgBAAANAAAAAAAAAAAAAACAAfwDAABPRUJQUy90b2MubmN4UEsBAhQAFAAAAAAAb3sxXVbtGtXBAAAAwQAAAA4AAAAAAAAAAAAAAIAB/wUAAE9FQlBTL2MxLnhodG1sUEsBAhQAFAAAAAAAb3sxXfy7oxDBAAAAwQAAAA4AAAAAAAAAAAAAAIAB7AYAAE9FQlBTL2MyLnhodG1sUEsFBgAAAAAGAAYAbAEAANkHAAAAAA==';

export default function localBookImportTest(): void {
  describe('LocalBookImportDevice', (): void => {
    it('imports real EPUB with the system parser and reads local chapters', 0, async (): Promise<void> => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const id = `import_device_test_${Date.now()}`;
      const path = `${context.cacheDir}/${id}.epub`;
      const output = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try {
        const bytes = new util.Base64Helper().decodeSync(EPUB_FIXTURE);
        await fileIo.write(output.fd, bytes.buffer);
      } finally { await fileIo.close(output); }
      try {
        const picked = new LocalImportFile();
        picked.uri = path; picked.ext = '.epub'; picked.name = 'EPUB fixture';
        const book = await LocalBookImportService.importBook(context, picked, id, '', '', '', (): void => {});
        expect(book.contentType).assertEqual('text');
        expect(book.chapters.length).assertEqual(2);
        const first = await fileIo.readText(book.chapters[0].source.value);
        const second = await fileIo.readText(book.chapters[1].source.value);
        expect(first).assertContain('EPUB 导入验证第1章');
        expect(second).assertContain('EPUB 导入验证第2章');
      } finally {
        try { await fileIo.unlink(path); } catch (_error) {}
        try { await fileIo.rmdir(`${context.filesDir}/ebooks/${id}`); } catch (_error) {}
      }
    });
  });
}
