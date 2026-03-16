import { SourceListViewModel } from "../viewmodel/SourceListViewModel";
import { Source } from "../model/Source";
import { AppStorageV2, SymbolGlyphModifier, PersistenceV2 } from "@kit.ArkUI";
import Logger from "../utils/Logger";
import SettingViewModel from "../viewmodel/SettingViewModel";

const TAG = "SourceManagementView";

/**
 * 表单数据类型
 */
interface FormData {
  name: string;
  url: string;
  description: string;
  token: string;
}

/**
 * 表单验证错误类型
 */
interface FormErrors {
  name?: ResourceStr;
  url?: ResourceStr;
  token?: ResourceStr;
}

/**
 * 数据源管理视图
 * 负责数据源的增删改查和用户信息显示
 */
@ComponentV2
export struct SourceManagementView {
  /**
   * 路由导航
   */
  @Consumer() pageInfos: NavPathStack = new NavPathStack();
  /**
   * 数据源列表 ViewModel
   */
  @Local viewModel: SourceListViewModel = AppStorageV2.connect(
    SourceListViewModel,
    "SourceListViewModel",
    () => new SourceListViewModel(),
  )!;

  /**
   * 系统设置 ViewModel
   */
  @Local settingModel: SettingViewModel = PersistenceV2.connect(
    SettingViewModel,
    "SettingViewModel",
    () => new SettingViewModel(),
  )!;

  /**
   * 是否展开数据源列表
   */
  @Local isSourceListExpanded: boolean = false;

  /**
   * 是否显示添加/编辑数据源表单
   */
  @Local showSourceForm: boolean = false;

  /**
   * 当前编辑的数据源（null表示添加模式）
   */
  @Local editingSource: Source | null = null;

  /**
   * 表单数据
   */
  @Local formData: FormData = {
    name: "",
    url: "",
    description: "",
    token: "",
  };

  /**
   * 表单当前步骤（0: 基本信息，1: 凭证信息）
   */
  @Local currentFormStep: number = 0;

  /**
   * 表单验证错误
   */
  @Local formErrors: FormErrors = {};

  /**
   * 页面生命周期：即将出现
   */
  aboutToAppear(): void {
    Logger.info(TAG, "SourceManagementView 即将出现");
  }

  /**
   * 页面生命周期：即将消失
   */
  aboutToDisappear(): void {
    Logger.info(TAG, "SourceManagementView 即将消失");
    // 清理二维码定时器
    this.viewModel.clearQRCodeTimer();
  }

  /**
   * Getter - 主数据源
   */
  @Computed
  get MainSource() {
    const id = this.settingModel.mainSource;
    let source = this.viewModel.sources[0];
    if (id) {
      source =
        this.viewModel.sources.find((source) => source.id === id) ?? this.viewModel.sources[0];
    }
    return source;
  }

  /**
   * 构建用户信息卡片区域
   */
  @Builder
  buildUserInfoCard() {
    Column({ space: 16 }) {
      if (this.viewModel.isLoading) {
        // 加载状态
        this.buildLoadingState();
      } else if (this.viewModel.isEmpty()) {
        // 空状态：显示添加数据源提示
        this.buildEmptyState();
      } else {
        // 有数据源：显示用户信息和数据源管理
        this.buildSourceList();
      }

      // 错误提示
      if (this.viewModel.errorMessage) {
        this.buildErrorMessage();
      }
    }.width("100%");
  }

