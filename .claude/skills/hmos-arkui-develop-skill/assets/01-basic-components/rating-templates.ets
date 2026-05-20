// Rating 组件示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/select/rating

// ========== 可交互评分 ==========

Rating({ rating: 1, indicator: false })
  .stars(5)
  .stepSize(0.5)

// ========== 只读评分 ==========

Rating({ rating: 1, indicator: true })
  .stars(5)
  .stepSize(0.5)

// ========== 场景中评分 ==========

Rating({ rating: 2, indicator: true })
  .stars(5)
  .stepSize(0.5)

// ========== 带状态Rating ==========

@ComponentV2
struct InteractiveRatingExample {
  @Local ratingValue: number = 1

  build() {
    Column() {
      Rating({ rating: this.ratingValue, indicator: false })
        .stars(5)
        .stepSize(0.5)
        .onChange((value: number) => {
          this.ratingValue = value
        })
      
      Text(`Rating: ${this.ratingValue}`)
    }
  }
}