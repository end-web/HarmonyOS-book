# MVVM架构工程目录结构规范

## MVVM架构概述

MVVM（Model-View-ViewModel）是ArkUI推荐的架构模式，将应用分为三个核心部分，实现数据、视图与逻辑的分离。

### 三层架构说明

#### Model层
- **职责**：数据访问层，负责数据结构定义、数据管理（获取、存储、更新等）以及业务逻辑处理
- **特点**：以数据为中心，不直接与用户界面交互
- **命名规范**：`XxxModel.ets`

#### View层
- **职责**：用户界面层，负责UI展示和用户交互
- **特点**：不包含业务逻辑，通过绑定ViewModel层的数据实现动态更新
- **组件分类**：
  - **页面组件**（pages）：提供整体页面布局，实现页面跳转、前后台事件处理等
  - **业务组件**（views）：被页面引用，构建出页面，包含ViewModel数据
  - **通用组件**（shares/common）：与项目无关的多项目共享组件，不包含ViewModel数据

#### ViewModel层
- **职责**：表示逻辑层，作为连接Model和View的桥梁
- **特点**：
  - 按照页面组织数据
  - 每个页面数据进行懒加载
  - 向上刷新UI，向下更新数据
- **命名规范**：`XxxViewModel.ets`

### 架构核心原则

1. **不可跨层访问**
   - View层不可以直接调用Model层的数据，只能通过ViewModel提供的方法进行调用
   - Model层不能直接操作UI，只能通知ViewModel层数据有更新

2. **下层不可访问上层数据**
   - 下层数据通过通知模式更新上层数据
   - ViewModel层的逻辑处理不应该依赖View层界面上的某个值

3. **非父子组件间不可直接访问**
   - 禁止直接访问父组件（必须使用事件或是订阅能力）
   - 禁止直接访问兄弟组件

## 工程目录结构

### 基础结构（推荐）

```
entry/
├── src/
│   ├── main/
│   │   ├── ets/
│   │   │   ├── model/                    # Model层 - 数据模型
│   │   │   │   ├── TaskModel.ets         # 单个任务数据结构
│   │   │   │   └── TaskListModel.ets     # 任务列表数据模型
│   │   │   │
│   │   │   ├── viewmodel/                # ViewModel层 - 视图模型
│   │   │   │   ├── TaskViewModel.ets     # 单个任务视图模型
│   │   │   │   └── TaskListViewModel.ets # 任务列表视图模型
│   │   │   │
│   │   │   ├── view/                     # View层 - 业务组件
│   │   │   │   ├── TitleView.ets         # 标题组件
│   │   │   │   ├── ListView.ets          # 列表组件
│   │   │   │   └── BottomView.ets        # 底部操作组件
│   │   │   │
│   │   │   ├── pages/                    # 页面组件
│   │   │   │   ├── Index.ets             # 主页面
│   │   │   │   └── SettingPage.ets       # 设置页面
│   │   │   │
│   │   │   ├── common/                   # 通用组件（可选）
│   │   │   │   └── CommonButton.ets
│   │   │   │
│   │   │   ├── utils/                    # 工具类（可选）
│   │   │   │   └── Logger.ets
│   │   │   │
│   │   │   └── entryability/             # Ability入口
│   │   │       └── EntryAbility.ets
│   │   │
│   │   └── resources/                    # 资源文件
│   │       ├── base/
│   │       │   ├── element/              # 字符串、颜色等资源
│   │       │   ├── media/                # 图片资源
│   │       │   └── profile/              # 配置文件
│   │       └── rawfile/                  # 原始文件
│   │           └── default_tasks.json
│   │
│   └── module.json5                      # 模块配置
│
└── build-profile.json5                   # 构建配置
```

### 完整示例结构（带多Ability）

