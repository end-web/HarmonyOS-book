import { common } from '@kit.AbilityKit';
import { RankingBoard, RankingPlatform } from '../../model/Ranking';
import { HttpClient } from '../http/HttpClient';
import { JsonObj } from '../builtin/JsonValue';
import { RankingParser } from './RankingParser';
import { RankingStorage } from './RankingStorage';

class RankingCacheRecord {
  fetchedAt: number;
  body: string;
  constructor(fetchedAt: number, body: string) {
    this.fetchedAt = fetchedAt;
    this.body = body;
  }
}

export class RankingService {
  static readonly HOME_URL: string = 'home://rankings';
  /** 榜单详情页最多展示 99 项，超出部分不解析进内存也不落盘。 */
  static readonly MAX_BOOKS: number = 99;
  private static readonly TTL: number = 6 * 60 * 60 * 1000;
  private static pending: Map<string, Promise<RankingBoard>> = new Map<string, Promise<RankingBoard>>();

  static platforms(): RankingPlatform[] {
    return [new RankingPlatform('', $r('app.string.home_recommendations')),
      new RankingPlatform('qidian', $r('app.string.ranking_qidian')),
      new RankingPlatform('lrts', $r('app.string.ranking_lrts')),
      new RankingPlatform('ximalaya', $r('app.string.ranking_ximalaya')),
      new RankingPlatform('qimao', $r('app.string.ranking_qimao')),
      new RankingPlatform('jjwxc', $r('app.string.ranking_jjwxc'))];
  }

  static boards(): RankingBoard[] {
    return [
      new RankingBoard('lr-hot', 'lrts', $r('app.string.ranking_lrts'), $r('app.string.ranking_hot'),
        'https://www.lrts.me/rank/hot/week'),
      new RankingBoard('qd-month', 'qidian', $r('app.string.ranking_qidian'), $r('app.string.ranking_month'),
        'https://m.qidian.com/rank/yuepiao/'),
      new RankingBoard('xm-free', 'ximalaya', $r('app.string.ranking_ximalaya'), $r('app.string.ranking_free'),
        'https://www.ximalaya.com/revision/rank/getRankList?rankType=freeAlbum&pageSize=50'),
      new RankingBoard('qd-finished', 'qidian', $r('app.string.ranking_qidian'), $r('app.string.ranking_finished'),
        'https://m.qidian.com/bestsell/'),
      new RankingBoard('qd-reading', 'qidian', $r('app.string.ranking_qidian'), $r('app.string.ranking_reading'),
        'https://m.qidian.com/rank/readindex/'),
      new RankingBoard('qd-recommend', 'qidian', $r('app.string.ranking_qidian'), $r('app.string.ranking_recommend'),
        'https://m.qidian.com/rank/rec/'),
      new RankingBoard('qd-new', 'qidian', $r('app.string.ranking_qidian'), $r('app.string.ranking_new'),
        'https://m.qidian.com/rank/newbook/'),
      new RankingBoard('qd-sales', 'qidian', $r('app.string.ranking_qidian'), $r('app.string.ranking_sales'),
        'https://m.qidian.com/rank/hotsales/'),
      new RankingBoard('lr-comment', 'lrts', $r('app.string.ranking_lrts'), $r('app.string.ranking_comment'),
        'https://www.lrts.me/rank/comment/week'),
      new RankingBoard('xm-paid', 'ximalaya', $r('app.string.ranking_ximalaya'), $r('app.string.ranking_paid'),
        'https://www.ximalaya.com/revision/rank/getRankList?rankType=paidAlbum&pageSize=50'),
      new RankingBoard('qm-boy', 'qimao', $r('app.string.ranking_qimao'), $r('app.string.ranking_boy_hot'),
        'https://www.qimao.com/paihang/boy/hot/'),
      new RankingBoard('qm-girl', 'qimao', $r('app.string.ranking_qimao'), $r('app.string.ranking_girl_hot'),
        'https://www.qimao.com/paihang/girl/hot/'),
      new RankingBoard('jj-total', 'jjwxc', $r('app.string.ranking_jjwxc'), $r('app.string.ranking_total_points'),
        'https://www.jjwxc.net/topten.php?orderstr=7'),
      new RankingBoard('jj-month', 'jjwxc', $r('app.string.ranking_jjwxc'), $r('app.string.ranking_monthly'),
        'https://www.jjwxc.net/topten.php?orderstr=5'),
      new RankingBoard('lr-search', 'lrts', $r('app.string.ranking_lrts'), $r('app.string.ranking_search_week'),
        'https://www.lrts.me/rank/search/week'),
      new RankingBoard('lr-free', 'lrts', $r('app.string.ranking_lrts'), $r('app.string.ranking_free_week'),
        'https://www.lrts.me/rank/down/week'),
      new RankingBoard('lr-sales', 'lrts', $r('app.string.ranking_lrts'), $r('app.string.ranking_sales_week'),
        'https://www.lrts.me/rank/male/week'),
      new RankingBoard('lr-finished', 'lrts', $r('app.string.ranking_lrts'), $r('app.string.ranking_finished_week'),
        'https://www.lrts.me/rank/female/week'),
      new RankingBoard('xm-hot', 'ximalaya', $r('app.string.ranking_ximalaya'), $r('app.string.ranking_audio_hot'),
        'https://www.ximalaya.com/revision/rank/v3/element?typeId=12&clusterId=52&pageNum=1&pageSize=30'),
      new RankingBoard('xm-new', 'ximalaya', $r('app.string.ranking_ximalaya'), $r('app.string.ranking_audio_new'),
        'https://www.ximalaya.com/revision/rank/v3/element?typeId=14&clusterId=70&pageNum=1&pageSize=30'),
      new RankingBoard('xm-reputation', 'ximalaya', $r('app.string.ranking_ximalaya'), $r('app.string.ranking_audio_reputation'),
        'https://www.ximalaya.com/revision/rank/v3/element?typeId=15&clusterId=394&pageNum=1&pageSize=30'),
      new RankingBoard('xm-vip', 'ximalaya', $r('app.string.ranking_ximalaya'), $r('app.string.ranking_novel_vip'),
        'https://www.ximalaya.com/revision/rank/v3/element?typeId=25&clusterId=362&pageNum=1&pageSize=30'),
      new RankingBoard('qm-boy-new', 'qimao', $r('app.string.ranking_qimao'), $r('app.string.ranking_boy_new'),
        'https://www.qimao.com/paihang/boy/new/date/'),
      new RankingBoard('qm-girl-new', 'qimao', $r('app.string.ranking_qimao'), $r('app.string.ranking_girl_new'),
        'https://www.qimao.com/paihang/girl/new/date/'),
      new RankingBoard('qm-boy-finished', 'qimao', $r('app.string.ranking_qimao'), $r('app.string.ranking_boy_finished'),
        'https://www.qimao.com/paihang/boy/over/date/'),
      new RankingBoard('qm-girl-finished', 'qimao', $r('app.string.ranking_qimao'), $r('app.string.ranking_girl_finished'),
        'https://www.qimao.com/paihang/girl/over/date/'),
      new RankingBoard('jj-season', 'jjwxc', $r('app.string.ranking_jjwxc'), $r('app.string.ranking_season'),
        'https://www.jjwxc.net/topten.php?orderstr=4'),
      new RankingBoard('jj-half-year', 'jjwxc', $r('app.string.ranking_jjwxc'), $r('app.string.ranking_half_year'),
        'https://www.jjwxc.net/topten.php?orderstr=6'),
      new RankingBoard('jj-vip', 'jjwxc', $r('app.string.ranking_jjwxc'), $r('app.string.ranking_vip_recommend'),
        'https://www.jjwxc.net/topten.php?orderstr=2'),
      new RankingBoard('jj-words', 'jjwxc', $r('app.string.ranking_jjwxc'), $r('app.string.ranking_words'),
        'https://www.jjwxc.net/topten.php?orderstr=8')
    ];
  }

