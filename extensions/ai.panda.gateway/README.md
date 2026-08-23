# 🐼 Panda AI — Extension Panda IDE

Transforme tes comptes IA web (**ChatGPT, Claude, Gemini, DeepSeek, Grok,
Mistral, Qwen, Kimi**) en **API OpenAI-compatible locale** (`:8000/v1`).

## Fonctionnement

1. **Install** (une fois) — clone [panda-ai](https://github.com/ferelking242/Panda-Ai)
   dans le rootfs Alpine + venv Python + dépendances.
2. **Start** — lance `uvicorn` en mode `BROWSER_MODE=android` dans un onglet
   Terminal dédié ("Panda AI Gateway").
3. **Sessions** — grâce au protocole v2 multi-session, chaque fournisseur vit
   dans **son propre onglet du navigateur intégré** de Panda IDE :
   - cookies isolés par profil `AI · <fournisseur>`
   - plusieurs IA actives simultanément
   - bascule instantanée (onglets gardés vivants)
4. **Utilise l'API** depuis n'importe quel client OpenAI :

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gemini-2.0-flash","messages":[{"role":"user","content":"Salut!"}]}'
```

## Commandes

| Commande | Rôle |
|---|---|
| `Panda AI: Install / Update Gateway` | Clone + venv + deps |
| `Panda AI: Start Gateway` (`ctrl+shift+a`) | Installe si besoin → démarre → ouvre les sessions |
| `Panda AI: Stop Gateway` | Arrête uvicorn |
| `Panda AI: Show Status` | install/server/provider |
| `Panda AI: Open Provider Session in Browser` | Ouvre un fournisseur dans le navigateur intégré |

## Configuration

- `ai.panda.gateway.provider` — fournisseur principal (`chatgpt`, …)
- `ai.panda.gateway.providerChain` — fallback multi-fournisseurs,
  ex `chatgpt,claude,gemini` → 3 sessions simultanées
- `ai.panda.gateway.apiToken` — token `pnd_…`

## Architecture

```
Extension (panneau) ──start──► Terminal "Panda AI Gateway" (uvicorn :8000)
                                        │ BROWSER_MODE=android
                                        ▼
                        AndroidPage(session_id="chatgpt"|"claude"|…)
                                        │ POST :9221/cmd {action, session}
                                        ▼
              Navigateur INTÉGRÉ Panda IDE — 1 session = 1 onglet isolé
```

Zéro doublon : aucune seconde WebView n'est créée, on réutilise le navigateur
de l'IDE (flutter_inappwebview). Voir
[`docs/ANDROID_MULTI_SESSION.md`](https://github.com/ferelking242/Panda-Ai/blob/main/docs/ANDROID_MULTI_SESSION.md).
