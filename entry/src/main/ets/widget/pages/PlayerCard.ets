// 听书卡片 UI - 2x2
// 卡片侧不能 import media/audio,所有播控通过 postCardAction call 事件回到 EntryAbility
let playerCardStorage = new LocalStorage();

@Entry(playerCardStorage)
@Component
struct PlayerCard {
  @LocalStorageProp('hasBook') hasBook: boolean = false;
  @LocalStorageProp('bookId') bookId: string = '';
  @LocalStorageProp('bookTitle') bookTitle: string = '没有正在播放';
  @LocalStorageProp('author') author: string = '';
  @LocalStorageProp('cover') cover: string = '';
  @LocalStorageProp('imgName') imgName: string = '';
  @LocalStorageProp('chapterTitle') chapterTitle: string = '';
  @LocalStorageProp('isPlaying') isPlaying: boolean = false;

  private postCall(method: string): void {
    postCardAction(this, {
      action: 'call',
      abilityName: 'EntryAbility',
      params: { method: method }
    });
  }

  /** 点击卡片信息区时打开当前书的播放页；无播放记录时回到应用主页。 */
  private openPlayer(): void {
    const target: string = this.hasBook && this.bookId.length > 0 ? 'player' : 'home';
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        from: 'widget',
        target: target,
        bookId: this.bookId
      }
    });
  }

  private hasCover(): boolean {
    return this.imgName.length > 0 || this.cover.length > 0;
  }

  build() {
    Stack() {
      // 与播放页保持一致：当前封面铺满模糊，再叠加深色遮罩。
      // formImages 存在时只创建 memory 图片，避免网络图加载失败后的占位层干扰封面。
      if (this.hasCover()) {
        if (this.imgName.length > 0) {
          Image('memory://' + this.imgName)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .sourceSize({ width: 120, height: 120 })
            .blur(40)
        } else {
          Image(this.cover)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .sourceSize({ width: 120, height: 120 })
            .blur(40)
        }
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#0D0D0D')
          .opacity(0.7)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#3B4650')
      }

      Column() {
        // 第一行:封面 + 书名/作者
        Row() {
          Stack() {
            if (this.hasCover()) {
              if (this.imgName.length > 0) {
                Image('memory://' + this.imgName)
                  .width('100%')
                  .height('100%')
                  .borderRadius(12)
                  .objectFit(ImageFit.Cover)
                  .syncLoad(true)
              } else {
                Image(this.cover)
                  .width('100%')
                  .height('100%')
                  .borderRadius(12)
                  .objectFit(ImageFit.Cover)
                  .syncLoad(true)
                  .alt($r('app.media.app_icon_legacy'))
              }
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
        // 封面与标题打开播放页，播控按钮仍单独走 call。
        .onClick(() => this.openPlayer())

        Blank()
          .width('100%')
          .onClick(() => this.openPlayer())

        // 第二行:仅展示集数/章节名
        if (this.chapterTitle.length > 0) {
          Text(this.chapterTitle)
            .fontSize(11)
            .fontColor('#CCFFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .onClick(() => this.openPlayer())
        }

        // 第三行:三按钮
        Row() {
          this.PlainBtn($r('sys.symbol.backward_end_fill'), 'prev')
          Stack() {
            if (this.isPlaying) {
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
            if (!this.hasBook) {
              this.openPlayer();
              return;
            }
            this.postCall(this.isPlaying ? 'pause' : 'play');
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
    .clip(true)
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
      if (!this.hasBook) {
        this.openPlayer();
        return;
      }
      this.postCall(method);
    })
  }
}
