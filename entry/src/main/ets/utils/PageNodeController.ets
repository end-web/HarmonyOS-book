import { NodeController, FrameNode, RenderNode, DrawContext } from '@kit.ArkUI';
import { drawing, common2D } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';

// 翻页绘制位置
export enum DrawPosition {
  DP_NONE = -1,
  DP_TOP = 0,
  DP_MIDDLE = 1,
  DP_BOTTOM = 2
}

// 翻页绘制状态
export enum DrawState {
  DS_NONE = 0,
  DS_MOVING = 1,
  DS_RELEASE = 2
}

// 翻页方向
export enum MoveForward {
  MF_NONE = 0,
  MF_FORWARD = 1,  // 向前翻（右->左）
  MF_BACKWARD = 2  // 向后翻（左->右）
}

// 坐标点
class MyPoint {
  x: number = 0;
  y: number = 0;

  constructor(x: number = 0, y: number = 0) {
    this.x = x;
    this.y = y;
  }
}

// 常量
const FRACTION_60 = 0.6;
const TIMER_DURATION = 16; // ~60fps
const DISTANCE_FRACTION = 30;

// 全局状态（通过 AppStorage 传递）
let windowWidth: number = 0;
let windowHeight: number = 0;
let positionX: number = -1;
let positionY: number = -1;
let drawPosition: DrawPosition = DrawPosition.DP_NONE;
let drawState: DrawState = DrawState.DS_NONE;
let pagePixelMap: image.PixelMap | null = null;
let isFinished: boolean = false;

// 贝塞尔曲线控制点
let pointA = new MyPoint();
let pointB = new MyPoint();
let pointC = new MyPoint();
let pointD = new MyPoint();
let pointE = new MyPoint();
let pointF = new MyPoint();
let pointG = new MyPoint();
let pointH = new MyPoint();
let pointI = new MyPoint();
let pointJ = new MyPoint();
let pointK = new MyPoint();

// 阴影距离
let lPathAShadowDis: number = 0;
let rPathAShadowDis: number = 0;

// Path 对象
let pathA: drawing.Path | null = null;
let pathC: drawing.Path | null = null;

// Brush 对象
let pathABrush: drawing.Brush | null = null;
let pathCBrush: drawing.Brush | null = null;

// 初始化绘制环境
function initDrawing(): void {
  if (!pathA) {
    pathA = new drawing.Path();
  }
  if (!pathC) {
    pathC = new drawing.Path();
  }
  if (!pathABrush) {
    pathABrush = new drawing.Brush();
    pathABrush.setColor(0xFFFFFFFF);
  }
  if (!pathCBrush) {
    pathCBrush = new drawing.Brush();
    pathCBrush.setColor(0xCCFFFFFF); // 半透明白色，模拟纸张背面
  }
}

// 计算点 A 的位置（根据触摸点）
function calcPointAByTouchPoint(touchPoint: MyPoint): void {
  let r = FRACTION_60 * windowWidth;
  pointA.x = touchPoint.x;

  if (pointF.y === windowHeight) {
    let tmpY = windowHeight - Math.abs(Math.sqrt(Math.pow(r, 2) - Math.pow(touchPoint.x - (windowWidth - r), 2)));
    pointA.y = touchPoint.y >= tmpY ? touchPoint.y : tmpY;
  } else {
    let tmpY = Math.abs(Math.sqrt(Math.pow(r, 2) - Math.pow(touchPoint.x - (windowWidth - r), 2)));
    pointA.y = touchPoint.y >= tmpY ? tmpY : touchPoint.y;
  }
}

// 计算两条线的交点
function getIntersectionPoint(p1: MyPoint, p2: MyPoint, p3: MyPoint, p4: MyPoint): MyPoint {
  let x1 = p1.x, y1 = p1.y, x2 = p2.x, y2 = p2.y;
  let x3 = p3.x, y3 = p3.y, x4 = p4.x, y4 = p4.y;

  let denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
  if (Math.abs(denom) < 0.001) {
    return new MyPoint((x1 + x2) / 2, (y1 + y2) / 2);
  }

  let t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom;
  return new MyPoint(x1 + t * (x2 - x1), y1 + t * (y2 - y1));
}

