class EegIsShowingSettings {
  bool isFftShowing;
  bool isFilterShowing;
  bool isBandsShowing;

  EegIsShowingSettings({
    this.isBandsShowing = false,
    this.isFftShowing = false,
    this.isFilterShowing = false,
  });
}
