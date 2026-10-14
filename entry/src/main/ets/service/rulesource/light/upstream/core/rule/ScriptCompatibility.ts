/**
 * Normalizes the small, deterministic part of Android/Java APIs commonly used
 * by Legado book-source scripts. This is deliberately an allow-list: filesystem,
 * process, reflection and UI access must never be emulated by imported rules.
 */
export class ScriptCompatibility {
  static normalize(code: string): string {
    return (code || '')
      .replace(/\bthis\.source\b/g, 'source')
      // Some aggregated sources probe this Legado fork class only to select a compatible branch.
      // Harmony uses the same "modified runtime" branch, so a standard Error constructor is a
      // safe equivalent and does not expose arbitrary Java package access.
      .replace(/\bnew\s+Packages\.io\.legato\.kazusa\.utils\.TimeoutCancellationException\s*\([^)]*\)/g,
        'true')
      // Sleeping the script thread is only used as a short UI/network delay. The Harmony request
      // pipeline is already asynchronous; retaining a blocking sleep would add no semantics.
      .replace(/\b(?:Packages\.)?java\.lang\.Thread\.sleep\s*\([^)]*\)/g, "''")
      .replace(/\bPackages\.(?=(?:android\.util\.Base64|java\.(?:net\.(?:URLDecoder|URLEncoder)|lang\.(?:Integer|Long|String|System)|util\.(?:Base64|UUID))))/g, '')
      .replace(/\b(?:android\.util\.Base64|java\.util\.Base64)\.encodeToString\s*\(/g, 'java.base64EncodeToString(')
      .replace(/\bandroid\.util\.Base64\.encode\s*\(/g, 'java.base64Encode(')
      .replace(/\b(?:android\.util\.Base64|java\.util\.Base64)\.decode\s*\(/g, 'java.base64Decode(')
      .replace(/\bjava\.util\.Base64\.getEncoder\(\)\.encodeToString\s*\(/g, 'java.base64EncodeToString(')
      .replace(/\bjava\.util\.Base64\.getDecoder\(\)\.decode\s*\(/g, 'java.base64Decode(')
      .replace(/\b(?:java\.net\.)?URLEncoder\.encode\s*\(/g, 'java.urlEncode(')
      .replace(/\b(?:java\.net\.)?URLDecoder\.decode\s*\(/g, 'java.urlDecode(')
      .replace(/\b(?:java\.lang\.)?System\.currentTimeMillis\(\)/g, 'Date.now()')
      .replace(/\b(?:java\.util\.)?UUID\.randomUUID\(\)/g, 'java.randomUUID()')
      .replace(/\b(?:java\.lang\.)?Integer\.parseInt\s*\(/g, 'parseInt(')
      .replace(/\b(?:java\.lang\.)?Long\.parseLong\s*\(/g, 'parseInt(')
      .replace(/\b(?:java\.lang\.)?(?:Integer|Long|String)\.valueOf\s*\(/g, 'String(')
      .replace(/\bnew\s+(?:java\.lang\.)?String\s*\(/g, 'String(')
      .replace(/\bnew\s+(?:java\.lang\.)?(?:StringBuilder|StringBuffer)\s*\(/g, 'StringBuilder(')
      .replace(/\bnew\s+(?:java\.util\.)?(?:HashMap|LinkedHashMap)\s*\(\s*\)/g, 'HashMap()')
      .replace(/\bnew\s+(?:java\.util\.)?(?:ArrayList|LinkedList)\s*\(\s*\)/g, 'ArrayList()')
      .replace(/\b(?:android\.text\.)?TextUtils\.isEmpty\s*\(/g, 'isEmpty(')
      .replace(/\b(?:android\.util\.Base64\.)?(?:DEFAULT|NO_WRAP|NO_PADDING|URL_SAFE)\b/g, '0')
      .replace(/\b(?:java\.nio\.charset\.)?StandardCharsets\.UTF_8\b/g, '"UTF-8"');
  }

  static unsupportedReason(code: string): string {
    const raw = code || '';
    if (!raw) return '';
    if (/\b(?:java\.lang\.(?:Runtime|ProcessBuilder)|android\.os\.Process|java\.lang\.reflect|java\.lang\.invoke)\b/i.test(raw)) {
      return '脚本请求了进程或反射能力';
    }
    if (/\b(?:java\.io\.|java\.nio\.file\.|android\.database\.|androidx?\.sqlite\.|android\.content\.Intent)\b/i.test(raw)) {
      return '脚本请求了文件、数据库或系统组件能力';
    }
    if (/\bjava\.(?:webView|downloadFile|cacheFile|unzipFile|unrarFile|un7zFile|unArchiveFile|readTxtFile|deleteFile|getFile|queryTTF|replaceFont)\s*\(/i.test(raw)) {
      return '脚本依赖当前未实现的 WebView、文件或字体扩展';
    }
    if (/\borg\.mozilla\.javascript\b/i.test(raw)) return '脚本依赖 Rhino 专用能力';

    const normalized = this.normalize(raw);
    const androidApi = normalized.match(/\bandroid\.([A-Za-z_$][A-Za-z0-9_$.]*)/i);
    if (androidApi) return `脚本依赖未映射的 Android API：android.${androidApi[1]}`;

    if (/\b(?:JavaImporter|Packages)\b/.test(normalized) && !this.isSupportedImportedWrapper(normalized)) {
      return '脚本依赖未映射的 Java 导入类';
    }
    if (/\bjavax?\.crypto\b/i.test(normalized) && !this.isSupportedCipherWrapper(normalized)) {
      return '脚本依赖未映射的 Java 加密流程';
    }
    return '';
  }

  private static isSupportedImportedWrapper(code: string): boolean {
    const withoutSupportedClasses = (code || '')
      .replace(/\b(?:JavaImporter|Packages)\b/g, '')
      .replace(/\b(?:javax?\.crypto(?:\.spec)?\.)?(?:Cipher|SecretKeySpec|IvParameterSpec)\b/g, '')
      .replace(/\bjava\.security\.MessageDigest\b/g, '')
      .replace(/\b(?:android\.util\.)?Base64\b/g, '')
      .replace(/\bjava\.net\.(?:URLDecoder|URLEncoder)\b/g, '')
      .replace(/[A-Za-z_$][A-Za-z0-9_$]*\s*=\s*new\s*\(\s*[^)]*\)/g, '');
    return !/\b(?:android|java|javax)\.[A-Za-z_$][A-Za-z0-9_$.]*/.test(withoutSupportedClasses) ||
      this.isSupportedCipherWrapper(code) || /\bMessageDigest\.getInstance\s*\(/.test(code);
  }

  private static isSupportedCipherWrapper(code: string): boolean {
    return /\bCipher\.getInstance\s*\(\s*(['"])(?:AES|DES|DESede|3DES)[^'"]*\1\s*\)/i.test(code) &&
      /\bSecretKeySpec\s*\(/.test(code);
  }
}
