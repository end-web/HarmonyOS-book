// 状态管理 V1/V2 示例模板

// ==================== V2 状态管理 ====================

// ========== @Local 组件内部状态 ==========
@ComponentV2
struct V2LocalExample {
  @Local count: number = 0
  @Local message: string = 'Hello V2'
  @Local items: string[] = []
  @Local userDate: Date = new Date()
  
  build() {
    Column({ space: 20 }) {
      Text(`计数: ${this.count}`)
        .fontSize(24)
      
      Text(this.message)
        .fontSize(20)
      
      Button('增加计数')
        .onClick(() => this.count++)
      
      Button('添加项目')
        .onClick(() => this.items.push(`Item ${this.items.length + 1}`))
      
      ForEach(this.items, (item: string) => {
        Text(item)
      })
      
      Button('修改日期')
        .onClick(() => {
          this.userDate.setDate(this.userDate.getDate() + 1)
        })
      
      Text(`日期: ${this.userDate.toLocaleDateString()}`)
    }
    .padding(20)
  }
}

// ========== @Param 父传子 ==========
@ComponentV2
struct V2ParamParent {
  @Local title: string = '标题'
  @Local count: number = 0
  
  build() {
    Column({ space: 20 }) {
      Text('父组件')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
      
      Text(`count: ${this.count}`)
      
      Button('增加')
        .onClick(() => this.count++)
      
      Divider()
      
      V2ParamChild({ title: this.title, count: this.count })
    }
    .padding(20)
  }
}

@ComponentV2
struct V2ParamChild {
  @Param title: string = ''
  @Param count: number = 0
  
  build() {
    Column({ space: 10 }) {
      Text('子组件')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      
      Text(`title: ${this.title}`)
      Text(`count: ${this.count}`)
    }
    .padding(10)
    .backgroundColor(0xf5f5f5)
    .borderRadius(8)
  }
}

// ========== @Param + @Event 双向通信 ==========
@ComponentV2
struct V2EventParent {
  @Local count: number = 0
  
  build() {
    Column({ space: 20 }) {
      Text(`父组件 count: ${this.count}`)
        .fontSize(20)
      
      V2EventChild({ 
        count: this.count,
        $onCountChange: (value: number) => {
          this.count = value
        }
      })
    }
    .padding(20)
  }
}

@ComponentV2
struct V2EventChild {
  @Param count: number = 0
  @Event $onCountChange: (value: number) => void = () => {}
  
  build() {
    Row({ space: 10 }) {
      Button('-')
        .onClick(() => this.$onCountChange(this.count - 1))
      
      Text(`${this.count}`)
        .fontSize(24)
        .width(50)
        .textAlign(TextAlign.Center)
      
      Button('+')
        .onClick(() => this.$onCountChange(this.count + 1))
    }
  }
}

// ========== @Require 必传参数 ==========
@ComponentV2
struct V2RequireParent {
  @Local userId: number = 123
  
  build() {
    Column() {
      V2RequireChild({ id: this.userId })
    }
  }
}

@ComponentV2
struct V2RequireChild {
  @Require @Param id: number
  @Param name: string = '默认名称'
  
  build() {
    Text(`ID: ${this.id}, Name: ${this.name}`)
  }
}

// ========== @ObservedV2 + @Trace 深度观测 ==========
@ObservedV2
class TaskModel {
  @Trace id: string = ''
  @Trace title: string = ''
  @Trace isDone: boolean = false
  @Trace subTasks: SubTask[] = []
  
  constructor(id: string, title: string) {
    this.id = id
    this.title = title
  }
  
  toggle() {
    this.isDone = !this.isDone
  }
}

@ObservedV2
class SubTask {
  @Trace name: string = ''
  @Trace completed: boolean = false
}

@ComponentV2
struct V2ObservedExample {
  @Local tasks: TaskModel[] = [
    new TaskModel('1', '任务1'),
    new TaskModel('2', '任务2'),
    new TaskModel('3', '任务3')
  ]
  
