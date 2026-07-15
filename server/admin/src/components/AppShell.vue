<script setup lang="ts">
import { Activity, Database, FileClock, LogOut, RadioTower } from 'lucide-vue-next';
import { useRouter } from 'vue-router';
import { useAuthStore } from '../stores/auth';

const router = useRouter();
const auth = useAuthStore();

async function logout(): Promise<void> {
  await auth.logout();
  await router.replace({ name: 'login' });
}
</script>

<template>
  <div class="app-frame">
    <aside class="sidebar">
      <div class="brand-block">
        <span class="brand-mark">简</span>
        <div><strong>简·欢</strong><small>源控制台</small></div>
      </div>
      <nav class="primary-nav" aria-label="主导航">
        <RouterLink :to="{ name: 'dashboard' }"><Activity :size="18" />运行概览</RouterLink>
        <RouterLink :to="{ name: 'sources' }"><RadioTower :size="18" />书源管理</RouterLink>
        <RouterLink :to="{ name: 'debug' }"><Database :size="18" />链路调试</RouterLink>
        <RouterLink :to="{ name: 'logs' }"><FileClock :size="18" />操作记录</RouterLink>
      </nav>
      <button class="sidebar-action" type="button" title="退出后台" @click="logout">
        <LogOut :size="18" /><span>退出</span>
      </button>
    </aside>
    <main class="workspace">
      <RouterView />
    </main>
  </div>
</template>
