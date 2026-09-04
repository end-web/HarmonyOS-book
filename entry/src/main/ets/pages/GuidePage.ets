import { AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

class GuideItem {
  id: string = '';
  action: ResourceStr = '';
  desc: ResourceStr = '';

  constructor(id: string, action: ResourceStr, desc: ResourceStr) {
    this.id = id;
    this.action = action;
    this.desc = desc;
  }
}

class GuideGroup {
  id: string = '';
  title: ResourceStr = '';
  items: GuideItem[] = [];

  constructor(id: string, title: ResourceStr, items: GuideItem[]) {
    this.id = id;
    this.title = title;
    this.items = items;
  }
}

/** 使用说明内容:每一条都对应代码里真实存在的交互 */
const GUIDE_GROUPS: GuideGroup[] = [
  new GuideGroup('home', $r('app.string.guide_group_home'), [
    new GuideItem('home-search', $r('app.string.guide_home_search_action'),
      $r('app.string.guide_home_search_desc')),
    new GuideItem('home-refresh', $r('app.string.guide_home_refresh_action'),
      $r('app.string.guide_home_refresh_desc')),
    new GuideItem('home-double-tap', $r('app.string.guide_home_top_action'),
      $r('app.string.guide_home_top_desc')),
  ]),
  new GuideGroup('common', $r('app.string.guide_group_common'), [
    new GuideItem('tab-double-tap', $r('app.string.guide_common_top_action'),
      $r('app.string.guide_common_top_desc')),
  ]),
  new GuideGroup('favorite', $r('app.string.guide_group_favorite'), [
    new GuideItem('favorite-open', $r('app.string.guide_favorite_open_action'),
      $r('app.string.guide_favorite_open_desc')),
    new GuideItem('favorite-refresh', $r('app.string.guide_favorite_refresh_action'),
      $r('app.string.guide_favorite_refresh_desc')),
    new GuideItem('favorite-remove', $r('app.string.guide_favorite_remove_action'),
      $r('app.string.guide_favorite_remove_desc')),
  ]),
  new GuideGroup('record', $r('app.string.guide_group_record'), [
    new GuideItem('record-select', $r('app.string.guide_record_select_action'),
      $r('app.string.guide_record_select_desc')),
    new GuideItem('record-play', $r('app.string.guide_record_play_action'),
      $r('app.string.guide_record_play_desc')),
  ]),
  new GuideGroup('player', $r('app.string.guide_group_player'), [
    new GuideItem('player-chapter', $r('app.string.guide_player_chapter_action'),
      $r('app.string.guide_player_chapter_desc')),
    new GuideItem('player-speed-reset', $r('app.string.guide_player_speed_action'),
      $r('app.string.guide_player_speed_desc')),
    new GuideItem('player-sleep', $r('app.string.guide_player_sleep_action'),
      $r('app.string.guide_player_sleep_desc')),
    new GuideItem('player-skip-clear', $r('app.string.guide_player_skip_action'),
      $r('app.string.guide_player_skip_desc')),
    new GuideItem('player-cast', $r('app.string.guide_player_cast_action'),
      $r('app.string.guide_player_cast_desc')),
  ]),
  new GuideGroup('reader', $r('app.string.guide_group_reader'), [
    new GuideItem('reader-open', $r('app.string.guide_reader_open_action'),
      $r('app.string.guide_reader_open_desc')),
    new GuideItem('reader-toolbar', $r('app.string.guide_reader_toolbar_action'),
      $r('app.string.guide_reader_toolbar_desc')),
    new GuideItem('reader-settings', $r('app.string.guide_reader_settings_action'),
      $r('app.string.guide_reader_settings_desc')),
  ]),
  new GuideGroup('source', $r('app.string.guide_group_source'), [
    new GuideItem('source-import', $r('app.string.guide_source_import_action'),
      $r('app.string.guide_source_import_desc')),
    new GuideItem('source-test', $r('app.string.guide_source_test_action'),
      $r('app.string.guide_source_test_desc')),
    new GuideItem('source-login', $r('app.string.guide_source_login_action'),
      $r('app.string.guide_source_login_desc')),
  ]),
  new GuideGroup('mini-player', $r('app.string.guide_group_mini_player'), [
    new GuideItem('mini-cover-progress', $r('app.string.guide_mini_cover_action'),
      $r('app.string.guide_mini_cover_desc')),
    new GuideItem('mini-cover-expand', $r('app.string.guide_mini_expand_action'),
      $r('app.string.guide_mini_expand_desc')),
  ]),
  new GuideGroup('system-media', $r('app.string.guide_group_system_media'), [
    new GuideItem('system-media-open', $r('app.string.guide_system_media_open_action'),
      $r('app.string.guide_system_media_open_desc')),
    new GuideItem('system-media-speed', $r('app.string.guide_system_speed_action'),
      $r('app.string.guide_system_speed_desc')),
  ]),
];

@ComponentV2
export struct GuidePage {
  @Param navStack: NavPathStack = new NavPathStack();

  @Builder
  groupCard(group: GuideGroup): void {
    Column({ space: AppSpace.Xs }) {
      Text(group.title)
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ left: AppSpace.Sm, bottom: AppSpace.Xs })

      Column() {
        ForEach(group.items, (item: GuideItem, idx: number) => {
          Column({ space: 2 }) {
            Text(item.action)
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium)
            Text(item.desc)
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })

          if (idx < group.items.length - 1) {
            Divider().color('#F0F0F0').margin({ left: AppSpace.Lg, right: AppSpace.Lg })
          }
        }, (item: GuideItem) => item.id)
      }
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => this.navStack.pop())
        Text('使用说明')
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
          .margin({ left: AppSpace.Sm })
      }
      .width('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Md
      })

      Scroll() {
        Column({ space: AppSpace.Lg }) {
          ForEach(GUIDE_GROUPS, (group: GuideGroup) => {
            this.groupCard(group)
          }, (group: GuideGroup) => group.id)

          Text($r('app.string.guide_footer'))
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: AppSpace.Sm, bottom: AppSpace.Xl })
        }
        .width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
