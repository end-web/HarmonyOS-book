import { describe, expect, it } from '@ohos/hypium';
import { RuleSourceLoginRouteParams } from '../main/ets/model/RuleSourceLogin';
import { RuleSourceChild } from '../main/ets/model/RuleSourceChild';
import { RuleSourceChildService } from '../main/ets/service/rulesource/RuleSourceChildService';

export default function ruleSourceChildServiceTest() {
  describe('RuleSourceChildService', () => {
    it('marks aggregate account routes separately from child login routes', 0, () => {
      const accountRoute = RuleSourceLoginRouteParams.forMainAccount(
        '光遇聚合', '光遇聚合', 'https://v1.gyks.cf/register');
      const childRoute = RuleSourceLoginRouteParams.of(
        '光遇聚合', 'QQ阅读', 'https://book.qq.com/');
      expect(accountRoute.isMainAccount).assertTrue();
      expect(childRoute.isMainAccount).assertFalse();
      expect(accountRoute.isValid()).assertTrue();
    });

    it('exposes stable child catalogs only for native aggregate sources', 0, () => {
      expect(RuleSourceChildService.supports('光遇聚合')).assertTrue();
      expect(RuleSourceChildService.supports('书山聚合')).assertTrue();
      expect(RuleSourceChildService.supports('https://example.com/source')).assertFalse();

      const guangYu = RuleSourceChildService.catalog('光遇聚合');
      const shuShan = RuleSourceChildService.catalog('书山聚合');
      expect(guangYu.length >= 10).assertTrue();
      expect(shuShan.length >= 40).assertTrue();
      expect(RuleSourceChildService.catalog('https://example.com/source').length).assertEqual(0);
    });

    it('keeps child ids unique across text and audio providers', 0, () => {
      const children = RuleSourceChildService.catalog('书山聚合');
      const ids = new Set<string>();
      for (const child of children) ids.add(child.id);
      expect(ids.size).assertEqual(children.length);
    });

    it('maps vip children to their own allowlisted provider login pages', 0, () => {
      const children = RuleSourceChildService.catalog('光遇聚合');
      let qqSource: RuleSourceChild | undefined = undefined;
      let shuQiSource: RuleSourceChild | undefined = undefined;
      let kuWoSource: RuleSourceChild | undefined = undefined;
      let unmappedSource: RuleSourceChild | undefined = undefined;
      for (const child of children) {
        if (child.name === 'svip_QQ阅读') qqSource = child;
        if (child.name === 'svip_书旗') shuQiSource = child;
        if (child.name === 'svip_酷我') kuWoSource = child;
        if (child.name === '有声库') unmappedSource = child;
      }
      expect(qqSource !== undefined).assertTrue();
      expect(shuQiSource !== undefined).assertTrue();
      expect(kuWoSource !== undefined).assertTrue();
      expect(unmappedSource !== undefined).assertTrue();
      if (qqSource !== undefined && shuQiSource !== undefined && kuWoSource !== undefined &&
        unmappedSource !== undefined) {
        expect(qqSource.loginUrl).assertEqual('https://book.qq.com/');
        expect(shuQiSource.loginUrl).assertEqual('https://www.shuqi.com/login');
        expect(kuWoSource.loginUrl).assertEqual('https://www.kuwo.cn/');
        expect(RuleSourceChildService.isAllowedLoginUrl(qqSource.loginUrl)).assertTrue();
        expect(RuleSourceChildService.isAllowedLoginUrl(shuQiSource.loginUrl)).assertTrue();
        expect(RuleSourceChildService.isAllowedLoginUrl(kuWoSource.loginUrl)).assertTrue();
        expect(unmappedSource.canOpenLogin()).assertFalse();
      }
      expect(RuleSourceChildService.isAllowedLoginUrl('https://v1.gyks.cf/register')).assertFalse();
      expect(RuleSourceChildService.isAllowedLoginUrl('https://v1.vossc.com/user_login')).assertFalse();
      expect(RuleSourceChildService.isAllowedLoginUrl('https://example.com/login')).assertFalse();
    });

    it('uses official child sites instead of the ShuShan aggregate account', 0, () => {
      const children = RuleSourceChildService.catalog('书山聚合');
      let jinJiangSource: RuleSourceChild | undefined = undefined;
      let xiMaLaYaSource: RuleSourceChild | undefined = undefined;
      let publicSource: RuleSourceChild | undefined = undefined;
      for (const child of children) {
        if (child.name === '晋江') jinJiangSource = child;
        if (child.name === '喜马拉雅') xiMaLaYaSource = child;
        if (child.name === '69书吧') publicSource = child;
      }
      expect(jinJiangSource !== undefined).assertTrue();
      expect(xiMaLaYaSource !== undefined).assertTrue();
      expect(publicSource !== undefined).assertTrue();
      if (jinJiangSource !== undefined && xiMaLaYaSource !== undefined &&
        publicSource !== undefined) {
        expect(jinJiangSource.loginUrl).assertEqual('https://my.jjwxc.net/login.php');
        expect(xiMaLaYaSource.loginUrl).assertEqual('https://www.ximalaya.com/');
        expect(publicSource.canOpenLogin()).assertFalse();
      }
    });
  });
}
