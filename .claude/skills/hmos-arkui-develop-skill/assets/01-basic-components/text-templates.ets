// Text 组件示例模板

// ========== 基础文本 ==========
@Entry
@Component
struct BasicTextExample {
  build() {
    Column({ space: 20 }) {
      // 基础文本
      Text('Hello ArkUI')
        .fontSize(20)
        .fontColor(Color.Black)
      
      // 富文本样式
      Text('样式文本')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(0x317aff)
        .fontStyle(FontStyle.Italic)
      
      // 文本对齐
      Text('这是一段较长的文本内容，用于演示文本对齐效果。')
        .width(200)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding(20)
  }
}

// ========== 文本溢出处理 ==========
@Entry
@Component
struct TextOverflowExample {
  build() {
    Column({ space: 20 }) {
      // 省略号截断
      Text('这是一段很长的文本内容，用于演示省略号截断效果，超出部分会显示省略号')
        .width(200)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      
      // 跑马灯效果
      Text('这是一段跑马灯文本，会自动滚动显示')
        .width(200)
        .textOverflow({ overflow: TextOverflow.Marquee })
      
      // 多行截断
      Text('这是一段很长的文本内容，用于演示多行截断效果，超出指定行数后显示省略号')
        .width(200)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding(20)
  }
}

// ========== 图文混排 ==========
@Entry
@Component
struct RichTextExample {
  build() {
    Column({ space: 20 }) {
      // Span 文本片段
      Text() {
        Span('普通文本')
        Span('红色文本')
          .fontColor(Color.Red)
          .fontWeight(FontWeight.Bold)
        Span('正常继续')
      }
      .fontSize(16)
      
      // 图文混排
      Text() {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(16)
          .fontColor(Color.Orange)
        Span(' 收藏')
          .fontSize(16)
        ImageSpan($r('app.media.icon'))
          .width(20)
          .height(20)
          .verticalAlign(ImageSpanAlignment.CENTER)
        Span(' 图标混排')
      }
    }
    .padding(20)
  }
}

// ========== 自适应字号 ==========
@Entry
@Component
struct AdaptiveTextExample {
  build() {
    Column({ space: 20 }) {
      // 字号自适应
      Text('这段文本会根据容器大小自适应字号')
        .width(150)
        .height(40)
        .maxFontSize(20)
        .minFontSize(10)
        .maxLines(1)
      
      // 行高自适应
      Text('这段文本会根据高度自适应行数')
        .width(150)
        .height(60)
        .maxLines(3)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MAX_LINES_FIRST)
    }
    .padding(20)
  }
}

// ========== 文本装饰 ==========
@Entry
@Component
struct TextDecorationExample {
  build() {
    Column({ space: 20 }) {
      // 下划线
      Text('下划线文本')
        .decoration({ type: TextDecorationType.Underline, color: Color.Blue })
      
      // 删除线
      Text('删除线文本')
        .decoration({ type: TextDecorationType.LineThrough, color: Color.Red })
      
      // 文本阴影
      Text('阴影文本')
        .textShadow({ radius: 4, color: Color.Gray, offsetX: 2, offsetY: 2 })
      
      // 渐变色文本
      Text('渐变文本')
        .shaderStyle({
          colors: [['#317aff', 0], ['#ff6b6b', 1]]
        })
    }
    .padding(20)
  }
}

// ========== 可选择文本 ==========
@Entry
@Component
struct SelectableTextExample {
  build() {
    Column({ space: 20 }) {
      // 可复制文本
      Text('这段文本可以长按选择和复制')
        .copyOption(CopyOptions.LocalDevice)
        .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
      
      // 带选中样式
      Text('可选中并查看选中效果')
        .copyOption(CopyOptions.LocalDevice)
        .selectedBackgroundColor(0x33317aff)
    }
    .padding(20)
  }
}

// ========== V2 组件文本 ==========
@ComponentV2
struct V2TextExample {
  @Local content: string = '动态内容'
  @Param maxLength: number = 100
  
  build() {
    Column({ space: 10 }) {
      Text(this.content)
        .fontSize(16)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      
      if (this.content.length > this.maxLength) {
        Text('内容过长，已截断')
          .fontSize(12)
          .fontColor(Color.Gray)
      }
    }
  }
}