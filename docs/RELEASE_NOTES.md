## Disk Cleaner 1.0.0

Première version publique.

- Analyse réelle et concurrente du dossier personnel (tailles allouées sur disque, liens symboliques jamais suivis).
- Treemap interactive avec vues **Category** et **Cleanup**, navigation par fil d'Ariane.
- Recommandations « Safe to remove » / « Review first » (npm, Next.js/Turbo, Gradle, Xcode, uv, Puppeteer, pip, Homebrew, Yarn/pnpm, CocoaPods, Android SDK, Ollama, worktrees, node_modules inactifs, simulateurs iOS…).
- Génération d'un script de nettoyage relisible (**l'app ne supprime jamais rien**).
- Binaire universel (Apple Silicon + Intel), macOS 13+.

**Installation :** ouvrez le `.dmg`, glissez l'app dans Applications. Au premier lancement : clic droit › Ouvrir (app non notariée), ou `xattr -dr com.apple.quarantine "/Applications/Disk Cleaner.app"`.
