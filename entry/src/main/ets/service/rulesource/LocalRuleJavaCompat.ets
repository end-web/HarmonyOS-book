/** Java data APIs implemented inside QuickJS; no Java VM or platform objects are exposed. */
export class LocalRuleJavaCompat {
  static code(): string {
    return String.raw`
{
  const boundedSize=function(n){n=Number(n);if(!Number.isInteger(n)||n<0||n>1048576)throw new Error('Invalid size or data budget exceeded');return n;};
  const iterator=function(values){let index=0;return {hasNext:function(){return index<values.length;},next:function(){if(index>=values.length)throw new Error('NoSuchElementException');return values[index++];}};};
  const collection=function(values){const out=Array.from(values||[]);
    Object.defineProperties(out,{
      iterator:{value:function(){return iterator(this);}},contains:{value:function(v){return this.includes(v);}},
      set:{value:function(i,v){i=Number(i);if(i<0||i>=this.length)throw new Error('IndexOutOfBoundsException');const old=this[i];this[i]=v;return old;}},
      add:{value:function(a,b){if(this.length>=1048576)throw new Error('Collection budget exceeded');if(arguments.length===1)this.push(a);else this.splice(Number(a),0,b);return true;}},
      addAll:{value:function(v){if(this.length+v.length>1048576)throw new Error('Collection budget exceeded');for(const item of v)this.push(item);return v.length>0;}},
      clear:{value:function(){this.length=0;}},remove:{value:function(v){const index=typeof v==='number'?v:this.indexOf(v);if(index<0||index>=this.length)return false;return this.splice(index,1)[0];}},
      indexOf:{value:Array.prototype.indexOf},subList:{value:function(a,b){return collection(this.slice(a,b));}}
    });return out;
  };
  class JavaMap {
    constructor(value){this.entries=new Map();if(value instanceof JavaMap)value.entries.forEach((v,k)=>this.entries.set(k,v));
      else if(value&&typeof value==='object')Object.keys(value).forEach(k=>this.entries.set(k,value[k]));}
    get(k){return this.entries.has(k)?this.entries.get(k):null;}
    getOrDefault(k,v){return this.entries.has(k)?this.entries.get(k):v;}
    put(k,v){const old=this.get(k);if(this.entries.size>=65536&&!this.entries.has(k))throw new Error('Map budget exceeded');this.entries.set(k,v);return old;}
    putAll(v){const m=v instanceof JavaMap?v:new JavaMap(v);m.entries.forEach((v,k)=>this.put(k,v));}
    remove(k){const old=this.get(k);this.entries.delete(k);return old;}
    containsKey(k){return this.entries.has(k);}
    containsValue(v){return Array.from(this.entries.values()).includes(v);}
    size(){return this.entries.size;}
    isEmpty(){return this.size()===0;}
    clear(){this.entries.clear();}
    keySet(){return collection(this.entries.keys());}
    values(){return collection(this.keySet().map(k=>this.get(k)));}
    entrySet(){return collection(this.keySet().map(k=>({getKey:()=>k,getValue:()=>this.get(k),setValue:v=>this.put(k,v)})));}
    toJSON(){const out=Object.create(null);this.keySet().forEach(k=>out[String(k)]=this.get(k));return out;}
    toString(){return '{'+this.keySet().map(k=>String(k)+'='+String(this.get(k))).join(', ')+'}';}
  }
  class TreeMap extends JavaMap {
    constructor(value){super(typeof value==='function'||value&&typeof value.compare==='function'?undefined:value);this.comparator=typeof value==='function'?value:value&&typeof value.compare==='function'?value.compare:undefined;}
    keySet(){return collection(Array.from(this.entries.keys()).sort(this.comparator||((a,b)=>a===b?0:a<b?-1:1)));}
    firstKey(){if(this.isEmpty())throw new Error('NoSuchElementException');return this.keySet()[0];}
    lastKey(){if(this.isEmpty())throw new Error('NoSuchElementException');return this.keySet()[this.size()-1];}
  }
  class HashSet {
    constructor(values){this.items=new Set(values||[]);}
    add(v){const size=this.size();if(size>=65536)throw new Error('Set budget exceeded');this.items.add(v);return size!==this.size();}
    addAll(values){let changed=false;for(const v of values)changed=this.add(v)||changed;return changed;}
    contains(v){return this.items.has(v);} remove(v){return this.items.delete(v);} size(){return this.items.size;}
    clear(){this.items.clear();} isEmpty(){return this.size()===0;} toArray(){return collection(this.items);}
    iterator(){return iterator(this.toArray());} toJSON(){return this.toArray();}
  }
  class TreeSet extends HashSet {toArray(){return collection(Array.from(this.items).sort((a,b)=>a===b?0:a<b?-1:1));}}
  const Arrays={asList:function(...v){return collection(v.length===1&&Array.isArray(v[0])?v[0]:v);},
    copyOf:function(v,n){const out=Array(boundedSize(n)).fill(0);for(let i=0;i<Math.min(v.length,n);i++)out[i]=v[i];return out;},
    copyOfRange:function(v,a,b){const out=Array(boundedSize(b-a)).fill(0);for(let i=0;i<out.length&&a+i<v.length;i++)out[i]=v[a+i];return out;},
    equals:function(a,b){return a===b||!!a&&!!b&&a.length===b.length&&a.every((v,i)=>v===b[i]);},
    fill:function(a,v){a.fill(v);},sort:function(a,c){a.sort(c&&c.compare?c.compare:c||((a,b)=>a===b?0:a<b?-1:1));},toString:function(a){return '['+a.join(', ')+']';}};
  const Collections={sort:Arrays.sort,reverse:function(a){a.reverse();},emptyList:function(){return collection([]);},
    singletonList:function(v){return collection([v]);},min:function(a){return Array.from(a).sort((a,b)=>a<b?-1:1)[0];},
    max:function(a){return Array.from(a).sort((a,b)=>a<b?1:-1)[0];},reverseOrder:function(){return {compare:function(a,b){return a===b?0:a<b?1:-1;}};}};

  const quote=function(v){return String(v).replace(/[.*+?^$()|[\]\\]/g,'\\$&');};
  const regexSource=function(value){return String(value).replace(/\\Q([\s\S]*?)\\E/g,(_m,v)=>quote(v)).replace(/\\A/g,'^').replace(/\\[zZ]/g,'$');};
  class Matcher {
    constructor(pattern,text){this.pattern=pattern;this.text=String(text);this.reset();}
    reset(text){if(text!==undefined)this.text=String(text);this.regex=new RegExp(this.pattern.source,this.pattern.flags+'g');this.match=null;return this;}
    find(start){if(start!==undefined)this.regex.lastIndex=Number(start);this.match=this.regex.exec(this.text);
      if(this.match&&this.match[0]==='')this.regex.lastIndex++;return this.match!==null;}
    matches(){this.match=new RegExp('^(?:'+this.pattern.source+')$',this.pattern.flags).exec(this.text);return !!this.match;}
    lookingAt(){this.match=new RegExp('^(?:'+this.pattern.source+')',this.pattern.flags).exec(this.text);return !!this.match;}
    group(index){if(!this.match)throw new Error('No match found');const value=typeof index==='string'?this.match.groups&&this.match.groups[index]:this.match[index||0];return value===undefined?null:value;}
    groupCount(){const match=this.match||new RegExp('(?:'+this.pattern.source+')|',this.pattern.flags).exec('');return match.length-1;}
    start(){if(!this.match)throw new Error('No match found');return this.match.index;}
    end(){return this.start()+this.match[0].length;}
    replaceAll(value){return this.text.replace(new RegExp(this.pattern.source,this.pattern.flags+'g'),String(value));}
    replaceFirst(value){return this.text.replace(new RegExp(this.pattern.source,this.pattern.flags),String(value));}
  }
  Matcher.quoteReplacement=function(value){return String(value).replace(/[$\\]/g,'\\$&');};
  const Pattern={CASE_INSENSITIVE:2,MULTILINE:8,LITERAL:16,DOTALL:32,UNICODE_CASE:64,UNICODE_CHARACTER_CLASS:256,
    quote:quote,matches:function(pattern,text){return this.compile(pattern).matcher(text).matches();},
    compile:function(text,flags){flags=Number(flags)||0;let source=flags&16?quote(text):regexSource(text),options='';
      source=source.replace(/^\(\?([ims]+)\)/,function(_m,f){options+=f;return '';});
      if(flags&2)options+='i';if(flags&8)options+='m';if(flags&32)options+='s';options=Array.from(new Set(options)).join('');
      new RegExp(source,options);return {source:source,flags:options,matcher:function(text){return new Matcher(this,text);},
        pattern:function(){return String(text);},split:function(text,limit){const result=String(text).split(new RegExp(source,options));
          if(!limit)while(result.length&&result[result.length-1]==='')result.pop();return limit>0?result.slice(0,limit):result;}};}};

  const parseInteger=function(value,radix){let text=String(value).trim(),base=Number(radix||10),sign=1n,n=0n;
    if(base<2||base>36||!Number.isInteger(base)||!text)throw new Error('NumberFormatException');
    if(text[0]==='-'||text[0]==='+'){if(text[0]==='-')sign=-1n;text=text.slice(1);}if(!text||text.length>100000)throw new Error('NumberFormatException');
    for(const c of text.toLowerCase()){const d='0123456789abcdefghijklmnopqrstuvwxyz'.indexOf(c);if(d<0||d>=base)throw new Error('NumberFormatException');n=n*BigInt(base)+BigInt(d);}return n*sign;};
  class BigInteger {
    constructor(value,radix){if(Array.isArray(radix)||ArrayBuffer.isView(radix)){let h=bytesHex(toBytes(radix));this.n=(h?BigInt('0x'+h):0n)*BigInt(Math.sign(Number(value)));}
      else if(Array.isArray(value)||ArrayBuffer.isView(value)){const b=toBytes(value);this.n=b.length?BigInt('0x'+bytesHex(b)):0n;if(b.length&&b[0]&128)this.n-=1n<<BigInt(b.length*8);}
      else this.n=value instanceof BigInteger?value.n:parseInteger(value??0,radix);}
    toString(radix){return this.n.toString(Number(radix)||10);} toJSON(){return this.toString();} valueOf(){return Number(this.n);}
    add(v){return new BigInteger(this.n+new BigInteger(v).n);} subtract(v){return new BigInteger(this.n-new BigInteger(v).n);}
    multiply(v){return new BigInteger(this.n*new BigInteger(v).n);} divide(v){return new BigInteger(this.n/new BigInteger(v).n);}
    remainder(v){return new BigInteger(this.n%new BigInteger(v).n);} mod(v){const n=new BigInteger(v).n;if(n<=0n)throw new Error('Non-positive modulus');return new BigInteger((this.n%n+n)%n);}
    pow(v){v=Number(v);if(!Number.isInteger(v)||v<0||v>65536)throw new Error('Exponent budget exceeded');return new BigInteger(this.n**BigInt(v));}
    modPow(exponent,modulus){let e=new BigInteger(exponent).n,m=new BigInteger(modulus).n;if(e<0n||m<=0n)throw new Error('Invalid modPow arguments');let b=(this.n%m+m)%m,r=1n;
      while(e){if(e&1n)r=r*b%m;e>>=1n;b=b*b%m;}return new BigInteger(r%m);}
    compareTo(v){const n=new BigInteger(v).n;return this.n===n?0:this.n<n?-1:1;} equals(v){return v instanceof BigInteger&&v.n===this.n;}
    abs(){return new BigInteger(this.n<0n?-this.n:this.n);} negate(){return new BigInteger(-this.n);} signum(){return this.n===0n?0:this.n<0n?-1:1;}
    intValue(){return Number(BigInt.asIntN(32,this.n));} longValue(){return new BigInteger(BigInt.asIntN(64,this.n));}
    bitLength(){const n=this.n<0n?~this.n:this.n;return n===0n?0:n.toString(2).length;}
    shiftLeft(v){return new BigInteger(this.n<<BigInt(Math.min(1048576,Number(v))));} shiftRight(v){return new BigInteger(this.n>>BigInt(Math.min(1048576,Number(v))));}
    and(v){return new BigInteger(this.n&new BigInteger(v).n);} or(v){return new BigInteger(this.n|new BigInteger(v).n);} xor(v){return new BigInteger(this.n^new BigInteger(v).n);}
    toByteArray(){let count=Math.max(1,Math.ceil((this.bitLength()+1)/8)),n=BigInt.asUintN(count*8,this.n),out=[];
      while(count--){out.unshift(Number(n&255n));n>>=8n;}return out;}
  }
  BigInteger.ZERO=new BigInteger(0);BigInteger.ONE=new BigInteger(1);BigInteger.TEN=new BigInteger(10);BigInteger.valueOf=v=>new BigInteger(v);
  const Long={parseLong:function(v,r){const n=parseInteger(v,r);if(n<-(1n<<63n)||n>=(1n<<63n))throw new Error('NumberFormatException');return new BigInteger(n);},
    valueOf:function(v){return this.parseLong(v);},toHexString:function(v){return BigInt.asUintN(64,new BigInteger(v).n).toString(16);},toString:function(v,r){return new BigInteger(v).toString(r);},
    MAX_VALUE:new BigInteger('9223372036854775807'),MIN_VALUE:new BigInteger('-9223372036854775808')};
  const Integer={parseInt:function(v,r){const n=parseInteger(v,r);if(n<-2147483648n||n>2147483647n)throw new Error('NumberFormatException');return Number(n);},
    valueOf:function(v){return this.parseInt(v);},toHexString:function(v){return (Number(v)>>>0).toString(16);},toString:function(v,r){return Number(v).toString(r||10);},MAX_VALUE:2147483647,MIN_VALUE:-2147483648};

  class JSONObject {
    constructor(value){this.data=value instanceof JSONObject?JSON.parse(value.toString()):typeof value==='string'?JSON.parse(value):value&&typeof value==='object'?JSON.parse(JSON.stringify(value)):{};
      if(!this.data||Array.isArray(this.data)||typeof this.data!=='object')throw new Error('JSONObject requires an object');}
    has(k){return Object.prototype.hasOwnProperty.call(this.data,String(k));} isNull(k){return !this.has(k)||this.data[String(k)]===null;}
    get(k){if(!this.has(k))throw new Error('JSONObject key not found: '+k);return jsonWrap(this.data[String(k)]);}
    opt(k){return this.has(k)?jsonWrap(this.data[String(k)]):null;}
    put(k,v){if(v===undefined||v===null)delete this.data[String(k)];else Object.defineProperty(this.data,String(k),{value:jsonUnwrap(v),writable:true,enumerable:true,configurable:true});return this;}
    remove(k){const v=this.opt(k);delete this.data[String(k)];return v;} length(){return Object.keys(this.data).length;}
    keys(){return iterator(Object.keys(this.data));} names(){return this.length()?new JSONArray(Object.keys(this.data)):null;}
    toString(indent){return JSON.stringify(this.data,null,indent||0);} toJSON(){return this.data;}
  }
  class JSONArray {
    constructor(value){this.data=value instanceof JSONArray?JSON.parse(value.toString()):typeof value==='string'?JSON.parse(value):Array.from(value||[]).map(jsonUnwrap);
      if(!Array.isArray(this.data))throw new Error('JSONArray requires an array');}
    length(){return this.data.length;} get(i){i=Number(i);if(i<0||i>=this.length())throw new Error('JSONArray index out of bounds');return jsonWrap(this.data[i]);}
    opt(i){return i>=0&&i<this.length()?this.get(i):null;} isNull(i){return this.opt(i)===null;}
    put(a,b){if(arguments.length===1)this.data.push(jsonUnwrap(a));else {const i=boundedSize(a);while(this.data.length<=i)this.data.push(null);this.data[i]=jsonUnwrap(b);}return this;}
    remove(i){return jsonWrap(this.data.splice(Number(i),1)[0]);} toString(indent){return JSON.stringify(this.data,null,indent||0);} toJSON(){return this.data;}
  }
  const jsonWrap=v=>Array.isArray(v)?new JSONArray(v):v&&typeof v==='object'?new JSONObject(v):v;
  const jsonUnwrap=v=>v instanceof JSONObject||v instanceof JSONArray?v.data:v;
  for(const type of [JSONObject,JSONArray]){
    for(const kind of ['String','Int','Long','Double','Boolean','JSONObject','JSONArray']){
      const convert=function(v){if(kind==='String')return String(v);if(kind==='Int')return Integer.parseInt(v);if(kind==='Long')return Long.parseLong(v);
        if(kind==='Double'){const n=Number(v);if(!Number.isFinite(n))throw new Error('Invalid JSON number');return n;}
        if(kind==='Boolean'){if(v===true||v==='true')return true;if(v===false||v==='false')return false;throw new Error('Invalid JSON boolean');}
        if(kind==='JSONObject'&&v instanceof JSONObject||kind==='JSONArray'&&v instanceof JSONArray)return v;throw new Error('Invalid JSON type');};
      type.prototype['get'+kind]=function(k){return convert(this.get(k));};
      type.prototype['opt'+kind]=function(k,fallback){try{const v=this.opt(k);if(v===null)throw new Error();return convert(v);}catch(e){return fallback!==undefined?fallback:kind==='String'?'':kind==='Boolean'?false:kind==='JSONObject'||kind==='JSONArray'?null:0;}};
    }
  }

  class ByteArrayInputStream {
    constructor(value,offset,length){const bytes=toBytes(value);offset=Number(offset)||0;this.bytes=bytes.slice(offset,length===undefined?undefined:offset+Number(length));this.position=0;this.marked=0;}
    read(target,offset,length){if(target===undefined)return this.position<this.bytes.length?this.bytes[this.position++]:-1;
      offset=Number(offset)||0;length=length===undefined?target.length-offset:boundedSize(length);if(length===0)return 0;
      if(this.position>=this.bytes.length)return -1;const count=Math.min(length,this.bytes.length-this.position);if(offset<0||offset+count>target.length)throw new Error('IndexOutOfBoundsException');
      for(let i=0;i<count;i++)target[offset+i]=this.bytes[this.position++];return count;}
    readAllBytes(){const out=this.bytes.slice(this.position);this.position=this.bytes.length;return out;}
    available(){return this.bytes.length-this.position;} skip(n){const count=Math.max(0,Math.min(Number(n),this.available()));this.position+=count;return count;}
    mark(){this.marked=this.position;} reset(){this.position=this.marked;} markSupported(){return true;} close(){}
  }
  class ByteArrayOutputStream {
    constructor(){this.bytes=[];}
    write(value,offset,length){const bytes=typeof value==='number'?[value&255]:toBytes(value).slice(Number(offset)||0,length===undefined?undefined:(Number(offset)||0)+Number(length));
      if(this.bytes.length+bytes.length>1048576)throw new Error('Byte stream budget exceeded');for(const b of bytes)this.bytes.push(b);}
    toByteArray(){return this.bytes.slice();} size(){return this.bytes.length;} reset(){this.bytes=[];} close(){} flush(){}
    writeTo(out){out.write(this.bytes);} toString(charset){return fromBytes(this.bytes,charset);}
  }
  class StringReader {constructor(value){this.text=String(value);this.position=0;} close(){} read(){return this.position<this.text.length?this.text.charCodeAt(this.position++):-1;}}
  class InputStreamReader extends StringReader {constructor(input,charset){super(fromBytes(input.readAllBytes(),charset));}}
  class BufferedReader extends StringReader {
    constructor(reader){super(reader.text===undefined?fromBytes(reader.readAllBytes()):reader.text.slice(reader.position||0));}
    readLine(){if(this.position>=this.text.length)return null;const remaining=this.text.slice(this.position),m=/\r\n|\r|\n/.exec(remaining);
      if(!m){this.position=this.text.length;return remaining;}this.position+=m.index+m[0].length;return remaining.slice(0,m.index);}
  }
  const Mac={getInstance:function(algorithm){let key=[],bytes=[];return {init:function(v){key=toBytes(v.bytes||v);bytes=[];},
    update:function(v,offset,length){const b=typeof v==='number'?[v&255]:toBytes(v);bytes.push(...b.slice(Number(offset)||0,length===undefined?undefined:(Number(offset)||0)+Number(length)));},
    doFinal:function(v){if(v!==undefined)this.update(v);const out=fromHex(java.hmac(algorithm,bytes,key));bytes=[];return out;},reset:function(){bytes=[];},getAlgorithm:function(){return algorithm;}};}};
  class EncodedKeySpec {constructor(bytes){this.bytes=toBytes(bytes);}getEncoded(){return this.bytes.slice();}}
  class X509EncodedKeySpec extends EncodedKeySpec {getFormat(){return 'X.509';}}
  class PKCS8EncodedKeySpec extends EncodedKeySpec {getFormat(){return 'PKCS#8';}}
  const KeyFactory={getInstance:function(algorithm){if(String(algorithm).toUpperCase()!=='RSA')throw new Error('Unsupported key algorithm');
    const key=function(spec,privateKey){if(!(spec instanceof EncodedKeySpec))throw new Error('Encoded key specification required');
      return {bytes:spec.getEncoded(),privateKey:privateKey,getEncoded:function(){return this.bytes.slice();},getAlgorithm:function(){return 'RSA';},getFormat:function(){return privateKey?'PKCS#8':'X.509';}};};
    return {generatePublic:function(spec){return key(spec,false);},generatePrivate:function(spec){return key(spec,true);}};}};
  const rsa=function(algorithm,mode,key,data,signature){return action('rsa',{algorithm:String(algorithm),mode:mode,key:bytesHex(key.bytes),
    privateKey:!!key.privateKey,data:bytesHex(data),signature:bytesHex(signature||[])});};
  const Signature={getInstance:function(algorithm){let key,mode='',bytes=[];return {
    initSign:function(v){key=v;mode='sign';bytes=[];},initVerify:function(v){key=v;mode='verify';bytes=[];},
    update:function(v,offset,length){const input=typeof v==='number'?[v&255]:toBytes(v);bytes.push(...input.slice(Number(offset)||0,length===undefined?undefined:(Number(offset)||0)+Number(length)));},
    sign:function(){if(mode!=='sign')throw new Error('Signature not initialized for signing');const out=fromHex(rsa(algorithm,mode,key,bytes)||'');bytes=[];return out;},
    verify:function(signature){if(mode!=='verify')throw new Error('Signature not initialized for verification');const result=rsa(algorithm,mode,key,bytes,toBytes(signature));bytes=[];return !!result;}};}};
  const compressBytes=function(value,compress,format){return fromHex(action('compress',{data:bytesHex(toBytes(value)),compress:compress,format:format})||'');};
  class GZIPInputStream extends ByteArrayInputStream {constructor(input){super(compressBytes(input.readAllBytes(),false,'gzip'));}}
  class InflaterInputStream extends ByteArrayInputStream {constructor(input){super(compressBytes(input.readAllBytes(),false,'zlib'));}}
  class GZIPOutputStream extends ByteArrayOutputStream {
    constructor(output){super();this.output=output;this.done=false;this.format='gzip';}
    write(...args){if(this.done)throw new Error('Stream already finished');super.write(...args);}
    finish(){if(!this.done){this.output.write(compressBytes(this.bytes,true,this.format));this.done=true;}}
    close(){this.finish();this.output.close();}
  }
  class DeflaterOutputStream extends GZIPOutputStream {constructor(output){super(output);this.format='zlib';}}
  class Inflater {
    constructor(raw){this.raw=!!raw;this.input=[];this.output=null;this.position=0;}
    setInput(value,offset,length){this.input=toBytes(value).slice(Number(offset)||0,length===undefined?undefined:(Number(offset)||0)+Number(length));this.output=null;this.position=0;}
    inflate(target,offset,length){if(this.output===null)this.output=compressBytes(this.input,false,this.raw?'raw':'zlib');
      offset=Number(offset)||0;length=length===undefined?target.length-offset:Number(length);const n=Math.min(length,this.output.length-this.position);
      if(offset<0||offset+n>target.length)throw new Error('IndexOutOfBoundsException');for(let i=0;i<n;i++)target[offset+i]=this.output[this.position++];return n;}
    finished(){return this.output!==null&&this.position===this.output.length;} needsInput(){return this.input.length===0;}
    reset(){this.input=[];this.output=null;this.position=0;} end(){this.reset();}
  }
  class CRC32 {constructor(){this.reset();}reset(){this.value=0xffffffff;}update(value,offset,length){const input=typeof value==='number'?[value&255]:toBytes(value).slice(Number(offset)||0,length===undefined?undefined:(Number(offset)||0)+Number(length));
    for(const b of input){this.value^=b;for(let i=0;i<8;i++)this.value=(this.value>>>1)^((this.value&1)?0xedb88320:0);}}
    getValue(){return (this.value^0xffffffff)>>>0;}}
  java.gzip=function(value){return compressBytes(value,true,'gzip');};java.unGzip=function(value){return compressBytes(value,false,'gzip');};
  const OriginalCipher=Cipher.getInstance;
  Cipher.getInstance=function(algorithm){let key,mode;const cipher=/^RSA(?:\/|$)/i.test(algorithm)?{
      init:function(m,k){key=k;mode=Number(m)===1?'encrypt':'decrypt';},doFinal:function(v){return fromHex(rsa(algorithm,mode,key,v)||'');}}:OriginalCipher(algorithm);
    let bytes=[];const finish=cipher.doFinal,initialize=cipher.init;
    cipher.init=function(...args){bytes=[];return initialize(...args);};cipher.update=function(v,offset,length){const data=toBytes(v);bytes.push(...data.slice(Number(offset)||0,length===undefined?undefined:(Number(offset)||0)+Number(length)));return [];};
    cipher.doFinal=function(v,offset,length){if(v!==undefined)cipher.update(v,offset,length);const result=finish(bytes);bytes=[];return result;};return cipher;};
  const charset=function(name){const value=String(name);return {name:()=>value,toString:()=>value};};
  class JavaURI {
    constructor(text,base){this.fields=action('uri',{text:String(text),base:base===undefined?'':String(base)})||{text:String(text)};}
    toString(){return this.fields.text;} toASCIIString(){return encodeURI(decodeURI(this.toString()));} toJSON(){return this.toString();}
    getScheme(){return this.fields.scheme||null;} getHost(){return this.fields.host||null;} getPort(){return this.fields.port?Number(this.fields.port):-1;}
    getPath(){return this.fields.path||'';}getQuery(){return this.fields.query||null;}getFragment(){return this.fields.fragment||null;}
    getRawPath(){return this.fields.rawPath||'';}getRawQuery(){return this.fields.rawQuery||null;}getRawFragment(){return this.fields.rawFragment||null;}
    getAuthority(){return this.fields.authority||null;} getUserInfo(){return this.fields.userInfo?decodeURIComponent(this.fields.userInfo):null;}
    isAbsolute(){return !!this.getScheme();}normalize(){return new JavaURI(this.toString());}resolve(value){return new JavaURI(value,this.toString());}
    toURL(){return new JavaURL(this.toString());}equals(v){return v instanceof JavaURI&&v.toString()===this.toString();}
  }
  JavaURI.create=function(v){return new JavaURI(v);};
  class JavaURL extends JavaURI {
    constructor(a,b,c,d){super(arguments.length===1?a:arguments.length===2?b:String(a)+'://'+String(b)+(arguments.length===4&&Number(c)>=0?':'+c:'')+String(arguments.length===4?d:c),arguments.length===2?a:undefined);}
    getProtocol(){return this.getScheme();} getFile(){return this.getRawPath()+(this.getRawQuery()===null?'':'?'+this.getRawQuery());}
    getRef(){return this.getFragment();}toExternalForm(){return this.toString();}toURI(){return new JavaURI(this.toString());}
    getDefaultPort(){return this.getProtocol()==='https'?443:this.getProtocol()==='http'?80:-1;}
  }
  const TimeZone={getTimeZone:function(id){const name=String(id);let hours;
    if(/^(UTC|GMT|Etc\/UTC)$/.test(name))hours=0;else if(/^(Asia\/Shanghai|Asia\/Hong_Kong|Asia\/Taipei)$/.test(name))hours=8;
    else {const m=/^(?:GMT|UTC)([+-])(\d{1,2})(?::?(\d{2}))?$/.exec(name);if(!m)throw new Error('Unsupported time zone: '+name);hours=(Number(m[2])+Number(m[3]||0)/60)*(m[1]==='-'?-1:1);}
    return {getID:()=>name,getRawOffset:()=>hours*3600000,hours:hours};}};
  class SimpleDateFormat {
    constructor(pattern){this.pattern=String(pattern||'yyyy-MM-dd HH:mm:ss');this.zone=undefined;}
    setTimeZone(zone){this.zone=zone.hours;}format(date){return formatTime(date instanceof Date?date.getTime():Number(date),this.pattern,this.zone);}
    parse(text){const tokens=[],pattern=this.pattern.replace(/'([^']*)'|yyyy|SSS|MM|dd|HH|mm|ss|./g,function(token,literal){
      if(literal!==undefined)return quote(literal);if(/^(yyyy|SSS|MM|dd|HH|mm|ss)$/.test(token)){tokens.push(token);return '(\\d{'+token.length+'})';}return quote(token);});
      const match=new RegExp('^'+pattern+'$').exec(String(text));if(!match)throw new Error('Unparseable date');const fields={yyyy:1970,MM:1,dd:1,HH:0,mm:0,ss:0,SSS:0};
      tokens.forEach((t,i)=>fields[t]=Number(match[i+1]));const values=[fields.yyyy,fields.MM-1,fields.dd,fields.HH,fields.mm,fields.ss,fields.SSS];
      return this.zone===undefined?new Date(...values):new Date(Date.UTC(...values)-this.zone*3600000);}
  }
  const encoder=function(urlSafe,padding){return {encodeToString:function(v){let out=encodeBase64(v,false);if(urlSafe)out=out.replace(/\+/g,'-').replace(/\//g,'_');return padding?out:out.replace(/=+$/,'');},
    encode:function(v){return toBytes(this.encodeToString(v));},withoutPadding:function(){return encoder(urlSafe,false);}};};
  javaBase64.getEncoder=function(){return encoder(false,true);};javaBase64.getUrlEncoder=function(){return encoder(true,true);};
  javaBase64.getMimeDecoder=javaBase64.getDecoder;
  androidBase64.encodeToString=function(v,flags){flags=Number(flags)||0;let out=encoder((flags&8)!==0,(flags&1)===0).encodeToString(v);
    if(!(flags&2)&&out.length){const newline=flags&4?'\r\n':'\n';out=out.match(/.{1,76}/g).join(newline)+newline;}return out;};
  const StandardCharsets={UTF_8:'UTF-8',UTF_16:'UTF-16',UTF_16BE:'UTF-16BE',UTF_16LE:'UTF-16LE',US_ASCII:'ASCII',ISO_8859_1:'ISO-8859-1'};
  const Charset={forName:charset,defaultCharset:()=>charset('UTF-8'),isSupported:function(name){return /^(utf-?8|utf-?16(?:be|le)?|ascii|us-ascii|iso-8859-1|gbk|gb2312|gb18030|big5)$/i.test(String(name));}};
  android.text={TextUtils:{isEmpty:v=>v===null||v===undefined||String(v).length===0,equals:(a,b)=>a===b||a!=null&&b!=null&&String(a)===String(b),
    join:(delimiter,tokens)=>Array.from(tokens).join(String(delimiter)),split:(text,pattern)=>String(text)===''?[]:String(text).split(new RegExp(pattern))}};
  java.lang.Integer=Integer;java.lang.Long=Long;java.lang.StringBuffer=StringBuilder;
  java.lang.Double={parseDouble:v=>Number(v),valueOf:v=>Number(v),isNaN:Number.isNaN,isInfinite:v=>!Number.isFinite(Number(v))};java.lang.Float=java.lang.Double;
  java.lang.Math=Math;java.lang.Character={isDigit:v=>/^[0-9]$/.test(String(v)),isWhitespace:v=>/^\s$/.test(String(v)),toLowerCase:v=>String(v).toLowerCase(),toUpperCase:v=>String(v).toUpperCase()};
  let sleepSequence=0;
  java.sleep=function(duration){duration=Number(duration);const done=action('sleep',{duration:duration,sequence:sleepSequence++});
    if(!done)throw new Error('Sleep action pending');scriptElapsed+=duration;};
  java.lang.Thread={sleep:function(duration){return java.sleep(duration);}};
  java.lang.System.currentTimeMillis=function(){return fixedNow+scriptElapsed;};
  java.lang.System.arraycopy=function(src,from,dest,to,count){const values=src.slice(Number(from),Number(from)+boundedSize(count));if(from<0||to<0||values.length!==count||to+count>dest.length)throw new Error('IndexOutOfBoundsException');for(let i=0;i<count;i++)dest[to+i]=values[i];};
  Object.assign(java.util,{HashMap:JavaMap,LinkedHashMap:JavaMap,TreeMap:TreeMap,ArrayList:function(v){return collection(typeof v==='number'?[]:v);},
    LinkedList:function(v){return collection(v);},HashSet:HashSet,LinkedHashSet:HashSet,TreeSet:TreeSet,Arrays:Arrays,Collections:Collections,
    regex:{Pattern:Pattern,Matcher:Matcher},Date:StableDate});
  java.math={BigInteger:BigInteger};java.io={ByteArrayInputStream:ByteArrayInputStream,ByteArrayOutputStream:ByteArrayOutputStream,StringReader:StringReader,InputStreamReader:InputStreamReader,BufferedReader:BufferedReader};
  java.net.URI=JavaURI;java.net.URL=JavaURL;java.text={SimpleDateFormat:SimpleDateFormat};java.util.TimeZone=TimeZone;
  java.nio={charset:{Charset:Charset,StandardCharsets:StandardCharsets}};javax.crypto.Mac=Mac;
  java.security.KeyFactory=KeyFactory;java.security.Signature=Signature;java.security.spec={X509EncodedKeySpec:X509EncodedKeySpec,PKCS8EncodedKeySpec:PKCS8EncodedKeySpec};
  java.util.zip={GZIPInputStream:GZIPInputStream,GZIPOutputStream:GZIPOutputStream,InflaterInputStream:InflaterInputStream,DeflaterOutputStream:DeflaterOutputStream,Inflater:Inflater,CRC32:CRC32};
  const org={json:{JSONObject:JSONObject,JSONArray:JSONArray}};Packages.org=org;globalThis.org=org;
  const registry=Object.create(null),packages=[];
  const register=function(path,pkg){packages.push(pkg);Object.keys(pkg).forEach(function(name){const v=pkg[name];
    if(typeof v==='function'||v&&typeof v==='object'&&Object.values(v).some(x=>typeof x==='function'))registry[path+'.'+name]=v;});};
  register('java.lang',java.lang);register('java.util',java.util);register('java.util.regex',java.util.regex);register('java.math',java.math);register('java.io',java.io);
  register('java.text',java.text);
  register('java.net',java.net);register('java.nio.charset',java.nio.charset);registry['java.nio.charset.StandardCharsets']=StandardCharsets;
  register('java.security',java.security);register('java.security.spec',java.security.spec);register('java.util.zip',java.util.zip);
  register('javax.crypto',javax.crypto);register('javax.crypto.spec',javax.crypto.spec);register('android.util',android.util);register('android.text',android.text);register('org.json',org.json);
  Java.type=function(name){name=String(name);if(/^(byte|char|int|long|java.lang.String)\[\]$/.test(name))return function(n){return Array(boundedSize(n)).fill(0);};
    if(!Object.prototype.hasOwnProperty.call(registry,name))throw new Error('Unsupported Java class: '+name);return registry[name];};
  const importInto=function(target,item){if(packages.includes(item)){Object.keys(item).forEach(k=>target[k]=item[k]);return;}
    const name=Object.keys(registry).find(k=>registry[k]===item);if(!name)throw new Error('Unsupported Java import');target[name.slice(name.lastIndexOf('.')+1)]=item;};
  globalThis.importClass=function(...types){types.forEach(t=>importInto(globalThis,t));};
  globalThis.importPackage=function(...types){types.forEach(t=>{if(!packages.includes(t))throw new Error('Unsupported Java package');importInto(globalThis,t);});};
  globalThis.JavaImporter=function(...types){const imports={};types.forEach(t=>importInto(imports,t));return imports;};
  ['java.util.HashMap','java.util.ArrayList','java.util.TreeMap','java.lang.Integer','java.lang.Long','java.math.BigInteger','java.util.regex.Pattern','javax.crypto.Mac','org.json.JSONObject','org.json.JSONArray'].forEach(name=>{
    globalThis[name.slice(name.lastIndexOf('.')+1)]=registry[name];});
}
`;
  }
}
