/** 等待指定毫秒后继续，用于让出线程或做重试间隔。 */
export function sleepMs(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}
