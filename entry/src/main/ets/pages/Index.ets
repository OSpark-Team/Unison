import { AppStorageV2, CommonModifier, LengthMetrics, PersistenceV2 } from '@kit.ArkUI';
import { BreakpointConstants } from '../common/BreakpointConstants';
import { WindowProperties } from '../model/WindowProperties';
import { HomeView } from '../view/HomeView';
import { LibraryView } from '../view/LibraryView';
import { MyView } from '../view/MyView';
import { UnisonPlusView } from '../view/UnisonPlusView';
import { MiniPlayerShell } from '../components/MiniPlayerShell';
import { SourceListViewModel } from '../viewmodel/SourceListViewModel';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import CurrentSourceViewModel from '../viewmodel/CurrentSourceViewModel';
import { ContinueSwitch } from '../utils/Continue';
import { PlaylistDetailParam } from './PlaylistDetail';
import SettingViewModel from '../viewmodel/SettingViewModel';
import { MiniPlayerUiState } from '../model/MiniPlayerUiState';

@Entry
@ComponentV2
struct Index {
  /** 路由导航栈 */
  @Provider() pageInfos: NavPathStack = new NavPathStack();
  /** 当前tab索引 */
  @Local currentIndex: number = 0;
  /** tab控制器 */
  @Local controller: TabsController = new TabsController();
  /**
   * 窗口属性
   */
  @Local windowProperties: WindowProperties =
    AppStorageV2.connect(WindowProperties, "WindowProperties", () => new WindowProperties())!;
  /** 系统设置 ViewModel（用于统一 UI 参数） */
  @Local settingModel: SettingViewModel =
    PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
  /**
   * 当前数据源 ViewModel
   */
  @Local currentSourceViewModel: CurrentSourceViewModel =
    AppStorageV2.connect(CurrentSourceViewModel, "CurrentSourceViewModel", () => new CurrentSourceViewModel())!;
  /**
   * 数据源列表 ViewModel
   */
  @Local sourceListViewModel: SourceListViewModel =
    AppStorageV2.connect(SourceListViewModel, 'SourceListViewModel', () => new SourceListViewModel())!;
  @Local miniPlayerUiState: MiniPlayerUiState =
    AppStorageV2.connect(MiniPlayerUiState, 'MiniPlayerUiState', () => new MiniPlayerUiState())!;
  @Local homeMiniPlayerVisible: boolean = true;
  @Local libraryMiniPlayerVisible: boolean = true;
  /**
   /** tab栏构建器 */
  @Builder
  tabBuilder(title: ResourceStr, targetIndex: number, selectedImg: Resource, normalImg: Resource) {
    Column({ space: 6 }) {
      SymbolGlyph(this.currentIndex === targetIndex ? selectedImg : normalImg)
        .fontSize(25)
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontColor([this.currentIndex === targetIndex ? $r('app.color.tab_selected') : $r('app.color.tab_normal')])
        .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.UP), this.currentIndex == targetIndex)

