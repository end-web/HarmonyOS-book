<script setup lang="ts">
import { LockKeyhole, LogIn } from 'lucide-vue-next';
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { formatError } from '../api';
import { useAuthStore } from '../stores/auth';

const password = ref('');
const loading = ref(false);
const error = ref('');
const auth = useAuthStore();
const router = useRouter();

async function submit(): Promise<void> {
  if (!password.value || loading.value) return;
  loading.value = true;
  error.value = '';
  try {
    await auth.login(password.value);
    await router.replace({ name: 'dashboard' });
  } catch (cause) {
    error.value = formatError(cause);
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <main class="login-page">
    <section class="login-panel" aria-labelledby="login-title">
      <div class="login-identity">
        <span class="brand-mark large">简</span>
        <div><h1 id="login-title">简·欢</h1><p>源控制台</p></div>
      </div>
      <form @submit.prevent="submit">
        <label for="password">管理密码</label>
        <div class="input-with-icon"><LockKeyhole :size="18" /><input id="password" v-model="password"
          type="password" autocomplete="current-password" autofocus /></div>
        <p v-if="error" class="form-error" role="alert">{{ error }}</p>
        <button class="primary-command" type="submit" :disabled="loading || !password">
          <LogIn :size="18" />{{ loading ? '登录中' : '登录' }}
        </button>
      </form>
    </section>
  </main>
</template>
