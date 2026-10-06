import { common } from '@kit.AbilityKit';
import { cert } from '@kit.DeviceCertificateKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { SubscriptionEnvelope, SubscriptionPayload } from './SubscriptionData';
import { LifetimeEnvelope, LifetimeOrder } from './LifetimeData';

class JwsHeader {
  alg: string = '';
  typ: string = '';
  x5c: string[] = [];
  crit?: string[];
}

/** Huawei IAP JWS：固定信任锚 + PKIX 证书链 + IAP 叶子 OID + ES256。 */
export class SubscriptionVerifier {
  private static root: cert.X509Cert | null = null;

  static decodeBase64(value: string, url: boolean = false): Uint8Array {
    if (typeof value !== 'string' || value.length === 0 || value.length > 131072 ||
      !(url ? /^[A-Za-z0-9_-]+$/ : /^[A-Za-z0-9+/]+={0,2}$/).test(value)) {
      throw new Error('Invalid base64');
    }
    let normalized = url ? value.replace(/-/g, '+').replace(/_/g, '/') : value;
    normalized += '='.repeat((4 - normalized.length % 4) % 4);
    return new util.Base64Helper().decodeSync(normalized);
  }

  /** JWS 的 R||S 签名转为 CryptoFramework 接受的 DER ECDSA 签名。 */
  static signatureDer(raw: Uint8Array): Uint8Array {
    if (raw.length !== 64) throw new Error('Invalid ES256 signature length');
    const r = SubscriptionVerifier.derInteger(raw.slice(0, 32));
    const s = SubscriptionVerifier.derInteger(raw.slice(32));
    const result = new Uint8Array(2 + r.length + s.length);
    result[0] = 0x30;
    result[1] = r.length + s.length;
    result.set(r, 2);
    result.set(s, 2 + r.length);
    return result;
  }

  private static derInteger(bytes: Uint8Array): Uint8Array {
    let offset = 0;
    while (offset < bytes.length - 1 && bytes[offset] === 0) offset++;
    const prefix = bytes[offset] >= 128 ? 1 : 0;
    const result = new Uint8Array(2 + prefix + bytes.length - offset);
    result[0] = 2;
    result[1] = result.length - 2;
    result.set(bytes.slice(offset), 2 + prefix);
    return result;
  }

  static async verify(context: common.Context, purchaseData: string): Promise<SubscriptionPayload> {
    if (typeof purchaseData !== 'string' || purchaseData.length > 262144) throw new Error('Oversized purchase');
    const envelope: SubscriptionEnvelope = JSON.parse(purchaseData);
    if (!envelope || typeof envelope.jwsSubscriptionStatus !== 'string') throw new Error('Missing subscription JWS');
    const payload: SubscriptionPayload = JSON.parse(await SubscriptionVerifier.verifyJws(context, envelope.jwsSubscriptionStatus));
    return payload;
  }

  static async verifyLifetime(context: common.Context, purchaseData: string): Promise<LifetimeOrder> {
    if (typeof purchaseData !== 'string' || purchaseData.length > 262144) throw new Error('Oversized purchase');
    const envelope: LifetimeEnvelope = JSON.parse(purchaseData);
    if (!envelope || typeof envelope.jwsPurchaseOrder !== 'string') throw new Error('Missing purchase JWS');
    const order: LifetimeOrder = JSON.parse(await SubscriptionVerifier.verifyJws(context, envelope.jwsPurchaseOrder));
    return order;
  }

  private static async verifyJws(context: common.Context, jws: string): Promise<string> {
    const parts = jws.split('.');
    if (parts.length !== 3) throw new Error('Invalid JWS');
    const decoder = util.TextDecoder.create('utf-8', { fatal: true });
    const header: JwsHeader = JSON.parse(decoder.decodeToString(SubscriptionVerifier.decodeBase64(parts[0], true)));
    if (!header || header.alg !== 'ES256' || header.typ !== 'JWT' ||
      !Array.isArray(header.x5c) || header.x5c.length !== 3 || header.crit !== undefined) {
      throw new Error('Invalid JWS header');
    }
    const certificates: cert.X509Cert[] = [];
    for (const value of header.x5c) {
      certificates.push(await cert.createX509Cert({
        data: SubscriptionVerifier.decodeBase64(value), encodingFormat: cert.EncodingFormat.FORMAT_DER
      }));
    }
    if (!SubscriptionVerifier.root) {
      SubscriptionVerifier.root = await cert.createX509Cert({
        data: await context.resourceManager.getRawFileContent('iap/huawei_cbg_root_ca_g2.cer'),
        encodingFormat: cert.EncodingFormat.FORMAT_DER
      });
    }
    // 绝不把 header 自带的根证书当作信任锚，也不使用系统 CA 扩大信任范围。
    const anchor: cert.X509TrustAnchor = { CACert: SubscriptionVerifier.root };
    const chain = cert.createX509CertChain(certificates.slice(0, 2));
    const date = new Date().toISOString().replace(/[-:]/g, '').replace('T', '').substring(0, 14) + 'Z';
    await chain.validate({ trustAnchors: [anchor], date: date, trustSystemCa: false });
    const leaf = certificates[0];
    const oids = leaf.getExtensionsObject().getOidList(cert.ExtensionOidType.EXTENSION_OID_TYPE_UNCRITICAL);
    const hasIapOid = oids.data.some((oid: Uint8Array): boolean =>
      decoder.decodeToString(oid).replace(/\0+$/, '') === '1.3.6.1.4.1.2011.2.415.1.1');
    if (!hasIapOid) throw new Error('Missing Huawei IAP certificate OID');
    const verifier = cryptoFramework.createVerify('ECC256|SHA256');
    await verifier.init(leaf.getPublicKey());
    const valid = await verifier.verify({ data: new util.TextEncoder().encodeInto(parts[0] + '.' + parts[1]) },
      { data: SubscriptionVerifier.signatureDer(SubscriptionVerifier.decodeBase64(parts[2], true)) });
    if (!valid) throw new Error('Invalid subscription signature');
    return decoder.decodeToString(SubscriptionVerifier.decodeBase64(parts[1], true));
  }
}
