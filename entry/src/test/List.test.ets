import localUnitTest from './LocalUnit.test';
import downloadPolicyTest from './DownloadPolicy.test';

export default function testsuite() {
  localUnitTest();
  downloadPolicyTest();
}
