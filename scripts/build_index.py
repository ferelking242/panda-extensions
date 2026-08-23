#!/usr/bin/env python3
"""build_index — génère index.json (point d'entrée ultra-rapide du registre).

Scanne extensions/<id>/panda.yaml et produit une entrée compacte par extension.
La marketplace ne lit QUE index.json (1 requête HTTP) pour tout afficher.

Usage:  python3 scripts/build_index.py
"""
import json
import os
import re
import sys
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_BASE = "https://raw.githubusercontent.com/ferelking242/panda-extensions/main"
REPO_URL = "https://github.com/ferelking242/panda-extensions"


def parse_yaml_minimal(text: str) -> dict:
    """Parser YAML minimal (mêmes conventions que panda_manifest.dart)."""
    doc: dict = {}
    stack = [(-1, doc)]
    for raw in text.split("\n"):
        line = raw.rstrip()
        if not line.strip() or line.strip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        m = re.match(r"^([^:#]+):\s*(.*)$", line.strip())
        if not m:
            continue
        key, value = m.group(1).strip(), m.group(2).strip()
        while stack and stack[-1][0] >= indent:
            stack.pop()
        parent = stack[-1][1]
        if value == "":
            parent[key] = {}
            stack.append((indent, parent[key]))
        else:
            v = value.strip("\"'")
            if v in ("true", "false"):
                parent[key] = v == "true"
            elif re.match(r"^\d+(\.\d+)*$", v):
                parent[key] = v  # garder versions en string ("1.0.0")
            else:
                parent[key] = v
    return doc


def resolve_icon(ext_dir_rel: str, ext_path: str, manifest_icon) -> dict:
    # 1) fichier local prioritaire → servi en raw URL (pas dupliqué dans le repo)
    for name in ("icon.svg", "icon.png"):
        if os.path.exists(os.path.join(ext_path, name)):
            return {"type": "url", "src": f"{RAW_BASE}/{ext_dir_rel}/{name}"}
    # 2) icône déclarée dans le manifest (lien externe)
    if isinstance(manifest_icon, dict) and manifest_icon.get("src"):
        return {"type": "url", "src": manifest_icon["src"]}
    if isinstance(manifest_icon, str):
        return {"type": "url", "src": manifest_icon}
    return {"type": "none", "src": None}


def build() -> int:
    extensions_dir = os.path.join(ROOT, "extensions")
    entries = []
    for ext_id in sorted(os.listdir(extensions_dir)):
        ext_path = os.path.join(extensions_dir, ext_id)
        yaml_path = os.path.join(ext_path, "panda.yaml")
        if not os.path.isfile(yaml_path):
            print(f"  ⚠️  skip {ext_id} (pas de panda.yaml)")
            continue
        doc = parse_yaml_minimal(open(yaml_path, encoding="utf-8").read())

        perms_raw = ""
        in_perms = False
        perms = []
        for line in open(yaml_path, encoding="utf-8"):
            s = line.strip()
            if s.startswith("permissions:"):
                in_perms = True
                continue
            if in_perms:
                if s.startswith("- ") and not s.startswith("- id:"):
                    perms.append(s[2:].strip())
                elif line.startswith(" ") is False and s:
                    in_perms = False

        icon = resolve_icon(f"extensions/{ext_id}", ext_path, doc.get("icon"))
        rel = f"extensions/{ext_id}"
        entry = {
            "id": doc.get("id", ext_id),
            "name": doc.get("name", ext_id),
            "version": doc.get("version", "0.0.0"),
            "author": doc.get("author"),
            "description": (doc.get("description") or "").strip().split("\n")[0],
            "icon": icon,
            "permissions": perms,
            "tags": [],
            "category": doc.get("category", "tools"),
            "path": rel,
            "manifest": f"{RAW_BASE}/{rel}/panda.yaml",
            "install": {"method": "files"},
            "featured": bool(doc.get("featured")),
        }
        entries.append(entry)
        print(f"  ✓ {entry['id']}@{entry['version']}")

    index = {
        "schema": "panda-registry-v1",
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "registry": {
            "name": "Panda Extensions Registry",
            "url": REPO_URL,
            "rawBase": RAW_BASE,
            "apiBase": REPO_URL.replace("https://github.com",
                                        "https://api.github.com/repos") + "/contents",
        },
        "categories": [
            {"id": "tools", "name": "Tools", "icon": "🔧"},
            {"id": "themes", "name": "Themes", "icon": "🎨"},
            {"id": "languages", "name": "Languages", "icon": "💻"},
            {"id": "ai", "name": "AI", "icon": "🤖"},
            {"id": "android", "name": "Android", "icon": "📱"},
        ],
    }

    # Nettoyage des anciens shards (sinon des fichiers obsolètes traînent)
    shards_dir = os.path.join(ROOT, "shards")
    if os.path.isdir(shards_dir):
        for f in os.listdir(shards_dir):
            os.remove(os.path.join(shards_dir, f))

    # ── Sharding : support de milliers d'extensions ──
    #  - featured : les ~20 mises en avant restent DANS index.json (affichage
    #    immédiat de la home sans requêtes supplémentaires)
    #  - le reste est découpé en shards de SHARD_SIZE, paginés à la demande
    SHARD_SIZE = 500
    featured = [e for e in entries if e.get("featured")][:20]
    rest = [e for e in entries if e not in featured]

    shards = []
    for i in range(0, len(rest), SHARD_SIZE):
        page = rest[i:i + SHARD_SIZE]
        name = f"shards/extensions-{len(shards)}.json"
        shard_path = os.path.join(ROOT, *name.split("/"))
        os.makedirs(os.path.dirname(shard_path), exist_ok=True)
        with open(shard_path, "w", encoding="utf-8") as f:
            json.dump({"schema": "panda-registry-shard-v1", "offset": i,
                       "count": len(page), "extensions": page},
                      f, ensure_ascii=False)
            f.write("\n")
        shards.append({"id": name, "count": len(page),
                       "url": f"{RAW_BASE}/{name}"})
        print(f"  📄 shard {name}: {len(page)} extensions")

    index["total"] = len(entries)
    index["featured"] = featured
    index["shards"] = {
        "size": SHARD_SIZE,
        "count": len(shards),
        "pages": shards,
    }
    if not shards:
        # petit registre : tout inline pour zéro requête supplémentaire
        index["inline"] = entries

    out = os.path.join(ROOT, "index.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"\n✅ {out} — {len(entries)} extension(s)")
    return 0


if __name__ == "__main__":
    sys.exit(build())
