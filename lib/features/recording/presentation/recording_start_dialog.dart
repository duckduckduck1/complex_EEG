import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/experiment_folder_name.dart';
import 'package:eeg_app_max30003_stm32/features/recording/domain/recording_models.dart';

Future<RecordingStartConfig?> showRecordingStartDialog(
  BuildContext context,
) async {
  final displayNameController = TextEditingController();
  final lpController = TextEditingController(text: '40');
  final hpController = TextEditingController(text: '0.5');
  final notchController = TextEditingController(text: '50');
  final pwmController = TextEditingController(text: '50');
  String? rootDirectory;
  var lpEnabled = true;
  var hpEnabled = true;
  var notchEnabled = false;
  var pwmLevel = 50;

  try {
    return await showDialog<RecordingStartConfig>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final parsedPwmLevel = int.tryParse(pwmController.text.trim());
            final pwmIsValid =
                parsedPwmLevel != null &&
                parsedPwmLevel >= 1 &&
                parsedPwmLevel <= 99;
            // Название станет именем папки, поэтому проверяем его сразу.
            final nameError = validateExperimentFolderName(
              displayNameController.text,
            );
            final canStart =
                rootDirectory != null && pwmIsValid && nameError == null;
            return AlertDialog(
              title: const Text('Начать эксперимент'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        key: const Key('recording-start-name-field'),
                        controller: displayNameController,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Название эксперимента',
                          hintText: 'Мышь 1',
                          helperText: 'Так будет названа папка с данными',
                          errorText:
                              displayNameController.text.isEmpty
                                  ? null
                                  : nameError,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              rootDirectory ?? 'Папка не выбрана',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final selected = await getDirectoryPath(
                                confirmButtonText: 'Выбрать',
                              );
                              if (selected != null) {
                                setDialogState(() {
                                  rootDirectory = selected;
                                });
                              }
                            },
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Папка'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const SizedBox(width: 64, child: Text('ШИМ')),
                          Expanded(
                            child: Slider(
                              value: pwmLevel.toDouble(),
                              min: 1,
                              max: 99,
                              divisions: 98,
                              label: '$pwmLevel',
                              onChanged:
                                  (value) => setDialogState(() {
                                    pwmLevel = value.round();
                                    pwmController.text = '$pwmLevel';
                                  }),
                            ),
                          ),
                          SizedBox(
                            width: 72,
                            child: TextField(
                              controller: pwmController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                suffixText: '%',
                                errorText: pwmIsValid ? null : '1–99',
                              ),
                              onChanged:
                                  (value) => setDialogState(() {
                                    final parsed = int.tryParse(value.trim());
                                    if (parsed != null &&
                                        parsed >= 1 &&
                                        parsed <= 99) {
                                      pwmLevel = parsed;
                                    }
                                  }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _FilterRow(
                        label: 'LP',
                        enabled: lpEnabled,
                        controller: lpController,
                        onEnabledChanged:
                            (value) => setDialogState(() {
                              lpEnabled = value;
                            }),
                      ),
                      _FilterRow(
                        label: 'HP',
                        enabled: hpEnabled,
                        controller: hpController,
                        onEnabledChanged:
                            (value) => setDialogState(() {
                              hpEnabled = value;
                            }),
                      ),
                      _FilterRow(
                        label: 'Notch',
                        enabled: notchEnabled,
                        controller: notchController,
                        onEnabledChanged:
                            (value) => setDialogState(() {
                              notchEnabled = value;
                            }),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed:
                      canStart
                          ? () {
                            Navigator.pop(
                              context,
                              RecordingStartConfig(
                                rootDirectory: rootDirectory!,
                                pwmLevel: parsedPwmLevel,
                                displayName: experimentFolderName(
                                  displayNameController.text,
                                ),
                                filters: RecordingFilters(
                                  lpHz: _parseDouble(lpController.text, 40),
                                  hpHz: _parseDouble(hpController.text, 0.5),
                                  notchHz: _parseDouble(
                                    notchController.text,
                                    50,
                                  ),
                                  isLpEnabled: lpEnabled,
                                  isHpEnabled: hpEnabled,
                                  isNotchEnabled: notchEnabled,
                                ),
                              ),
                            );
                          }
                          : null,
                  child: const Text('Старт'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    displayNameController.dispose();
    lpController.dispose();
    hpController.dispose();
    notchController.dispose();
    pwmController.dispose();
  }
}

class _FilterRow extends StatelessWidget {
  final String label;
  final bool enabled;
  final TextEditingController controller;
  final ValueChanged<bool> onEnabledChanged;

  const _FilterRow({
    required this.label,
    required this.enabled,
    required this.controller,
    required this.onEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Switch(value: enabled, onChanged: onEnabledChanged),
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(suffixText: 'Hz'),
          ),
        ),
      ],
    );
  }
}

double _parseDouble(String value, double fallback) {
  return double.tryParse(value.replaceAll(',', '.')) ?? fallback;
}
