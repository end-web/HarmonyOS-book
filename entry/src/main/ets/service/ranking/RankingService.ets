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
      new RankingBoard('qd-month', 'qidian', $r('app.string.ranking_qidian'), $r('app.string.ranking_month'),
        'https://m.qidian.com/rank/yuepiao/'),
      new RankingBoard('lr-hot', 'lrts', $r('app.string.ranking_lrts'), $r('app.string.ranking_hot'),
        'https://www.lrts.me/rank/hot/week'),
      new RankingBoard('xm-free', 'ximalaya', $r('app.string.ranking_ximalaya'), $r('app.string.ranking_free'),
        'https://www.ximalaya.com/revision/rank/getRankList?rankType=freeAlbum&pageSize=50'),
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
        'https://www.jjwxc.net/topten.php?orderstr=5')
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
        board.books = books;
        board.fetchedAt = time;
        board.stale = Date.now() - time >= RankingService.TTL;
      }
    } catch (_error) { /* 损坏缓存回退网络。 */ }
    return board;
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
      next.books = books;
      next.fetchedAt = Date.now();
      await RankingStorage.write(context, board.id, JSON.stringify(new RankingCacheRecord(next.fetchedAt, response.body)));
    } catch (_error) {
      next.unavailable = next.books.length === 0;
      next.stale = next.books.length > 0;
    }
    return next;
  }
}
