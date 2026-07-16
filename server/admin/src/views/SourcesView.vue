<script setup lang="ts">
import { Activity, AlertTriangle, CloudDownload, FileJson, Plus, RefreshCw, Search, Trash2, X } from 'lucide-vue-next';
import { onMounted, ref } from 'vue';
import { api, formatError } from '../api';
import HealthStrip from '../components/HealthStrip.vue';
import type { Source, SourceCatalog, SourceSyncSummary } from '../types';

const sources = ref<Source[]>([]);
const catalogs = ref<SourceCatalog[]>([]);
const loading = ref(false);
const syncingCatalogs = ref(false);
const error = ref('');
const notice = ref('');
const importOpen = ref(false);
const importMode = ref<'json' | 'url'>('json');
const content = ref('');
const remoteUrl = ref('');
const enableImported = ref(false);
const testKeyword = ref('');
const importing = ref(false);
const busyId = ref('');

async function load(): Promise<void> {
  loading.value = true;
  try { sources.value = await api<Source[]>('/api/admin/sources'); error.value = ''; }
  catch (cause) { error.value = formatError(cause); }
  finally { loading.value = false; }
}

async function loadCatalogs(): Promise<void> {
  try { catalogs.value = await api<SourceCatalog[]>('/api/admin/source-catalogs'); }
  catch (cause) { error.value = formatError(cause); }
}

async function refreshAll(): Promise<void> {
  await Promise.all([load(), loadCatalogs()]);
}

async function syncCatalogs(): Promise<void> {
  syncingCatalogs.value = true;
  notice.value = '';
  error.value = '';
  try {
    const result = await api<SourceSyncSummary>('/api/admin/source-catalogs/sync', { method: 'POST' });
    const ok = result.catalogs.filter((catalog) => catalog.ok).length;
    const audio = result.catalogs.reduce((sum, catalog) => sum + catalog.audio, 0);
    const enabled = result.catalogs.reduce((sum, catalog) => sum + catalog.enabled, 0);
    notice.value = `目录更新完成：${ok}/${result.catalogs.length} 个成功，筛出 ${audio} 个音频源，新启用 ${enabled} 个`;
    await refreshAll();
  } catch (cause) { error.value = formatError(cause); }
  finally { syncingCatalogs.value = false; }
}

async function update(source: Source, enabled: boolean): Promise<void> {
  busyId.value = source.id;
  try {
    await api(`/api/admin/sources/${source.id}`, { method: 'PATCH', body: JSON.stringify({ enabled }) });
    notice.value = enabled ? '来源已启用' : '来源已停用';
    await load();
  } catch (cause) { error.value = formatError(cause); }
  finally { busyId.value = ''; }
}

async function test(source: Source): Promise<void> {
  busyId.value = source.id;
  notice.value = '';
  try {
    const result = await api<{ ok: boolean; latencyMs: number; items: unknown[] }>(`/api/admin/sources/${source.id}/test`, {
      method: 'POST', body: JSON.stringify({ keyword: source.testKeyword || undefined })
    });
    notice.value = result.ok ? `检测通过 · ${result.latencyMs} ms · ${result.items.length} 条结果` : '检测失败';
    await load();
  } catch (cause) { error.value = formatError(cause); }
  finally { busyId.value = ''; }
}

async function remove(source: Source): Promise<void> {
  if (source.kind !== 'legado' || !window.confirm(`删除“${source.name}”？`)) return;
  busyId.value = source.id;
  try { await api(`/api/admin/sources/${source.id}`, { method: 'DELETE' }); await load(); }
  catch (cause) { error.value = formatError(cause); }
  finally { busyId.value = ''; }
}

async function importSources(): Promise<void> {
  importing.value = true;
  error.value = '';
  try {
    const body = importMode.value === 'json' ? { content: content.value, enabled: enableImported.value, testKeyword: testKeyword.value }
      : { url: remoteUrl.value, enabled: enableImported.value, testKeyword: testKeyword.value };
    const imported = await api<Source[]>('/api/admin/sources/import', { method: 'POST', body: JSON.stringify(body) });
    notice.value = `已导入 ${imported.length} 个音频源`;
    importOpen.value = false;
    content.value = '';
    remoteUrl.value = '';
    await load();
  } catch (cause) { error.value = formatError(cause); }
  finally { importing.value = false; }
}

function stateLabel(source: Source): string {
  return { healthy: '正常', degraded: '波动', down: '离线', unknown: '待检测' }[source.state];
}

function kindLabel(source: Source): string {
  return { legado: '阅读音频', guowei: '免费听书王 API', podcast: '开放播客', archive: '公版目录' }[source.kind];
}

function catalogStateLabel(catalog: SourceCatalog): string {
  return { idle: '待同步', running: '同步中', healthy: '正常', degraded: '失败' }[catalog.state];
}

function formatTime(value: string | null): string {
  return value ? new Date(value).toLocaleString('zh-CN', { hour12: false }) : '尚未同步';
}

onMounted(refreshAll);
</script>

