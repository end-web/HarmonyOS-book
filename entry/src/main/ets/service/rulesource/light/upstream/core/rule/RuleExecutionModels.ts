import { Book, BookChapter, BookSource } from '../../model/data/Book';
import { RuleValue } from './RuleValue';
import { BookSourceDebugContext } from '../book/BookSourceDebugModels';

export class RuleExecutionPriority {
  static readonly BACKGROUND: number = 0;
  static readonly PRELOAD: number = 1;
  static readonly VISIBLE: number = 2;
  static readonly INTERACTIVE: number = 3;
}

export class RuleFieldRequest {
  name: string = '';
  rule: string = '';
  resolveUrl: boolean = false;
  listResult: boolean = false;
  joinMatches: boolean = false;

  constructor(name: string = '', rule: string = '', resolveUrl: boolean = false,
    listResult: boolean = false, joinMatches: boolean = false) {
    this.name = name;
    this.rule = rule;
    this.resolveUrl = resolveUrl;
    this.listResult = listResult;
    this.joinMatches = joinMatches;
  }
}

export class RuleBatchExecutionRequest {
  source: BookSource = new BookSource();
  book: Book | null = null;
  chapter: BookChapter | null = null;
  stage: string = '';
  ownerId: string = '';
  /** Preferred typed input. contents remains available for legacy call sites and display fallbacks. */
  typedContents: RuleValue[] = [];
  contents: string[] = [];
  baseUrl: string = '';
  fields: RuleFieldRequest[] = [];
  contextValues: Record<string, string> = {};
  priority: number = RuleExecutionPriority.VISIBLE;
  timeoutMs: number = 15000;
  uiSliceMs: number = 6;
  itemChunkSize: number = 16;
  readerActionMode: boolean = false;
  debugContext: BookSourceDebugContext | null = null;
}

export class RuleBatchExecutionResult {
  values: Record<string, string>[] = [];
  contextValues: string[] = [];
  errors: string[] = [];
  elapsedMs: number = 0;
  yieldedCount: number = 0;
  cancelled: boolean = false;
}