  build() {
    Column({ space: 10 }) {
      Text('任务列表')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
      
      ForEach(this.tasks, (task: TaskModel) => {
        TaskItem({ task: task })
      })
      
      Button('添加任务')
        .onClick(() => {
          this.tasks.push(new TaskModel(
            `${this.tasks.length + 1}`,
            `任务${this.tasks.length + 1}`
          ))
        })
    }
    .padding(20)
  }
}

@ComponentV2
struct TaskItem {
  @Param task: TaskModel = new TaskModel('', '')
  
  build() {
    Row() {
      Checkbox({ name: this.task.id, group: 'tasks' })
        .select(this.task.isDone)
        .onChange((value: boolean) => {
          this.task.toggle()
        })
      
      Text(this.task.title)
        .fontSize(16)
        .fontColor(this.task.isDone ? Color.Gray : Color.Black)
        .decoration({ 
          type: this.task.isDone ? TextDecorationType.LineThrough : TextDecorationType.None 
        })
        .layoutWeight(1)
        .margin({ left: 10 })
    }
    .width('100%')
    .padding(10)
    .backgroundColor(0xf5f5f5)
    .borderRadius(8)
  }
}

// ========== @Provider/@Consumer 跨组件 ==========
@ComponentV2
struct V2ProviderExample {
  @Local theme: string = 'light'
  @Local count: number = 0
  
  build() {
    Column({ space: 20 }) {
      Text(`当前主题: ${this.theme}`)
        .fontSize(20)
      
      Button('切换主题')
        .onClick(() => {
          this.theme = this.theme === 'light' ? 'dark' : 'light'
        })
      
      @Provider({ theme: this.theme, count: this.count }) {
        DeepChildComponent()
      }
    }
    .padding(20)
  }
}

@ComponentV2
struct DeepChildComponent {
  @Consumer('theme') theme: string = 'light'
  @Consumer('count') count: number = 0
  
  build() {
    Column() {
      Text(`深层组件主题: ${this.theme}`)
        .fontSize(16)
        .padding(10)
        .backgroundColor(this.theme === 'dark' ? Color.Black : Color.White)
        .fontColor(this.theme === 'dark' ? Color.White : Color.Black)
        .borderRadius(8)
      
      Text(`计数: ${this.count}`)
    }
  }
}

// ========== @Monitor 监听变化 ==========
@ComponentV2
struct V2MonitorExample {
  @Local count: number = 0
  @Local message: string = 'Hello'
  @Local history: string[] = []
  
  @Monitor('count')
  onCountChange(monitor: IMonitor) {
    const result = monitor.value('count')
    this.history.push(`count: ${result?.before} -> ${result?.now}`)
  }
  
  @Monitor('message')
  onMessageChange(monitor: IMonitor) {
    const result = monitor.value('message')
    console.info(`message changed: ${result?.before} -> ${result?.now}`)
  }
  
  build() {
    Column({ space: 20 }) {
      Text(`count: ${this.count}`)
      Text(`message: ${this.message}`)
      
      Button('count + 1')
        .onClick(() => this.count++)
      
      Button('修改 message')
        .onClick(() => this.message = `Hello ${this.count}`)
      
      Text('变化历史:')
        .fontWeight(FontWeight.Bold)
      
      ForEach(this.history, (item: string) => {
        Text(item).fontSize(12)
      })
    }
    .padding(20)
  }
}

// ========== @Computed 计算属性 ==========
@ComponentV2
struct V2ComputedExample {
  @Local firstName: string = '张'
  @Local lastName: string = '三'
  @Local price: number = 100
  @Local quantity: number = 2
  
  @Computed
  get fullName(): string {
    return `${this.firstName}${this.lastName}`
  }
  
  @Computed
  get total(): number {
    return this.price * this.quantity
  }
  