// 计算所有路径点
function calcPointsXY(): void {
  pointG.x = (pointA.x + pointF.x) / 2;
  pointG.y = (pointA.y + pointF.y) / 2;

  let fgX = pointF.x - pointG.x;
  let fgY = pointF.y - pointG.y;
  let fgLen = Math.sqrt(fgX * fgX + fgY * fgY);

  if (fgLen < 1) {
    isFinished = true;
    return;
  }

  pointE.x = pointG.x - (pointF.y - pointG.y) * (pointF.y - pointG.y) / (pointF.x - pointG.x);
  pointE.y = pointF.y;

  pointH.x = pointF.x;
  pointH.y = pointG.y - (pointF.x - pointG.x) * (pointF.x - pointG.x) / (pointF.y - pointG.y);

  pointC.x = pointE.x - (pointF.x - pointE.x) / 2;
  pointC.y = pointF.y;

  pointJ.x = pointF.x;
  pointJ.y = pointH.y - (pointF.y - pointH.y) / 2;

  pointB = getIntersectionPoint(pointA, pointE, pointC, pointJ);
  pointK = getIntersectionPoint(pointA, pointH, pointC, pointJ);

  pointD.x = (pointC.x + 2 * pointE.x + pointB.x) / 4;
  pointD.y = (2 * pointE.y + pointC.y + pointB.y) / 4;

  pointI.x = (pointJ.x + 2 * pointH.x + pointK.x) / 4;
  pointI.y = (2 * pointH.y + pointJ.y + pointK.y) / 4;

  // 计算阴影距离
  let lA = pointA.y - pointE.y;
  let lB = pointE.x - pointA.x;
  let lC = pointA.x * pointE.y - pointE.x * pointA.y;
  lPathAShadowDis = Math.abs((lA * pointD.x + lB * pointD.y + lC) / Math.hypot(lA, lB));

  let rA = pointA.y - pointH.y;
  let rB = pointH.x - pointA.x;
  let rC = pointA.x * pointH.y - pointH.x * pointA.y;
  rPathAShadowDis = Math.abs((rA * pointI.x + rB * pointI.y + rC) / Math.hypot(rA, rB));

  // 检查绘制区域是否还在窗口内
  if (!checkDrawingAreaInWindow()) {
    isFinished = true;
  }
}

// 检查绘制区域是否在窗口内
function checkDrawingAreaInWindow(): boolean {
  if (pointA.x < 0 || pointA.y < 0 || pointA.x > windowWidth || pointA.y > windowHeight) {
    return false;
  }
  return true;
}

// 初始化数据
function init(): void {
  let x = positionX;
  let y = positionY;
  pointA = new MyPoint(x, y);

  if (drawPosition === DrawPosition.DP_TOP) {
    pointF = new MyPoint(windowWidth, 0);
    if (drawState !== DrawState.DS_RELEASE) {
      calcPointAByTouchPoint(new MyPoint(x, y));
    }
  } else if (drawPosition === DrawPosition.DP_BOTTOM) {
    pointF = new MyPoint(windowWidth, windowHeight);
    if (drawState !== DrawState.DS_RELEASE) {
      calcPointAByTouchPoint(new MyPoint(x, y));
    }
  } else {
    // 中间区域
    pointA.y = windowHeight - 1;
    pointF.x = windowWidth;
    pointF.y = windowHeight;
  }

  calcPointsXY();
}

// 绘制阴影区域
function drawShadow(canvas: drawing.Canvas, shaderEffect: drawing.ShaderEffect, rect: common2D.Rect): void {
  let tmpBrush = new drawing.Brush();
  tmpBrush.setShaderEffect(shaderEffect);
  canvas.attachBrush(tmpBrush);
  canvas.drawRect(rect.left, rect.top, rect.right, rect.bottom);
  canvas.detachBrush();
}

