// BindSheet 半模态页面示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/container/bindsheet

// ========== 模态半模态 ==========

@ComponentV2
struct ModalBindSheetExample {
  @Local isShow: boolean = false

  @Builder
  myBuilder() {
    Column() {
      Text('半模态内容')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_list_card'))
  }

  build() {
    Column() {
      Button('显示模态半模态')
        .onClick(() => {
          this.isShow = true
        })
    }
    .bindSheet(this.isShow, this.myBuilder(), {
      detents: [SheetSize.MEDIUM],
      blurStyle: BlurStyle.Thick,
      showClose: true,
      title: { title: '标题' },
      enableOutsideInteractive: false
    })
  }
}

// ========== 非模态半模态 ==========

@ComponentV2
struct NonModalBindSheetExample {
  @Local isShow: boolean = false

  @Builder
  myBuilder() {
    Column() {
      Text('半模态内容')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_list_card'))
  }

  build() {
    Column() {
      Button('显示非模态半模态')
        .onClick(() => {
          this.isShow = true
        })
    }
    .bindSheet(this.isShow, this.myBuilder(), {
      detents: [SheetSize.MEDIUM],
      blurStyle: BlurStyle.Thick,
      showClose: true,
      title: { title: '标题' },
      enableOutsideInteractive: true
    })
  }
}

// ========== 大尺寸半模态 ==========

.bindSheet(this.isShow, this.myBuilder(), {
  height: SheetSize.LARGE,
  blurStyle: BlurStyle.Thick,
  showClose: true,
  title: { title: '标题' },
  enableOutsideInteractive: false
})

// ========== 中等尺寸半模态 ==========

.bindSheet(this.isShow, this.myBuilder(), {
  height: SheetSize.MEDIUM,
  blurStyle: BlurStyle.Thick,
  showClose: true,
  title: { title: '标题' },
  enableOutsideInteractive: false
})

// ========== 自定义高度半模态 ==========

.bindSheet(this.isShow, this.myBuilder(), {
  height: 600,
  blurStyle: BlurStyle.Thick,
  showClose: true,
  title: { title: '标题' },
  enableOutsideInteractive: false
})

// ========== 可滚动半模态 ==========

.bindSheet(this.isShow, this.myScrollBuilder(), {
  detents: [SheetSize.LARGE, 200],
  blurStyle: BlurStyle.Thick,
  showClose: true,
  title: { title: '标题' },
  enableOutsideInteractive: false
})

@Builder
myScrollBuilder() {
  List() {
    ListItem() {
      Text('列表项')
    }
  }
  .width('100%')
  .height('100%')
}