  build() {
    Column({ space: 20 }) {
      Text(`姓名: ${this.fullName}`)
        .fontSize(24)
      
      TextInput({ text: $$this.firstName, placeholder: '姓' })
        .width(100)
      
      TextInput({ text: $$this.lastName, placeholder: '名' })
        .width(100)
      
      Divider()
      
      Text(`单价: ${this.price}`)
      Text(`数量: ${this.quantity}`)
      Text(`总价: ${this.total}`)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
      
      Row({ space: 10 }) {
        Button('-').onClick(() => { if (this.quantity > 1) this.quantity-- })
        Text(`${this.quantity}`)
        Button('+').onClick(() => this.quantity++)
      }
    }
    .padding(20)
  }
}

// ========== @Computed + @Monitor 组合 ==========
@ObservedV2
class Temperature {
  @Trace celsius: number = 20
  
  @Computed
  get fahrenheit(): number {
    return this.celsius * 9 / 5 + 32
  }
  
  @Computed
  get kelvin(): number {
    return (this.fahrenheit - 32) * 5 / 9 + 273.15
  }
  
  @Monitor('fahrenheit')
  onFahrenheitChange(monitor: IMonitor) {
    console.info(`Fahrenheit: ${monitor.value()?.before} -> ${monitor.value()?.now}`)
  }
}

@ComponentV2
struct TemperatureConverter {
  temp: Temperature = new Temperature()
  
  build() {
    Column({ space: 20 }) {
      Row({ space: 20 }) {
        Button('-')
          .onClick(() => this.temp.celsius--)
        
        Text(`Celsius ${this.temp.celsius.toFixed(1)}`)
          .fontSize(24)
        
        Button('+')
          .onClick(() => this.temp.celsius++)
      }
      
      Text(`Fahrenheit ${this.temp.fahrenheit.toFixed(2)}`)
        .fontSize(20)
      
      Text(`Kelvin ${this.temp.kelvin.toFixed(2)}`)
        .fontSize(20)
    }
    .padding(20)
  }
}

// ==================== V1 状态管理 ====================

// ========== @State 基础 ==========
@Entry
@Component
struct V1StateExample {
  @State count: number = 0
  @State message: string = 'Hello'
  
  build() {
    Column({ space: 20 }) {
      Text(`计数: ${this.count}`)
        .fontSize(24)
      
      Text(this.message)
        .fontSize(20)
      
      Row({ space: 10 }) {
        Button('-')
          .onClick(() => this.count--)
        
        Button('+')
          .onClick(() => this.count++)
      }
    }
    .padding(20)
  }
}

// ========== @Prop 父传子 ==========
@Entry
@Component
struct V1PropExample {
  @State title: string = '标题'
  @State count: number = 0
  
  build() {
    Column({ space: 20 }) {
      Text('父组件')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
      
      Text(`count: ${this.count}`)
      
      Button('增加')
        .onClick(() => this.count++)
      
      Divider()
      
      ChildComponent({ title: this.title, count: this.count })
    }
    .padding(20)
  }
}

@Component
struct ChildComponent {
  @Prop title: string = ''
  @Prop count: number = 0
  
  build() {
    Column({ space: 10 }) {
      Text('子组件')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      
      Text(`title: ${this.title}`)
      Text(`count: ${this.count}`)
    }
    .padding(10)
    .backgroundColor(0xf5f5f5)
    .borderRadius(8)
  }
}

// ========== @Link 双向绑定 ==========
@Entry
@Component
struct V1LinkExample {
  @State count: number = 0
  
  build() {
    Column({ space: 20 }) {
      Text(`父组件 count: ${this.count}`)
        .fontSize(20)
      
      CounterComponent({ count: $count })
    }
    .padding(20)
  }
}

@Component
struct CounterComponent {
  @Link count: number
  
  build() {
    Row({ space: 10 }) {
      Button('-')
        .onClick(() => this.count--)
      
      Text(`${this.count}`)
        .fontSize(24)
        .width(50)
        .textAlign(TextAlign.Center)
      
      Button('+')
        .onClick(() => this.count++)
    }
  }
}

// ========== @Observed/@ObjectLink 嵌套对象 ==========
@Observed
class UserModel {
  name: string = ''
  age: number = 0
  address: AddressModel = new AddressModel()
  
  constructor(name: string, age: number) {
    this.name = name
    this.age = age
  }
}

