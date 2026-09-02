import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { PreferenceService } from '../main/ets/service/PreferenceService';

export default function searchHistoryTest() {
  describe('SearchHistoryTest', () => {
    let preferenceService: PreferenceService;

    beforeAll(async () => {
      console.info('SearchHistoryTest: beforeAll called');
    });

    beforeEach(async () => {
      preferenceService = PreferenceService.getInstance();
      await preferenceService.clearSearchHistory();
    });

    afterEach(async () => {
      await preferenceService.clearSearchHistory();
    });

    afterAll(() => {
      console.info('SearchHistoryTest: afterAll called');
    });

    /**
     * @tc.number: SearchHistory_AddKeyword_001
     * @tc.name: testAddSearchKeyword
     * @tc.desc: 测试添加搜索关键词
     */
    it('testAddSearchKeyword', 0, async () => {
      await preferenceService.addSearchHistory('测试关键词');
      const history = await preferenceService.getSearchHistory();

      expect(history.length).assertEqual(1);
      expect(history[0]).assertEqual('测试关键词');
    });

    /**
     * @tc.number: SearchHistory_AddMultiple_002
     * @tc.name: testAddMultipleKeywords
     * @tc.desc: 测试添加多个搜索关键词
     */
    it('testAddMultipleKeywords', 0, async () => {
      await preferenceService.addSearchHistory('关键词1');
      await preferenceService.addSearchHistory('关键词2');
      await preferenceService.addSearchHistory('关键词3');

      const history = await preferenceService.getSearchHistory();

      expect(history.length).assertEqual(3);
      expect(history[0]).assertEqual('关键词3'); // 最新的在前
      expect(history[1]).assertEqual('关键词2');
      expect(history[2]).assertEqual('关键词1');
    });

    /**
     * @tc.number: SearchHistory_Duplicate_003
     * @tc.name: testDuplicateKeyword
     * @tc.desc: 测试重复关键词会移到最前
     */
    it('testDuplicateKeyword', 0, async () => {
      await preferenceService.addSearchHistory('关键词1');
      await preferenceService.addSearchHistory('关键词2');
      await preferenceService.addSearchHistory('关键词1'); // 重复

      const history = await preferenceService.getSearchHistory();

      expect(history.length).assertEqual(2);
      expect(history[0]).assertEqual('关键词1'); // 移到最前
      expect(history[1]).assertEqual('关键词2');
    });

    /**
     * @tc.number: SearchHistory_MaxLimit_004
     * @tc.name: testMaxHistoryLimit
     * @tc.desc: 测试最多保存10条历史
     */
    it('testMaxHistoryLimit', 0, async () => {
      for (let i = 1; i <= 12; i++) {
        await preferenceService.addSearchHistory(`关键词${i}`);
      }

      const history = await preferenceService.getSearchHistory();

      expect(history.length).assertEqual(10);
      expect(history[0]).assertEqual('关键词12'); // 最新的
      expect(history[9]).assertEqual('关键词3');  // 最早的两条被删除
    });

    /**
     * @tc.number: SearchHistory_Remove_005
     * @tc.name: testRemoveKeyword
     * @tc.desc: 测试删除单个关键词
     */
    it('testRemoveKeyword', 0, async () => {
      await preferenceService.addSearchHistory('关键词1');
      await preferenceService.addSearchHistory('关键词2');
      await preferenceService.addSearchHistory('关键词3');

      await preferenceService.removeSearchHistory('关键词2');
      const history = await preferenceService.getSearchHistory();

      expect(history.length).assertEqual(2);
      expect(history[0]).assertEqual('关键词3');
      expect(history[1]).assertEqual('关键词1');
    });

    /**
     * @tc.number: SearchHistory_Clear_006
     * @tc.name: testClearHistory
     * @tc.desc: 测试清空历史
     */
    it('testClearHistory', 0, async () => {
      await preferenceService.addSearchHistory('关键词1');
      await preferenceService.addSearchHistory('关键词2');

      await preferenceService.clearSearchHistory();
      const history = await preferenceService.getSearchHistory();

      expect(history.length).assertEqual(0);
    });

    /**
     * @tc.number: SearchHistory_EmptyKeyword_007
     * @tc.name: testEmptyKeyword
     * @tc.desc: 测试空关键词不会被添加
     */
    it('testEmptyKeyword', 0, async () => {
      await preferenceService.addSearchHistory('');
      await preferenceService.addSearchHistory('  ');

      const history = await preferenceService.getSearchHistory();

      expect(history.length).assertEqual(0);
    });
  });
}
