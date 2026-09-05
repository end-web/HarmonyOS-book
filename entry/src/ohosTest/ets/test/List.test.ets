import abilityTest from './Ability.test';
import shuShanContentCryptoTest from './ShuShanContentCrypto.test';
import localRuleFeaturesTest from '../../../test/LocalRuleFeatures.test';
import localRuleRequestLimiterTest from '../../../test/LocalRuleRequestLimiter.test';
import localRuleCompatibilityTest from '../../../test/LocalRuleCompatibility.test';
import localRuleRuntimeTest from '../../../test/LocalRuleRuntime.test';
import localRulePersistenceTest from './LocalRulePersistence.test';
import localRuleBrowserIntegrationTest from './LocalRuleBrowserIntegration.test';
import sourcePlaybackSmokeTest from './SourcePlaybackSmoke.test';

export default function testsuite() {
  abilityTest();
  shuShanContentCryptoTest();
  localRuleFeaturesTest();
  localRuleRequestLimiterTest();
  localRuleCompatibilityTest();
  localRuleRuntimeTest();
  localRulePersistenceTest();
  localRuleBrowserIntegrationTest();
  sourcePlaybackSmokeTest();
}
