// Название эксперимента становится именем папки на диске оператора, поэтому его
// проверяем как имя файловой системы — до старта записи, а не после.

/// Символы, запрещённые в именах папок Windows.
const _forbiddenCharacters = r'\/:*?"<>|';

/// Имена, зарезервированные Windows: папку с таким именем создать нельзя.
const _reservedNames = <String>{
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

const _maxLength = 120;

/// Приводит введённое название к имени папки (обрезает крайние пробелы).
String experimentFolderName(String rawName) => rawName.trim();

/// Проверяет название эксперимента как имя папки.
///
/// Возвращает `null`, если имя годится, иначе — текст ошибки для оператора.
/// Специально **не чистим** имя молча: оператор должен видеть папку ровно с тем
/// названием, которое ввёл.
String? validateExperimentFolderName(String rawName) {
  final name = experimentFolderName(rawName);
  if (name.isEmpty) {
    return 'Введите название эксперимента — так будет названа папка';
  }
  if (name.length > _maxLength) {
    return 'Название слишком длинное (максимум $_maxLength символов)';
  }
  for (final code in name.codeUnits) {
    if (code < 0x20) {
      return 'В названии есть непечатаемые символы';
    }
  }
  for (final char in _forbiddenCharacters.split('')) {
    if (name.contains(char)) {
      return 'Нельзя использовать символы $_forbiddenCharacters';
    }
  }
  if (name.endsWith('.') || name.endsWith(' ')) {
    return 'Название не может заканчиваться точкой или пробелом';
  }
  final withoutExtension = name.split('.').first.toUpperCase();
  if (_reservedNames.contains(withoutExtension)) {
    return 'Это название зарезервировано системой — выберите другое';
  }
  return null;
}

/// Папка эксперимента с таким названием уже есть.
///
/// Записывать в неё нельзя: перемешаем два эксперимента и затрём `signal.bin`.
/// Поэтому старт отклоняется, а оператор вводит другое название.
class ExperimentFolderExists implements Exception {
  const ExperimentFolderExists(this.folderName);

  final String folderName;

  @override
  String toString() =>
      'Папка «$folderName» уже существует — выберите другое название';
}
