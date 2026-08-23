/// GatewayService — installe et pilote le serveur panda-ai DANS le rootfs.
///
/// Patterns validés (hérités de dev.panda.device) :
///   - Tout binaire Python/venv vit dans le rootfs → toujours via ProotRunner
///   - Le process serveur tourne dans un onglet Terminal (visible, logs
///     lisibles) comme `flutter run`
///   - Health check / sessions via curl local (:8000 API, :9221 bridge)
library panda_ai.gateway_service;

import 'dart:convert';

import 'package:panda_sdk/panda_sdk.dart';

import 'proot_runner.dart';

/// URLs des fournisseurs (miroir de src/config.py de panda-ai).
const Map<String, String> kProviderUrls = {
  'chatgpt': 'https://chatgpt.com',
  'claude': 'https://claude.ai',
  'gemini': 'https://aistudio.google.com/app/prompts/new_chat',
  'deepseek': 'https://chat.deepseek.com',
  'grok': 'https://grok.com',
  'mistral': 'https://chat.mistral.ai/chat',
  'qwen': 'https://chat.qwen.ai',
  'kimi': 'https://kimi.moonshot.cn',
};

class GatewayService {
  final TerminalAPI _terminal;
  final StorageAPI _storage;
  final PandaLogger _log;
  final void Function(String line)? onLog;

  static const installPath = '/opt/panda-ai';
  static const repoUrl = 'https://github.com/ferelking242/Panda-Ai.git';

  GatewayService({
    required TerminalAPI terminal,
    required StorageAPI storage,
    required PandaLogger logger,
    this.onLog,
  })  : _terminal = terminal,
        _storage = storage,
        _log = logger;

  // ── Config persistée ────────────────────────────────────────────────

  Future<String> provider() async =>
      await _storage.get('gateway.provider') ?? 'chatgpt';
  Future<String> providerChain() async =>
      await _storage.get('gateway.providerChain') ?? '';
  Future<String> apiToken() async =>
      await _storage.get('gateway.apiToken') ?? '';

  Future<void> setProvider(String p) => _storage.set('gateway.provider', p);
  Future<void> setProviderChain(String c) =>
      _storage.set('gateway.providerChain', c);
  Future<void> setApiToken(String t) => _storage.set('gateway.apiToken', t);

  // ── État ────────────────────────────────────────────────────────────

  Future<bool> isInstalled() async {
    final r = await ProotRunner.run(
        'test -d $installPath/src && test -f $installPath/requirements.txt && echo OK');
    return r.output.trim() == 'OK';
  }

  /// Gateway actif ? (/healthz est ouvert, sans auth)
  Future<bool> isRunning({int port = 8000}) async {
    final r = await ProotRunner.run(
        'curl -s -m 3 http://127.0.0.1:$port/healthz || true');
    return r.output.trim().isNotEmpty &&
        !r.output.contains('error') &&
        !r.output.contains('refused');
  }

  // ── Installation (une fois) ────────────────────────────────────────

  Future<bool> install({
    String branch = 'main',
    void Function(int progress, String message)? onProgress,
  }) async {
    void step(int p, String m) {
      _log.info('[PandaAI] $m');
      onProgress?.call(p, m);
      onLog?.call('▸ $m');
    }

    try {
      step(5, 'Clonage panda-ai…');
      await ProotRunner.run(
        'rm -rf /opt/panda-ai.tmp && '
        'git clone --depth 1 -b $branch $repoUrl /opt/panda-ai.tmp 2>&1 '
        '| tail -2 && rm -rf $installPath && mv /opt/panda-ai.tmp $installPath',
        onLine: onLog,
      );

      step(30, 'Création du venv Python…');
      await ProotRunner.run(
        'cd $installPath && python3 -m venv .venv 2>&1 | tail -1',
        onLine: onLog,
      );

      step(55, 'Installation des dépendances (fastapi, uvicorn, httpx)…');
      await ProotRunner.run(
        'cd $installPath && . .venv/bin/activate && '
        'pip install --no-cache-dir -r requirements.txt 2>&1 | tail -3',
        onLine: onLog,
        timeout: const Duration(minutes: 20),
      );

      step(90, 'Vérification…');
      final ok = await isInstalled();
      step(100, ok ? 'Panda AI installé 🐼' : 'Installation incomplète');
      return ok;
    } catch (e) {
      _log.error('[PandaAI] Installation échouée', e);
      return false;
    }
  }