// 绘制下一页上的阴影
function drawPathBShadow(canvas: drawing.Canvas): void {
  canvas.save();
  let deepColor = 0xFF111111;
  let lightColor = 0x00111111;
  let gradientColors = [deepColor, lightColor];

  let aToF = Math.hypot(pointA.x - pointF.x, pointA.y - pointF.y);
  let viewDiagonalLength = Math.hypot(windowWidth, windowHeight);

  let left = 0;
  let right = 0;
  let top = pointC.y;
  let bottom = viewDiagonalLength + pointC.y;

  if (pointF.x === windowWidth && pointF.y === 0) {
    left = pointC.x;
    right = pointC.x + aToF / 4;
  } else {
    left = pointC.x - aToF / 4;
    right = pointC.x;
  }

  let deltaX = pointH.y - pointF.y;
  let deltaY = pointE.x - pointF.x;
  let radians = Math.atan2(deltaY, deltaX);
  let rotateDegrees = radians * 180 / Math.PI;

  let startPt: common2D.Point = { x: pointF.y === 0 ? right : left, y: top };
  let endPt: common2D.Point = { x: pointF.y === 0 ? left : right, y: top };
  let shaderEffect = drawing.ShaderEffect.createLinearGradient(
    endPt,
    startPt,
    gradientColors,
    drawing.TileMode.MIRROR
  );

  canvas.rotate(rotateDegrees, pointC.x, pointC.y);

  let rect: common2D.Rect = { left, top, right, bottom };
  drawShadow(canvas, shaderEffect, rect);
  canvas.restore();
}

// 绘制翻页背面
function drawPathC(canvas: drawing.Canvas): void {
  if (!pathC || !pagePixelMap) return;

  canvas.attachBrush(pathABrush!);
  pathC.reset();
  pathC.moveTo(pointI.x, pointI.y);
  pathC.lineTo(pointD.x, pointD.y);
  pathC.lineTo(pointB.x, pointB.y);
  pathC.lineTo(pointA.x, pointA.y);
  pathC.lineTo(pointK.x, pointK.y);
  pathC.close();
  canvas.drawPath(pathC);

  // 绘制背面内容
  canvas.save();
  canvas.clipPath(pathC);

  // 设置翻转矩阵
  let eh = Math.hypot(pointF.x - pointE.x, pointH.y - pointF.y);
  if (eh > 0) {
    let sin0 = (pointF.x - pointE.x) / eh;
    let cos0 = (pointH.y - pointF.y) / eh;
    let value = [0, 0, 0, 0, 0, 0, 0, 0, 1.0];
    value[0] = -(1 - 2 * sin0 * sin0);
    value[1] = 2 * sin0 * cos0;
    value[3] = 2 * sin0 * cos0;
    value[4] = 1 - 2 * sin0 * sin0;

    let matrix = new drawing.Matrix();
    matrix.setMatrix(value);
    matrix.preTranslate(-pointE.x, -pointE.y);
    matrix.postTranslate(pointE.x, pointE.y);
    canvas.concatMatrix(matrix);
  }

  // 绘制页面内容
  let verts = [0, 0, windowWidth, 0, 0, windowHeight, windowWidth, windowHeight];
  canvas.drawPixelMapMesh(pagePixelMap, 1, 1, verts, 0, null, 0);
  canvas.restore();

  // 绘制背面颜色遮罩
  canvas.detachBrush();
  canvas.attachBrush(pathCBrush!);
  canvas.drawPath(pathC);
  canvas.detachBrush();

  // 绘制背面阴影
  canvas.save();
  canvas.clipPath(pathC);
  drawPathCShadow(canvas);
  canvas.restore();
}