  static async cached(context: common.Context, board: RankingBoard): Promise<RankingBoard> {
    try {
      const text = await RankingStorage.read(context, board.id);
      if (!text) return board;
      const record = new JsonObj(JSON.parse(text));
      const time = record.getInt('fetchedAt');
      if (time <= 0 || time > Date.now() + 60000 || Date.now() - time > 30 * 86400000) return board;
      const books = RankingParser.parse(board.platformId, board.id, record.getString('body'));
      if (books.length > 0) {
        board.books = books.slice(0, RankingService.MAX_BOOKS);
        board.fetchedAt = time;
        board.stale = Date.now() - time >= RankingService.TTL;
      }
    } catch (_error) { /* 损坏缓存回退网络。 */ }
    return board;
  }

  /** 首屏先读先显；缓存解析与联网均不等待其余全部榜单完成。 */
  static async loadProgressively(context: common.Context, boards: RankingBoard[], force: boolean,
    onUpdate: (board: RankingBoard) => void, isCurrent: () => boolean): Promise<void> {
    let cursor = 0;
    const worker = async (): Promise<void> => {
      while (isCurrent() && cursor < boards.length) {
        let board = boards[cursor++];
        if (board.books.length === 0) {
          board = await RankingService.cached(context, board);
          if (!isCurrent()) return;
          if (board.books.length > 0) onUpdate(board);
        }
        if (!isCurrent()) return;
        const loaded = await RankingService.load(context, board, force);
        if (!isCurrent()) return;
        if (loaded !== board || board.books.length === 0) onUpdate(loaded);
      }
    };
    await Promise.all([worker(), worker(), worker()]);
  }

  static async load(context: common.Context, board: RankingBoard, force: boolean): Promise<RankingBoard> {
    if (!force && board.books.length > 0 && !board.stale) return board;
    const running = RankingService.pending.get(board.id);
    if (running !== undefined) return running;
    const task = RankingService.fetch(context, board).finally((): void => {
      RankingService.pending.delete(board.id);
    });
    RankingService.pending.set(board.id, task);
    return task;
  }

  private static async fetch(context: common.Context, board: RankingBoard): Promise<RankingBoard> {
    const next = new RankingBoard(board.id, board.platformId, board.platformName, board.title, board.endpoint);
    next.books = board.books;
    next.fetchedAt = board.fetchedAt;
    try {
      const response = await HttpClient.request(board.endpoint, { timeout: 12000 });
      if (response.statusCode !== 200) throw new Error(`Ranking HTTP ${response.statusCode}`);
      const books = RankingParser.parse(board.platformId, board.id, response.body);
      if (books.length === 0) throw new Error('Ranking page changed or empty');
      next.books = books.slice(0, RankingService.MAX_BOOKS);
      next.fetchedAt = Date.now();
      await RankingStorage.write(context, board.id, JSON.stringify(new RankingCacheRecord(next.fetchedAt, response.body)));
    } catch (_error) {
      next.unavailable = next.books.length === 0;
      next.stale = next.books.length > 0;
    }
    return next;
  }
}
