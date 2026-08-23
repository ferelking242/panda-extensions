/// Panda AI — Extension entry point.
///
/// Panda AI transforme tes comptes IA web (ChatGPT, Claude, Gemini,
/// DeepSeek, Grok, Mistral, Qwen, Kimi) en API OpenAI-compatible locale.
///
/// Workflow :
///   1. Install : clone panda-ai dans le rootfs + venv + deps
///   2. Start   : uvicorn :8000 en BROWSER_MODE=android (terminal dédié)
///   3. Sessions: chaque fournisseur = un onglet isolé du navigateur
///      intégré de Panda IDE (protocole v2 multi-session)
///   4. Stop / Status / Open Session depuis le panneau latéral
library panda_ai;

import 'dart:async';

import 'package:panda_sdk/panda_sdk.dart';

import 'gateway_service.dart';

class PandaAiExtension extends PandaExtension {
  @override
  String get id => 'ai.panda.gateway';

  @override
  String get name => 'Panda AI';

  @override
  String get version => '1.0.0';

  GatewayService? _gw;
  ExtensionContext? _ctx;

  /// Flux d'état consommé par la vue sidebar (gateway_panel).
  final StreamController<GatewayState> _state =
      StreamController<GatewayState>.broadcast();
  Stream<GatewayState> get onState => _state.stream;

  void _emit({String? message, int? progress, String? logLine}) =>
      _state.add(GatewayState(message: message, progress: progress, logLine: logLine));

  @override
  Future<void> onActivate(ExtensionContext context) async {
    _ctx = context;
    _gw = GatewayService(
      terminal: context.terminal,
      storage: context.storage,
      logger: context.logger,
      onLog: (line) => _emit(logLine: line),
    );

    context.commands.register('$id.install', (_) => install());
    context.commands.register('$id.start', (_) => start());
    context.commands.register('$id.stop', (_) => stop());
    context.commands.register('$id.status', (_) => showStatus());
    context.commands.register('$id.openSession', (_) => pickAndOpenSession());

    context.logger.info('Panda AI activé');
    // État initial asynchrone (ne bloque pas l'activation)
    unawaited(refreshStatus());
  }

  @override
  Future<void> onDeactivate() async {
    await _state.close();
  }

  // ── Commandes ──────────────────────────────────────────────────────

  Future<void> install() async {
    _emit(message: 'Installation…', progress: 0);
    final ok = await _gw!.install(
      onProgress: (p, m) => _emit(progress: p, message: m),
    );
    if (ok) {
      await _ctx!.window.showInformation('Panda AI est prêt 🐼');
    } else {
      await _ctx!.window.showError(
          'Installation échouée — consulte le panneau Panda AI pour les logs.');
    }
    await refreshStatus();
  }

  /// Démarrage intelligent : installe si besoin, puis lance le serveur,
  /// puis ouvre les sessions des fournisseurs configurés.
  Future<void> start() async {
    if (!await _gw!.isInstalled()) {
      await install();
      if (!await _gw!.isInstalled()) return;
    }
    _emit(message: 'Démarrage du gateway…', progress: null);
    final term = await _gw!.start();

    // Attendre que l'API réponde (max ~20 s) sans bloquer l'UI
    var up = false;
    for (var i = 0; i < 10 && !up; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      up = await _gw!.isRunning();
      _emit(message: up ? 'Gateway actif' : 'Démarrage… (${i * 2}s)');
    }

    if (!up) {
      await _ctx!.window.showWarning(
          'Le gateway ne répond pas encore — regarde l\'onglet '
          '"Panda AI Gateway" du terminal.');
    } else {
      await _ctx!.window.showInformation('Panda AI actif sur :8000 🐼');
    }
    unawaited(term);
    await refreshStatus();
  }

  Future<void> stop() async {
    await _gw!.stop();
    _emit(message: 'Arrêté');
    await _ctx!.window.showInformation('Panda AI arrêté.');
    await refreshStatus();
  }

  Future<void> refreshStatus() async {
    final line = await _gw!.statusLine();
    _emit(message: line);
  }

  Future<void> showStatus() async {
    final line = await _gw!.statusLine();
    await _ctx!.window.showInformation('Panda AI — $line',
        actions: ['Démarrer', 'Ouvrir une session']);
  }

  /// Sélecteur rapide de fournisseur → ouvre sa session navigateur.
  Future<void> pickAndOpenSession() async {
    const providers = [
      'chatgpt', 'claude', 'gemini', 'deepseek',
      'grok', 'mistral', 'qwen', 'kimi',
    ];
    final picked = await _ctx!.window.showQuickPick(
      providers.map((p) => p).toList(),
      title: 'Panda AI — fournisseur à ouvrir dans le navigateur',
    );
    if (picked == null) return;
    final session = await _gw!.openSession(picked);
    if (session == null) {
      await _ctx!.window.showWarning(
          'Bridge injoignable — démarre d\'abord le gateway (et panda-ide).');
    }
  }

  // Utilisé par la vue sidebar (chips de fournisseurs).
  Future<bool> isRunning() => _gw!.isRunning();
  Future<bool> isInstalled() => _gw!.isInstalled();

  Future<String> provider() => _gw!.provider();
  Future<void> setProvider(String p) => _gw!.setProvider(p);

  Future<String> providerChain() => _gw!.providerChain();
  Future<void> setProviderChain(String c) => _gw!.setProviderChain(c);

  Future<List<Map<String, dynamic>>> listSessions() => _gw!.listSessions();
}

/// État diffusé à la vue sidebar.
class GatewayState {
  final String? message;
  final int? progress; // 0..100
  final String? logLine;

  const GatewayState({this.message, this.progress, this.logLine});
}