  // ── Démarrage / arrêt ───────────────────────────────────────────────

  /// Lance le gateway dans un onglet Terminal dédié (mode WebView Android).
  /// Chaque fournisseur de la chaîne ouvrira sa propre session navigateur.
  Future<Terminal?> start({
    String? provider,
    int port = 8000,
    int bridgePort = 9221,
  }) async {
    if (!await isInstalled()) {
      _log.warning('[PandaAI] Gateway non installé');
      return null;
    }
    final prov = provider ?? await this.provider();
    final chain = await providerChain();
    final token = await apiToken();

    // Script de lancement idempotent dans le rootfs
    await ProotRunner.run(
      "cat > $installPath/start-android.sh << 'EOS'\n"
      '#!/bin/sh\n'
      'cd $installPath\n'
      '. .venv/bin/activate 2>/dev/null || true\n'
      'export BROWSER_MODE=android\n'
      'export WEBVIEW_BRIDGE_PORT=$bridgePort\n'
      'export API_HOST=127.0.0.1\n'
      'export API_PORT=$port\n'
      "export PROVIDER='$prov'\n"
      "export PROVIDER_CHAIN='$chain'\n"
      "${token.isNotEmpty ? "export API_TOKEN='$token'\n" : ''}"
      'exec python -m uvicorn src.api.server:app '
      '--host 127.0.0.1 --port $port --log-level info\n'
      'EOS\n'
      'chmod +x $installPath/start-android.sh',
      onLine: onLog,
    );

    // Stopper une instance précédente puis lancer dans le terminal intégré
    await stop();
    final term = await _terminal.createTerminal(name: 'Panda AI Gateway');
    await term.sendText('$installPath/start-android.sh');
    _log.info('[PandaAI] Gateway démarré sur :$port (provider=$prov)');
    return term;
  }

  Future<void> stop() async {
    await ProotRunner.run(
      'pkill -f "uvicorn src.api.server" 2>/dev/null; true',
      onLine: onLog,
    );
  }

  // ── Sessions WebView (protocole v2) ────────────────────────────────

  /// Crée/attache la session d'un fournisseur → un onglet isolé du
  /// navigateur intégré de Panda IDE (cookies séparés par profil).
  Future<String?> openSession(String session, {int bridgePort = 9221}) async {
    final url = kProviderUrls[session] ?? kProviderUrls['chatgpt']!;
    final body =
        '{"action":"session.create","session":"$session","url":"$url"}';
    final r = await ProotRunner.run(
      "curl -s -m 5 -X POST http://127.0.0.1:$bridgePort/cmd "
      "-H 'Content-Type: application/json' -d '$body'",
      onLine: onLog,
    );
    if (r.output.contains('"result"')) {
      _log.info('[PandaAI] session "$session" ouverte dans le navigateur');
      return session;
    }
    _log.warning('[PandaAI] bridge injoignable (${r.output.trim()})');
    return null;
  }

  /// Liste les sessions actives côté IDE.
  Future<List<Map<String, dynamic>>> listSessions(
      {int bridgePort = 9221}) async {
    final r = await ProotRunner.run(
      "curl -s -m 5 -X POST http://127.0.0.1:$bridgePort/cmd "
      "-H 'Content-Type: application/json' "
      "-d '{\"action\":\"sessions.list\"}'",
      onLine: onLog,
    );
    final out = r.output.trim();
    if (!out.contains('"result"')) return const [];
    try {
      final jsonStart = out.indexOf('{');
      final decoded = json.decode(out.substring(jsonStart))
          as Map<String, dynamic>;
      final result = decoded['result'];
      return result is List
          ? result.whereType<Map<String, dynamic>>().toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  // ── Statut formaté pour l'UI ───────────────────────────────────────

  Future<String> statusLine({int port = 8000}) async {
    final installed = await isInstalled();
    final running = installed && await isRunning(port: port);
    final prov = await provider();
    final chain = await providerChain();
    return 'install:${installed ? '✓' : '✗'} · server:'
        '${running ? '✓' : '✗'} · provider:$prov'
        '${chain.isNotEmpty ? ' · chain:$chain' : ''}';
  }
}
