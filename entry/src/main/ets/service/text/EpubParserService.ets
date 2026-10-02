import { bookParser } from '@hms.core.readerservice.bookParser';

/** 仅在能力检查后动态加载此本地模块，让编译器正确链接 ReaderKit HSP。 */
export class EpubParserService {
  static open(path: string): Promise<bookParser.BookParserHandler> {
    return bookParser.getDefaultHandler(path);
  }
}
