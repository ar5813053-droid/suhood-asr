import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/asr/engine_ids.dart';
import '../engine/asr/zipformer32_model_store.dart';
import '../state/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1419),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A2332),
        title: const Text(
          'Settings',
          style: TextStyle(color: Color(0xFFE8E6E3), fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFE8E6E3)),
      ),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _SectionTitle('ASR engine'),
              const SizedBox(height: 8),
              _EngineTile(
                id: kEngineZipformerQuran32,
                selected: state.selectedEngineId == kEngineZipformerQuran32,
                onTap: () => state.selectEngine(kEngineZipformerQuran32),
              ),
              const SizedBox(height: 8),
              _EngineTile(
                id: kEngineQuranAsrSmall,
                selected: state.selectedEngineId == kEngineQuranAsrSmall,
                onTap: () => state.selectEngine(kEngineQuranAsrSmall),
              ),
              const SizedBox(height: 8),
              Text(
                'No automatic fallback. Switching engines stops recording.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
              const SizedBox(height: 24),
              const _SectionTitle('Zipformer Quran 3.2 installation'),
              const SizedBox(height: 8),
              _ZipformerInstallCard(state: state),
              const SizedBox(height: 24),
              const _SectionTitle('About recognition'),
              const SizedBox(height: 8),
              Text(
                'AI recognition can be wrong and is not a substitute for a '
                'qualified Quran teacher. Output is not an authoritative '
                'religious ruling. The app is free: no ads, no subscriptions.',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF8B949E),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _EngineTile extends StatelessWidget {
  final String id;
  final bool selected;
  final VoidCallback onTap;

  const _EngineTile({
    required this.id,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A2332),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF2D6A4F)
                  : const Color(0xFF2A3544),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected
                    ? const Color(0xFF95D5B2)
                    : const Color(0xFF8B949E),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      engineDisplayName(id),
                      style: const TextStyle(
                        color: Color(0xFFE8E6E3),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      engineSubtitle(id),
                      style: const TextStyle(
                        color: Color(0xFF8B949E),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZipformerInstallCard extends StatelessWidget {
  final AppState state;
  const _ZipformerInstallCard({required this.state});

  String _stateLabel(Zipformer32InstallState s) {
    switch (s) {
      case Zipformer32InstallState.notInstalled:
        return 'Not installed';
      case Zipformer32InstallState.filesImported:
        return 'Files imported';
      case Zipformer32InstallState.error:
        return 'Error';
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = state.zipformerStore;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A3544)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Status: ${_stateLabel(store.state)}',
            style: const TextStyle(color: Color(0xFFE8E6E3), fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            store.statusDetail,
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            store.isReadyForInference
                ? 'Inference Ready: yes (${state.zipformerLastInitMs} ms init)'
                : 'Inference Ready: no',
            style: TextStyle(
              color: store.isReadyForInference
                  ? const Color(0xFF95D5B2)
                  : const Color(0xFFE9C46A),
              fontSize: 12,
            ),
          ),
          if (state.zipformerInitMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              state.zipformerInitMessage!,
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
            ),
          ],
          if (store.lastError != null) ...[
            const SizedBox(height: 8),
            Text(
              store.lastError!,
              style: const TextStyle(color: Color(0xFFE07A5F), fontSize: 12),
            ),
          ],
          if (state.isImportingZipformer) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: store.importProgress > 0 ? store.importProgress : null,
              backgroundColor: const Color(0xFF2A3544),
              color: const Color(0xFF2D6A4F),
            ),
          ],
          const SizedBox(height: 12),
          if (state.isInitializingZipformer) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(
              backgroundColor: Color(0xFF2A3544),
              color: Color(0xFF2D6A4F),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: state.isImportingZipformer ||
                          state.isInitializingZipformer
                      ? null
                      : () => state.importZipformerModel(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF95D5B2),
                    side: const BorderSide(color: Color(0xFF2D6A4F)),
                  ),
                  child: const Text('Import model files'),
                ),
              ),
              const SizedBox(width: 8),
              if (store.filesVerified)
                Expanded(
                  child: ElevatedButton(
                    onPressed: state.isImportingZipformer ||
                            state.isInitializingZipformer
                        ? null
                        : () => state.loadZipformerEngine(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D6A4F),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      store.isReadyForInference ? 'Reload engine' : 'Load engine',
                    ),
                  ),
                ),
            ],
          ),
          if (store.filesVerified || store.isReadyForInference)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: state.isImportingZipformer ||
                        state.isInitializingZipformer
                    ? null
                    : () => state.clearZipformerModel(),
                child: const Text('Remove files', style: TextStyle(fontSize: 12)),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Select ${Zipformer32Specs.onnxFileName} and '
            '${Zipformer32Specs.tokensFileName} from device storage.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
