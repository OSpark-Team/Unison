
/**
 * ResourceUtil
 *
 * 统一通过 resourceManager 获取字符串资源，避免 `$r(...).toString()` 的 [object Object] 问题。
 *
 */
export class ResourceUtil {
  private appContext: Context | undefined = undefined;

  public setAppContext(context: Context): void {
    this.appContext = context;
  }

  public getString(context: Context, res: Resource): string {

    try {
      return context.resourceManager.getStringSync(res.id);
    } catch {
      throw new Error('Failed to get string resource: ' + res.id);
    }
  }

  public getAppString(res: Resource, fallback: string): string {
    if (!this.appContext) {
      return fallback;
    }

    try {
      return this.getString(this.appContext, res);
    } catch {
      return fallback;
    }
  }
}

export const resourceUtil = new ResourceUtil();