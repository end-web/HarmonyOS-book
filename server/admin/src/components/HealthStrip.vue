<script setup lang="ts">
import type { HealthEvent } from '../types';

defineProps<{ events: HealthEvent[] }>();

function title(event: HealthEvent): string {
  const time = new Date(event.createdAt).toLocaleString('zh-CN', { hour12: false });
  return `${time} · ${event.ok ? '正常' : event.errorCode || '失败'} · ${event.latencyMs}ms`;
}
</script>

<template>
  <div class="health-strip" aria-label="最近健康记录">
    <span v-for="(event, index) in events" :key="`${event.createdAt}-${index}`"
      :class="['health-tick', event.ok ? 'is-ok' : 'is-fail']" :title="title(event)" />
    <span v-for="index in Math.max(0, 24 - events.length)" :key="`empty-${index}`" class="health-tick is-empty" />
  </div>
</template>
