// 听书卡片 UI - 2x2
// 卡片侧不能 import media/audio,所有播控通过 postCardAction call 事件回到 EntryAbility
let playerCardStorage = new LocalStorage();

@Entry(playerCardStorage)
@Component
struct PlayerCard {
  @LocalStorageProp('hasBook') hasBook: number = 0;
  @LocalStorageProp('bookId') bookId: string = '';
  @LocalStorageProp('bookTitle') bookTitle: string = '没有正在播放';
  @LocalStorageProp('author') author: string = '';
  @LocalStorageProp('cover') cover: string = '';
  @LocalStorageProp('imgName') imgName: string = '';
  @LocalStorageProp('chapterTitle') chapterTitle: string = '';
  @LocalStorageProp('isPlaying') isPlaying: number = 0;
  @LocalStorageProp('bgColor') bgColor: string = '';

  private postCall(method: string): void {
    postCardAction(this, {
      action: 'call',
      abilityName: 'EntryAbility',
      params: { method: method }
    });
  }

  /**
   * 短按封面/标题:软拉起,回到用户上次离开的位置(对齐控制中心规范)。
   * 应用在后台 → 直接拉起停在当前页;冷启动 → 停在主 Tab。
   * 卡片不再提供"直接进播放器"入口,用户进 App 后自己判断要不要进。
   */
  private resumeApp(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        from: 'widget',
        target: 'resume',
        bookId: this.bookId
      }
    });
  }

  private hasCover(): boolean {
    return this.imgName.length > 0;
  }

  private coverSrc(): string {
    return 'memory://' + this.imgName;
  }

  build() {
    Stack() {
      // 背景层：有染色时用融合色渐变，否则封面铺底或默认渐变
      // 不加 borderRadius，由最外层 Stack 统一 clip，避免多层裁剪产生毛边
      if (this.bgColor.length > 0) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 160,
            colors: [[this.bgColor, 0], ['#FF0F0F0F', 1]]
          })
      } else if (this.hasCover()) {
        Image(this.coverSrc())
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .syncLoad(true)
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#99000000')
      } else {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 135,
            colors: [['#FF2A2A3E', 0], ['#FF1A1A2E', 1]]
          })
      }

      Column() {
        // 第一行:封面 + 书名/作者
        Row() {
          Stack() {
            if (this.hasCover()) {
              Image(this.coverSrc())
                .width('100%')
                .height('100%')
                .borderRadius(12)
                .objectFit(ImageFit.Cover)
                .syncLoad(true)
            } else {
              Column() {
                Text('听')
                  .fontSize(22)
                  .fontColor(Color.White)
                  .fontWeight(FontWeight.Bold)
              }
              .width('100%')
              .height('100%')
              .borderRadius(12)
              .backgroundColor('#33FFFFFF')
              .justifyContent(FlexAlign.Center)
            }
          }
          .width(60)
          .height(60)
          .backgroundColor(Color.Transparent)
          .borderRadius(12)
          .clip(true)

          Column() {
            // 书名:最多 2 行,超过才省略
            Text(this.bookTitle)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .lineHeight(16)
            if (this.author.length > 0) {
              // 作者:换行展示,最多 2 行才省略
              Text(this.author)
                .fontSize(10)
                .fontColor('#B3FFFFFF')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .margin({ top: 2 })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 10 })
        }
        .width('100%')
        // 卡片不支持 gesture(LongPressGesture),改成短按软拉起;
        // 进播放器靠下方第二行右侧的展开按钮
        .onClick(() => this.resumeApp())

        Blank()

        // 第二行:仅展示集数/章节名
        if (this.chapterTitle.length > 0) {
          Text(this.chapterTitle)
            .fontSize(11)
            .fontColor('#CCFFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        // 第三行:三按钮
        Row() {
          this.PlainBtn($r('sys.symbol.backward_end_fill'), 'prev')
          Stack() {
            if (this.isPlaying === 1) {
              SymbolGlyph($r('sys.symbol.pause_fill'))
                .fontSize(22)
                .fontColor(['#FF1F1F1F'])
            } else {
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(22)
                .fontColor(['#FF1F1F1F'])
            }
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(Color.White)
          .onClick(() => {
            if (this.hasBook !== 1) {
              this.resumeApp();
              return;
            }
            this.postCall(this.isPlaying === 1 ? 'pause' : 'play');
          })
          this.PlainBtn($r('sys.symbol.forward_end_fill'), 'next')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ top: 8 })
      }
      .width('100%')
      .height('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
  }

  /** 左右按钮:无背景圆圈,纯图标 */
  @Builder
  PlainBtn(icon: Resource, method: string) {
    Stack() {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor(['#FFFFFFFF'])
    }
    .width(36)
    .height(36)
    .onClick(() => {
      if (this.hasBook !== 1) {
        this.resumeApp();
        return;
      }
      this.postCall(method);
    })
  }
}
