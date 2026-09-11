import { hvigor, HvigorPlugin } from '@ohos/hvigor';
import { hapTasks, OhosHapContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { copyFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const preserveLayeredIcon: HvigorPlugin = {
  pluginId: 'listenbook.preserve-layered-icon',
  apply(node) {
    hvigor.nodesEvaluated(() => {
      const context: OhosHapContext = node.getContext(OhosPluginId.OHOS_HAP_PLUGIN);
      context.targets(target => {
        const targetName = target.getTargetName();
        node.registerTask({
          name: `${targetName}@PreserveLayeredIcon`,
          dependencies: [`${targetName}@CompileResource`],
          postDependencies: [`${targetName}@ProcessCompiledResources`],
          run() {
            // SDK restool 的 ScaleIcons 会把分层 PNG 固定缩到 512px。
            // 在资源编译后、HAP 打包签名前保留 AGC 要求的 1024px 原图。
            // 依据：openharmony/developtools_global_resource_tool/src/compression_parser.cpp
            const sourceDir = join(context.getModulePath(), 'src/main/resources/base/media');
            const outputDir = join(target.getModulePathDetails().getIntermediatesRes(), 'resources/base/media');
            for (const layer of ['foreground', 'background']) {
              const name = `app_icon_${layer}.png`;
              const source = join(sourceDir, name);
              const png = readFileSync(source);
              if (png.readUInt32BE(16) !== 1024 || png.readUInt32BE(20) !== 1024) {
                throw new Error(`${name} must be 1024x1024; run scripts/generate_app_icon.py`);
              }
              copyFileSync(source, join(outputDir, name));
            }
          }
        });
      });
    });
  }
};

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [preserveLayeredIcon]
}