<template>
  <section class="view">
    <header class="view-header">
      <div><p class="eyebrow">来源配置</p><h1>音频书源</h1></div>
      <div class="header-actions">
        <button class="icon-command" type="button" title="刷新列表" @click="refreshAll"><RefreshCw :size="19" /></button>
        <button class="secondary-command" type="button" :disabled="syncingCatalogs" @click="syncCatalogs">
          <CloudDownload :size="18" />{{ syncingCatalogs ? '更新中' : '更新网络目录' }}
        </button>
        <button class="primary-command compact" type="button" @click="importOpen = true"><Plus :size="18" />导入书源</button>
      </div>
    </header>
    <p v-if="error" class="inline-alert"><AlertTriangle :size="17" />{{ error }}</p>
    <p v-if="notice" class="inline-notice">{{ notice }}</p>
    <div class="section-heading">
      <div><h2>自动目录</h2><p>服务器启动后同步一次，并在每天 04:20（北京时间）自动更新。</p></div>
    </div>
    <div class="catalog-band">
      <article v-for="catalog in catalogs" :key="catalog.id" class="catalog-item">
        <div class="catalog-heading">
          <div><strong>{{ catalog.name }}</strong><a :href="catalog.pageUrl" target="_blank" rel="noreferrer">查看目录</a></div>
          <span :class="['status-label', catalog.state === 'healthy' ? 'state-healthy' : 'state-degraded']">
            {{ catalogStateLabel(catalog) }}
          </span>
        </div>
        <dl>
          <div><dt>发现</dt><dd>{{ catalog.lastTotal }}</dd></div>
          <div><dt>音频</dt><dd>{{ catalog.lastAudio }}</dd></div>
          <div><dt>变更</dt><dd>{{ catalog.lastChanged }}</dd></div>
        </dl>
        <small :title="catalog.lastErrorCode || ''">{{ catalog.lastErrorCode || formatTime(catalog.lastSuccessAt) }}</small>
      </article>
    </div>
    <div class="table-frame">
      <table class="source-table">
        <thead><tr><th>启用</th><th>来源</th><th>类型</th><th>状态</th><th>健康脉冲</th><th>累计成功 / 失败</th><th class="align-right">操作</th></tr></thead>
        <tbody>
          <tr v-for="source in sources" :key="source.id">
            <td><label class="switch-control"><input type="checkbox" :checked="source.enabled" :disabled="busyId === source.id"
              @change="update(source, ($event.target as HTMLInputElement).checked)" /><span /></label></td>
            <td><strong>{{ source.name }}</strong><small class="truncate-source" :title="source.sourceUrl">{{ source.sourceUrl }}</small></td>
            <td>{{ kindLabel(source) }}</td>
            <td><span :class="['status-label', `state-${source.state}`]">{{ stateLabel(source) }}</span></td>
            <td><HealthStrip :events="source.health" /></td>
            <td class="mono">{{ source.successCount }} / {{ source.failureCount }}</td>
            <td><div class="row-actions">
              <button class="icon-command small" type="button" title="检测来源" :disabled="busyId === source.id" @click="test(source)">
                <Activity :size="17" /></button>
              <button v-if="source.kind === 'legado'" class="icon-command small danger" type="button" title="删除来源"
                :disabled="busyId === source.id" @click="remove(source)"><Trash2 :size="17" /></button>
            </div></td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-if="importOpen" class="modal-backdrop" @click.self="importOpen = false">
      <section class="modal" role="dialog" aria-modal="true" aria-labelledby="import-title">
        <header><div><p class="eyebrow">仅接收 bookSourceType = 1</p><h2 id="import-title">导入阅读音频源</h2></div>
          <button class="icon-command" type="button" title="关闭" @click="importOpen = false"><X :size="19" /></button></header>
        <div class="segmented-control">
          <button type="button" :class="{ active: importMode === 'json' }" @click="importMode = 'json'"><FileJson :size="17" />JSON</button>
          <button type="button" :class="{ active: importMode === 'url' }" @click="importMode = 'url'"><Search :size="17" />远程地址</button>
        </div>
        <label v-if="importMode === 'json'" class="field-label">书源 JSON<textarea v-model="content" rows="12" spellcheck="false" /></label>
        <label v-else class="field-label">HTTPS 地址<input v-model="remoteUrl" type="url" placeholder="https://example.com/audio-sources.json" /></label>
        <div class="form-row">
          <label class="field-label">检测关键词<input v-model="testKeyword" type="text" placeholder="可稍后填写" /></label>
          <label class="checkbox-control"><input v-model="enableImported" type="checkbox" />导入后启用</label>
        </div>
        <footer><button class="secondary-command" type="button" @click="importOpen = false">取消</button>
          <button class="primary-command compact" type="button" :disabled="importing || (importMode === 'json' ? !content : !remoteUrl)"
            @click="importSources"><Plus :size="18" />{{ importing ? '导入中' : '导入' }}</button></footer>
      </section>
    </div>
  </section>
</template>
