## Disk Cleaner 1.1.0

Nouveautés de l'Explorer (demandées par Pierre) :

- **Simple clic = sélection** d'une tuile (contour bleu, nom · chemin · taille affichés). Clic dans le vide ou **Échap** pour désélectionner.
- **Double‑clic = entrer** dans un dossier (tuile parente ou sous‑tuile), avec fil d'Ariane. Pas de délai sur le simple clic.
- **Bouton « Supprimer »** en bas à droite (et ⌘⌫) : met l'élément sélectionné **à la Corbeille** (`FileManager.trashItem`, récupérable) après confirmation *Mettre à la Corbeille / Annuler*. Jamais de suppression définitive.
  - Refusé hors du dossier personnel (liens symboliques résolus), pour `~` lui‑même et pour les dossiers de premier niveau protégés (`~/Library`, `~/Desktop`, `~/Documents`, `~/Downloads`, `~/Pictures`, `~/Music`, `~/Movies`…) — leur contenu reste supprimable.
  - Désactivé en mode démo et pour les tuiles regroupant de petits éléments.
  - Mise à jour immédiate de la treemap, des tailles parentes, des statistiques et des recommandations, sans nouvelle analyse.
- Corrections : les noms de tuiles ne sont tronqués que lorsque la place manque vraiment ; suppression de la fine bande « wrapper » sous `.gradle/caches` (démo) et des tuiles « fil » de moins de 6 pt.
- Le script de nettoyage est inchangé : il n'est jamais exécuté par l'app.

**Installation :** ouvrez le `.dmg`, glissez l'app dans Applications. Au premier lancement : clic droit › Ouvrir (app non notariée), ou `xattr -dr com.apple.quarantine "/Applications/Disk Cleaner.app"`. L'espace n'est libéré qu'après avoir vidé la Corbeille.
