import 'package:flutter_test/flutter_test.dart';
import 'package:eeg_app_max30003_stm32/fuetures/main_page/widgets/apps/eeg_widget/sub_widget/mosaic/mosaic_layout.dart';

void main() {
  int columnsFor(
    int devices, {
    double width = 1900,
    double height = 950,
    double gap = 8,
  }) {
    return mosaicColumns(
      deviceCount: devices,
      availableWidth: width,
      availableHeight: height,
      gap: gap,
    );
  }

  test('одно устройство занимает экран целиком', () {
    expect(columnsFor(1), 1);
  });

  test('десять устройств на большом мониторе помещаются без прокрутки', () {
    // 1920×1080 за вычетом шапки и панели инструментов.
    final columns = columnsFor(10);
    final rows = (10 / columns).ceil();
    final panelWidth = (1900 - 8 * (columns - 1)) / columns;
    final panelHeight = (950 - 8 * (rows - 1)) / rows;

    expect(panelWidth, greaterThanOrEqualTo(260));
    expect(panelHeight, greaterThanOrEqualTo(200));
  });

  test('на ноутбуке панели остаются читаемыми, а не сжимаются в марки', () {
    // 1366×768 — панелей нужного размера на все десять не хватит, и это
    // правильный исход: часть уезжает в прокрутку.
    final columns = columnsFor(10, width: 1350, height: 640);
    final panelWidth = (1350 - 8 * (columns - 1)) / columns;

    expect(
      panelWidth,
      greaterThanOrEqualTo(260),
      reason: 'нечитаемых панелей быть не должно ни при каком числе устройств',
    );
  });

  test('узкое окно сваливает мозаику в одну колонку', () {
    expect(columnsFor(6, width: 400, height: 900), 1);
  });

  test('четыре устройства разводятся сеткой, а не строкой', () {
    // Ровный экран: 2×2 ближе к пропорциям панели, чем 4×1.
    expect(columnsFor(4, width: 1900, height: 950), 2);
  });

  test('число колонок не превышает числа устройств', () {
    for (var devices = 1; devices <= 10; devices++) {
      expect(
        columnsFor(devices),
        lessThanOrEqualTo(devices),
        reason: 'пустые колонки — потерянное место',
      );
    }
  });

  test('вырожденные размеры не роняют раскладку', () {
    expect(columnsFor(10, width: 0, height: 0), greaterThanOrEqualTo(1));
  });
}
