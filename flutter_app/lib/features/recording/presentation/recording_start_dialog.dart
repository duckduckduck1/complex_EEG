import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:iot/features/recording/domain/recording_models.dart';

Future<RecordingStartConfig?> showRecordingStartDialog(
  BuildContext context,
) async {
  final displayNameController = TextEditingController();
  final lpController = TextEditingController(text: '40');
  final hpController = TextEditingController(text: '0.5');
  final notchController = TextEditingController(text: '50');
  String? rootDirectory;
  var lpEnabled = true;
  var hpEnabled = true;
  var notchEnabled = false;

  try {
    return await showDialog<RecordingStartConfig>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canStart = rootDirectory != null;
            return AlertDialog(
              title: const Text('Начать эксперимент'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: displayNameController,
                        decoration: const InputDecoration(
                          labelText: 'Имя эксперимента',
                          hintText: 'опционально',
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
                                displayName: _blankToNull(
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

String? _blankToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double _parseDouble(String value, double fallback) {
  return double.tryParse(value.replaceAll(',', '.')) ?? fallback;
}
