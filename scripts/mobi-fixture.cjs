// Minimal Palm Database/MOBI6 binary fixtures; no parser code is reused here.
const MOBI_COVER_PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAADwAAABaCAIAAABrM6JiAAAAaklEQVR4nO3OUQkAIBBAMaMY1dL+G8N3MFiArXv2OOv7QDpMWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOmBk+gGX5GDoGfTlRAAAAABJRU5ErkJggg==', 'base64');
function mobiFixture(options = {}) {
  const text = options.text ?? '<html><head><title>忽略</title></head><body><h1>第一章 初见</h1><p>中文😀 &amp; 正文</p><mbp:pagebreak/><h2>第二章 重逢</h2><p>第二章内容</p></body></html>';
  const bytes = options.bytes ?? Buffer.from(text);
  const compression = options.compression ?? 2;
  const records = options.records ?? Array.from({ length: Math.ceil(bytes.length / 29) }, (_, i) => {
    const part = bytes.subarray(i * 29, (i + 1) * 29);
    if (compression !== 2) return part;
    const runs = [];
    for (let j = 0; j < part.length; j += 8) {
      const run = part.subarray(j, j + 8);
      runs.push(Buffer.from([run.length]), run);
    }
    return Buffer.concat(runs);
  });
  const title = Buffer.from('MOBI 测试书');
  const author = Buffer.from('测试作者');
  const images = options.images ?? (options.cover ? [MOBI_COVER_PNG] : []);
  const authorRecord = Buffer.alloc(8 + author.length);
  authorRecord.writeUInt32BE(100); authorRecord.writeUInt32BE(authorRecord.length, 4); author.copy(authorRecord, 8);
  const metadata = [authorRecord];
  for (const [type, offset] of [[201, options.coverOffset ?? (options.cover ? 0 : undefined)], [202, options.thumbnailOffset]]) {
    if (offset === undefined) continue;
    const record = Buffer.alloc(12);
    record.writeUInt32BE(type); record.writeUInt32BE(12, 4); record.writeUInt32BE(offset, 8);
    metadata.push(record);
  }
  const exth = Buffer.concat([Buffer.alloc(12), ...metadata]);
  exth.write('EXTH'); exth.writeUInt32BE(exth.length, 4); exth.writeUInt32BE(metadata.length, 8);
  const header = Buffer.alloc(16 + 232);
  header.writeUInt16BE(compression, 0);
  header.writeUInt32BE(bytes.length, 4);
  header.writeUInt16BE(records.length, 8);
  header.writeUInt16BE(4096, 10);
  header.writeUInt16BE(options.encryption ?? 0, 12);
  header.write('MOBI', 16); header.writeUInt32BE(232, 20); header.writeUInt32BE(2, 24);
  header.writeUInt32BE(options.encoding ?? 65001, 28); header.writeUInt32BE(options.version ?? 6, 36);
  header.writeUInt32BE(header.length + exth.length, 84); header.writeUInt32BE(title.length, 88);
  header.writeUInt32BE(options.firstImage ?? (images.length ? records.length + 1 : 0xffffffff), 108);
  header.writeUInt32BE(0x40, 128); header.writeUInt16BE(options.flags ?? 0, 242);
  const all = [Buffer.concat([header, exth, title]), ...records, ...images, ...(options.extraRecords ?? [])];
  const pdb = Buffer.alloc(78 + all.length * 8 + 2);
  pdb.write('Fixture'); pdb.write('BOOKMOBI', 60); pdb.writeUInt16BE(all.length, 76);
  let offset = pdb.length;
  all.forEach((record, index) => { pdb.writeUInt32BE(offset, 78 + index * 8); offset += record.length; });
  return Buffer.concat([pdb, ...all]);
}
module.exports = { mobiFixture, MOBI_COVER_PNG };
