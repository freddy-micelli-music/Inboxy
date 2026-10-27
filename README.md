# Inboxy

**LA BOITE À GMAIL.**

Application macOS native pour réunir et organiser plusieurs comptes Gmail dans des sessions indépendantes.

Éditeur : **Frédéric Fantino**.

## Télécharger et installer

[Télécharger Inboxy 0.3.9 pour macOS](https://github.com/freddy-micelli-music/Inboxy/releases/download/v0.3.9/Inboxy-0.3.9-macOS.zip)

macOS 14 minimum. Application universelle pour **Apple Silicon et Intel**.

1. Quitter Inboxy si l’application est ouverte.
2. Télécharger et décompresser le fichier ZIP.
3. Glisser **Inboxy.app** dans **Applications** et remplacer l’ancienne version si nécessaire.

Cette version est un prototype avec signature locale, sans notarisation Apple. Le téléchargement ne contient aucun compte Gmail préconfiguré. Les profils existants restent stockés localement sur le Mac.

## Premier lancement

Inboxy démarre sans compte ni message fictif. Cliquer sur **Connecter mon premier compte Gmail**, saisir son adresse puis effectuer la connexion sur la page Google dans Inboxy. Les comptes déjà enregistrés sur le Mac sont conservés lors d’une mise à jour.

## Fonctions

- Plusieurs comptes Gmail avec un stockage WebKit indépendant par profil.
- Comptes renommables, suppression locale et réorganisation par glisser-déposer.
- Compteurs de messages non lus et notifications.
- Navigation repositionnable, dossiers Gmail et libellés intégrés.
- Thèmes clair/sombre et zoom du contenu.
- Sauvegarde chiffrée des profils et sessions transférables, restauration avec aperçu.
- Blocs Dossiers Gmail, Travail et Personnel redimensionnables dans la barre latérale.
- Version affichée et vérification des mises à jour au démarrage, avec signal de couleur doux et lien vers GitHub.
- Agenda du compte sélectionné, raccourci SwissTransfer et prochain rendez-vous défilant cliquable.

Le code ne fixe pas de plafond de 30 comptes. La charge réelle de plus de 30 connexions simultanées n’a pas été validée ; les politiques de connexion Google restent applicables. Le bandeau Agenda lit le planning chargé par Google, avec le fuseau du navigateur/Mac, et ne parcourt pas tous les événements futurs.

## Compiler

Ouvrir **Aeris.xcodeproj** avec Xcode, sélectionner le schéma **Aeris**, puis lancer sur **My Mac**. Le produit compilé s’appelle **Inboxy** ; les noms historiques du projet sont conservés pour la continuité des profils.

```sh
xcodebuild -project Aeris.xcodeproj -scheme Aeris -configuration Release -derivedDataPath build build
sh ./check.sh
```

Aucune dépendance externe. Voir [les détails de développement](DEVELOPPEMENT.md), [l’architecture](ARCHITECTURE.md) et [les validations et limites](VALIDATION.md).

## À propos

Inboxy est un logiciel indépendant de traitement et d’organisation des boîtes Gmail. Il n’est pas affilié à Google LLC.

Merci d’utiliser Inboxy. Vos retours sont précieux pour faire évoluer l’application.

© 2027 Fantino. Tous droits réservés.

## Transférer ses comptes sur un autre Mac

Dans **Général**, choisir **Sauvegarder mes comptes…**, créer un mot de passe dédié et conserver le fichier `.inboxybackup` privé. Sur le Mac de destination, utiliser **Restaurer mes comptes…** avec le même mot de passe, vérifier l’aperçu puis confirmer. Les comptes déjà présents restent intacts.

La sauvegarde chiffrée inclut les cookies de session et le stockage local lorsque les deux Mac utilisent macOS 26 ou plus. Google peut demander une vérification ou une reconnexion : une migration sans ressaisie n’est pas garantie. Les messages hors ligne et le cache complet ne sont pas inclus. Pour compiler les nouvelles APIs conditionnelles, utiliser Xcode 26 ou plus récent ; l’application fonctionne toujours à partir de macOS 14.

Dans la navigation latérale, tirer les deux petites poignées entre les trois blocs pour modifier leurs hauteurs. Les proportions sont mémorisées ; un double-clic remet les valeurs initiales.
