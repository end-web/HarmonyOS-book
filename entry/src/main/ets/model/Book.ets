/**
 * 音频来源抽象
 * rawfile: 资源文件名（已不再使用，保留以便未来内置音频）
 * url: 网络流地址
 * file: 本地导入沙箱路径
 */
export interface AudioSource {
  type: 'rawfile' | 'url' | 'file';
  value: string;
}

export interface Chapter {
  id: string;
  index: number;
  title: string;
  duration: number;
  source: AudioSource;
}

export interface Book {
  id: string;
  title: string;
  author: string;
  narrator: string;
  cover: string;
  category: string;
  intro: string;
  totalDuration: number;
  chapterCount: number;
  rating: number;
  tags: string[];
  chapters: Chapter[];
  bookUrl: string;
  sourceUrl: string;
}
