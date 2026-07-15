<script setup lang="ts">
import { AlertTriangle, BookOpen, Gauge, RefreshCw, Server, Waves } from 'lucide-vue-next';
import { computed, onMounted, ref } from 'vue';
import { api, formatError } from '../api';
import HealthStrip from '../components/HealthStrip.vue';
import type { Source, Summary } from '../types';

const summary = ref<Summary | null>(null);
const loading = ref(false);
const error = ref('');

const availability = computed(() => {
  if (!summary.value || summary.value.sourceCount === 0) return '0%';
  return `${Math.round(summary.value.healthy / summary.value.sourceCount * 100)}%`;
});

async function load(): Promise<void> {
  loading.value = true;
  error.value = '';
  try { summary.value = await api<Summary>('/api/admin/summary'); }
  catch (cause) { error.value = formatError(cause); }
  finally { loading.value = false; }
}

function stateLabel(source: Source): string {
  return { healthy: '正常', degraded: '波动', down: '离线', unknown: '待检测' }[source.state];
}

function time(value: string | null): string {
  return value ? new Date(value).toLocaleString('zh-CN', { hour12: false }) : '尚无记录';
}

onMounted(load);
</script>

<template>
  <section class="view">
    <header class="view-header">
      <div><p class="eyebrow">运行状态</p><h1>聚合服务概览</h1></div>
      <button class="icon-command" type="button" title="刷新状态" :disabled="loading" @click="load">
        <RefreshCw :size="19" :class="{ spinning: loading }" />
      </button>
    </header>
    <p v-if="error" class="inline-alert"><AlertTriangle :size="17" />{{ error }}</p>
    <div v-if="summary" class="metric-band">
      <div><Server :size="18" /><span>解析引擎</span><strong :class="summary.engineReady ? 'text-ok' : 'text-fail'">
        {{ summary.engineReady ? '就绪' : '异常' }}</strong></div>
      <div><Gauge :size="18" /><span>来源健康率</span><strong>{{ availability }}</strong></div>
      <div><Waves :size="18" /><span>启用来源</span><strong>{{ summary.sourceCount }}</strong></div>
      <div><BookOpen :size="18" /><span>书籍 / 章节缓存</span><strong>{{ summary.cachedBooks }} / {{ summary.cachedChapters }}</strong></div>
    </div>
    <div class="section-heading"><div><h2>来源脉冲</h2><p>最近 24 次检测</p></div></div>
    <div class="table-frame">
      <table>
        <thead><tr><th>来源</th><th>状态</th><th>最近响应</th><th>健康脉冲</th><th>最后成功</th></tr></thead>
        <tbody>
          <tr v-for="source in summary?.sources || []" :key="source.id">
            <td><strong>{{ source.name }}</strong><small>{{ source.kind === 'legado' ? '阅读音频规则' : source.kind === 'podcast' ? '公开 RSS 目录' : '公版目录' }}</small></td>
            <td><span :class="['status-label', `state-${source.state}`]">{{ stateLabel(source) }}</span></td>
            <td class="mono">{{ source.lastLatencyMs === null ? '—' : `${source.lastLatencyMs} ms` }}</td>
            <td><HealthStrip :events="source.health" /></td>
            <td>{{ time(source.lastSuccessAt) }}</td>
          </tr>
          <tr v-if="summary && summary.sources.length === 0"><td colspan="5" class="empty-cell">没有启用的来源</td></tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