// 绘制背面阴影
function drawPathCShadow(canvas: drawing.Canvas): void {
  let deepColor = 0x40111111;
  let lightColor = 0x00111111;
  let gradientColors = [deepColor, lightColor];

  let startPt: common2D.Point = { x: pointI.x, y: pointI.y };
  let endPt: common2D.Point = { x: pointD.x, y: pointD.y };
  let shaderEffect = drawing.ShaderEffect.createLinearGradient(
    endPt,
    startPt,
    gradientColors,
    drawing.TileMode.CLAMP
  );

  let tmpBrush = new drawing.Brush();
  tmpBrush.setShaderEffect(shaderEffect);
  canvas.attachBrush(tmpBrush);

  let path = new drawing.Path();
  path.moveTo(pointI.x, pointI.y);
  path.lineTo(pointD.x, pointD.y);
  path.lineTo(pointB.x, pointB.y);
  path.lineTo(pointA.x, pointA.y);
  path.lineTo(pointK.x, pointK.y);
  path.close();
  canvas.drawPath(path);
  canvas.detachBrush();
}

// 获取当前页裁剪区域
function getPathA(): void {
  if (!pathA) return;

  pathA.reset();
  if (pointF.x === windowWidth && pointF.y === 0) {
    pathA.lineTo(pointC.x, pointC.y);
    pathA.quadTo(pointE.x, pointE.y, pointB.x, pointB.y);
    pathA.lineTo(pointA.x, pointA.y);
    pathA.lineTo(pointK.x, pointK.y);
    pathA.quadTo(pointH.x, pointH.y, pointJ.x, pointJ.y);
    pathA.lineTo(windowWidth, windowHeight);
    pathA.lineTo(0, windowHeight);
    pathA.close();
  } else {
    pathA.lineTo(0, windowHeight);
    pathA.lineTo(pointC.x, pointC.y);
    pathA.quadTo(pointE.x, pointE.y, pointB.x, pointB.y);
    pathA.lineTo(pointA.x, pointA.y);
    pathA.lineTo(pointK.x, pointK.y);
    pathA.quadTo(pointH.x, pointH.y, pointJ.x, pointJ.y);
    pathA.lineTo(windowWidth, 0);
    pathA.close();
  }
}

// 绘制当前页内容
function drawPathAContent(canvas: drawing.Canvas): void {
  if (!pathA || !pagePixelMap) return;

  canvas.attachBrush(pathABrush!);
  canvas.save();
  canvas.clipPath(pathA);

  let verts = [0, 0, windowWidth, 0, 0, windowHeight, windowWidth, windowHeight];
  canvas.drawPixelMapMesh(pagePixelMap, 1, 1, verts, 0, null, 0);
  canvas.restore();

  // 绘制当前页阴影
  if (drawPosition === DrawPosition.DP_MIDDLE) {
    drawPathAHorizontalShadow(canvas);
  } else {
    drawPathALeftShadow(canvas);
    drawPathARightShadow(canvas);
  }
}

// 绘制水平阴影
function drawPathAHorizontalShadow(canvas: drawing.Canvas): void {
  let shadowWidth = Math.min(30, lPathAShadowDis);
  if (shadowWidth <= 0) return;

  let deepColor = 0x30111111;
  let lightColor = 0x00111111;
  let gradientColors = [deepColor, lightColor];

  let startPt: common2D.Point = { x: pointC.x, y: pointC.y };
  let endPt: common2D.Point = { x: pointC.x + shadowWidth, y: pointC.y };
  let shaderEffect = drawing.ShaderEffect.createLinearGradient(
    endPt,
    startPt,
    gradientColors,
    drawing.TileMode.CLAMP
  );

  let tmpBrush = new drawing.Brush();
  tmpBrush.setShaderEffect(shaderEffect);
  canvas.attachBrush(tmpBrush);
  canvas.drawRect(pointC.x, pointC.y - windowHeight, pointC.x + shadowWidth, pointC.y);
  canvas.detachBrush();
}

