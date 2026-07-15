import { defineStore } from 'pinia';
import { api } from '../api';

export const useAuthStore = defineStore('auth', {
  state: () => ({ authenticated: false, checked: false }),
  actions: {
    async check(): Promise<boolean> {
      try {
        const result = await api<{ authenticated: boolean }>('/api/admin/session');
        this.authenticated = result.authenticated;
      } catch {
        this.authenticated = false;
      }
      this.checked = true;
      return this.authenticated;
    },
    async login(password: string): Promise<void> {
      await api('/api/admin/session', { method: 'POST', body: JSON.stringify({ password }) });
      this.authenticated = true;
      this.checked = true;
    },
    async logout(): Promise<void> {
      await api('/api/admin/session', { method: 'DELETE' });
      this.authenticated = false;
    }
  }
});