      Text(title)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.currentIndex === targetIndex ? $r('app.color.tab_selected') : $r('app.color.tab_normal'))
    }
    .borderRadius({ topLeft: this.settingModel.radiusTabTop, topRight: this.settingModel.radiusTabTop })
    .onClick(() => {
      this.getUIContext()?.animateTo({
        duration: 150,
        curve: Curve.EaseInOut
      }, () => {
        this.controller.changeIndex(targetIndex)
        this.currentIndex = targetIndex
      })
    })
    .margin({
      bottom: this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ?
        this.windowProperties.bottomRect / 2 : 0
    })
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 当前选中的数据源索引
   */
  @Local selectedSourceIndex: number = 0;

  /**
   * 切换数据源
   */
  switchSource(index: number): void {
    this.selectedSourceIndex = index;
    if (index >= 0 && index < this.sourceListViewModel.sources.length) {
      this.currentSourceViewModel.source = this.sourceListViewModel.sources[index];
    }
  }

  /**
   * 获取数据源选项列表
   */
  @Computed
  get sourceOptions(): SelectOption[] {
    return this.sourceListViewModel.sources.map((source) => {
      return { value: source.name } as SelectOption;
    });
  }

  /**
   * 数据源选择器构建器
   */
  @Builder
  SourceSelector() {
    Select(this.sourceOptions)
      .selected(this.selectedSourceIndex)
      .value(this.currentSourceViewModel.source?.name ?? '')
      .height(40)
      .onSelect((index: number) => {
        this.switchSource(index);
      })
  }

  private shouldShowMiniPlayer(): boolean {
    if (this.miniPlayerUiState.nowPlayingLandscapeActive) {
      return false;
    }
    if (this.miniPlayerUiState.contentCardDetailActive) {
      return false;
    }
    if (this.miniPlayerUiState.playlistDetailActive) {
      return this.miniPlayerUiState.playlistDetailVisible;
    }
    if (this.currentIndex === 0) {
      return this.homeMiniPlayerVisible;
    }
    if (this.currentIndex === 1) {
      return this.libraryMiniPlayerVisible;
    }
    return false;
  }

  onBackPress(): boolean {
    if (this.miniPlayerUiState.isExpanded) {
      this.miniPlayerUiState.collapseRequestVersion += 1;
      return true;
    }
    return false;
  }

  // /**
  //  * 搜索Builder
  //  */
  // @Builder
  // SearchBox() {
  //   if (this.currentIndex === 0) {
  //     Column() {
  //       // 搜索框
  //       Search({ placeholder: $r('app.string.home_search_placeholder'), value: this.searchKeyword })
  //         .width('100%')
  //         .onChange((value: string) => {
  //           this.searchKeyword = value;
  //         })
  //     }
  //     .margin({
  //       left: this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? 120 : 16,
  //       right: this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? 20 : 16,
  //     })
  //   } else if (this.currentIndex === 1) {
  //     Row({ space: 12 }) {
  //       if (this.sourceListViewModel.sources.length > 1) {
  //         this.SourceSelector()
  //       }
  //       // 右侧：搜索框
  //       Search({ placeholder: $r('app.string.library_search_placeholder'), value: this.searchKeyword })
  //         .layoutWeight(1)
  //         .onChange((value: string) => {
  //           this.searchKeyword = value;
  //         })
  //     }
  //     .margin({
  //       left: this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? 120 : 16,
  //       right: this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? 20 : 16,
  //     })
  //   }
  // }

  /**
   * 主内容区域
   */
  @Builder
  Main() {
    Tabs({
      controller: this.controller,
      barModifier: new CommonModifier().padding(this.windowProperties.currentBreakpoint !==
      BreakpointConstants.BREAKPOINT_SM ?
        { top: "15%", bottom: "15%" } : 0)
    }) {
      TabContent() {
        HomeView({
          onMiniPlayerVisibilityChange: (visible: boolean) => {
            this.homeMiniPlayerVisible = visible;
          }
        })
      }
      .tabBar(this.tabBuilder($r('app.string.toolbar_home_title'), 0, $r('sys.symbol.house_fill'),
        $r('sys.symbol.house')))

      TabContent() {
        LibraryView({
          onMiniPlayerVisibilityChange: (visible: boolean) => {
            this.libraryMiniPlayerVisible = visible;
          }
        })
      }
      .tabBar(this.tabBuilder($r('app.string.toolbar_library_title'), 1, $r('sys.symbol.puzzle_fill'),
        $r('sys.symbol.puzzle')))

      TabContent() {
        UnisonPlusView()
      }
      .tabBar(this.tabBuilder($r('app.string.toolbar_ai_title'), 2, $r('sys.symbol.airplane_fill'),
        $r('sys.symbol.airplane')))

      TabContent() {
        MyView()
      }
      .tabBar(this.tabBuilder($r('app.string.toolbar_my_title'), 3, $r('sys.symbol.person_fill'),
        $r('sys.symbol.person')))
    }
    .animation({
      duration: 400,
      curve: Curve.Friction,
    })
    .scrollable(false)
    .divider({
      strokeWidth: this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? 1 : 0,
      color: $r('app.color.divider')
    })
    .onContentWillChange((currentIndex: number, comingIndex: number) => {
      this.currentIndex = comingIndex;
      if (this.currentIndex === 1) {
        // 拉取最新数据
        this.currentSourceViewModel.refreshUserPlaylists()
      }
      return true;
    })
    .barHeight(this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ?
      this.windowProperties.bottomRect + 48 : undefined)
    .barWidth(this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? 100 : undefined)
    .barPosition(this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? BarPosition.End :
      BarPosition.Start)
    .vertical(this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM)
    .width('100%')
    .height('100%')
  }

  aboutToAppear() {
    // 获取接续数据
    const continueData = ContinueSwitch.getContinueData();
    if (continueData) {
      const page = continueData.page;
      if (page === "playing") {
        // 播放页
        // TODO:
      } else if (page === "detail") {
        // 歌单详情页
        this.pageInfos.pushPathByName("PlaylistDetail", {
          playlistId: continueData.id,
          sourceId: continueData.sourceId,
          playlist: continueData.playlist
        } as PlaylistDetailParam, true);
      }
    }

    // 设置路由拦截
    this.pageInfos.setInterception({
      willShow: (from: NavDestinationContext | 'navBar', to: NavDestinationContext | 'navBar') => {
        if (typeof from === 'string') {
          // let target = to as NavDestinationContext;
          // console.info(`from page is navigation home -> ${target.pathInfo.name}`);
          this.showDynamicIsland = false
        } else if (typeof to === 'string') {
          // let target = from as NavDestinationContext;
          // console.info(`${target.pathInfo.name} -> to page is navigation home`);
          this.showDynamicIsland = true;
        }
      }
    });
  }

  @Builder
  buildFloatingDynamicIsland() {
    if (this.showDynamicIsland) {
      DynamicIsland({
        isExpanded: this.isDynamicIslandExpanded!!,
        expandAlignment: Alignment.TopEnd,
        compWidthCollapsed: 120,
        compWidthExpanded: this.windowProperties.winWidth - 32,
        onOpenNowPlaying: () => {
          this.getUIContext()?.animateTo({
            curve: curves.interpolatingSpring(0, 1, 328, 37)
          }, () => {
            this.isDynamicIslandExpanded = false;
            // 不使用默认导航动画，避免叠加动画
            this.pageInfos.pushPathByName('NowPlaying', undefined, false);
          })
        }
      })
        .position({
          top: this.windowProperties.topRect + 4,
          right: 16,
        })
        .zIndex(999)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      HdsNavigation(this.pageInfos) {
        this.Main()
      }
      .height('100%')
      .width('100%')
      .mode(NavigationMode.Stack)
      .backgroundColor($r('app.color.background_primary'))
      .hideBackButton(true)
      .ignoreLayoutSafeArea()
      .titleBar({
        content: {
          title: {
            mainTitle: 'Unison',
          },
        },
        avoidLayoutSafeArea: true,
        padding: {
          start: this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? LengthMetrics.vp(120) :
            undefined,
        },
      })
      .titleMode(HdsNavigationTitleMode.MINI)

      MiniPlayerShell({
        visible: this.shouldShowMiniPlayer(),
        bottomOffset: this.windowProperties.bottomRect + 12
      })
        .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor($r('app.color.background_primary'))
  }
}