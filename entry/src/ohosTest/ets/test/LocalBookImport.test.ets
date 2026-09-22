import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { describe, expect, it } from '@ohos/hypium';
import { LocalBookImportService, LocalImportFile } from '../../../main/ets/service/LocalBookImportService';

const EPUB_FIXTURE: string = 'UEsDBBQAAAAAAKRRNl1vYassFAAAABQAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi9lcHViK3ppcFBLAwQUAAAAAACkUTZdHgvXyd0AAADdAAAAFgAAAE1FVEEtSU5GL2NvbnRhaW5lci54bWw8P3htbCB2ZXJzaW9uPSIxLjAiPz48Y29udGFpbmVyIHZlcnNpb249IjEuMCIgeG1sbnM9InVybjpvYXNpczpuYW1lczp0YzpvcGVuZG9jdW1lbnQ6eG1sbnM6Y29udGFpbmVyIj48cm9vdGZpbGVzPjxyb290ZmlsZSBmdWxsLXBhdGg9Ik9FQlBTL2NvbnRlbnQub3BmIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi9vZWJwcy1wYWNrYWdlK3htbCIvPjwvcm9vdGZpbGVzPjwvY29udGFpbmVyPlBLAwQUAAAAAACkUTZdQyqb3PMCAADzAgAAEQAAAE9FQlBTL2NvbnRlbnQub3BmPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz48cGFja2FnZSB2ZXJzaW9uPSIyLjAiIHVuaXF1ZS1pZGVudGlmaWVyPSJpZCIgeG1sbnM9Imh0dHA6Ly93d3cuaWRwZi5vcmcvMjAwNy9vcGYiPjxtZXRhZGF0YSB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iPjxkYzp0aXRsZT7nroDlkKxFUFVC6aqM6K+BPC9kYzp0aXRsZT48ZGM6Y3JlYXRvcj7mnKzlnLDmtYvor5U8L2RjOmNyZWF0b3I+PGRjOmxhbmd1YWdlPnpoLUNOPC9kYzpsYW5ndWFnZT48ZGM6aWRlbnRpZmllciBpZD0iaWQiPmhzZGEtZml4dHVyZTwvZGM6aWRlbnRpZmllcj48bWV0YSBuYW1lPSJjb3ZlciIgY29udGVudD0iY292ZXItaW1hZ2UiLz48L21ldGFkYXRhPjxtYW5pZmVzdD48aXRlbSBpZD0ibmN4IiBocmVmPSJ0b2MubmN4IiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94LWR0Ym5jeCt4bWwiLz48aXRlbSBpZD0iYzEiIGhyZWY9ImMxLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iYzIiIGhyZWY9ImMyLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iY292ZXItaW1hZ2UiIGhyZWY9IkltYWdlcy9jb3Zlci5wbmciIG1lZGlhLXR5cGU9ImltYWdlL3BuZyIvPjwvbWFuaWZlc3Q+PHNwaW5lIHRvYz0ibmN4Ij48aXRlbXJlZiBpZHJlZj0iYzEiLz48aXRlbXJlZiBpZHJlZj0iYzIiLz48L3NwaW5lPjwvcGFja2FnZT5QSwMEFAAAAAAApFE2XSDnyM3YAQAA2AEAAA0AAABPRUJQUy90b2MubmN4PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz48bmN4IHhtbG5zPSJodHRwOi8vd3d3LmRhaXN5Lm9yZy96Mzk4Ni8yMDA1L25jeC8iIHZlcnNpb249IjIwMDUtMSI+PGhlYWQ+PG1ldGEgbmFtZT0iZHRiOnVpZCIgY29udGVudD0iaHNkYS1maXh0dXJlIi8+PC9oZWFkPjxkb2NUaXRsZT48dGV4dD7nroDlkKxFUFVC6aqM6K+BPC90ZXh0PjwvZG9jVGl0bGU+PG5hdk1hcD48bmF2UG9pbnQgaWQ9Im4xIiBwbGF5T3JkZXI9IjEiPjxuYXZMYWJlbD48dGV4dD7nrKzkuIDnq6Ag5rWL6K+VPC90ZXh0PjwvbmF2TGFiZWw+PGNvbnRlbnQgc3JjPSJjMS54aHRtbCIvPjwvbmF2UG9pbnQ+PG5hdlBvaW50IGlkPSJuMiIgcGxheU9yZGVyPSIyIj48bmF2TGFiZWw+PHRleHQ+56ys5LqM56ugIOWujOaIkDwvdGV4dD48L25hdkxhYmVsPjxjb250ZW50IHNyYz0iYzIueGh0bWwiLz48L25hdlBvaW50PjwvbmF2TWFwPjwvbmN4PlBLAwQUAAAAAACkUTZdVu0a1cEAAADBAAAADgAAAE9FQlBTL2MxLnhodG1sPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCI+PGhlYWQ+PHRpdGxlPuesrDHnq6A8L3RpdGxlPjwvaGVhZD48Ym9keT48aDE+56ysMeeroDwvaDE+PHA+6L+Z5pivIEVQVUIg5a+85YWl6aqM6K+B56ysMeeroOOAgjwvcD48L2JvZHk+PC9odG1sPlBLAwQUAAAAAACkUTZd/LujEMEAAADBAAAADgAAAE9FQlBTL2MyLnhodG1sPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCI+PGhlYWQ+PHRpdGxlPuesrDLnq6A8L3RpdGxlPjwvaGVhZD48Ym9keT48aDE+56ysMueroDwvaDE+PHA+6L+Z5pivIEVQVUIg5a+85YWl6aqM6K+B56ysMueroOOAgjwvcD48L2JvZHk+PC9odG1sPlBLAwQUAAAAAACkUTZdn07eCaMAAACjAAAAFgAAAE9FQlBTL0ltYWdlcy9jb3Zlci5wbmeJUE5HDQoaCgAAAA1JSERSAAAAPAAAAFoIAgAAAGszomIAAABqSURBVHic7c4BCQAgEAAxq9nCtGYzhvcwWICtu8846/tAOkxaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6YGT6AQaIRM224tKnAAAAAElFTkSuQmCCUEsBAhQAFAAAAAAApFE2XW9hqywUAAAAFAAAAAgAAAAAAAAAAAAAAIABAAAAAG1pbWV0eXBlUEsBAhQAFAAAAAAApFE2XR4L18ndAAAA3QAAABYAAAAAAAAAAAAAAIABOgAAAE1FVEEtSU5GL2NvbnRhaW5lci54bWxQSwECFAAUAAAAAACkUTZdQyqb3PMCAADzAgAAEQAAAAAAAAAAAAAAgAFLAQAAT0VCUFMvY29udGVudC5vcGZQSwECFAAUAAAAAACkUTZdIOfIzdgBAADYAQAADQAAAAAAAAAAAAAAgAFtBAAAT0VCUFMvdG9jLm5jeFBLAQIUABQAAAAAAKRRNl1W7RrVwQAAAMEAAAAOAAAAAAAAAAAAAACAAXAGAABPRUJQUy9jMS54aHRtbFBLAQIUABQAAAAAAKRRNl38u6MQwQAAAMEAAAAOAAAAAAAAAAAAAACAAV0HAABPRUJQUy9jMi54aHRtbFBLAQIUABQAAAAAAKRRNl2fTt4JowAAAKMAAAAWAAAAAAAAAAAAAACAAUoIAABPRUJQUy9JbWFnZXMvY292ZXIucG5nUEsFBgAAAAAHAAcAsAEAACEJAAAAAA==';

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
        const preview = await LocalBookImportService.preview(context, picked);
        expect(preview.title).assertEqual('简听EPUB验证');
        expect(preview.author).assertEqual('本地测试');
        expect(preview.cover.endsWith('/cover.jpg')).assertTrue();
        const book = await LocalBookImportService.importBook(context, picked, id,
          preview.title, preview.author, preview.cover, (): void => {});
        await fileIo.rmdir(preview.directory);
        expect(book.contentType).assertEqual('text');
        expect(book.cover.endsWith('/cover.jpg')).assertTrue();
        expect((await fileIo.stat(book.cover)).size > 0).assertTrue();
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
