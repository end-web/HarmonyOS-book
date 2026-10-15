type NativeDraftValue = string | number | boolean | null | NativeDraftValue[] | { [key: string]: NativeDraftValue };
type NativeDraftObject = { [key: string]: NativeDraftValue };

export class NativeSourceField {
  path: string = '';
  key: string = '';
  kind: string = 'string';
  value: string = '';
  exists: boolean = false;
  readOnly: boolean = false;
}

/** UI edits the original native definition, never the compatibility-rule projection. */
export class NativeSourceDraft {
  private root: NativeDraftObject;
  private invalid = new Map<string, string>();
  private ids = new Map<string, string>();
  private nextId = 0;
  static readonly stages = ['search', 'detail', 'toc', 'content', 'explore', 'login'];

  constructor(json: string = '{}') {
    const parsed: NativeDraftValue = JSON.parse(json);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('Invalid source object');
    this.root = parsed;
  }

  private parts(path: string): string[] { return path ? path.split('/').slice(1).map(s => s.replace(/~1/g, '/').replace(/~0/g, '~')) : []; }
  private child(path: string, key: string): string { return path + '/' + key.replace(/~/g, '~0').replace(/\//g, '~1'); }
  parent(path: string): string { return path.slice(0, path.lastIndexOf('/')); }
  private safe(key: string): boolean { return !['__proto__', 'prototype', 'constructor'].includes(key); }
  private get(path: string): NativeDraftValue | undefined {
    let value: NativeDraftValue | undefined = this.root;
    for (const key of this.parts(path)) {
      if (!this.safe(key) || !value || typeof value !== 'object') return undefined;
      value = Array.isArray(value) ? value[Number(key)] : Object.prototype.hasOwnProperty.call(value, key) ? value[key] : undefined;
    }
    return value;
  }

  private schema(path: string): Record<string, string> {
    const keys = this.parts(path), key = keys[keys.length - 1] || '';
    const request = {url:'string',method:'string',headers:'object',body:'string',webView:'boolean'};
    const stage = {...request,let:'object',fail:'string',list:'string',fields:'object'};
    if (!path) return {name:'string',url:'string',group:'string',comment:'string',type:'string',enabled:'boolean',
      enabledExplore:'boolean',rate:'string',headers:'object',vars:'array',voices:'array',let:'object',lib:'string'};
    if (keys.length === 1) {
      switch (key) {
        case 'search': return stage;
        case 'detail': return {...stage,keep:'object'};
        case 'toc': return {...stage,nextUrl:'string',reverse:'boolean'};
        case 'content': return {...stage,text:'string',images:'string',audio:'string',video:'string',nextUrl:'string',
          replace:'array',fetch:'object',comments:'object',links:'array'};
        case 'explore': return {...stage,menus:'array',dynamicMenus:'object'};
        case 'login': return {url:'string',cookies:'array',check:'object'};
      }
    }
    if (key === 'fields') return {name:'string',author:'string',bookUrl:'string',coverUrl:'string',intro:'string',
      title:'string',url:'string',type:'string'};
    if (key === 'dynamicMenus') return {...request,list:'string',title:'string',target:'string'};
    if (key === 'check') return {...request,ok:'string',name:'string'};
    if (key === 'comments') return {when:'string',stats:'object',counts:'string',paragraphUrl:'string',chapterUrl:'string',max:'number'};
    if (key === 'stats') return request;
    const parent = keys[keys.length - 2];
    if (parent === 'vars') return {key:'string',label:'string',options:'array',default:'string',filter:'boolean'};
    if (parent === 'voices') return {id:'string',name:'string'};
    if (parent === 'menus') return {title:'string',url:'string',when:'string',headers:'object'};
    if (parent === 'links') return {label:'string',url:'string',when:'string'};
    if (parent === 'replace') return {pattern:'string',with:'string',flags:'string'};
    if (parent === 'fetch') return {...request,when:'string'};
    return {};
  }

  kind(path: string): string {
    const value = this.get(path);
    if (value !== undefined) return value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value;
    const key = this.parts(path).pop() || '';
    return this.schema(this.parent(path))[key] || 'object';
  }
  fields(path: string): NativeSourceField[] {
    const value = this.get(path);
    const actual = value && typeof value === 'object' ? Object.keys(value) : [];
    const keys = Array.from(new Set([...actual,...Object.keys(this.schema(path))]));
    return keys.filter(key => this.safe(key) && (path || !NativeSourceDraft.stages.includes(key))).map(key => {
      const item = new NativeSourceField();
      item.path = this.child(path,key); item.key = key;
      const value = this.get(item.path);
      item.exists = value !== undefined; item.kind = this.kind(item.path);
      item.value = this.invalid.get(item.path) ?? (value === undefined ? '' :
        typeof value === 'object' && value !== null ? String(Object.keys(value).length) : String(value));
      if (value === undefined && !path && ['enabled','enabledExplore'].includes(key)) item.value = 'true';
      item.readOnly = !path && ['url','sourceFormat','version','nativeSource'].includes(key);
      return item;
    });
  }
  /** Array indexes are paths, not node identities. Remap IDs after removal. */
  stableKey(path: string): string {
    let id = this.ids.get(path);
    if (!id) { id = `native-field-${++this.nextId}`; this.ids.set(path,id); }
    return id;
  }
  private set(path: string, value: NativeDraftValue): void {
    const parts = this.parts(path);
    let node: NativeDraftValue = this.root, currentPath = '';
    for (let i = 0; i < parts.length; i++) {
      const key = parts[i];
      if (!this.safe(key) || !node || typeof node !== 'object') throw new Error('Invalid field path');
      const last = i === parts.length - 1;
      const nextPath = this.child(currentPath,key);
      const next = last ? value : this.get(nextPath) ?? (this.kind(nextPath) === 'array' ? [] : {});
      if (Array.isArray(node)) node[Number(key)] = next;
      else node[key] = next;
      node = next; currentPath = nextPath;
    }
  }
  edit(field: NativeSourceField, text: string): void {
    if (field.readOnly) throw new Error('Read-only field');
    if (field.kind === 'number') {
      if (!text.trim() || !Number.isFinite(Number(text))) { this.invalid.set(field.path,text); return; }
      this.set(field.path,Number(text));
    } else if (field.kind === 'boolean') this.set(field.path,text === 'true');
    else if (field.kind === 'null') this.set(field.path,null);
    else this.set(field.path,text);
    this.invalid.delete(field.path);
  }
  errorPath(): string { return this.invalid.keys().next().value || ''; }
  add(path: string, key: string, kind: string): void {
    const array = this.kind(path) === 'array';
    const value = this.get(path);
    const name = array ? String(Array.isArray(value) ? value.length : 0) : key.trim();
    if (!name || !this.safe(name)) throw new Error('Invalid field name');
    const target = this.child(path,name);
    if (this.get(target) !== undefined) throw new Error('Field already exists');
    const next: NativeDraftValue = kind === 'object' ? {} : kind === 'array' ? [] : kind === 'number' ? 0 :
      kind === 'boolean' ? false : kind === 'null' ? null : '';
    this.set(target,next);
  }
  remove(field: NativeSourceField): void {
    if (field.readOnly) throw new Error('Read-only field');
    const parentPath = this.parent(field.path), parent = this.get(parentPath);
    if (Array.isArray(parent)) {
      const index = Number(field.key);
      parent.splice(index,1);
      for (const map of [this.ids,this.invalid]) {
        const remapped = new Map<string,string>();
        for (const [path,value] of map) {
          if (!path.startsWith(parentPath+'/')) { remapped.set(path,value); continue; }
          const suffix = path.slice(parentPath.length+1), slash = suffix.indexOf('/');
          const entry = Number(slash < 0 ? suffix : suffix.slice(0,slash));
          if (entry !== index) remapped.set(parentPath+'/'+(entry > index ? entry-1 : entry)+(slash<0?'':suffix.slice(slash)),value);
        }
        map.clear(); for (const [path,value] of remapped) map.set(path,value);
      }
    } else if (parent && typeof parent === 'object') {
      delete parent[field.key];
      for (const key of this.invalid.keys()) if (key === field.path || key.startsWith(field.path+'/')) this.invalid.delete(key);
    }
  }
  serialize(): string {
    if (this.invalid.size) throw new Error(this.errorPath());
    return JSON.stringify(this.root);
  }
}
