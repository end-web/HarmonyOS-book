// Counter 组件示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/input/counter

// ========== Inline 内联计数器 ==========

CounterComponent({
  options: {
    type: CounterType.INLINE,
    inlineOptions: {
      value: 1,
      min: 0,
      step: 2,
      max: 99,
      textWidth: 60,
      onChange: (value: number) => {
        console.info('Counter: ' + value.toString())
      }
    }
  }
})

// ========== List 列表计数器 ==========

CounterComponent({
  options: {
    type: CounterType.LIST,
    numberOptions: {
      label: '数量',
      min: 0,
      value: 1,
      max: 99
    }
  }
})

// ========== Compact 紧凑计数器 ==========

CounterComponent({
  options: {
    type: CounterType.COMPACT,
    numberOptions: {
      label: '数量',
      value: 1,
      min: 0,
      max: 99,
      step: 1
    }
  }
})