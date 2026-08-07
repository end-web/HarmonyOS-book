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
  /** 章节页 URL（用于解析音频时调 BookSourceService.getAudioUrl）。
   *  source.value 在播放期间会被解析后的真实音频 URL 覆盖，
   *  此字段保留原始章节页 URL，重启/续播时可以重新解析（避免临时签名链接过期）。 */
  originSourceValue?: string;
}

export interface Book {
  id: string;
  /** 内容类型：audio=有声书；text=旧版文本记录，仅用于升级过滤，不再提供阅读能力。 */
  contentType?: 'audio' | 'text';
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
  variables?: Record<string, string>;
  /** 跳过片头秒数（每本书独立设置） */
  skipIntro?: number;
  /** 跳过片尾秒数（每本书独立设置） */
  skipOutro?: number;
  /** 是否完结（源端 status=1；用于详情页"状态"展示） */
  completed?: boolean;
}
