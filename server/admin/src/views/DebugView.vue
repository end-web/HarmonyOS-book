<script setup lang="ts">
import { AlertTriangle, ExternalLink, LoaderCircle, Play, Search } from 'lucide-vue-next';
import { ref } from 'vue';
import { api, formatError } from '../api';
import type { Book, Chapter } from '../types';

const keyword = ref('Alice');
const books = ref<Book[]>([]);
const selectedBook = ref<Book | null>(null);
const chapters = ref<Chapter[]>([]);
const selectedChapter = ref<Chapter | null>(null);
const resolution = ref<{ url: string; format: string; expiresAt: number | null } | null>(null);
const loading = ref('');
const error = ref('');

async function search(): Promise<void> {
  if (!keyword.value.trim()) return;
  loading.value = 'search'; error.value = ''; selectedBook.value = null; chapters.value = []; resolution.value = null;
  try {
    const result = await api<{ items: Book[] }>('/api/admin/debug/search?q=' + encodeURIComponent(keyword.value.trim()));
    books.value = result.items;
  } catch (cause) { error.value = formatError(cause); }
  finally { loading.value = ''; }
}

async function openBook(book: Book): Promise<void> {
  selectedBook.value = book; selectedChapter.value = null; resolution.value = null; loading.value = 'chapters'; error.value = '';
  try {
    selectedBook.value = await api<Book>(`/api/v1/audio-books/${book.id}`);
    chapters.value = await api<Chapter[]>(`/api/v1/audio-books/${book.id}/chapters`);
  } catch (cause) { error.value = formatError(cause); }
  finally { loading.value = ''; }
}

async function resolve(chapter: Chapter): Promise<void> {
  selectedChapter.value = chapter; resolution.value = null; loading.value = 'resolve'; error.value = '';
  try {
    resolution.value = await api(`/api/v1/audio-chapters/${chapter.id}/resolve`, { method: 'POST' });
  } catch (cause) { error.value = formatError(cause); }
  finally { loading.value = ''; }
}
</script>

<template>
  <section class="view full-height-view">
    <header class="view-header"><div><p class="eyebrow">端到端验证</p><h1>搜索与播放链路</h1></div></header>
    <form class="debug-search" @submit.prevent="search">
      <Search :size="19" /><input v-model="keyword" type="search" placeholder="输入书名或作者" />
      <button class="primary-command compact" type="submit" :disabled="loading === 'search'">
        <LoaderCircle v-if="loading === 'search'" :size="18" class="spinning" /><Search v-else :size="18" />搜索</button>
    </form>
    <p v-if="error" class="inline-alert"><AlertTriangle :size="17" />{{ error }}</p>
    <div class="debug-grid">
      <section class="debug-pane"><header><h2>搜索结果</h2><span>{{ books.length }}</span></header>
        <button v-for="book in books" :key="book.id" type="button" :class="['result-row', { active: selectedBook?.id === book.id }]"
          @click="openBook(book)">
          <img :src="book.cover" alt="" /><span><strong>{{ book.title }}</strong><small>{{ book.author }} · {{ book.sourceName }}</small></span>
        </button>
        <p v-if="books.length === 0" class="pane-empty">尚无搜索结果</p>
      </section>
      <section class="debug-pane"><header><h2>章节目录</h2><span>{{ chapters.length }}</span></header>
        <div v-if="loading === 'chapters'" class="pane-loading"><LoaderCircle :size="20" class="spinning" />正在解析目录</div>
        <button v-for="chapter in chapters" :key="chapter.id" type="button"
          :class="['chapter-row', { active: selectedChapter?.id === chapter.id }]" @click="resolve(chapter)">
          <span class="mono">{{ String(chapter.index + 1).padStart(3, '0') }}</span><strong>{{ chapter.title }}</strong><Play :size="16" />
        </button>
        <p v-if="!selectedBook" class="pane-empty">选择一本书查看章节</p>
      </section>
      <section class="debug-pane resolution-pane"><header><h2>播放解析</h2><span>{{ resolution?.format || '—' }}</span></header>
        <div v-if="loading === 'resolve'" class="pane-loading"><LoaderCircle :size="20" class="spinning" />正在解析音频</div>
        <template v-else-if="resolution">
          <dl><dt>章节</dt><dd>{{ selectedChapter?.title }}</dd><dt>格式</dt><dd class="mono">{{ resolution.format }}</dd>
            <dt>有效期</dt><dd>{{ resolution.expiresAt ? new Date(resolution.expiresAt).toLocaleString('zh-CN') : '长期有效' }}</dd></dl>
          <a class="secondary-command" :href="resolution.url" target="_blank" rel="noreferrer"><ExternalLink :size="17" />检查音频地址</a>
        </template>
        <p v-else class="pane-empty">选择章节执行播放解析</p>
      </section>
    </div>
  </section>
</template>
