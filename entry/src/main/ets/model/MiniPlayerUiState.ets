@ObservedV2
export class MiniPlayerUiState {
  @Trace isExpanded: boolean = false;
  @Trace playlistDetailActive: boolean = false;
  @Trace playlistDetailVisible: boolean = true;
  @Trace contentCardDetailActive: boolean = false;
  @Trace nowPlayingLandscapeActive: boolean = false;
  @Trace collapseRequestVersion: number = 0;
  @Trace resumeExpandedAfterLandscape: boolean = false;
}