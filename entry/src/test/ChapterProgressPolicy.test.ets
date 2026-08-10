import { describe, it, expect } from '@ohos/hypium';
import { ChapterProgressPolicy } from '../main/ets/service/ChapterProgressPolicy';

export default function chapterProgressPolicyTest() {
  describe('ChapterProgressPolicy', () => {
    it('restores a saved position in the effective playback range', 0, () => {
      expect(ChapterProgressPolicy.resolveResumePosition(90000, 300000, 0, 0)).assertEqual(90000);
      expect(ChapterProgressPolicy.resolveResumePosition(180000, 300000, 30000, 20000)).assertEqual(180000);
    });

    it('never resumes before or immediately after the skipped intro', 0, () => {
      expect(ChapterProgressPolicy.resolveResumePosition(20000, 300000, 30000, 0)).assertEqual(30000);
      expect(ChapterProgressPolicy.resolveResumePosition(34000, 300000, 30000, 0)).assertEqual(30000);
    });

    it('treats the end of the effective range as completed', 0, () => {
      expect(ChapterProgressPolicy.resolveResumePosition(275000, 300000, 30000, 20000)).assertEqual(30000);
      expect(ChapterProgressPolicy.resolveResumePosition(260000, 300000, 30000, 20000)).assertEqual(260000);
    });

    it('keeps a meaningful saved position when duration is not known yet', 0, () => {
      expect(ChapterProgressPolicy.resolveResumePosition(90000, 0, 15000, 20000)).assertEqual(90000);
    });
  });
}
