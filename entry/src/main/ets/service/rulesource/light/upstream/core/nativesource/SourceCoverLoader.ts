import { BookSource } from '../../model/data/Book';
import { HttpClient } from '../http/HttpClient';
import { NativeSourceSpec } from './NativeSourceSpec';
import { SourceCoverUrl } from './SourceCoverUrl';
import { SourceImageDecoder } from './SourceImageDecoder';

/** Call inside the host's source session. The host owns scheduling, cache and image rendering. */
export class SourceCoverLoader {
  static async load(http: HttpClient, source: BookSource, raw: string): Promise<Uint8Array> {
    if (SourceCoverUrl.source(raw) !== source.bookSourceUrl) throw new Error('Cover source mismatch');
    const spec = NativeSourceSpec.unpack(source.jsLib)?.coverDecode;
    if (!spec) throw new Error('Source has no coverDecode declaration');
    SourceImageDecoder.validate(spec);
    const response = await http.executeBinary({
      cookieSource: source.bookSourceUrl,
      url: SourceCoverUrl.address(raw), method: 'GET',
      headers: { 'Accept': 'image/*', 'User-Agent': 'Mozilla/5.0' },
      connectTimeout: 10000, readTimeout: 15000
    }, SourceImageDecoder.MAX_BYTES);
    if (!response.success) throw new Error('Cover download failed');
    return SourceImageDecoder.decode(response.data, spec);
  }
}