// 绘制左侧阴影
function drawPathALeftShadow(canvas: drawing.Canvas): void {
  let shadowWidth = Math.min(20, lPathAShadowDis);
  if (shadowWidth <= 0) return;

  let deepColor = 0x20111111;
  let lightColor = 0x00111111;
  let gradientColors = [deepColor, lightColor];

  let startPt: common2D.Point = { x: pointE.x, y: pointE.y };
  let endPt: common2D.Point = { x: pointE.x + shadowWidth, y: pointE.y };
  let shaderEffect = drawing.ShaderEffect.createLinearGradient(
    endPt,
    startPt,
    gradientColors,
    drawing.TileMode.CLAMP
  );

  let tmpBrush = new drawing.Brush();
  tmpBrush.setShaderEffect(shaderEffect);
  canvas.attachBrush(tmpBrush);

  let path = new drawing.Path();
  path.moveTo(pointE.x, pointE.y);
  path.lineTo(pointB.x, pointB.y);
  path.lineTo(pointB.x + shadowWidth, pointB.y);
  path.lineTo(pointE.x + shadowWidth, pointE.y);
  path.close();
  canvas.drawPath(path);
  canvas.detachBrush();
}

// 绘制右侧阴影
function drawPathARightShadow(canvas: drawing.Canvas): void {
  let shadowWidth = Math.min(20, rPathAShadowDis);
  if (shadowWidth <= 0) return;

  let deepColor = 0x20111111;
  let lightColor = 0x00111111;
  let gradientColors = [deepColor, lightColor];

  let startPt: common2D.Point = { x: pointH.x, y: pointH.y };
  let endPt: common2D.Point = { x: pointH.x, y: pointH.y + shadowWidth };
  let shaderEffect = drawing.ShaderEffect.createLinearGradient(
    endPt,
    startPt,
    gradientColors,
    drawing.TileMode.CLAMP
  );

  let tmpBrush = new drawing.Brush();
  tmpBrush.setShaderEffect(shaderEffect);
  canvas.attachBrush(tmpBrush);

  let path = new drawing.Path();
  path.moveTo(pointH.x, pointH.y);
  path.lineTo(pointK.x, pointK.y);
  path.lineTo(pointK.x, pointK.y + shadowWidth);
  path.lineTo(pointH.x, pointH.y + shadowWidth);
  path.close();
  canvas.drawPath(path);
  canvas.detachBrush();
}

// 自定义渲染节点
export class PageFlipRenderNode extends RenderNode {
  draw(context: DrawContext): void {
    const canvas = context.canvas;

    // 初始化数据
    init();
    if (isFinished) {
      return;
    }

    // 绘制下一页阴影
    drawPathBShadow(canvas);

    // 绘制翻页背面
    drawPathC(canvas);

    // 获取当前页裁剪区域
    getPathA();

    // 绘制当前页内容
    drawPathAContent(canvas);
  }
}

// NodeController
export class PageFlipNodeController extends NodeController {
  private node: FrameNode | null = null;
  private renderNode: PageFlipRenderNode | null = null;

  makeNode(context: UIContext): FrameNode {
    this.node = new FrameNode(context);
    return this.node;
  }

  updateNode(node: FrameNode): void {
    // 触发重绘
    if (this.renderNode) {
      this.node?.invalidate();
    }
  }

  // 更新绘制参数
  updateDrawParams(
    winWidth: number,
    winHeight: number,
    posX: number,
    posY: number,
    pos: DrawPosition,
    state: DrawState,
    pixelMap: image.PixelMap | null
  ): void {
    windowWidth = winWidth;
    windowHeight = winHeight;
    positionX = posX;
    positionY = posY;
    drawPosition = pos;
    drawState = state;
    pagePixelMap = pixelMap;
    isFinished = false;

    initDrawing();
  }

  // 获取是否绘制完成
  getIsFinished(): boolean {
    return isFinished;
  }

  // 重置
  reset(): void {
    isFinished = false;
    positionX = -1;
    positionY = -1;
    drawPosition = DrawPosition.DP_NONE;
    drawState = DrawState.DS_NONE;
    pagePixelMap = null;
  }
}

// 导出常量
export { TIMER_DURATION, DISTANCE_FRACTION };