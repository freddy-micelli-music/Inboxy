# Inboxy

**LA BOITE À GMAIL.**

Application macOS native pour réunir et organiser plusieurs comptes Gmail dans des sessions indépendantes.

Éditeur : **Frédéric Fantino**.

## Télécharger et installer

[Télécharger Inboxy 0.3.14 pour macOS](https://github.com/freddy-micelli-music/Inboxy/releases/download/v0.3.14/Inboxy-0.3.14-macOS.zip)

macOS 14 minimum. Application universelle pour **Apple Silicon et Intel**.

1. Quitter Inboxy si l’application est ouverte.
2. Télécharger et décompresser le fichier ZIP.
3. Ouvrir le dossier obtenu : **Inboxy.app**, le raccourci **Applications** et **MISE-A-JOUR.txt** sont réunis.
4. Glisser **Inboxy.app** sur ce raccourci et remplacer l’ancienne version si nécessaire.
5. Relancer Inboxy depuis **Applications**.

Cette version est un prototype avec signature locale, sans notarisation Apple. Le téléchargement ne contient aucun compte Gmail préconfiguré. Les profils existants restent stockés localement sur le Mac.

## Premier lancement

Inboxy démarre sans compte ni message fictif. Cliquer sur **Connecter mon premier compte Gmail**, saisir son adresse puis effectuer la connexion sur la page Google dans Inboxy. Les comptes déjà enregistrés sur le Mac sont conservés lors d’une mise à jour.

## Fonctions

- Téléchargement des pièces jointes vers Téléchargements, doublons préservés et accès au dernier fichier dans le Finder.
- Plusieurs comptes Gmail avec un stockage WebKit indépendant par profil.
- Comptes renommables, suppression locale et réorganisation par glisser-déposer.
- Compteurs de messages non lus et notifications.
- Navigation repositionnable, dossiers Gmail et libellés intégrés.
- Thèmes clair/sombre et zoom du contenu.
- Sauvegarde chiffrée des profils et sessions transférables, restauration avec aperçu.
- Blocs Dossiers Gmail, Travail et Personnel redimensionnables dans la barre latérale.
- Version affichée et vérification des mises à jour au démarrage, avec signal de couleur doux.
- Agenda du compte sélectionné, raccourci SwissTransfer et prochain rendez-vous défilant cliquable.

Le code ne fixe pas de plafond de 30 comptes. La charge réelle de plus de 30 connexions simultanées n’a pas été validée ; les politiques de connexion Google restent applicables. Le bandeau Agenda lit le planning chargé par Google, avec le fuseau du navigateur/Mac, et ne parcourt pas tous les événements futurs.

## Compiler

Ouvrir **Aeris.xcodeproj** avec Xcode, sélectionner le schéma **Aeris**, puis lancer sur **My Mac**. Le produit compilé s’appelle **Inboxy** ; les noms historiques du projet sont conservés pour la continuité des profils.

```sh
xcodebuild -project Aeris.xcodeproj -scheme Aeris -configuration Release -derivedDataPath build build
sh ./check.sh
```

Sparkle 2.10.0 est téléchargé depuis la distribution officielle à la première compilation puis contrôlé par SHA-256. Une connexion réseau est nécessaire à cette étape. Voir [les détails de développement](DEVELOPPEMENT.md), [l’architecture](ARCHITECTURE.md) et [les validations et limites](VALIDATION.md).

## À propos

Inboxy est un logiciel indépendant de traitement et d’organisation des boîtes Gmail. Il n’est pas affilié à Google LLC.

Merci d’utiliser Inboxy. Vos retours sont précieux pour faire évoluer l’application.

© 2027 Fantino. Tous droits réservés.

## Transférer ses comptes sur un autre Mac

Dans **Général**, choisir **Sauvegarder mes comptes…**, créer un mot de passe dédié et conserver le fichier `.inboxybackup` privé. Sur le Mac de destination, utiliser **Restaurer mes comptes…** avec le même mot de passe, vérifier l’aperçu puis confirmer. Les comptes déjà présents restent intacts.

La sauvegarde chiffrée inclut les cookies de session et le stockage local lorsque les deux Mac utilisent macOS 26 ou plus. Google peut demander une vérification ou une reconnexion : une migration sans ressaisie n’est pas garantie. Les messages hors ligne et le cache complet ne sont pas inclus. Pour compiler les nouvelles APIs conditionnelles, utiliser Xcode 26 ou plus récent ; l’application fonctionne toujours à partir de macOS 14.

Dans la navigation latérale, tirer les deux petites poignées entre les trois blocs pour modifier leurs hauteurs. Les proportions sont mémorisées ; un double-clic remet les valeurs initiales.

## Préparation automatique de l’installation

Chaque compilation avec le schéma partagé prépare, après signature, un dossier dans `Distribution` avec l’application, le raccourci Applications et le guide texte de mise à jour. Le ZIP de ce dossier est prêt à distribuer. Le script `build.sh` effectue aussi cette préparation, et `package.sh` permet de la lancer sur un bundle Inboxy déjà signé. Les fichiers `package.sh` et `INSTALLATION.txt.in` doivent rester à la racine du projet.


## Version 0.3.13 — pièces jointes

Le bouton de téléchargement Gmail est pris en charge par WebKit dans la session du compte concerné : réponses serveur, fichiers blob et fenêtres de téléchargement. Les fichiers vont dans Téléchargements ; les doublons reçoivent un numéro, et les erreurs de transfert restent visibles.

116 contrôles automatiques réussis et essais WebKit avec fichiers synthétiques, dont un serveur exigeant le cookie de session. La pièce jointe Gmail privée de chaque utilisateur reste à vérifier après installation.

Pour activer la nouvelle clé de signature, installer une fois cette version manuellement. Le flux de production et l’archive dédiée sont signés. Le remplacement et la relance ont été vérifiés dans une application de test indépendante.

[Code source complet de 0.3.14](https://github.com/freddy-micelli-music/Inboxy/releases/download/v0.3.14/Inboxy-0.3.14-Sources.zip) · [SHA-256 des archives](https://github.com/freddy-micelli-music/Inboxy/releases/download/v0.3.14/SHA256SUMS.txt)

## Nouveautés 0.3.13

Après un téléchargement réussi, le fichier est affiché dans le Finder puis ouvert
avec l’application associée par macOS. Au démarrage, Inboxy propose une nouvelle
version : « Installer et relancer » ou « Plus tard ». La validation lance le
téléchargement, la vérification de signature, l’installation et la relance.

**Activation initiale :** installez une fois la version 0.3.13 manuellement pour
intégrer la nouvelle clé publique de signature. Les versions précédentes ne
connaissent pas cette clé. Les mises à jour suivantes utilisent le flux signé
`appcast.xml` et l’archive dédiée `-Update.zip`. Les comptes restent sur le Mac.

## Nouveautés 0.3.14 - retour après envoi

Après la confirmation Gmail « Message envoyé », Inboxy revient à la boîte de réception du même compte. Une erreur ou un envoi programmé ne provoque pas de retour prématuré. Les confirmations en français et en anglais sont prises en charge.

La clé de signature de 0.3.13 est conservée : cette mise à jour est compatible avec les installations 0.3.13.
