import { Book, BookSource, SearchBook } from '../../model/data/Book';
import { BookTypeSupport } from './BookTypeSupport';
import { BookUrlResolver } from './BookUrlResolver';
import { EncodedSourceUrl } from './EncodedSourceUrl';

/**
 * Bridges source-owned metadata carried by virtual book/catalog URLs into the normal book model.
 * This deliberately interprets only generic field names and media labels; endpoints and publisher
 * protocols remain entirely inside the imported source.
 */
export class BookSourceMetadataSupport {
  static applySearchBook(source: BookSource, book: SearchBook, urls: string[] = []): void {
    const metadata = this.collect(urls.length > 0 ? urls : [book.bookUrl]);
    book.variable = this.mergeVariables(book.variable, metadata);
    book.originName = this.displayOriginName(source, this.subSource(metadata));
    BookTypeSupport.applySearchBookType(book, source, this.mediaTab(metadata), this.subSource(metadata));
  }

  static applyBook(source: BookSource, book: Book, urls: string[] = []): void {
    const candidates = urls.length > 0 ? urls : [book.bookUrl, book.tocUrl];
    const metadata = this.collect(candidates);
    book.variable = this.mergeVariables(book.variable, metadata);
    book.originName = this.displayOriginName(source, this.subSource(metadata));
    BookTypeSupport.applyBookType(book, source, this.mediaTab(metadata), this.subSource(metadata));
  }

  private static collect(urls: string[]): Record<string, string> {
    const result: Record<string, string> = {};
    for (const url of urls) {
      const values = EncodedSourceUrl.scalarVariables(url || '');
      for (const key of ['source', 'sources', 'tab', 'mediaType', 'contentType']) {
        const value = this.cleanValue(values[key] || '');
        if (value) result[key] = value;
      }
    }
    return result;
  }

  private static mergeVariables(raw: string, metadata: Record<string, string>): string {
    let result = raw || '{}';
    for (const key of ['source', 'sources', 'tab', 'mediaType', 'contentType']) {
      if (metadata[key]) result = BookUrlResolver.setVariableJson(result, key, metadata[key]);
    }
    const subSource = this.subSource(metadata);
    if (subSource) result = BookUrlResolver.setVariableJson(result, 'subSource', subSource);
    return result;
  }

  private static mediaTab(metadata: Record<string, string>): string {
    return metadata['tab'] || metadata['mediaType'] || metadata['contentType'] || '';
  }

  private static subSource(metadata: Record<string, string>): string {
    return metadata['source'] || metadata['sources'] || '';
  }

  private static displayOriginName(source: BookSource, subSource: string): string {
    const sourceName = this.cleanValue(source.bookSourceName || source.bookSourceUrl || '');
    const childName = this.cleanValue(subSource);
    if (!childName || childName === sourceName) return sourceName;
    return `${sourceName} · ${childName}`;
  }

  private static cleanValue(value: string): string {
    return String(value || '').replace(/[\r\n\t]+/g, ' ').trim().substring(0, 80);
  }
}
