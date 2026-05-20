// Image 组件示例模板

// ========== 基础图片 ==========
@Entry
@Component
struct BasicImageExample {
  build() {
    Column({ space: 20 }) {
      // 本地图片
      Image($r('app.media.icon'))
        .width(100)
        .height(100)
      
      // 网络图片
      Image('https://example.com/image.png')
        .width(100)
        .height(100)
        .alt($r('app.media.placeholder'))  // 占位图
      
      // Base64 图片
      Image('data:image/png;base64,iVBORw0KGgo...')
        .width(100)
        .height(100)
    }
    .padding(20)
  }
}

// ========== 图片缩放模式 ==========
@Entry
@Component
struct ImageScaleExample {
  build() {
    Column({ space: 20 }) {
      // 填充容器
      Image($r('app.media.icon'))
        .width(100)
        .height(100)
        .objectFit(ImageFit.Fill)
      
      // 保持比例填满
      Image($r('app.media.icon'))
        .width(100)
        .height(100)
        .objectFit(ImageFit.Cover)
      
      // 保持比例完整显示
      Image($r('app.media.icon'))
        .width(100)
        .height(100)
        .objectFit(ImageFit.Contain)
      
      // 居中显示
      Image($r('app.media.icon'))
        .width(100)
        .height(100)
        .objectFit(ImageFit.Center)
      
      // 缩放到合适大小
      Image($r('app.media.icon'))
        .width(100)
        .height(100)
        .objectFit(ImageFit.ScaleDown)
    }
    .padding(20)
  }
}

// ========== 圆角/圆形图片 ==========
@Entry
@Component
struct RoundedImageExample {
  build() {
    Column({ space: 20 }) {
      // 圆角图片
      Image($r('app.media.icon'))
        .width(100)
        .height(80)
        .borderRadius(12)
      
      // 圆形图片（头像）
      Image($r('app.media.avatar'))
        .width(80)
        .height(80)
        .borderRadius(40)
        .clip(true)
      
      // 圆形边框头像
      Image($r('app.media.avatar'))
        .width(80)
        .height(80)
        .borderRadius(40)
        .border({ width: 2, color: Color.White })
    }
    .padding(20)
  }
}

// ========== 图片加载状态 ==========
@Entry
@Component
struct ImageLoadingExample {
  @State imageSrc: string = 'https://example.com/large-image.png'
  
  build() {
    Column({ space: 20 }) {
      Image(this.imageSrc)
        .width(200)
        .height(150)
        .alt($r('app.media.placeholder'))
        .onComplete(() => {
          console.info('图片加载完成')
        })
        .onError(() => {
          console.error('图片加载失败')
        })
    }
    .padding(20)
  }
}

// ========== 图片渲染模式 ==========
@Entry
@Component
struct ImageRenderExample {
  build() {
    Column({ space: 20 }) {
      // 原图
      Image($r('app.media.icon'))
        .width(100)
        .height(100)
      
      // SVG 图片
      Image($r('app.media.icon_svg'))
        .width(100)
        .height(100)
        .fillColor(Color.Blue)  // SVG 填充色
      
      // Symbol 图标
      SymbolGlyph($r('sys.symbol.star_fill'))
        .fontSize(40)
        .fontColor([Color.Orange])
    }
    .padding(20)
  }
}

// ========== 图片滤镜效果 ==========
@Entry
@Component
struct ImageFilterExample {
  build() {
    Column({ space: 20 }) {
      // 原图
      Image($r('app.media.icon'))
        .width(100)
        .height(100)
      
      // 模糊效果
      Image($r('app.media.icon'))
        .width(100)
        .height(100)
        .blur(5)
      
      // 灰度效果
      Image($r('app.media.icon'))
        .width(100)
        .height(100)
        .grayscale(1)
      
      // 亮度调整
      Image($r('app.media.icon'))
        .width(100)
        .height(100)
        .brightness(0.5)
      
      // 对比度
      Image($r('app.media.icon'))
        .width(100)
        .height(100)
        .contrast(1.5)
    }
    .padding(20)
  }
}

// ========== V2 组件图片 ==========
@ComponentV2
struct V2ImageExample {
  @Param src: ResourceStr = $r('app.media.icon')
  @Param width: number = 100
  @Param height: number = 100
  @Local isLoading: boolean = true
  
  build() {
    Stack() {
      if (this.isLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
      }
      
      Image(this.src)
        .width(this.width)
        .height(this.height)
        .objectFit(ImageFit.Cover)
        .onComplete(() => {
          this.isLoading = false
        })
    }
  }
}