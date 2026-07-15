import { createRouter, createWebHistory } from 'vue-router';
import { useAuthStore } from './stores/auth';
import AppShell from './components/AppShell.vue';
import LoginView from './views/LoginView.vue';
import DashboardView from './views/DashboardView.vue';
import SourcesView from './views/SourcesView.vue';
import DebugView from './views/DebugView.vue';
import LogsView from './views/LogsView.vue';

export const router = createRouter({
  history: createWebHistory('/admin/'),
  routes: [
    { path: '/login', name: 'login', component: LoginView, meta: { public: true } },
    {
      path: '/',
      component: AppShell,
      children: [
        { path: '', name: 'dashboard', component: DashboardView },
        { path: 'sources', name: 'sources', component: SourcesView },
        { path: 'debug', name: 'debug', component: DebugView },
        { path: 'logs', name: 'logs', component: LogsView }
      ]
    }
  ]
});

router.beforeEach(async (to) => {
  const auth = useAuthStore();
  if (!auth.checked) await auth.check();
  if (!to.meta.public && !auth.authenticated) return { name: 'login' };
  if (to.name === 'login' && auth.authenticated) return { name: 'dashboard' };
  return true;
});
