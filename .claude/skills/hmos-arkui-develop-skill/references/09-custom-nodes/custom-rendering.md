# 自定义渲染 (XComponent)

XComponent是一种渲染组件，用于EGL/OpenGLES和媒体数据写入，满足高级自定义渲染需求。

## 适用场景

| 场景类型 | 使用场景 |
|---------|---------|
| 高性能渲染 | 游戏画面、3D图形、复杂动画 |
| 媒体数据处理 | 相机预览、视频播放、图像处理 |

> 简单2D绘制请使用Canvas，参考 [图形绘制](../04-ui-components/graphics-drawing.md)

---

## 渲染方式对比

| 方式 | 适用场景 | 特点 |
|-----|---------|------|
| Canvas | 简单2D绘制 | ArkTS侧实现，开发简单 |
| XComponent + NAPI | 高性能渲染 | Native侧实现，性能最优 |
| DrawingCanvas | 高级2D绘制 | 使用Drawing模块，功能丰富 |

---

## XComponent渲染原理

XComponent持有一个Surface，开发者通过NativeWindow等接口申请并提交Buffer至图形队列：

```
应用RequestBuffer → 生产帧数据 → FlushBuffer提交 → 系统渲染获取帧 → 渲染到屏幕 → ReleaseBuffer释放
```

XComponent负责创建Surface并嵌入UI界面，Surface默认位置和大小与XComponent组件一致，可通过`setXComponentSurfaceRect`自定义调整。

---

## 创建XComponent

```typescript
XComponent({
  id: 'xcomponent',
  type: XComponentType.SURFACE,
  libraryname: 'nativerender'
})
  .width('100%')
  .height('100%')
  .onLoad(() => {
    // Surface创建完成
  })
```

### XComponentType

| 类型 | 说明 |
|-----|------|
| SURFACE | 绘制内容单独展示到屏幕 |
| COMPONENT | 作为容器执行非UI逻辑，动态加载显示内容 |
| TEXTURE | 绘制内容与组件合成后展示 |

---

## Surface生命周期管理

### 方式一：XComponentController（ArkTS侧）

适用于相机预览、视频播放等已封装接口场景，或对跨语言性能损耗不敏感的开发。

```typescript
class MyXComponentController extends XComponentController {
  onSurfaceCreated(surfaceId: string): void {
    // XComponent创建完成且Surface创建后触发
    console.info(`Surface created: ${surfaceId}`);
    nativeRender.SetSurfaceId(BigInt(surfaceId));
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    // Surface大小变化触发重新布局后触发
    console.info(`Surface changed: ${rect.surfaceWidth}x${rect.surfaceHeight}`);
    nativeRender.ChangeSurface(BigInt(surfaceId), rect.surfaceWidth, rect.surfaceHeight);
  }

  onSurfaceDestroyed(surfaceId: string): void {
    // XComponent组件被销毁时触发
    console.info(`Surface destroyed: ${surfaceId}`);
    nativeRender.DestroySurface(BigInt(surfaceId));
  }
}

@Entry
@Component
struct XComponentPage {
  controller: XComponentController = new MyXComponentController();

  build() {
    XComponent({
      type: XComponentType.SURFACE,
      controller: this.controller
    })
      .width('100%')
      .height('100%')
  }
}
```

#### XComponentController方法

| 方法 | 说明 |
|-----|------|
| getXComponentSurfaceId() | 获取Surface ID |
| setXComponentSurfaceRect(rect) | 设置Surface显示区域（宽高、偏移） |
| getXComponentSurfaceRect() | 获取Surface显示区域 |
| lockCanvas() | 获取DrawingCanvas画布对象 |
| unlockCanvasAndPost(canvas) | 释放画布并提交绘制 |
| setXComponentSurfaceRotation(options) | 设置屏幕旋转时是否锁定方向 |
| getXComponentSurfaceRotation() | 获取旋转锁定设置 |

### 方式二：OH_ArkUI_SurfaceHolder（Native侧）

适用于复杂交互逻辑、追求极致性能、需自主控制Surface的场景。

**ArkTS侧：**

```typescript
import native from 'libnativerender.so';

XComponent({ type: XComponentType.SURFACE })
  .id('XComponentSurfaceHolder')
  .onAttach(() => {
    let xcNode = this.getUIContext().getAttachedFrameNodeById('XComponentSurfaceHolder');
    if (xcNode) {
      native.bindNode('XComponentSurfaceHolder', xcNode);
    }
  })
  .onDetach(() => {
    native.unbindNode('XComponentSurfaceHolder');
  })
```

**Native侧（C++）：**

