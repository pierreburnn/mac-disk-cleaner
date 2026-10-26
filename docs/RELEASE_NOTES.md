## Disk Cleaner 1.2.1

Corrections après relecture de la 1.2.0 :

- **Zoom** : pendant l'animation, la tuile qui grandit affiche déjà ses sous‑tuiles à l'échelle (plus de rectangle vide). À la fin du zoom, la treemap occupe toute la zone de l'Explorer. L'animation inverse par le fil d'Ariane fonctionne de la même manière. Nouveaux tests de disposition et d'animation.
- **Contours de sélection** : ils correspondent toujours au compteur. Une tuile sélectionnée trop petite pour afficher son nom a un contour de 3 pt et un léger fond bleu, et son nom apparaît au survol. Une sélection cachée dans un dossier réduit est signalée par un contour pointillé et un badge sur ce dossier, et le bandeau l'indique (« 1 dans un dossier réduit »).
- **Confirmation** : les chemins s'affichent en `~/…`.
- **Supprimer (N)** compte les chemins réels mis à la Corbeille, comme la confirmation. Le panneau affiche « N items · M chemins ».

## Disk Cleaner 1.2.0 (rappel)

Nouveautés demandées par Pierre :

- **Sélection multiple** : un simple clic **ajoute** une tuile à la sélection, un nouveau clic la **retire**. Toutes les tuiles sélectionnées gardent le contour bleu. **Échap** vide la sélection.
- **Panneau « Selection »** : la liste de tout ce qui est sélectionné. Les tuiles cliquées sont en tête (« Selected in explorer » : nom, chemin, taille, case à cocher, bouton ✕), les recommandations Safe to remove / Review first suivent. Le total ne compte jamais deux fois un chemin inclus dans un autre.
- **Supprimer (N)** met à la Corbeille **tout ce qui est coché** : les tuiles et les chemins réels des recommandations. Une seule confirmation liste les éléments, les chemins et le total. Seul `trashItem` est utilisé, avec les mêmes protections qu'avant (`~`, dossiers de premier niveau, hors du dossier personnel, liens symboliques). Les chemins refusés sont ignorés et signalés, puis un résumé indique « X mis à la Corbeille, Y refusés ou en erreur ». Tout est mis à jour sans nouvelle analyse.
- **Copy script / Save…** utilisent la même sélection : les tuiles cliquées sont ajoutées au script, qui n'est jamais exécuté par l'app.
- **Animation de zoom** au double‑clic (la tuile s'agrandit, ≈ 0,35 s) et animation inverse par le fil d'Ariane. Elle respecte « Réduire les animations ».
- **Légende** : libellés complets, sur deux lignes si nécessaire, sans jamais chevaucher le bouton.

**Installation :** ouvrez le `.dmg` et glissez l'app dans Applications. Au premier lancement : clic droit › Ouvrir (app non notariée), ou `xattr -dr com.apple.quarantine "/Applications/Disk Cleaner.app"`. L'espace n'est libéré qu'après avoir vidé la Corbeille.
