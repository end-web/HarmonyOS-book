import { MEDALS, MedalAward, MedalDefinition } from '../model/Medal';
import { MedalService } from '../service/MedalService';
import { AuthService } from '../service/AuthService';
import { ProfileMenuDestination } from '../components/ProfileMenuDestination';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct AchievementPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local auth: AuthService = AuthService.instance;
  @Local medalService: MedalService = MedalService.instance;
  @Local medalBusy: boolean = false;
  private readonly medals: MedalDefinition[] = MEDALS;

  private async loadMedals(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.medalBusy) return;
    this.medalBusy = true;
    try {
      await this.medalService.init(context);
      await this.medalService.refreshUnlocks(true);
    } catch (_error) {
      this.toast($r('app.string.medal_load_failed'));
    } finally {
      this.medalBusy = false;
    }
  }

  private async chooseMedal(item: MedalDefinition): Promise<void> {
    if (!this.auth.isLoggedIn || !this.medalService.ready || this.medalBusy) return;
    const unlocked = this.medalService.isUnlocked(item.id);
    const wearing = this.medalService.selectedMedalId === item.id;
    const award = this.medalService.awards.find((value: MedalAward): boolean => value.medalId === item.id);
    let message: ResourceStr = $r('app.string.account_national_day_medal_date');
    if (item.hours > 0) {
      if (!unlocked) {
        const minutes = Math.max(1, Math.ceil((item.hours * 3600 - this.medalService.totalSeconds) / 60));
        message = $r('app.string.medal_remaining', item.hours, Math.floor(minutes / 60), minutes % 60);
      } else if (award?.historical) {
        message = $r('app.string.medal_historical', item.hours);
      } else if (award !== undefined) {
        const date = new Date(award.unlockedAt);
        message = $r('app.string.medal_awarded_date', item.hours,
          `${date.getFullYear()}.${String(date.getMonth() + 1).padStart(2, '0')}.${String(date.getDate()).padStart(2, '0')}`);
      }
    }
    this.medalBusy = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: item.name,
        message,
        buttons: unlocked ? [
          { text: $r('app.string.medal_close'), color: $r('sys.color.font_secondary') },
          { text: wearing ? $r('app.string.medal_unequip') : $r('app.string.medal_equip'), color: AppColor.Brand }
        ] : [{ text: $r('app.string.medal_close'), color: AppColor.Brand }]
      });
      if (unlocked && result.index === 1 && this.auth.isLoggedIn) {
        await this.medalService.equipMedal(wearing ? '' : item.id);
        this.toast(wearing ? $r('app.string.medal_unequipped') : $r('app.string.medal_equipped'));
      }
    } catch (_error) {
      this.toast($r('app.string.medal_save_failed'));
    } finally {
      this.medalBusy = false;
    }
  }

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context) this.auth.restore(context);
    this.loadMedals();
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  build() {
    ProfileMenuDestination({ pageBackground: $r('sys.color.background_secondary') }) {
      Column() {
        Row({ space: AppSpace.Sm }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
            .width(44)
            .height(44)
            .onClick(() => this.navStack.pop())
            .accessibilityText($r('app.string.account_back'))
          Text($r('app.string.achievement_title'))
            .fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
        }
        .width('100%')
        .padding({ top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
          left: AppSpace.Sm, right: AppSpace.Md, bottom: AppSpace.Sm })

        Scroll() {
          Column({ space: AppSpace.Lg }) {
            if (this.auth.isLoggedIn) {
              this.medalCard()
            } else {
              Column({ space: AppSpace.Md }) {
                Text($r('app.string.achievement_login_hint'))
                  .fontSize(AppFont.Body)
                  .fontColor($r('sys.color.font_secondary'))
                Button($r('app.string.hw_auth_login_title'))
                  .fontColor(Color.White)
                  .backgroundColor(AppColor.Brand)
                  .enabled(!this.auth.logging && !this.auth.restoring)
                  .onClick(() => this.navStack.pushPathByName('account', ''))
              }
              .width('100%')
              .padding(AppSpace.Lg)
              .backgroundColor($r('sys.color.comp_background_primary'))
              .borderRadius(AppRadius.Lg)
            }
          }
          .width('100%')
          .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Sm,
            bottom: WindowUtils.getBottomSafeVp() + AppSpace.Xl })
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_secondary'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }

  @Builder
  medalCard() {
    Column({ space: AppSpace.Md }) {
      Text($r('app.string.account_medal_list'))
        .fontSize(AppFont.BodyL)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
      if (this.medalService.failed) {
        Button($r('app.string.medal_load_failed'))
          .fontColor(AppColor.Brand)
          .backgroundColor(Color.Transparent)
          .enabled(!this.medalBusy)
          .onClick(() => this.loadMedals())
      }
      if (this.medalService.ready) {
        Text($r('app.string.medal_summary', this.medalService.awards.length, this.medals.length,
          (Math.floor(this.medalService.totalSeconds / 360) / 10).toFixed(1)))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
        if (this.medalService.newAwardCount > 0) {
          Text($r('app.string.medal_new_awards', this.medalService.newAwardCount))
            .fontSize(AppFont.Caption)
            .fontColor(AppColor.Brand)
        }
        Grid() {
          ForEach(this.medals, (item: MedalDefinition) => {
            GridItem() {
              Column({ space: 4 }) {
                Image(item.image)
                  .width(64)
                  .height(64)
                  .objectFit(ImageFit.Contain)
                  .interpolation(ImageInterpolation.Medium)
                  .grayscale(this.medalService.isUnlocked(item.id) ? 0 : 1)
                  .opacity(this.medalService.isUnlocked(item.id) ? 1 : 0.4)
                  .accessibilityText(item.name)
                Text(item.name)
                  .fontSize(AppFont.Caption)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.hours === 0 ? $r('app.string.account_national_day_medal_date') :
                  $r('app.string.medal_hours', item.hours))
                  .fontSize(11)
                  .fontColor($r('sys.color.font_secondary'))
                Text(this.medalService.selectedMedalId === item.id ? $r('app.string.medal_wearing') :
                  this.medalService.isUnlocked(item.id) ? $r('app.string.medal_unlocked') : $r('app.string.medal_locked'))
                  .fontSize(11)
                  .fontColor(this.medalService.selectedMedalId === item.id ? AppColor.Brand :
                    $r('sys.color.font_tertiary'))
              }
              .width('100%')
              .padding({ top: AppSpace.Sm, bottom: AppSpace.Sm })
              .borderRadius(AppRadius.Md)
              .border({ width: 1, color: this.medalService.selectedMedalId === item.id ? AppColor.Brand : Color.Transparent })
              .alignItems(HorizontalAlign.Center)
              .onClick(() => this.chooseMedal(item))
              .enabled(!this.medalBusy)
            }
          }, (item: MedalDefinition) => item.id)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(AppSpace.Sm)
        .rowsGap(AppSpace.Sm)
        .width('100%')
        Text($r('app.string.medal_scope_hint'))
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
      } else if (!this.medalService.failed) {
        LoadingProgress().width(24).height(24).color(AppColor.Brand)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
  }

}
