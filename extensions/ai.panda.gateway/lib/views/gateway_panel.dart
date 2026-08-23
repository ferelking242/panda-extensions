/// PandaAiPanel — vue sidebar de l'extension Panda AI.
///
/// Rendu par l'hôte de vues de l'IDE quand la contribution
/// `views.sidebar` du manifest est activée.
library panda_ai.views.gateway_panel;

import 'package:flutter/material.dart';

import '../extension.dart';

const _kProviders = [
  'chatgpt', 'claude', 'gemini', 'deepseek',
  'grok', 'mistral', 'qwen', 'kimi',
];

class PandaAiPanel extends StatelessWidget {
  final PandaAiExtension extension;

  const PandaAiPanel({super.key, required this.extension});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GatewayState>(
      stream: extension.onState,
      initialData: const GatewayState(message: 'Prêt'),
      builder: (context, snap) {
        final state = snap.data!;
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── En-tête ──
                Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF00D4FF), Color(0xFF7B2FF7)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Panda AI',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text('Tes comptes IA → API locale :8000',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ]),

                const SizedBox(height: 20),

                // ── Étapes ──
                _StepTile(
                  n: 1,
                  title: 'Installer le gateway',
                  subtitle: state.progress != null && state.progress! < 100
                      ? '${state.message ?? '…'}'
                      : 'Clone + venv Python (une fois)',
                  onTap: () => extension.install(),
                  progress: state.progress,
                ),
                _StepTile(
                  n: 2,
                  title: 'Démarrer sur :8000',
                  subtitle:
                      'Mode WebView Android — sessions multi-IA simultanées',
                  onTap: () => extension.start(),
                ),

                const SizedBox(height: 16),

                // ── Fournisseurs (chips → session navigateur) ──
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _kProviders
                        .map((p) => ActionChip(
                              label: Text(p,
                                  style: const TextStyle(fontSize: 12)),
                              avatar: const Icon(Icons.open_in_browser,
                                  size: 14),
                              onPressed: () =>
                                  extension.setProvider(p).then((_) {
                                extension.start();
                              }),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Chip = fournisseur principal au démarrage. '
                  'Chaque IA vit dans son onglet isolé du navigateur intégré.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.7)),
                ),

                const SizedBox(height: 20),

                // ── Actions principales ──
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Démarrer le gateway'),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF00A8CC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => extension.start(),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: const Text('Arrêter'),
                  onPressed: () => extension.stop(),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.dashboard_customize),
                  label: const Text('Ouvrir une session navigateur'),
                  onPressed: () => extension.pickAndOpenSession(),
                ),

                // ── Statut + console ──
                if (state.message != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(state.message!,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
                if (state.logLine != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      child: Text(state.logLine!,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════

class _StepTile extends StatelessWidget {
  final int n;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final int? progress;

  const _StepTile({
    required this.n,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: const Color(0xFF00D4FF).withValues(alpha: 0.15),
          child: Text('$n',
              style: const TextStyle(fontSize: 12, color: Color(0xFF00A8CC))),
        ),
        title: Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withValues(alpha: 0.7))),
        trailing: (progress != null && progress! < 100)
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, value: progress! > 0 ? progress! / 100 : null),
              )
            : const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}