@Observed
class AddressModel {
  city: string = ''
  street: string = ''
}

@Entry
@Component
struct V1ObservedExample {
  @State user: UserModel = new UserModel('张三', 25)
  
  build() {
    Column({ space: 20 }) {
      Text(`姓名: ${this.user.name}`)
      Text(`年龄: ${this.user.age}`)
      
      UserInfo({ user: this.user })
      
      Button('修改姓名')
        .onClick(() => {
          this.user.name = '李四'
        })
    }
    .padding(20)
  }
}

@Component
struct UserInfo {
  @ObjectLink user: UserModel
  
  build() {
    Column({ space: 10 }) {
      Text('用户信息卡片')
        .fontWeight(FontWeight.Bold)
      
      Text(`姓名: ${this.user.name}`)
      Text(`年龄: ${this.user.age}`)
      
      Button('年龄+1')
        .onClick(() => this.user.age++)
    }
    .padding(15)
    .backgroundColor(0xf5f5f5)
    .borderRadius(8)
  }
}

// ========== @Provide/@Consume 跨组件 ==========
@Entry
@Component
struct V1ProvideExample {
  @Provide('theme') theme: string = 'light'
  @Provide('count') count: number = 0
  
  build() {
    Column({ space: 20 }) {
      Text(`当前主题: ${this.theme}`)
      
      Button('切换主题')
        .onClick(() => {
          this.theme = this.theme === 'light' ? 'dark' : 'light'
        })
      
      DeepChild()
    }
    .padding(20)
  }
}

@Component
struct DeepChild {
  @Consume('theme') theme: string
  @Consume('count') count: number
  
  build() {
    Column() {
      Text(`主题: ${this.theme}`)
        .backgroundColor(this.theme === 'dark' ? Color.Black : Color.White)
        .fontColor(this.theme === 'dark' ? Color.White : Color.Black)
        .padding(10)
      
      Text(`计数: ${this.count}`)
    }
  }
}

// ========== @Watch 监听变化 ==========
@Entry
@Component
struct V1WatchExample {
  @State @Watch('onCountChange') count: number = 0
  @State @Watch('onMessageChange') message: string = 'Hello'
  
  onCountChange(propName: string) {
    console.info(`${propName} changed to ${this.count}`)
  }
  
  onMessageChange(propName: string) {
    console.info(`${propName} changed to ${this.message}`)
  }
  
  build() {
    Column({ space: 20 }) {
      Text(`count: ${this.count}`)
      Text(`message: ${this.message}`)
      
      Button('count + 1')
        .onClick(() => {
          if (this.count < 100) {
            this.count++
          }
        })
      
      Button('修改 message')
        .onClick(() => this.message = `Hello ${this.count}`)
    }
    .padding(20)
  }
}

// ==================== V1/V2 混用 (API 19+) ====================

// ========== V1 → V2 传递 ==========
import { UIUtils } from '@kit.ArkUI'

@Observed
class SharedData {
  value: number = 0
}

@Component
struct V1Parent {
  @State data: SharedData = new SharedData()
  
  build() {
    Column() {
      Text(`V1: ${this.data.value}`)
        .onClick(() => this.data.value++)
      
      V2Child({ data: UIUtils.enableV2Compatibility(this.data) })
    }
  }
}

@ComponentV2
struct V2Child {
  @Param data: SharedData = new SharedData()
  
  build() {
    Text(`V2: ${this.data.value}`)
      .onClick(() => this.data.value++)
  }
}

// ========== V2 → V1 传递 ==========
@ComponentV2
struct V2Parent {
  @Local data: SharedData = UIUtils.enableV2Compatibility(UIUtils.makeV1Observed(new SharedData()))
  
  build() {
    Column() {
      Text(`V2: ${this.data.value}`)
        .onClick(() => this.data.value++)
      
      V1Child({ data: this.data })
    }
  }
}

@Component
struct V1Child {
  @ObjectLink data: SharedData
  
  build() {
    Text(`V1: ${this.data.value}`)
      .onClick(() => this.data.value++)
  }
}