  /**
   * 构建加载状态
   */
  @Builder
  buildLoadingState() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color($r("app.color.primary_color"))
      Text($r("app.string.loading"))
        .fontSize(14)
        .fontColor($r("app.color.text_secondary"))
    }
    .width("100%")
    .padding(24)
    .backgroundColor($r("app.color.background_card"))
    .borderRadius(this.settingModel.radiusCard)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }

  /**
   * 构建空状态提示
   */
  @Builder
  buildEmptyState() {
    Column({ space: 16 }) {
      // 空状态图标
      SymbolGlyph($r("sys.symbol.person"))
        .fontSize(64)
        .fontColor([$r("app.color.text_tertiary")])

      // 空状态文本
      Text($r("app.string.no_data_source_title"))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r("app.color.text_primary"))
      Text($r("app.string.no_data_source_description"))
        .fontSize(14)
        .fontColor($r("app.color.text_secondary"))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 8 })
    }
    .width("100%")
    .padding(24)
    .backgroundColor($r("app.color.background_card"))
    .borderRadius(this.settingModel.radiusCard)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
    .onClick(() => {
      this.showAddSourceForm();
    });
  }

  /**
   * 构建错误消息
   */
  @Builder
  buildErrorMessage() {
    Row({ space: 12 }) {
      SymbolGlyph($r("sys.symbol.exclamationmark_triangle"))
        .fontSize(20)
        .fontColor([$r("app.color.error")])
      Column({ space: 4 }) {
        Text($r("app.string.error_occurred"))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r("app.color.error"))
        Text(this.viewModel.errorMessage)
          .fontSize(12)
          .fontColor($r("app.color.text_secondary"))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width("100%")
    .padding(12)
    .backgroundColor($r("app.color.background_card"))
    .borderRadius(this.settingModel.radiusItem)
    .border({
      width: 1,
      color: $r("app.color.error"),
      style: BorderStyle.Solid,
    });
  }

  /**
   * 构建数据源列表
   */
  @Builder
  buildSourceList() {
    Column({ space: 12 }) {
      // 主数据源卡片（显示第一个数据源）
      if (this.viewModel.sources.length > 0) {
        this.buildMainSourceCard(this.MainSource);
      }

      // 展开的数据源列表
      if (this.isSourceListExpanded && this.viewModel.sources.length > 1) {
        Column({ space: 8 }) {
          ForEach(this.viewModel.sources.slice(1), (source: Source) => {
            this.buildSourceItem(source);
          })
        }
        .width("100%")
        .animation({
          duration: 300,
          curve: Curve.EaseInOut,
        });
      }

      // 添加数据源按钮（在展开状态下显示）
      if (this.isSourceListExpanded) {
        this.buildAddSourceButton();
      }
    }.width("100%");
  }

  /**
   * 构建主数据源卡片
   */
  @Builder
  buildMainSourceCard(source: Source) {
    Row({ space: 12 }) {
      // 头像
      Image(source.user?.avatar || $r("app.media.startIcon"))
        .width(48)
        .height(48)
        .borderRadius(24)
        .backgroundColor($r("app.color.background_secondary"))

      // 用户信息
      Column({ space: 4 }) {
        Text(source.user?.name || source.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r("app.color.text_primary"))
        Text(source.name)
          .fontSize(14)
          .fontColor($r("app.color.text_secondary"))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 展开/收起按钮
      SymbolGlyph($r("sys.symbol.chevron_down"))
        .fontSize(20)
        .fontColor([$r("app.color.text_tertiary")])
        .rotate({ z: 1, angle: this.isSourceListExpanded ? 180 : 0 })
        .animation({
          duration: 300,
          curve: Curve.EaseInOut,
        })
    }
    .width("100%")
    .padding(16)
    .backgroundColor($r("app.color.background_card"))
    .borderRadius(this.settingModel.radiusCard)
    .onClick(() => {
      this.isSourceListExpanded = !this.isSourceListExpanded;
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
    .bindContextMenu(this.buildSourceMenu(source), ResponseType.LongPress, {
      preview: MenuPreviewMode.NONE,
    })
    .bindContextMenu(this.buildSourceMenu(source), ResponseType.RightClick, {
      enableArrow: false,
    });
  }

  /**
   * 构建数据源项
   */
  @Builder
  buildSourceItem(source: Source) {
    Row({ space: 12 }) {
      // 头像
      Image(source.user?.avatar || $r("app.media.startIcon"))
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r("app.color.background_secondary"))

      // 用户信息
      Column({ space: 2 }) {
        Text(source.user?.name || source.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r("app.color.text_primary"))
        Text(source.name)
          .fontSize(12)
          .fontColor($r("app.color.text_secondary"))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width("100%")
    .padding(12)
    .backgroundColor($r("app.color.background_card"))
    .borderRadius(this.settingModel.radiusItem)
    .bindContextMenu(this.buildSourceMenu(source), ResponseType.LongPress, {
      preview: MenuPreviewMode.NONE,
    })
    .bindContextMenu(this.buildSourceMenu(source), ResponseType.RightClick, {
      enableArrow: false,
    });
  }

  private iconMain = new SymbolGlyphModifier($r("sys.symbol.star_fill"))
    .fontColor([$r("app.color.text_primary")])
    .fontSize(16)
    .fontWeight(FontWeight.Regular);

  private iconEdit = new SymbolGlyphModifier($r("sys.symbol.pencil_line"))
    .fontColor([$r("app.color.accent")])
    .fontSize(16)
    .fontWeight(FontWeight.Regular);

  private iconDelete = new SymbolGlyphModifier($r("sys.symbol.trash"))
    .fontColor([Color.Red])
    .fontSize(16)
    .fontWeight(FontWeight.Regular);

  /**
   * 构建数据源菜单
   */
  @Builder
  buildSourceMenu(source: Source) {
    Menu() {
      MenuItem({
        symbolStartIcon: this.iconMain,
        content: $r("app.string.set_main"),
        labelInfo: "",
      })
        .onClick(() => {
          this.settingModel.mainSource = source.id;
        })
        .enabled(this.settingModel.mainSource !== source.id)
      MenuItem({ symbolStartIcon: this.iconEdit, content: $r("app.string.edit"), labelInfo: "" })
        .onClick(() => {
          this.showEditSourceForm(source);
        })
      MenuItem({
        symbolStartIcon: this.iconDelete,
        content: $r("app.string.delete"),
        labelInfo: "",
      })
        .onClick(() => {
          this.showDeleteConfirmDialog(source);
        })
    };
  }

  /**
   * 构建添加数据源按钮
   */
  @Builder
  buildAddSourceButton() {
    Row({ space: 8 }) {
      SymbolGlyph($r("sys.symbol.plus"))
        .fontSize(16)
        .fontColor([$r("app.color.primary_color")])
      Text($r("app.string.add_data_source"))
        .fontSize(14)
        .fontColor($r("app.color.primary_color"))
    }
    .width("100%")
    .padding(12)
    .backgroundColor($r("app.color.background_card"))
    .borderRadius(this.settingModel.radiusItem)
    .border({
      width: 1,
      color: $r("app.color.primary_color"),
      style: BorderStyle.Dashed,
    })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showAddSourceForm();
    });
  }

  /**
   * 显示添加数据源表单
   */
  private showAddSourceForm(): void {
    this.editingSource = null;
    this.resetForm();
    this.showSourceForm = true;
  }

  /**
   * 显示编辑数据源表单
   */
  private showEditSourceForm(source: Source): void {
    this.editingSource = source;
    // 预填充表单数据
    this.formData = {
      name: source.name,
      url: source.url,
      description: source.description,
      token: source.token,
    };
    this.formErrors = {};
    this.currentFormStep = 0;
    this.viewModel.clearQRCodeTimer();
    this.showSourceForm = true;
  }

  /**
   * 显示删除确认对话框
   */
  private showDeleteConfirmDialog(source: Source): void {
    this.getUIContext()
      .getPromptAction()
      .showDialog({
        title: $r("app.string.delete_data_source_title"),
        message: $r("app.string.delete_data_source_message", source.name),
        buttons: [
          { text: $r("app.string.cancel"), color: $r("app.color.text_secondary") },
          { text: $r("app.string.delete"), color: $r("app.color.error") },
        ],
      })
      .then((result) => {
        if (result.index === 1) {
          this.deleteSource(source);
        }
      });
  }

  /**
   * 删除数据源
   */
  private async deleteSource(source: Source): Promise<void> {
    try {
      const success = await this.viewModel.deleteSource(source.id);
      if (success) {
        this.getUIContext()
          .getPromptAction()
          .showToast({
            message: $r("app.string.delete_success"),
          });
      } else {
        this.getUIContext()
          .getPromptAction()
          .showToast({
            message: $r("app.string.delete_failed", this.viewModel.errorMessage),
          });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      Logger.error(TAG, `删除数据源失败: ${errorMessage}`);
      this.getUIContext()
        .getPromptAction()
        .showToast({
          message: $r("app.string.delete_failed", errorMessage),
        });
    }
  }

  /**
   * 验证表单数据
   */
  private validateForm(): boolean {
    this.formErrors = {};
    let isValid = true;

    // 验证名称
    if (!this.formData.name.trim()) {
      this.formErrors.name = $r("app.string.form_error_name_required");
      isValid = false;
    }

    // 验证URL
    if (!this.formData.url.trim()) {
      this.formErrors.url = $r("app.string.form_error_url_required");
      isValid = false;
    } else if (!this.isValidUrl(this.formData.url)) {
      this.formErrors.url = $r("app.string.form_error_url_invalid");
      isValid = false;
    }

    // 在第二步验证凭证
    if (this.currentFormStep === 1 && !this.formData.token.trim() && !this.viewModel.tokenFromQR) {
      this.formErrors.token = $r("app.string.form_error_token_required");
      isValid = false;
    }

    return isValid;
  }

  /**
   * 验证URL格式
   */
  private isValidUrl(url: string): boolean {
    const urlPattern = /^(http|https):\/\/[a-zA-Z0-9-.]+(:\d+)?(\/[a-zA-Z0-9-._?&=]*)?$/;
    return urlPattern.test(url);
  }

  /**
   * 提交表单
   */
  private async submitForm(): Promise<void> {
    if (!this.validateForm()) {
      return;
    }

    // 使用二维码获取的凭证或手动输入的凭证
    const token = this.viewModel.tokenFromQR || this.formData.token;

    if (this.editingSource) {
      // 编辑模式
      await this.updateSource(token);
    } else {
      // 添加模式
      await this.addSource(token);
    }
  }

  /**
   * 添加数据源
   */
  private async addSource(token: string): Promise<void> {
    try {
      const source = new Source();
      source.name = this.formData.name;
      source.url = this.formData.url;
      source.description = this.formData.description;
      source.token = token;

      const success = await this.viewModel.addSource(source);
      if (success) {
        this.showSourceForm = false;
        this.resetForm();
        this.getUIContext()
          .getPromptAction()
          .showToast({
            message: $r("app.string.add_source_success"),
          });
      } else {
        this.getUIContext()
          .getPromptAction()
          .showToast({
            message: $r("app.string.add_source_failed", this.viewModel.errorMessage),
          });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      Logger.error(TAG, `添加数据源失败: ${errorMessage}`);
      this.getUIContext()
        .getPromptAction()
        .showToast({
          message: $r("app.string.add_source_failed", errorMessage),
        });
    }
  }

  /**
   * 更新数据源
   */
  private async updateSource(token: string): Promise<void> {
    if (!this.editingSource) return;

    try {
      this.editingSource.name = this.formData.name;
      this.editingSource.url = this.formData.url;
      this.editingSource.description = this.formData.description;
      this.editingSource.token = token;

      const success = await this.viewModel.updateSource(this.editingSource);
      if (success) {
        this.showSourceForm = false;
        this.resetForm();
        this.getUIContext()
          .getPromptAction()
          .showToast({
            message: $r("app.string.update_source_success"),
          });
      } else {
        this.getUIContext()
          .getPromptAction()
          .showToast({
            message: $r("app.string.update_source_failed", this.viewModel.errorMessage),
          });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      Logger.error(TAG, `更新数据源失败: ${errorMessage}`);
      this.getUIContext()
        .getPromptAction()
        .showToast({
          message: $r("app.string.update_source_failed", errorMessage),
        });
    }
  }

  /**
   * 重置表单
   */
  private resetForm(): void {
    this.formData = {
      name: "",
      url: "",
      description: "",
      token: "",
    };
    this.formErrors = {};
    this.currentFormStep = 0;
    this.viewModel.clearQRCodeTimer();
  }

  /**
   * 构建数据源表单弹窗
   */
  @Builder
  buildSourceFormSheet() {
    Column({ space: 0 }) {
      // 表单标题栏
      Row() {
        Button($r("app.string.cancel"))
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .fontColor($r("app.color.text_secondary"))
          .borderRadius(this.settingModel.radiusItem)
          .onClick(() => {
            this.showSourceForm = false;
            this.resetForm();
          })
        Blank()
        Text(
          this.editingSource ? $r("app.string.edit_data_source") : $r("app.string.add_data_source"),
        )
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r("app.color.text_primary"))
        Blank()
        Button(this.currentFormStep === 0 ? $r("app.string.next") : $r("app.string.save"))
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .fontColor($r("app.color.primary_color"))
          .borderRadius(this.settingModel.radiusItem)
          .onClick(() => {
            if (this.currentFormStep === 0) {
              if (this.validateForm()) {
                this.currentFormStep = 1;
              }
            } else {
              this.submitForm();
            }
          })
      }
      .width("100%")
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r("app.color.background_card"))
      Divider()
        .strokeWidth(1)
        .color($r("app.color.divider"))

      // 表单内容
      if (this.currentFormStep === 0) {
        this.buildBasicInfoForm();
      } else {
        this.buildCredentialForm();
      }
    }
    .width("100%")
    .height("100%")
    .backgroundColor($r("app.color.background_primary"))
    .align(Alignment.Top);
  }

  /**
   * 构建基本信息表单
   */
  @Builder
  buildBasicInfoForm() {
    Scroll() {
      Column({ space: 16 }) {
        // 数据源名称
        Column({ space: 8 }) {
          Text($r("app.string.data_source_name"))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r("app.color.text_primary"))
            .alignSelf(ItemAlign.Start)
          TextInput({
            placeholder: $r("app.string.data_source_name_placeholder"),
            text: this.formData.name,
          })
            .width("100%")
            .onChange((value) => {
              this.formData.name = value;
              if (this.formErrors.name) {
                this.formErrors.name = undefined;
              }
            })

          if (this.formErrors.name) {
            Text(this.formErrors.name)
              .fontSize(12)
              .fontColor($r("app.color.error"))
              .alignSelf(ItemAlign.Start);
          }
        }

        // 数据源地址
        Column({ space: 8 }) {
          Text($r("app.string.data_source_url"))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r("app.color.text_primary"))
            .alignSelf(ItemAlign.Start)
          TextInput({
            placeholder: $r("app.string.data_source_url_placeholder"),
            text: this.formData.url,
          })
            .width("100%")
            .onChange((value) => {
              this.formData.url = value;
              if (this.formErrors.url) {
                this.formErrors.url = undefined;
              }
            })

          if (this.formErrors.url) {
            Text(this.formErrors.url)
              .fontSize(12)
              .fontColor($r("app.color.error"))
              .alignSelf(ItemAlign.Start);
          }
        }

        // 数据源描述
        Column({ space: 8 }) {
          Text($r("app.string.data_source_description"))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r("app.color.text_primary"))
            .alignSelf(ItemAlign.Start)
          TextArea({
            placeholder: $r("app.string.data_source_description_placeholder"),
            text: this.formData.description,
          })
            .width("100%")
            .height(100)
            .onChange((value) => {
              this.formData.description = value;
            })
        }
      }
      .width("100%")
      .padding(16)
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
    .layoutWeight(1);
  }

  /**
   * 构建凭证信息表单
   */
  @Builder
  buildCredentialForm() {
    Scroll() {
      Column({ space: 16 }) {
        // // 返回按钮
        // Row() {
        //   SymbolGlyph($r("sys.symbol.arrow_left"))
        //     .fontSize(20)
        //     .fontColor([$r('app.color.primary_color')])
        //
        //   Text($r('app.string.back'))
        //     .fontSize(16)
        //     .fontColor($r('app.color.primary_color'))
        //     .margin({ left: 4 })
        // }
        // .onClick(() => {
        //   this.currentFormStep = 0;
        // })
        // .alignSelf(ItemAlign.Start)

        // 手动输入凭证
        Column({ space: 8 }) {
          Text($r("app.string.credential_token"))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r("app.color.text_primary"))
            .alignSelf(ItemAlign.Start)
          TextArea({
            placeholder: $r("app.string.credential_token_placeholder"),
            text: this.viewModel.tokenFromQR || this.formData.token,
          })
            .width("100%")
            .height(100)
            .onChange((value) => {
              this.formData.token = value;
              if (this.formErrors.token) {
                this.formErrors.token = undefined;
              }
            })

          if (this.formErrors.token) {
            Text(this.formErrors.token)
              .fontSize(12)
              .fontColor($r("app.color.error"))
              .alignSelf(ItemAlign.Start);
          }
        }

        // 二维码获取凭证
        this.buildQRCodeSection()
      }
      .width("100%")
      .padding(16)
    }
    .align(Alignment.Top)
    .layoutWeight(1);
  }

  /**
   * 构建二维码区域
   */
  @Builder
  buildQRCodeSection() {
    Column({ space: 16 }) {
      Divider()
        .strokeWidth(1)
        .color($r("app.color.divider"))
      Text($r("app.string.qr_code_credential_title"))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r("app.color.text_primary"))
        .alignSelf(ItemAlign.Start)
      Text($r("app.string.qr_code_credential_description"))
        .fontSize(14)
        .fontColor($r("app.color.text_secondary"))
        .alignSelf(ItemAlign.Start)

      if (!this.viewModel.qrCodeVisible) {
        // 生成二维码按钮
        Button($r("app.string.generate_qr_code"))
          .width(200)
          .height(40)
          .backgroundColor($r("app.color.button_primary"))
          .fontColor($r("app.color.button_label_primary"))
          .onClick(async () => {
            if (this.formData.url) {
              // 直接传递 URL，避免创建未完全初始化的 Source 实例
              await this.viewModel.generateQRCode(this.formData.url);
            }
          })
          .alignSelf(ItemAlign.Center);
      } else {
        // 二维码显示区域
        Column({ space: 12 }) {
          Image(this.viewModel.qrCodeUrl)
            .width(144)
            .height(144)
            .backgroundColor(Color.White)
            .borderRadius(this.settingModel.radiusItem)
            .alignSelf(ItemAlign.Center)
          Text(this.viewModel.qrCodeStatusText)
            .fontSize(14)
            .fontColor(
              this.viewModel.qrCodeStatus === 2
                ? $r("app.color.success")
                : this.viewModel.qrCodeStatus === -1
                  ? $r("app.color.error")
                  : $r("app.color.text_secondary"),
            )
            .textAlign(TextAlign.Center)
            .alignSelf(ItemAlign.Center)

          if (this.viewModel.qrCodeStatus === -1) {
            Button($r("app.string.regenerate_qr_code"))
              .width(160)
              .height(36)
              .backgroundColor($r("app.color.button_primary"))
              .fontColor($r("app.color.button_label_primary"))
              .onClick(async () => {
                if (this.formData.url) {
                  // 直接传递 URL，避免创建未完全初始化的 Source 实例
                  await this.viewModel.generateQRCode(this.formData.url);
                }
              })
              .alignSelf(ItemAlign.Center);
          }
        };
      }
    };
  }

  build() {
    Column() {
      this.buildUserInfoCard()
    }
    .width("100%")
    .bindSheet($$this.showSourceForm, this.buildSourceFormSheet(), {
      height: SheetSize.LARGE,
      showClose: false,
      preferType: SheetType.CENTER,
      onWillDismiss: () => {
        this.showSourceForm = false;
      },
    });
  }
}
