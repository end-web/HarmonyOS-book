<script setup lang="ts">
import { RefreshCw } from 'lucide-vue-next';
import { onMounted, ref } from 'vue';
import { api } from '../api';
import type { AuditLog } from '../types';

const logs = ref<AuditLog[]>([]);
const loading = ref(false);

async function load(): Promise<void> {
  loading.value = true;
  try { logs.value = await api<AuditLog[]>('/api/admin/logs?limit=200'); }
  finally { loading.value = false; }
}

function actionName(action: string): string {
  const names: Record<string, string> = {
    'admin.login': '后台登录', 'admin.login_failed': '登录失败', 'source.import': '导入书源',
    'source.update': '更新书源', 'source.delete': '删除书源', 'source.test': '检测书源', 'cache.clear': '清理缓存'
  };
  return names[action] ?? action;
}

onMounted(load);
</script>

<template>
  <section class="view">
    <header class="view-header"><div><p class="eyebrow">审计记录</p><h1>操作日志</h1></div>
      <button class="icon-command" type="button" title="刷新日志" @click="load"><RefreshCw :size="19" :class="{ spinning: loading }" /></button></header>
    <div class="table-frame"><table><thead><tr><th>时间</th><th>操作</th><th>目标</th><th>结果</th></tr></thead>
      <tbody><tr v-for="log in logs" :key="log.id"><td class="mono">{{ new Date(log.createdAt).toLocaleString('zh-CN', { hour12: false }) }}</td>
        <td><strong>{{ actionName(log.action) }}</strong></td><td class="mono compact-text">{{ log.target }}</td><td>{{ log.detail }}</td></tr>
        <tr v-if="logs.length === 0"><td colspan="4" class="empty-cell">没有操作记录</td></tr></tbody></table></div>
  </section>
</template>
