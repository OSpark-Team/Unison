import { deviceInfo } from "@kit.BasicServicesKit";

/**
 * AppConstants
 */
export class AppConstants {
  /** 是否使用新特性，必须APIVersion >= 20 */
  static readonly USE_NEW_FEATURE: boolean = deviceInfo.sdkApiVersion >= 20;
}