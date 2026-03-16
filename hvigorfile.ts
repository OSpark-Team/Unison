import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { hvigor } from '@ohos/hvigor';

// 实现自定义插件
function debugPlugin(): HvigorPlugin {
  return {
    pluginId: 'debugPlugin',
    async apply(currentNode: HvigorNode): Promise<void> {
      clearDebugConfig(currentNode);
    }
  }
}

function clearDebugConfig(currentNode: HvigorNode) {
  const buildMode = hvigor.getParameter().getExtParam('buildMode');
  if (buildMode === 'release') {
    const hapContext = currentNode.getContext(OhosPluginId.OHOS_HAP_PLUGIN);
    if (!hapContext) {
      return;
    }

    // 去掉动态import变量表达式对应的runtimeOnly配置
    const buildProfileOpt = hapContext.getBuildProfileOpt();
    let runtimeOnly = buildProfileOpt?.buildOption?.arkOptions?.runtimeOnly;
    if (runtimeOnly?.packages?.includes(DebugPkg)) {
      runtimeOnly.packages = runtimeOnly.packages.filter((pkg) => pkg !== DebugPkg);
      console.log(`entry:debugPlugin, 打release包前删除build-profile.json5中${DebugPkg}相关配置`);
    }
    hapContext.setBuildProfileOpt(buildProfileOpt);

    // 删除entry对debug-db的依赖
    const dependenciesOpt = hapContext.getDependenciesOpt();
    delete dependenciesOpt[DebugPkg];
    console.log(`entry:debugPlugin, 打release包前删除${DebugPkg}调试用依赖包`);
    hapContext.setDependenciesOpt(dependenciesOpt);
  }
}

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [debugPlugin()]       /* Custom plugin to extend the functionality of Hvigor. */
}