```cpp
#include <arkui/native_node.h>
#include <arkui/native_xcomponent.h>

static std::unordered_map<std::string, ArkUI_NodeHandle> nodeHandleMap_;
static std::unordered_map<void*, OH_ArkUI_SurfaceHolder*> surfaceHolderMap_;

napi_value BindNode(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    // 获取节点ID
    std::string nodeId = value2String(env, args[0]);
    
    // 获取节点句柄
    ArkUI_NodeHandle handle;
    OH_ArkUI_GetNodeHandleFromNapiValue(env, args[1], &handle);
    
    // 创建SurfaceHolder
    OH_ArkUI_SurfaceHolder *holder = OH_ArkUI_SurfaceHolder_Create(handle);
    nodeHandleMap_[nodeId] = handle;
    surfaceHolderMap_[handle] = holder;
    
    // 创建SurfaceCallback并注册生命周期回调
    OH_ArkUI_SurfaceCallback *callback = OH_ArkUI_SurfaceCallback_Create();
    OH_ArkUI_SurfaceCallback_SetSurfaceCreatedEvent(callback, OnSurfaceCreated);
    OH_ArkUI_SurfaceCallback_SetSurfaceChangedEvent(callback, OnSurfaceChanged);
    OH_ArkUI_SurfaceCallback_SetSurfaceDestroyedEvent(callback, OnSurfaceDestroyed);
    OH_ArkUI_SurfaceHolder_AddSurfaceCallback(holder, callback);
    
    return nullptr;
}

void OnSurfaceCreated(OH_ArkUI_SurfaceHolder *holder) {
    // 获取NativeWindow进行渲染
    OHNativeWindow *window = OH_ArkUI_XComponent_GetNativeWindow(holder);
    // 初始化EGL/GLES环境...
}

void OnSurfaceChanged(OH_ArkUI_SurfaceHolder *holder, uint64_t width, uint64_t height) {
    // 调整渲染尺寸
}

void OnSurfaceDestroyed(OH_ArkUI_SurfaceHolder *holder) {
    // 释放渲染资源
}
```

---

## 开发范式选择

| 开发范式 | 生命周期管理 | 适用场景 |
|---------|------------|---------|
| ArkTS声明式UI + XComponentController | ArkTS侧 | 简单场景，使用已封装接口 |
| ArkTS声明式UI + OH_ArkUI_SurfaceHolder | Native侧 | 追求性能，复杂交互 |
| ArkTS自定义节点 + XComponentController | ArkTS侧 | 需动态创建组件 |
| ArkTS自定义节点 + OH_ArkUI_SurfaceHolder | Native侧 | 动态创建 + 高性能 |
| NDK接口 + OH_ArkUI_SurfaceHolder | Native侧 | 全Native开发 |

---

## DrawingCanvas绘制

在XComponent上使用Drawing模块进行2D绘制。

```typescript
import { drawing } from '@kit.ArkGraphics2D';

XComponent({ type: XComponentType.SURFACE, controller: this.controller })
  .onLoad(() => {
    let canvas = this.controller.lockCanvas();
    if (canvas) {
      // 清空画布
      canvas.drawColor(255, 255, 255, 255);
      
      // 创建画刷并绘制
      let brush = new drawing.Brush();
      brush.setColor({ alpha: 255, red: 39, green: 135, blue: 217 });
      canvas.attachBrush(brush);
      canvas.drawRect({ left: 100, right: 300, top: 100, bottom: 300 });
      canvas.detachBrush();
      
      // 提交绘制
      this.controller.unlockCanvasAndPost(canvas);
    }
  })
```

> **注意：** lockCanvas/unlockCanvasAndPost必须配对使用，不支持同时使用NDK侧NativeWindow。

---

## 常用属性

| 属性 | 说明 |
|-----|------|
| enableAnalyzer(enable: boolean) | 启用AI分析（主体识别、文字识别） |
| enableSecure(isSecure: boolean) | 防止截屏录屏 |
| hdrBrightness(brightness: number) | 调整HDR视频亮度（0.0-1.0） |

---

## 约束与限制

1. **SURFACE类型不支持：** 动态属性设置、自定义绘制、背景设置(backgroundColor除外)、图像效果(shadow除外)
2. **renderFit默认值：** TEXTURE和SURFACE类型默认为RenderFit.RESIZE_FILL
3. **Surface尺寸限制：** surfaceWidth和surfaceHeight不可超过8192px
4. **沉浸式场景：** 默认布局的SurfaceRect不包括安全区，需主动设置

---

## 性能优化建议

1. **及时释放资源** - onSurfaceDestroyed中释放Native资源
2. **控制绘制频率** - 使用帧率控制接口
3. **避免重复创建** - Surface复用而非重复创建
4. **Surface尺寸控制** - 通过setXComponentSurfaceRect精确设置