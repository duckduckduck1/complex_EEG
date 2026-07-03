class FillterSettings {
  double lp;
  double hp;
  double notch;
  bool isLpOn;
  bool isHpOn;
  bool isNotchOn;

  FillterSettings({
    this.lp = 40,
    this.hp = 0.5,
    this.notch = 50,
    this.isLpOn = false,
    this.isHpOn = false,
    this.isNotchOn = false,
  });
}
