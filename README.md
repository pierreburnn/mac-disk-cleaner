# Disk Cleaner

**Disk Cleaner** est une application macOS native (SwiftUI) qui analyse l'espace occupé par votre dossier personnel, l'affiche sous forme de *treemap* interactive et vous recommande ce qui peut être nettoyé : caches de paquets, sorties de build, SDK, modèles d'IA, worktrees oubliés…

> 🔒 **L'application ne supprime jamais rien.** Elle génère un script shell lisible que vous copiez, relisez puis exécutez vous‑même dans le Terminal si vous le souhaitez.

![Vue Catégories](docs/screenshots/explorer-category.png)

![Vue Nettoyage](docs/screenshots/explorer-cleanup.png)

*Zoom sur un dossier (clic sur la tuile « Desktop ») :*

![Zoom Desktop](docs/screenshots/explorer-desktop.png)

*Analyse réelle (dossier personnel du Mac de la CI GitHub, aucune donnée de démo) :*

![Analyse réelle](docs/screenshots/explorer-real.png)

*(Captures générées automatiquement par la CI en mode démo, avec des données fictives.)*

## Téléchargement

- Dernière version : <https://github.com/pierreburnn/mac-disk-cleaner/releases/latest>
- Lien direct v1.0.0 : [DiskCleaner-1.0.0.dmg](https://github.com/pierreburnn/mac-disk-cleaner/releases/download/v1.0.0/DiskCleaner-1.0.0.dmg)

Compatible macOS 13 Ventura et plus récent, Mac Apple Silicon **et** Intel (binaire universel).

## Installation

1. Téléchargez le fichier `DiskCleaner-1.0.0.dmg`.
2. Ouvrez‑le, puis glissez **Disk Cleaner** sur le raccourci **Applications**.
3. Éjectez le disque image.

### Premier lancement (application non signée)

L'application est signée « ad hoc » mais n'est pas notariée par Apple : Gatekeeper la bloque au premier lancement. Trois solutions, au choix :

- **Clic droit** (ou Ctrl‑clic) sur *Disk Cleaner* dans le dossier Applications › **Ouvrir**, puis confirmez **Ouvrir**.
- Ou bien : lancez l'app une fois, puis allez dans **Réglages Système › Confidentialité et sécurité**, faites défiler jusqu'au message concernant *Disk Cleaner* et cliquez sur **Ouvrir quand même**.
- Ou bien, dans le Terminal :

  ```bash
  xattr -dr com.apple.quarantine "/Applications/Disk Cleaner.app"
  ```

### Accès complet au disque (recommandé)

Certains dossiers (Mail, Messages, Safari, conteneurs d'apps…) sont protégés par macOS. Si l'analyse n'a pas pu les lire, un bandeau s'affiche avec un bouton **Open Full Disk Access settings** qui mène directement à **Réglages Système › Confidentialité et sécurité › Accès complet au disque**. Ajoutez‑y *Disk Cleaner*, puis relancez l'analyse (bouton **Rescan**).

## Utilisation

- **Statistiques** en haut : espace libre après nettoyage (espace libre actuel + gain sélectionné), total « Safe to remove », total « Needs review », et la part du disque non analysée (système et applications).
- **Explorer** : votre dossier personnel en treemap, chaque rectangle proportionnel à l'espace réellement occupé sur le disque. Cliquez sur une tuile pour l'ouvrir, utilisez le fil d'Ariane (`~ Home › …`) pour revenir en arrière. Le sélecteur **Category / Cleanup** bascule entre les couleurs par catégorie et la mise en évidence de ce qui est nettoyable (hachures vertes).
- **Recommendations** : cochez les éléments à nettoyer, dépliez une ligne (chevron) pour voir le détail et les chemins, ou révélez‑les dans le Finder.
- **Select safe** coche tous les éléments sans risque ; **Copy script** copie le script de nettoyage dans le presse‑papiers ; *Fichier › Save Script…* (⌘S) l'enregistre en `.sh`.

### Recommandations détectées

| Groupe | Élément | Emplacement |
|---|---|---|
| Safe to remove | Cache npm | `~/.npm` (`npm cache clean --force`) |
| Safe to remove | Sorties de build Next.js & Turbo | `.next`, `.turbo` dans vos projets |
| Safe to remove | Caches Gradle | `~/.gradle/caches`, `~/.gradle/wrapper/dists` |
| Safe to remove | Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` |
| Safe to remove | Caches uv & Puppeteer | `~/.cache/uv`, `~/.cache/puppeteer` |
| Safe to remove | Cache pip | `~/Library/Caches/pip`, `~/.cache/pip` |
| Safe to remove | Cache Homebrew | `~/Library/Caches/Homebrew` (`brew cleanup -s`) |
| Safe to remove | Caches Yarn & pnpm | `~/Library/Caches/Yarn`, `~/.pnpm-store`… |
| Safe to remove | Cache CocoaPods | `~/Library/Caches/CocoaPods` |
| Review first | Android SDK & émulateurs | `~/Library/Android`, `~/.android` |
| Review first | Modèles Ollama | `~/.ollama/models` |
| Review first | Worktrees (Claude Code…) | `<projet>/.claude/worktrees` |
| Review first | `node_modules` de projets inactifs | projets non modifiés depuis 30 jours |
| Review first | Simulateurs iOS | `~/Library/Developer/CoreSimulator/Devices` |
| Review first | Archives Xcode & iOS DeviceSupport | `~/Library/Developer/Xcode/…` |
| Review first | Cache Hugging Face | `~/.cache/huggingface` |
| Review first | Caches d'applications | `~/Library/Caches` (hors éléments ci‑dessus) |
| Review first | Corbeille | `~/.Trash` |

## Sécurité

- Aucune suppression, aucun déplacement de fichier n'est effectué par l'application.
- Le script généré commence par un avertissement, utilise `set -euo pipefail`, vérifie l'existence de chaque chemin avant de le supprimer, protège les chemins (espaces, apostrophes) et **refuse** tout chemin situé hors de votre dossier personnel.
- L'analyse ne suit jamais les liens symboliques et ne traverse pas les autres volumes ; les tailles affichées sont les tailles réellement allouées sur le disque.

## Compiler depuis les sources

Prérequis : macOS 13+ avec Xcode 15 ou plus récent.

```bash
swift build                 # compilation
swift test                  # tests unitaires (XCTest)
swift run DiskCleaner       # lancer l'app
swift run DiskCleaner --demo   # mode démo (données fictives)
scripts/build_app.sh 1.0.0  # .app universelle signée ad hoc + .dmg dans dist/
```

Captures d'écran en mode démo : `"dist/Disk Cleaner.app/Contents/MacOS/DiskCleaner" --snapshot ./screenshots`.
Capture d'une vraie analyse de votre dossier personnel : `… --snapshot-real ./screenshots`.

Le mode démo (`--demo` ou variable d'environnement `DISK_CLEANER_DEMO=1`) sert uniquement aux captures ; en mode normal, toutes les données viennent de l'analyse réelle.

### Architecture

- `Sources/DiskCleanerCore` : logique testable sans interface (analyse du disque, catégories, règles de nettoyage, génération du script, mise en page treemap, formatage des tailles).
- `Sources/DiskCleaner` : interface SwiftUI.
- `Tests/DiskCleanerCoreTests` : tests XCTest (faux dossier personnel temporaire, script, treemap…).
- `.github/workflows/ci.yml` : build, tests, `.dmg`, captures et publication des releases sur les tags `v*`.

## Limitations

- Application non notariée (voir « Premier lancement »).
- Seul le dossier personnel est analysé ; le reste du disque (système, applications) apparaît dans « Not scanned ».
- Les petits fichiers profonds sont regroupés dans leur dossier parent pour limiter la mémoire utilisée.

## Licence

MIT © 2026 LucyLap