```
entry/
├── src/
│   ├── main/
│   │   ├── ets/
│   │   │   ├── model/                    # Model层
│   │   │   │   ├── TaskModel.ets
│   │   │   │   └── TaskListModel.ets
│   │   │   │
│   │   │   ├── viewmodel/                # ViewModel层
│   │   │   │   ├── TaskViewModel.ets
│   │   │   │   └── TaskListViewModel.ets
│   │   │   │
│   │   │   ├── view/                     # 业务组件
│   │   │   │   ├── TitleView.ets
│   │   │   │   ├── ListView.ets
│   │   │   │   └── BottomView.ets
│   │   │   │
│   │   │   ├── pages/                    # 页面组件
│   │   │   │   ├── Index.ets
│   │   │   │   ├── TodoListPage.ets
│   │   │   │   └── SettingPage.ets
│   │   │   │
│   │   │   ├── common/                   # 通用组件
│   │   │   │   └── CommonComponent.ets
│   │   │   │
│   │   │   ├── utils/                    # 工具类
│   │   │   │   └── Logger.ets
│   │   │   │
│   │   │   ├── entryability/             # 主Ability
│   │   │   │   └── EntryAbility.ets
│   │   │   │
│   │   │   └── settingability/           # 设置Ability（如需要）
│   │   │       └── SettingAbility.ets
│   │   │
│   │   └── resources/
│   │       ├── base/
│   │       │   ├── element/
│   │       │   │   ├── string.json
│   │       │   │   └── color.json
│   │       │   ├── media/
│   │       │   │   ├── finished.png
│   │       │   │   └── unfinished.png
│   │       │   └── profile/
│   │       │       └── main_pages.json
│   │       └── rawfile/
│   │           └── default_tasks.json
```

## 各层实现示例

### Model层示例

**TaskModel.ets**
```typescript
export default class TaskModel {
  public taskName: string = 'Todo';
  public isFinish: boolean = false;
}
```

**TaskListModel.ets**
```typescript
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import TaskModel from './TaskModel';

export default class TaskListModel {
  public tasks: TaskModel[] = [];

  constructor(tasks: TaskModel[]) {
    this.tasks = tasks;
  }

  async loadTasks(context: common.UIAbilityContext) {
    let getJson = await context.resourceManager.getRawFileContent('default_tasks.json');
    let textDecoderOptions: util.TextDecoderOptions = { ignoreBOM: true };
    let textDecoder = util.TextDecoder.create('utf-8', textDecoderOptions);
    let result = textDecoder.decodeToString(getJson);
    this.tasks = JSON.parse(result).map((task: TaskModel) => {
      let newTask = new TaskModel();
      newTask.taskName = task.taskName;
      newTask.isFinish = task.isFinish;
      return newTask;
    });
  }
}
```

### ViewModel层示例

**TaskViewModel.ets**
```typescript
import TaskModel from '../model/TaskModel';

@ObservedV2
export default class TaskViewModel {
  @Trace public taskName: string = 'Todo';
  @Trace public isFinish: boolean = false;

  updateTask(task: TaskModel) {
    this.taskName = task.taskName;
    this.isFinish = task.isFinish;
  }

  updateIsFinish(): void {
    this.isFinish = !this.isFinish;
  }
}
```

**TaskListViewModel.ets**
```typescript
import { common } from '@kit.AbilityKit';
import { Type } from '@kit.ArkUI';
import TaskListModel from '../model/TaskListModel';
import TaskViewModel from './TaskViewModel';

@ObservedV2
export default class TaskListViewModel {
  @Type(TaskViewModel)
  @Trace public tasks: TaskViewModel[] = [];

  async loadTasks(context: common.UIAbilityContext) {
    let taskList = new TaskListModel([]);
    await taskList.loadTasks(context);
    for (let task of taskList.tasks) {
      let taskViewModel = new TaskViewModel();
      taskViewModel.updateTask(task);
      this.tasks.push(taskViewModel);
    }
  }

  finishAll(ifFinish: boolean): void {
    for (let task of this.tasks) {
      task.isFinish = ifFinish;
    }
  }

  addTask(newTask: TaskViewModel): void {
    this.tasks.push(newTask);
  }

  removeTask(removedTask: TaskViewModel): void {
    this.tasks.splice(this.tasks.indexOf(removedTask), 1);
  }
}
```

### View层示例

