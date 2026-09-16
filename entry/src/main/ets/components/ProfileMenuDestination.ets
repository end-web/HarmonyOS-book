import { WindowUtils } from '../utils/WindowUtils';

/** “我的”菜单共用的整页转场，每个路由独立保存位移状态。 */
@ComponentV2
export struct ProfileMenuDestination {
  @Param pageBackground: ResourceColor = $r('sys.color.background_primary');
  @Event onBackRequested: () => boolean = (): boolean => false;
  @BuilderParam content: () => void = this.emptyContent;
  @Local translateX: string = '0%';

  @Builder
  emptyContent(): void {
  }

  build() {
    NavDestination() {
      this.content()
    }
    .hideTitleBar(true)
    .backgroundColor(this.pageBackground)
    .onBackPressed(() => this.onBackRequested())
    .translate({ x: this.translateX })
    .customTransition((operation: NavigationOperation, isEnter: boolean): Array<NavDestinationTransition> => {
      const enteringFromRight = operation !== NavigationOperation.POP && isEnter;
      const exitingToRight = operation === NavigationOperation.POP && !isEnter;
      this.translateX = enteringFromRight ? '100%' : '0%';
      return [{
        duration: WindowUtils.getPageTransitionDuration(),
        curve: Curve.EaseInOut,
        event: () => {
          this.translateX = exitingToRight ? '100%' : '0%';
        }
      }];
    })
  }
}
