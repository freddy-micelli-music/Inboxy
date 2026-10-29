# Validation Inboxy 0.3.13

Version 0.3.13, build 16. Compilation Release universelle Intel et Apple Silicon.
116 contrôles réussis : ouverture du fichier sauvegardé et traitement d’une
application associée indisponible, proposition au démarrage, report Plus tard,
nouvelle proposition au clic et blocage pendant une connexion de compte.

La fenêtre de proposition a été observée dans une application indépendante,
sans compte Gmail réel. Le téléchargement WebKit a été vérifié auparavant sur
des fichiers synthétiques (blobs, fenêtres, réponses HTTP et session par cookie).
Le parcours d’installation Sparkle a été validé précédemment dans une application
de test indépendante ; il ne constitue pas un essai de la mise à jour publique.

La signature Ed25519 de l’archive et du flux est vérifiée avec la clé publique
embarquée, sans accès à la clé privée. Installation initiale de 0.3.13 nécessaire
pour cette nouvelle clé. Signature locale ; application non notariée par Apple.
