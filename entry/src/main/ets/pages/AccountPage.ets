import { MEDALS, MedalAward, MedalDefinition } from '../model/Medal';
import { MedalService } from '../service/MedalService';
import { BusinessError } from '@kit.BasicServicesKit';
import { AccountAvatar } from '../components/AccountAvatar';
import { ProfileMenuDestination } from '../components/ProfileMenuDestination';
import { AuthService, HwAuthErrorCode } from '../service/AuthService';
import { AppBackupSnapshot } from '../service/AppBackupService';
import { AutoBackupService } from '../service/AutoBackupService';
import {
  LocalBackupError, LocalBackupErrorCode, LocalBackupPhase, LocalBackupService
} from '../service/LocalBackupService';
import {
  CloudBackupError, CloudBackupErrorCode, CloudBackupInfo, CloudBackupPhase, CloudBackupService
} from '../service/CloudBackupService';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct AccountPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local auth: AuthService = AuthService.instance;
  @Local cloud: CloudBackupService = CloudBackupService.instance;
  @Local local: LocalBackupService = LocalBackupService.instance;
  @Local automatic: AutoBackupService = AutoBackupService.instance;
  @Local manualPending: boolean = false;
  @Local autoReady: boolean = false;
  @Local message: ResourceStr = '';
  @Local hasMessage: boolean = false;
  @Local cloudSystemCode: number = 0;
  @Local localMessage: ResourceStr = '';
  @Local hasLocalMessage: boolean = false;
  @Local localBackupExpanded: boolean = false;
  @Local cloudBackupExpanded: boolean = false;
  private finishConfirmation: ((confirmed: boolean) => void) | null = null;

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
    this.loadMedals();
    const context = this.getUIContext().getHostContext();
    if (context) {
      this.auth.restore(context).then(async (): Promise<void> => {
        await this.automatic.refresh(context);
        this.autoReady = true;
        await this.cloud.refresh(context);
      });
    }
  }

  aboutToDisappear(): void {
    this.finishConfirmation?.(false);
    this.finishConfirmation = null;
    if (!this.automatic.running) this.cloud.cancel();
    this.local.cancel();
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private interceptBack(): boolean {
    if (!this.manualPending && ((!this.auth.dataOperation && !this.auth.logging) || this.automatic.running)) return false;
    this.toast($r('app.string.account_wait_operation'));
    return true;
  }

  private manualAvailable(): boolean {
    return !this.manualPending && !this.automatic.configuring && !this.auth.logging &&
      (!this.auth.restoring || this.automatic.running) && (!this.auth.dataOperation || this.automatic.running);
  }

  private async runManual(action: () => Promise<void>): Promise<void> {
    if (!this.manualAvailable()) return;
    this.manualPending = true;
    await this.automatic.pauseForManual();
    try {
      await action();
    } finally {
      this.automatic.resumeAfterManual();
      this.manualPending = false;
    }
  }

  private async setAutomatic(enabled: boolean, days: number): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.auth.isLoggedIn || !this.manualAvailable()) return;
    try {
      await this.automatic.configure(context, enabled, days);
    } catch (_error) {
      this.toast($r('app.string.auto_backup_save_failed'));
    }
  }

  private autoFrequency(): ResourceStr {
    return this.automatic.settings.intervalDays === 7 ? $r('app.string.auto_backup_weekly') :
      this.automatic.settings.intervalDays === 3 ? $r('app.string.auto_backup_three_days') :
        $r('app.string.auto_backup_daily');
  }

  private chooseFrequency(): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: $r('app.string.auto_backup_frequency'),
      buttons: [
        { text: $r('app.string.auto_backup_daily'), color: AppColor.Brand },
        { text: $r('app.string.auto_backup_three_days'), color: AppColor.Brand },
        { text: $r('app.string.auto_backup_weekly'), color: AppColor.Brand }
      ]
    }).then((result): void => {
      this.setAutomatic(this.automatic.settings.enabled, result.index === 2 ? 7 : result.index === 1 ? 3 : 1);
    }).catch((): void => {});
  }

  private autoStatus(): ResourceStr {
    if (!this.auth.isLoggedIn) return $r('app.string.auto_backup_login_required');
    if (this.automatic.storageFailed) return $r('app.string.auto_backup_save_failed');
    if (this.automatic.accountId !== this.auth.openID || !this.automatic.settings.enabled) {
      return $r('app.string.auto_backup_off');
    }
    if (this.automatic.settings.needsDecision) return $r('app.string.auto_backup_existing');
    if (this.automatic.running && this.cloud.busy) return $r('app.string.auto_backup_running');
    if (this.automatic.settings.errorCode === CloudBackupErrorCode.CANCELLED) {
      return $r('app.string.auto_backup_waiting');
    }
    if (this.automatic.settings.errorCode !== 0) return this.cloudErrorText(this.automatic.settings.errorCode);
    return $r('app.string.auto_backup_ready');
  }

  private lastBackupAt(): number {
    return Math.max(this.cloud.lastBackupAt,
      this.automatic.accountId === this.auth.openID ? this.automatic.settings.lastSuccessAt : 0);
  }

  private async updateProfile(): Promise<void> {
    if (this.auth.dataOperation || this.auth.logging || this.auth.restoring) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    try {
      await this.auth.login(context);
      await this.automatic.refresh(context);
      await this.cloud.refresh(context);
      this.toast($r('app.string.account_profile_updated'));
    } catch (error) {
      const failure: BusinessError = error;
      if (failure.code === HwAuthErrorCode.USER_CANCEL || failure.code === HwAuthErrorCode.REQUEST_REFUSE) return;
      this.toast(failure.code === HwAuthErrorCode.NETWORK ? $r('app.string.hw_auth_network_error') :
        failure.code === HwAuthErrorCode.CERT_INVALID ? $r('app.string.hw_auth_unavailable') :
          $r('app.string.account_profile_failed'));
    }
  }

  private profileActionColor(): ResourceColor {
    return this.auth.isLoggedIn ? AppColor.Brand : $r('sys.color.font_tertiary');
  }

  private logout(): void {
    if (!this.manualAvailable()) return;
    this.getUIContext().showAlertDialog({
      title: $r('app.string.hw_auth_logout_title'),
      message: $r('app.string.hw_auth_logout_message'),
      primaryButton: {
        value: $r('app.string.hw_auth_logout_title'),
        fontColor: '#FF3B30',
        action: () => {
          this.runManual(async (): Promise<void> => {
            await this.auth.logout();
            const context = this.getUIContext().getHostContext();
            if (context) await this.automatic.refresh(context);
            this.cloud.lastBackupAt = 0;
            this.navStack.pop();
            this.toast($r('app.string.hw_auth_logout_success'));
          }).catch(() => this.toast($r('app.string.hw_auth_logout_failed')));
        }
      },
      secondaryButton: { value: $r('app.string.hw_auth_cancel'), action: () => {} }
    });
  }

  private async backup(): Promise<void> {
    if (this.auth.dataOperation || this.auth.logging || this.auth.restoring) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.hasMessage = false;
    this.cloudSystemCode = 0;
    try {
      if (this.automatic.settings.needsDecision && !await this.confirmRestore(
        $r('app.string.auto_backup_use_local_title'), $r('app.string.auto_backup_use_local_message'),
        $r('app.string.auto_backup_use_local_title'))) return;
      const result = await this.cloud.backup(context);
      await this.automatic.recordManualSuccess(context, result);
      this.message = $r('app.string.cloud_backup_success');
      this.hasMessage = true;
    } catch (error) {
      this.showCloudError(error);
    }
  }

  private async restore(): Promise<void> {
    if (this.auth.dataOperation || this.auth.logging || this.auth.restoring) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.hasMessage = false;
    this.cloudSystemCode = 0;
    const accountId = this.auth.openID;
    try {
      const restored = await this.cloud.restore(context,
        (info: CloudBackupInfo): Promise<boolean> => this.confirmRestore(
          $r('app.string.cloud_restore_confirm_title'),
          $r('app.string.cloud_restore_confirm_message', this.formatDate(info.exportedAt),
            info.bookCount, info.sourceCount)));
      if (restored) {
        await this.automatic.recordRestoreSuccess(context, accountId);
        this.message = $r('app.string.cloud_restore_success');
        this.hasMessage = true;
      }
    } catch (error) {
      this.showCloudError(error);
    }
  }

  private async exportLocal(): Promise<void> {
    if (this.auth.dataOperation || this.auth.logging || this.auth.restoring) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.hasLocalMessage = false;
    try {
      const snapshot = await this.local.backup(context);
      if (snapshot) {
        this.localMessage = $r('app.string.local_backup_success', snapshot.ruleSources.length);
        this.hasLocalMessage = true;
      }
    } catch (error) {
      this.showLocalError(error);
    }
  }

  private async restoreLocal(): Promise<void> {
    if (this.auth.dataOperation || this.auth.logging || this.auth.restoring) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.hasLocalMessage = false;
    try {
      const restored = await this.local.restore(context,
        (snapshot: AppBackupSnapshot): Promise<boolean> => this.confirmRestore(
          $r('app.string.local_restore_confirm_title'),
          $r('app.string.cloud_restore_confirm_message', this.formatDate(snapshot.exportedAt),
            snapshot.preferences.favorites.length, snapshot.ruleSources?.length ?? 0)));
      if (restored) {
        this.localMessage = $r('app.string.cloud_restore_success');
        this.hasLocalMessage = true;
      }
    } catch (error) {
      this.showLocalError(error);
    }
  }

  private showLocalError(error: LocalBackupError): void {
    if (error.code === LocalBackupErrorCode.CANCELLED) return;
    switch (error.code) {
      case LocalBackupErrorCode.INVALID_BACKUP:
        this.localMessage = $r('app.string.local_backup_invalid'); break;
      case LocalBackupErrorCode.TOO_LARGE:
        this.localMessage = $r('app.string.local_backup_too_large'); break;
      case LocalBackupErrorCode.FILE_ACCESS:
        this.localMessage = $r('app.string.local_backup_file_error'); break;
      case LocalBackupErrorCode.RESTORE_FAILED:
        this.localMessage = $r('app.string.cloud_error_restore'); break;
      default:
        this.localMessage = $r('app.string.local_backup_prepare_error'); break;
    }
    this.hasLocalMessage = true;
  }

  private localPhaseText(): ResourceStr {
    switch (this.local.phase) {
      case LocalBackupPhase.SELECTING: return $r('app.string.local_backup_selecting');
      case LocalBackupPhase.COPYING: return $r('app.string.local_backup_copying');
      case LocalBackupPhase.CONFIRMING: return $r('app.string.cloud_phase_confirming');
      case LocalBackupPhase.RESTORING: return $r('app.string.cloud_phase_restoring');
      default: return $r('app.string.cloud_phase_preparing');
    }
  }

  private confirmRestore(title: ResourceStr, message: ResourceStr,
    confirmText: ResourceStr = $r('app.string.cloud_restore_confirm')): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      const finish = (confirmed: boolean): void => {
        this.finishConfirmation = null;
        resolve(confirmed);
      };
      this.finishConfirmation = finish;
      this.getUIContext().showAlertDialog({
        title,
        message,
        primaryButton: { value: confirmText, action: () => finish(true) },
        secondaryButton: { value: $r('app.string.hw_auth_cancel'), action: () => finish(false) },
        cancel: () => finish(false)
      });
    });
  }

  private showCloudError(error: CloudBackupError): void {
    this.message = this.cloudErrorText(error.code);
    this.cloudSystemCode = error.systemCode ?? 0;
    this.hasMessage = true;
  }

  private cloudErrorText(code: CloudBackupErrorCode): ResourceStr {
    switch (code) {
      case CloudBackupErrorCode.UNAVAILABLE: return $r('app.string.cloud_error_unavailable');
      case CloudBackupErrorCode.NETWORK: return $r('app.string.cloud_error_network');
      case CloudBackupErrorCode.BATTERY: return $r('app.string.cloud_error_battery');
      case CloudBackupErrorCode.CLOUD_FULL: return $r('app.string.cloud_error_cloud_full');
      case CloudBackupErrorCode.LOCAL_FULL: return $r('app.string.cloud_error_local_full');
      case CloudBackupErrorCode.HOT: return $r('app.string.cloud_error_hot');
      case CloudBackupErrorCode.SERVER: return $r('app.string.cloud_error_server');
      case CloudBackupErrorCode.TIMEOUT: return $r('app.string.cloud_error_timeout');
      case CloudBackupErrorCode.CANCELLED: return $r('app.string.cloud_error_cancelled');
      case CloudBackupErrorCode.ACCOUNT_CHANGED: return $r('app.string.cloud_error_account');
      case CloudBackupErrorCode.NO_BACKUP: return $r('app.string.cloud_error_empty');
      case CloudBackupErrorCode.INVALID_BACKUP: return $r('app.string.cloud_error_invalid');
      case CloudBackupErrorCode.RESTORE_FAILED: return $r('app.string.cloud_error_restore');
      case CloudBackupErrorCode.CLOUD_FILE_FAILURE: return $r('app.string.cloud_error_file');
      default: return $r('app.string.cloud_error_local');
    }
  }

  private phaseText(): ResourceStr {
    switch (this.cloud.phase) {
      case CloudBackupPhase.SYNCING: return $r('app.string.cloud_phase_syncing');
      case CloudBackupPhase.DOWNLOADING: return $r('app.string.cloud_phase_downloading');
      case CloudBackupPhase.CONFIRMING: return $r('app.string.cloud_phase_confirming');
      case CloudBackupPhase.RESTORING: return $r('app.string.cloud_phase_restoring');
      default: return $r('app.string.cloud_phase_preparing');
    }
  }

  private formatDate(value: number): string {
    const date = new Date(value);
    return `${date.getFullYear()}/${String(date.getMonth() + 1).padStart(2, '0')}/${String(date.getDate()).padStart(2, '0')} ` +
      `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }

  build() {
    ProfileMenuDestination({
      pageBackground: $r('sys.color.background_secondary'),
      onBackRequested: (): boolean => this.interceptBack()
    }) {
      Column() {
        Row({ space: AppSpace.Sm }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
            .width(40)
            .height(40)
            .onClick(() => { if (!this.interceptBack()) this.navStack.pop(); })
            .accessibilityText($r('app.string.account_back'))
          Text($r('app.string.account_title'))
            .fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
        }
        .width('100%')
        .padding({ top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
          left: AppSpace.Sm, right: AppSpace.Md, bottom: AppSpace.Sm })

        Scroll() {
          Column({ space: AppSpace.Lg }) {
            this.profileCard()
            if (this.auth.isLoggedIn) {
              this.medalCard()
            }
            this.localBackupCard()
            this.backupCard()
            if (this.auth.isLoggedIn) {
              Button($r('app.string.hw_auth_logout_title'), { type: ButtonType.Normal })
                .width('100%')
                .height(52)
                .fontSize(AppFont.BodyL)
                .fontColor($r('sys.color.font_secondary'))
                .backgroundColor($r('sys.color.comp_background_primary'))
                .borderRadius(AppRadius.Lg)
                .enabled(this.manualAvailable())
                .onClick(() => this.logout())
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
  profileCard() {
    Row({ space: AppSpace.Md }) {
      AccountAvatar({ uri: this.auth.avatarUri, avatarSize: 48 })
      Column({ space: 4 }) {
        Text(this.auth.isLoggedIn ? (this.auth.nickName || $r('app.string.hw_auth_account_title')) :
          $r('app.string.hw_auth_login_title'))
          .fontSize(AppFont.Title)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.auth.isLoggedIn ? $r('app.string.account_huawei_connected') : $r('app.string.account_local_available'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.profileActionButton()
    }
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
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

  @Builder
  profileActionButton() {
    Stack() {
      if (this.auth.logging || this.auth.restoring) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(AppColor.Brand)
      } else {
        SymbolGlyph(this.auth.isLoggedIn ? $r('sys.symbol.arrow_clockwise') : $r('sys.symbol.chevron_right'))
          .fontSize(22)
          .fontColor([this.profileActionColor()])
      }
    }
    .width(40)
    .height(40)
    .enabled(this.manualAvailable())
    .accessibilityText(this.auth.isLoggedIn ? $r('app.string.account_profile_refresh') :
      $r('app.string.hw_auth_login_title'))
    .onClick(() => this.runManual((): Promise<void> => this.updateProfile()))
  }

  @Builder
  localBackupCard() {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.local_backup_title'))
          .fontSize(AppFont.BodyL)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        SymbolGlyph(this.localBackupExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .width('100%')
      .constraintSize({ minHeight: 40 })
      .onClick(() => { this.localBackupExpanded = !this.localBackupExpanded; })
      if (this.localBackupExpanded) {
        Text($r('app.string.local_backup_description'))
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
          .lineHeight(21)
        Column() {
          this.backupAction(true, true)
          Divider().color($r('sys.color.comp_divider')).strokeWidth(0.5).margin({ left: 36 })
          this.backupAction(false, true)
        }
        .width('100%')
        .enabled(this.manualAvailable())
        .opacity(this.manualAvailable() ? 1 : 0.5)
        if (this.local.busy) {
          Row({ space: AppSpace.Sm }) {
            LoadingProgress().width(20).height(20).color(AppColor.Brand)
            Text(this.localPhaseText()).fontSize(AppFont.Body).fontColor(AppColor.Brand).layoutWeight(1)
          }
          .width('100%')
          .constraintSize({ minHeight: 40 })
        }
        if (this.hasLocalMessage) {
          Text(this.localMessage)
            .fontSize(AppFont.Body)
            .lineHeight(21)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
        Text($r('app.string.local_backup_exclusions'))
          .fontSize(AppFont.Caption)
          .lineHeight(19)
          .fontColor($r('sys.color.font_tertiary'))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
  }

  @Builder
  automaticBackupSettings() {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.auto_backup_title'))
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.auth.isLoggedIn &&
          this.automatic.accountId === this.auth.openID && this.automatic.settings.enabled })
          .selectedColor(AppColor.Brand)
          .enabled(this.autoReady && this.auth.isLoggedIn && this.manualAvailable())
          .accessibilityText($r('app.string.auto_backup_title'))
          .onChange((enabled: boolean): void => { this.setAutomatic(enabled, this.automatic.settings.intervalDays); })
      }
      .width('100%')
      .constraintSize({ minHeight: 44 })
      if (this.auth.isLoggedIn && this.automatic.accountId === this.auth.openID && this.automatic.settings.enabled) {
        Row({ space: AppSpace.Sm }) {
          Text($r('app.string.auto_backup_frequency'))
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          Text(this.autoFrequency()).fontSize(AppFont.Body).fontColor($r('sys.color.font_secondary'))
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(20).fontColor([$r('sys.color.font_tertiary')])
        }
        .width('100%')
        .constraintSize({ minHeight: 44 })
        .enabled(this.manualAvailable())
        .onClick(() => this.chooseFrequency())
      }
      Text(this.autoStatus()).fontSize(AppFont.Caption).lineHeight(19)
        .fontColor($r('sys.color.font_secondary'))
      if (this.auth.isLoggedIn && this.automatic.accountId === this.auth.openID &&
        this.automatic.settings.enabled && this.automatic.settings.errorCode !== 0 &&
        !this.automatic.settings.needsDecision) {
        Text($r('app.string.auto_backup_retry')).fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
        if (this.automatic.settings.systemCode !== 0) {
          Text($r('app.string.cloud_error_code', this.automatic.settings.systemCode)).fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      Text($r('app.string.auto_backup_description')).fontSize(AppFont.Caption).lineHeight(19)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  backupCard() {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.cloud_title'))
          .fontSize(AppFont.BodyL)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        SymbolGlyph(this.cloudBackupExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .width('100%')
      .constraintSize({ minHeight: 40 })
      .onClick(() => { this.cloudBackupExpanded = !this.cloudBackupExpanded; })
      if (this.cloudBackupExpanded) {
        Text($r('app.string.cloud_description'))
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
          .lineHeight(21)
        Text(this.auth.isLoggedIn && this.lastBackupAt() > 0
          ? $r('app.string.cloud_last_backup', this.formatDate(this.lastBackupAt()))
          : $r('app.string.cloud_last_backup_unknown'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))

        this.automaticBackupSettings()

        Column() {
          this.backupAction(true, false)
          Divider().color($r('sys.color.comp_divider')).strokeWidth(0.5).margin({ left: 36 })
          this.backupAction(false, false)
        }
        .width('100%')
        .enabled(this.auth.isLoggedIn && this.manualAvailable())
        .opacity(this.auth.isLoggedIn && this.manualAvailable() ? 1 : 0.5)

        if (this.cloud.busy) {
          Row({ space: AppSpace.Sm }) {
            LoadingProgress().width(20).height(20).color(AppColor.Brand)
            Text(this.phaseText()).fontSize(AppFont.Body).fontColor(AppColor.Brand).layoutWeight(1)
            if (this.cloud.phase !== CloudBackupPhase.RESTORING && this.cloud.phase !== CloudBackupPhase.CONFIRMING) {
              Button($r('app.string.hw_auth_cancel'))
                .fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_secondary'))
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .onClick(() => this.cloud.cancel())
            }
          }
          .width('100%')
          .constraintSize({ minHeight: 40 })
        }
        if (this.hasMessage) {
          Text(this.message)
            .fontSize(AppFont.Body)
            .lineHeight(21)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          if (this.cloudSystemCode !== 0) {
            Text($r('app.string.cloud_error_code', this.cloudSystemCode))
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
          }
        }
        Text($r('app.string.cloud_backup_exclusions'))
          .fontSize(AppFont.Caption)
          .lineHeight(19)
          .fontColor($r('sys.color.font_tertiary'))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
  }

  @Builder
  backupAction(upload: boolean, local: boolean) {
    Row({ space: AppSpace.Sm }) {
      SymbolGlyph(upload ? $r('sys.symbol.arrow_up_circle') : $r('sys.symbol.arrow_down_circle'))
        .fontSize(24)
        .fontColor([AppColor.Brand])
        .width(28)
        .height(28)
      Column({ space: 2 }) {
        Text(local ? (upload ? $r('app.string.local_backup_export') : $r('app.string.local_backup_restore')) :
          (upload ? $r('app.string.cloud_backup_now') : $r('app.string.cloud_restore')))
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
        Text(local ? (upload ? $r('app.string.local_backup_export_desc') : $r('app.string.local_backup_restore_desc')) :
          (upload ? $r('app.string.cloud_backup_now_desc') : $r('app.string.cloud_restore_desc')))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(24).fontColor([$r('sys.color.font_tertiary')])
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ top: AppSpace.Sm, bottom: AppSpace.Sm })
    .onClick(() => {
      if (local) {
        this.runManual((): Promise<void> => upload ? this.exportLocal() : this.restoreLocal());
      } else {
        this.runManual((): Promise<void> => upload ? this.backup() : this.restore());
      }
    })
  }
}
