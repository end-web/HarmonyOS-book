import localUnitTest from './LocalUnit.test';
import downloadPolicyTest from './DownloadPolicy.test';
import asyncSingleFlightTest from './AsyncSingleFlight.test';
import builtInAudioCapabilityTest from './BuiltInAudioCapability.test';
import tingYouRequestPolicyTest from './TingYouRequestPolicy.test';
import searchCacheTest from './SearchCache.test';
import listeningHistoryPolicyTest from './ListeningHistoryPolicy.test';
import chapterProgressPolicyTest from './ChapterProgressPolicy.test';

export default function testsuite() {
  localUnitTest();
  downloadPolicyTest();
  asyncSingleFlightTest();
  builtInAudioCapabilityTest();
  tingYouRequestPolicyTest();
  searchCacheTest();
  listeningHistoryPolicyTest();
  chapterProgressPolicyTest();
}