**TitleView.ets**
```typescript
@ComponentV2
export default struct TitleView {
  @Param tasksUnfinished: number = 0;

  build() {
    Column() {
      Text('To do')
        .fontSize(40)
        .margin(10)
      Text(`Unfinished: ${this.tasksUnfinished}`)
        .margin({ left: 10, bottom: 10 })
    }
  }
}
```

**ListView.ets**
```typescript
import TaskViewModel from '../viewmodel/TaskViewModel';
import TaskListViewModel from '../viewmodel/TaskListViewModel';

@ComponentV2
struct TaskItem {
  @Param task: TaskViewModel = new TaskViewModel();
  @Event deleteTask: () => void = () => {};

  build() {
    Row() {
      Image(this.task.isFinish ? $r('app.media.finished') : $r('app.media.unfinished'))
        .width(28)
        .height(28)
      Text(this.task.taskName)
        .decoration({ type: this.task.isFinish ? TextDecorationType.LineThrough : TextDecorationType.None })
      Button('Delete')
        .onClick(() => this.deleteTask())
    }
    .onClick(() => this.task.updateIsFinish())
  }
}

@ComponentV2
export default struct ListView {
  @Param taskList: TaskListViewModel = new TaskListViewModel();

  build() {
    Repeat<TaskViewModel>(this.taskList.tasks)
      .each((obj: RepeatItem<TaskViewModel>) => {
        TaskItem({
          task: obj.item,
          deleteTask: () => this.taskList.removeTask(obj.item)
        })
      })
  }
}
```

### Page层示例

**TodoListPage.ets**
```typescript
import TaskListViewModel from '../viewmodel/TaskListViewModel';
import { common } from '@kit.AbilityKit';
import { PersistenceV2 } from '@kit.ArkUI';
import TitleView from '../view/TitleView';
import ListView from '../view/ListView';
import BottomView from '../view/BottomView';

@Entry
@ComponentV2
struct TodoList {
  @Local taskList: TaskListViewModel = PersistenceV2.connect(
    TaskListViewModel, 
    'TaskList', 
    () => new TaskListViewModel()
  )!;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  async aboutToAppear() {
    if (this.taskList.tasks.length === 0) {
      await this.taskList.loadTasks(this.context);
    }
  }

  @Computed
  get tasksUnfinished(): number {
    return this.taskList.tasks.filter(task => !task.isFinish).length;
  }

  build() {
    Column() {
      TitleView({ tasksUnfinished: this.tasksUnfinished })
      ListView({ taskList: this.taskList })
      BottomView({ taskList: this.taskList })
    }
    .height('100%')
    .width('100%')
  }
}
```

## 状态管理装饰器选择

### V1版本装饰器
- `@State`：组件内状态
- `@Prop`：父子单向传递
- `@Link`：父子双向传递
- `@Observed`、`@ObjectLink`：嵌套对象观测
- `@Track`：类属性追踪

### V2版本装饰器（推荐）
- `@Local`：组件内部状态观测
- `@Param`：组件接收外部输入
- `@Event`：组件对外输出
- `@ObservedV2`、`@Trace`：类属性观测变化
- `@Monitor`：监听状态变量
- `@Computed`：计算属性
- `AppStorageV2`：应用全局状态存储
- `PersistenceV2`：持久化状态存储

## 最佳实践建议

1. **命名规范**
   - Model层：`XxxModel.ets`
   - ViewModel层：`XxxViewModel.ets`
   - View层组件：`XxxView.ets` 或 `XxxComponent.ets`
   - 页面：`XxxPage.ets` 或功能性命名如 `Index.ets`

2. **文件组织**
   - 每个功能模块建议创建独立的Model、ViewModel、View
   - 复杂页面可拆分为多个子组件
   - 通用组件放在`common`目录

3. **数据流向**
   - 单向数据流：Model → ViewModel → View
   - 事件向上传递：View → ViewModel → Model

4. **懒加载**
   - ViewModel数据按页面组织，实现懒加载
   - 避免在应用启动时加载所有数据

5. **组件复用**
   - 业务组件：包含ViewModel数据，不可跨项目共享
   - 通用组件：不包含ViewModel数据，可跨项目共享

## 参考资源

- [MVVM模式（V1）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-mvvm)
- [MVVM模式（V2）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-mvvm-v2)

