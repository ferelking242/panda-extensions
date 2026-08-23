# 🐼 Panda Extensions Registry

Registre officiel des extensions **Panda IDE** — comme le marketplace VS Code, mais un dépôt GitHub.

## ⚡ Point d'entrée ultra-rapide

La marketplace ne lit qu'**un seul fichier** :

```
https://raw.githubusercontent.com/ferelking242/panda-extensions/main/index.json
```

→ 1 requête HTTP = tout le catalogue (icônes, versions, permissions, tags).

## Structure

```
panda-extensions/
├── index.json                      ← ENTRY POINT (généré, jamais édité à la main)
├── README.md
├── scripts/
│   └── build_index.py              ← génère index.json en scannant extensions/
├── assets/
│   └── icons/                      ← icônes partagées (optionnel)
└── extensions/
    └── <publisher>.<name>/         ← ex: dev.panda.device
        ├── panda.yaml              ← manifest panda-v1
        ├── icon.svg|icon.png       ← icône locale (prioritaire sur les liens)
        └── lib/*.dart              ← code source de l'extension
```

## Format du manifest `panda.yaml`

```yaml
id: dev.panda.device          # reverse-DNS unique
name: Panda Device
version: "1.0.0"              # semver string
author: "Ferelking"
description: |
  Multi-ligne supporté.

# Icône : lien externe OU fichier local icon.svg/icon.png (prioritaire)
icon:
  type: url
  src: "https://..."

panda:
  min_version: "1.0.0"
  platforms: [android, linux]

activation:
  events: [onStartup]

# Permissions IDE (sandbox) + TÉLÉPHONE (demande runtime Android)
permissions:
  - terminal            # IDE : terminal rootfs
  - network             # IDE : réseau via SDK
  - clipboard           # 📱 téléphone : demande runtime
  - camera              # 📱 téléphone : demande runtime
  - microphone          # 📱 téléphone : demande runtime

contributes:
  commands: [...]
  views:
    sidebar: [...]
  configuration: {...}
```

### Permissions disponibles

| Permission | Portée | Comportement |
|-----------|--------|--------------|
| `terminal` | IDE | Accordée après consentement à l'install |
| `network` | IDE | idem |
| `storage` | IDE | idem |
| `notifications` | IDE | idem |
| `clipboard` | 📱 Android | Dialog rationale → permission runtime |
| `camera` | 📱 Android | idem |
| `microphone` | 📱 Android | idem |
| `location` | 📱 Android | idem |
| `contacts` | 📱 Android | idem |

## Installation côté IDE (sans rebuild APK)

L'app télécharge les fichiers dans son stockage privé au runtime :

```
GET /repos/ferelking242/panda-extensions/contents/extensions/<id>?ref=main   ← liste récursive
GET raw.githubusercontent.com/.../<fichier>                                  ← chaque fichier
→ $appDir/extensions/<id>/                                                   ← PluginManager.loadAll()
```

Désinstallation = suppression du dossier + unload. **Aucun rebuild, aucun redémarrage d'APK.**

## Publier une extension

1. `extensions/mon-ext/panda.yaml` + code
2. Icône : dépose `icon.svg`/`icon.png` **ou** mets un lien dans le manifest
3. `python3 scripts/build_index.py`
4. Push → la marketplace affiche l'extension instantanément
