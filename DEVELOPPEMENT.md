# Inboxy

Application macOS renommée le 23 octobre 2026. L’icône reprend l’image fournie par l’utilisateur, sans modification graphique, déclinée aux tailles macOS dans `Resources/AppIcon.icns`. L’original est conservé dans `Resources/Inboxy-Original.png`.

Le nom visible et le produit sont Inboxy. Le projet de développement reste `Aeris.xcodeproj`, schéma `Aeris`, avec une cible et un produit Inboxy. L’identifiant de bundle, le dossier de données historique et le service du Trousseau sont conservés pour retrouver les comptes existants sans migration de session.

— Gmail dans une application macOS native

Projet Xcode SwiftUI + WebKit pour réunir des comptes Gmail dans des profils indépendants. Le parcours principal est désormais : **adresse e-mail → profil local → Gmail dans Inboxy**, sans ouvrir le navigateur habituel pour ce parcours.

**État : prototype.** Deux comptes réels connectés par l’utilisateur ont été vérifiés à l’écran : leurs boîtes Gmail sont distinctes et leurs sessions se restaurent après relancement. Le correctif d’identification WebKit supprime le bandeau de navigateur incompatible. Les trames internes et redirections Google régionales sont autorisées ; un échec de vérification des cookies peut déclencher une seule reprise depuis Gmail. Un bouton Réessayer reprend ensuite la navigation dans le même stockage de compte. Les autres comptes et parcours de connexion restent à tester. Une adresse saisie n’est pas une identité authentifiée. Le premier lancement propose de connecter son premier compte Gmail, sans compte ni message fictif.

## Lancer avec Xcode

1. Ouvrir `Aeris.xcodeproj`.
2. Choisir **Aeris → My Mac**.
3. Cliquer sur **▶︎** ou appuyer sur **⌘R**.

macOS 14 minimum ; Xcode 26 ou plus récent. Projet vérifié avec Xcode 27.1 / Swift 6.4 en mode langage Swift 5. Aucune dépendance externe. Signature locale ; le binaire Release fourni est universel Intel + Apple Silicon, sans notarisation de distribution.

## Ajouter un compte dans Inboxy

1. Cliquer sur **+** ou appuyer sur **⌘⇧N**.
2. Saisir l’adresse Gmail ou Google Workspace, puis éventuellement un nom et un groupe.
3. Cliquer sur **Ouvrir Gmail dans Inboxy**.
4. Effectuer la connexion sur la page Google affichée dans l’application. Vérifier le domaine affiché et l’identité du compte dans Gmail. Aucun champ de mot de passe Google n’est créé dans l’interface SwiftUI d’Inboxy.
5. Répéter pour chaque adresse : chaque profil reçoit son propre stockage WebKit persistant.

Ce parcours ne nécessite pas de projet Google Cloud. Il ne constitue pas une connexion OAuth à l’API Gmail. Les compteurs sont relevés dans Gmail avec la session indépendante de chaque profil. Une valeur non encore vérifiée reste inconnue.

Si Google affiche « navigateur non sécurisé » ou refuse la connexion intégrée, ce profil ne peut pas être considéré comme connecté. Aeris ne contourne pas ce refus et n’importe pas les cookies de Safari/Chrome. Le moteur reste le WebKit du système ; son identification est complétée par les informations de compatibilité de la version Safari installée et le nom Aeris. Les authentifications SSO externes à Google ne sont pas prises en charge dans ce prototype. Des liens externes ordinaires peuvent s’ouvrir dans le navigateur système.

## Sessions indépendantes et nombre de comptes

Chaque profil possède un UUID stable et un `WKWebsiteDataStore(forIdentifier:)` distinct. Les données de navigation ne sont donc pas volontairement partagées entre les profils. Trois vues web au maximum restent en cache ; les cookies restent dans les stockages persistants quand une vue est déchargée.

Il n’y a aucune limite de 30 comptes dans le code. La restauration de 45 profils distincts est vérifiée. Cela ne prouve pas que Google acceptera la connexion de 45 comptes ni que la charge réelle sera satisfaisante : ce test reste à faire. Le plafond du sélecteur multi-comptes d’une même session de navigateur ne sert pas de modèle de stockage à Aeris.

## Nouveautés 0.3.3 — largeur récupérée et dossiers intégrés

Le panneau Gmail d’origine reste retiré de la mise en page : sa marge gauche et sa largeur réservée sont supprimées pour élargir réellement les e-mails. Le **+** à côté de **Corbeille** déplie désormais les dossiers et libellés **dans la navigation Inboxy, sous Corbeille**, sans réafficher la barre Gmail. Le **−** replie ce volet natif. Un champ recherche les libellés ; la liste défile indépendamment des comptes.

Le volet propose En attente, Brouillons, Programmés, Tous les messages, Spam, Importants, puis les catégories et libellés présents dans la navigation du Gmail affiché. Un clic ouvre le dossier dans le stockage du compte courant. Les noms et liens proviennent uniquement des éléments de navigation Gmail ; les corps des messages ne sont pas lus. Les routes sont validées et reconstruites avec le compte courant, en conservant leur encodage. Quand la barre Inboxy est horizontale, le même bouton ouvre le volet dans une fenêtre contextuelle. L’ouverture du volet est mémorisée ; l’ancienne préférence de réaffichage du panneau Gmail ne s’applique plus.

## Version 0.3.2 — comportement remplacé par la version 0.3.3

La navigation propre à Gmail est masquée par défaut. Un petit **+** à droite de **Corbeille** dans Inboxy la réaffiche ; le **−** la masque ensuite. Le même bouton est disponible après Corbeille lorsque la navigation Inboxy est horizontale. Le choix est mémorisé et réappliqué à l’actualisation et aux autres profils. Les menus sont seulement masqués visuellement dans Gmail ; les libellés restent sur le compte et leurs compteurs peuvent encore être relevés. La règle est limitée aux documents HTTPS de `mail.google.com/mail/` et ne modifie ni les pages de connexion ni Agenda. L’intégration dépend de la structure de Gmail et pourra nécessiter une adaptation si Google la change.

## Nouveautés 0.3.1 — harmonisation de l’interface

Les deux bandeaux reprennent le fond vert très sombre de la navigation. Le texte « Profil indépendant » et sa description sont masqués ; le cadenas conserve le domaine en aide contextuelle. Le zoom affiche une loupe, le pourcentage et un curseur horizontal de 50 à 200 %, en complément des commandes clavier. L’Agenda utilise une icône de calendrier plus grande, colorée, affichant le mois et le jour. Le réglage du mode démonstration et son explication sont retirés de l’onglet Général.

## Nouveautés 0.3.0 — 24 octobre 2026

- Bandeau principal noir, y compris la zone du titre macOS, avec nom/adresse lisibles dans tous les thèmes.
- Photo du compte fournie par Gmail à la place des initiales du bandeau. Une silhouette ronde sert de remplacement pendant le chargement ou si la photo est indisponible. Les pastilles de non lus de la liste des comptes restent conservées.
- Bouton graphique de disposition : choisir À gauche, En haut, En bas ou À droite dans les quatre aperçus. Le choix reste mémorisé.
- Bouton **Agenda**, près de l’identité du compte : Google Agenda dans une fenêtre Inboxy utilisant le même stockage WebKit que ce compte. Fermer la fenêtre libère la vue ; aucun événement n’est créé automatiquement.
- **⌘− / ⌘+** : zoom du contenu Gmail, de 50 à 200 %, mémorisé par profil. **⌘0** ou clic sur le pourcentage près de « Profil indépendant » : retour à 100 %. Le menu Présentation/View contient aussi ces commandes. Le bandeau et la liste des comptes gardent leur taille.

Le zoom utilise l’API publique [WKWebView.pageZoom](https://developer.apple.com/documentation/webkit/wkwebview/pagezoom). Le partage Gmail/Agenda reste à l’intérieur du seul profil concerné, avec les [stockages WebKit identifiés](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/).

## Fonctions

- Barre latérale sombre, comptes groupés, recherche de comptes, thèmes clair/sombre/automatique.
- ⌘K : sélecteur rapide ; ⌘1–9 : comptes 1 à 9 ; ⌃Tab / ⌃⇧Tab : compte suivant/précédent.
- ⌘R : actualiser le profil courant ; ⌘N : nouveau message dans Gmail intégré pour un profil WEB.
- Les dossiers Réception, Non lus, Favoris et Envoyés naviguent dans Gmail pour un profil WEB, même si le bouton était déjà sélectionné. La sélection native suit aussi les changements de dossier effectués directement dans Gmail.
- Le compteur Réception concerne le compte sélectionné. Il suit le compteur Gmail de la vue chargée ; une valeur inconnue est affichée « — ». Une pastille ronde remplace les initiales : rouge avec le nombre de non lus, grise à zéro, « — » ou indicateur de progression avant le premier relevé. Le Dock additionne les derniers compteurs connus.
- Dans **Vos comptes**, cliquer sur **…** à droite d’un compte, ou faire un clic droit : **Renommer…** ouvre un champ de nom ; **Supprimer le compte…** ouvre une confirmation. Le nom est propre à Aeris et sauvegardé entre les lancements. La suppression retire le profil et sa session locale sans supprimer le compte Google ni les messages Gmail.
- **⌘, → Comptes** permet aussi de modifier le nom et le groupe, ou de retirer un profil. Pendant une suppression, sa ligne est temporairement désactivée.

## Méthode API optionnelle

Le lien **Autre méthode : API Gmail…** dans l’ajout de compte conserve la lecture native déjà réalisée. Ce parcours utilise un navigateur système pour l’autorisation OAuth et reste distinct des profils WEB. Il n’est pas sélectionné par défaut.

Pour cette méthode uniquement : activer Gmail API dans Google Cloud, configurer le consentement et les utilisateurs de test, créer un client OAuth **Application de bureau**, puis importer son JSON `installed`. Les jetons sont enregistrés dans le Trousseau par UUID ; la lecture utilise `gmail.readonly`. Un compte API peut être affiché en lecture native ou dans un profil web séparé, mais ses jetons API ne connectent pas automatiquement ce profil web.

Tous les comptes WEB sont relevés en arrière-plan avec un cycle visé de 60 secondes, via leur propre stockage WebKit. Deux vues temporaires au maximum lisent le compteur de réception ; elles sont libérées après le résultat, sans toucher à la vue courante ni au cache interactif de trois vues. Le cycle démarre aussi au lancement. Si Gmail est lent ou inaccessible, un relevé expire après 20 secondes et le cycle complet peut dépasser une minute ; les cycles ne se chevauchent pas. Après un échec, le dernier chiffre connu reste affiché avec un avertissement et l’heure du dernier relevé dans l’infobulle. Aucune valeur inconnue n’est transformée en zéro. Le premier relevé ne parcourt pas individuellement les messages et ne les marque pas comme lus.

La méthode API optionnelle utilise le même rythme cible pour ses compteurs et reste nécessaire aux alertes système de ce prototype. Une hausse nette peut manquer des arrivées compensées par des lectures. La surveillance fonctionne tant qu’Inboxy tourne et que le Mac peut exécuter l’application ; elle ne tourne pas après ⌘Q et ne réveille pas le Mac en veille.

La lecture native est en lecture seule, par pages de 25 messages, avec corps texte chargé à la sélection. Elle ne marque pas les messages comme lus, ne rend pas le HTML et ne télécharge pas les pièces jointes. Nouveau message/Répondre pour un compte API ouvrent le navigateur. Le scope restreint `gmail.readonly` entraîne des exigences de vérification selon la distribution. Aucun client Google ni consentement n’a été créé automatiquement.

## Vérifications et documents

- [VALIDATION.md](VALIDATION.md) : contrôles réussis et limites des essais.
- [ARCHITECTURE.md](ARCHITECTURE.md) : séparation des profils, Google et Mailplane, stockage et étapes restantes.
- `./check.sh` : 94 contrôles, dont encodages OAuth/MIME, compatibilité des anciens comptes et persistance de 45 profils WEB.
- `./check.sh --webkit` : contrôle supplémentaire de cookies dans deux profils de test, à lancer dans un Terminal normal. Non validé dans l’environnement restreint de l’agent.
- `./build.sh` : méthode de compilation supplémentaire ; le projet Xcode reste le parcours habituel.

### Classer les comptes

Glissez un compte par son nom ou son avatar vers la position souhaitée. Une ligne verte indique l’insertion avant ou après la ligne visée. Un dépôt dans l’autre groupe déplace aussi le compte entre Travail et Personnel. L’ordre des comptes réels est conservé au relancement.

## Version 0.2.0 — 24 octobre 2026

- Corbeille, après Envoyés, ouvre le dossier du compte Gmail sélectionné. Ce bouton ne vide pas la corbeille.
- La taille minimale de contenu passe à 760 × 520 points. Le zoom natif permet de faire tenir la fenêtre dans un écran vertical.
- Le bouton **Position** dans l’en-tête déplace la navigation à gauche, à droite, en haut ou en bas. Le choix est mémorisé. Les comptes se parcourent horizontalement en haut/bas et leur glisser-déposer suit cette orientation.
- Les pages externes HTTP/HTTPS ouvertes depuis Gmail passent dans le navigateur par défaut, y compris les pages Google publiques. Les dossiers Gmail et les étapes de connexion restent dans le profil indépendant.
- Dans le Finder : sélectionner les fichiers, clic droit → **Envoyer avec Inboxy…** (ou Services → Envoyer avec Inboxy…). Choisir le compte expéditeur. Dans le brouillon Gmail, cliquer **Joindre les fichiers** ou sur le trombone pour transmettre les fichiers en attente au compte choisi. Vérifier leur présence avant l’envoi. Aucun message n’est envoyé automatiquement. Compresser les dossiers avant de les joindre.

Installer cette version dans Applications et la lancer au moins une fois pour enregistrer le service Finder. Si macOS le masque, vérifier Réglages Système → Clavier → Raccourcis clavier → Services. Les liens mailto sont aussi gérés avec choix du compte, destinataires, objet et texte. Le bouton **Utiliser Inboxy pour les liens e-mail** des réglages demande explicitement à macOS de choisir Inboxy pour ces liens. Le service Finder est distinct du bouton Partager → Mail fourni par Apple, qui n’est pas remplacé automatiquement.


Inboxy 0.3.4 — intégration Seeview-Pro (25 octobre 2026)
Accepte un document local .seeviewmail (JSON version 1) avec destinataire, objet, texte et nom du PDF voisin. Une seule demande de composition associe tous ces éléments. Contrôles : taille maximale du document, PDF local de même dossier, signature PDF et absence de traversée de chemin ou de lien symbolique sortant. La sélection du compte et la confirmation d’ajout de pièce jointe restent manuelles. Aucun envoi automatique.
Compilation Release universelle réussie. Contrat producteur/récepteur et cas invalides contrôlés. Test réel : fenêtre de choix de compte affichant destinataire, objet et Proposition.pdf ; test annulé sans envoi.

## Version 0.3.5 — raccourci SwissTransfer (26 octobre 2026)

Une icône rouge de transfert est placée juste à côté d’Agenda dans le bandeau. Sa tuile mesure 34 × 36 points, comme celle du calendrier, avec le même habillage. Le bouton ouvre https://www.swisstransfer.com/fr dans le navigateur par défaut via macOS. Aucun fichier ni adresse de compte n’est ajouté au lien. L’intégration Seeview-Pro de la version 0.3.4 reste conservée.

## Version 0.3.6 — prochain rendez-vous défilant (26 octobre 2026)

Un bandeau placé immédiatement après SwissTransfer annonce le prochain événement à venir du planning Google Agenda chargé pour le compte sélectionné : date, heure et titre, défilant de droite à gauche. Un clic ouvre la fiche correspondante dans Agenda avec la session indépendante du compte. Le relevé du compte actif se renouvelle chaque minute ; le changement de compte remplace le bandeau. Le survol suspend le défilement et le réglage macOS de réduction des animations affiche un texte fixe. Le bandeau passe sur une deuxième ligne lorsque l’espace disponible est étroit.

Les informations sont lues dans le planning rendu par Google, sans nouvelle autorisation OAuth, sans écriture d’événement et sans copie de cookies vers un autre profil. Les rendez-vous restent en mémoire. Les événements passés, annulés ou refusés reconnus sont écartés, les doublons regroupés et les journées entières prises en charge. La période effectivement chargée et les calendriers visibles dans Google déterminent les résultats : les pages futures non chargées et les calendriers masqués ne sont pas parcourus intégralement. Le message d’absence précise donc « Aucun prochain RDV affiché ». Une session expirée ou une lecture impossible propose d’ouvrir Agenda.

L’heure est interprétée dans le fuseau du navigateur/Mac : conserver le même fuseau d’affichage dans Google Agenda pour un classement correct. L’intégration dépend de la structure des pages Google. Si la fiche ne peut plus être retrouvée après le clic, Agenda reste ouvert avec une indication pour la vérifier. Les raccourcis SwissTransfer et l’intégration Seeview-Pro sont conservés.

## Version 0.3.7 — signature et disponibilité des mises à jour (27 octobre 2026)

La signature près du logo est désormais **LA BOITE À GMAIL**, dans les dispositions verticale et horizontale. Le bas de la navigation affiche la version réellement lue dans l’application, sous le relevé des comptes ; dans les dispositions horizontales, elle figure au bas à droite de la barre.

À chaque démarrage, une vérification unique interroge la dernière version stable publiée sur le dépôt public [Inboxy](https://github.com/freddy-micelli-music/Inboxy). Aucun compte GitHub, cookie Gmail ou donnée de compte n’est utilisé. Un clic sur la version permet de relancer la vérification. Si une version numérique plus récente possède un installateur Inboxy déjà téléversé, le texte annonce sa disponibilité et sa couleur évolue doucement du vert au doré puis revient, en boucle. Le réglage macOS de réduction des animations conserve une couleur fixe.

Un clic sur la nouvelle version ouvre sa page GitHub dans le navigateur ; l’installation reste manuelle. Une panne réseau, une limite de requêtes ou une réponse invalide affiche « À vérifier », sans prétendre que le logiciel est à jour. Les brouillons, préversions et liens de téléchargement hors du dépôt Inboxy sont refusés. Le numéro de version d’une publication doit suivre le format `vMAJEUR.MINEUR.CORRECTIF`, avec un fichier `Inboxy-MAJEUR.MINEUR.CORRECTIF-macOS.zip`.

Ce mécanisme signale les nouvelles versions ; il ne télécharge ni n’installe du code automatiquement. L’application reste signée localement et non notariée par Apple.

## Version 0.3.8 — premier compte Gmail (27 octobre 2026)

Une nouvelle installation affiche **Bienvenue dans Inboxy**, sans compte ni message fictif. Le bouton **Connecter mon premier compte Gmail** ouvre le formulaire de connexion intégrée existant. Aucun compte n’est ajouté avant la saisie et la validation de l’utilisateur. Le menu de démonstration et les données d’exemple ont été retirés du programme. L’écran d’accueil revient également si l’utilisateur retire son dernier compte.

Les installations existantes conservent leurs profils, leur ordre et leurs UUID. Le champ historique `isDemo` reste uniquement pour décoder les anciens fichiers et ignorer un éventuel profil fictif enregistré dans ceux-ci, sans effacer ni réécrire le fichier à la lecture. Les sessions Google sont conservées.

## Version 0.3.9 — sauvegarde privée et panneaux redimensionnables (27 octobre 2026)

### Sauvegarder et transférer les comptes

Dans **Réglages → Général → Sauvegarde et restauration**, choisir **Sauvegarder mes comptes…**. Créer un mot de passe dédié au fichier, le confirmer puis choisir son emplacement. Le fichier `.inboxybackup` contient les profils dans leur ordre, leurs noms/groupes/options, leurs cookies de session et, à partir de macOS 26, leur stockage local WebKit. Les jetons de la méthode API sont inclus lorsqu’ils sont accessibles au Trousseau. Les mots de passe Gmail ne sont pas recueillis.

Sur l’autre Mac : installer Inboxy, ouvrir **Général → Restaurer mes comptes…**, saisir le mot de passe du fichier et le sélectionner. Un aperçu indique les comptes qui seront ajoutés ; cliquer sur **Restaurer les comptes**. Les adresses déjà présentes sont ignorées, sans distinction de casse. Les comptes et sessions existants ne sont pas remplacés. Chaque compte ajouté reçoit un nouveau stockage indépendant ; l’ordre des nouveaux comptes suit celui de la sauvegarde.

Le fichier est chiffré avec AES-256-GCM et une clé dérivée du mot de passe par PBKDF2-HMAC-SHA256, avec sel aléatoire et 200 000 itérations. Inboxy ne conserve pas le mot de passe de sauvegarde. Garder le fichier privé et conserver son mot de passe séparément ; il est nécessaire pour restaurer. Les fichiers de sauvegarde sont exclus du suivi Git par défaut.

**Une connexion sans ressaisie n’est pas garantie sur un autre Mac.** Google peut invalider une session, exiger une vérification ou demander une reconnexion. Le transfert du stockage local exige macOS 26 ou plus sur les deux Mac ; les cookies sont transférables dès macOS 14. Les bases IndexedDB, les caches complets, les clés liées à l’appareil et une copie hors ligne des messages ne sont pas inclus. L’import WebKit d’une session fictive est testé localement ; une migration réelle vers un deuxième Mac avec acceptation par Google n’a pas été validée.

Les APIs publiques utilisées sont [WKHTTPCookieStore](https://developer.apple.com/documentation/webkit/wkhttpcookiestore) et [WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore). Le SDK macOS 26 est nécessaire pour compiler ; l’application garde une cible d’exécution macOS 14.

### Ajuster la place des blocs

Dans la barre latérale à gauche ou à droite, deux petites poignées vertes séparent les **dossiers Gmail**, **Travail** et **Personnel**. Faire glisser une poignée vers le haut ou le bas pour modifier les hauteurs. Chaque bloc possède son propre défilement. Les proportions sont mémorisées pour les prochains lancements ; un double-clic sur une poignée remet les proportions initiales. Le bouton + de Corbeille conserve l’accès aux dossiers et libellés dans le premier panneau. La navigation placée en haut ou en bas conserve sa présentation en ruban.

## Version 0.3.10 — dossier d’installation prêt à glisser (27 octobre 2026)

Le ZIP distribué contient un dossier **Inboxy-0.3.10** réunissant **Inboxy.app**, le raccourci **Applications** et **MISE-A-JOUR.txt**. Quitter Inboxy, faire glisser l’application sur Applications, accepter le remplacement si nécessaire, puis relancer depuis Applications. Le texte explique aussi la première installation, la conservation des comptes locaux, le transfert vers un autre Mac et la recherche de nouvelles versions.

`package.sh` génère ce dossier et son ZIP à partir d’une application déjà signée. Il vérifie la signature avant et après copie. Le schéma Xcode exécute cette préparation après la compilation et la signature ; `build.sh` l’appelle également après sa signature locale. Les sorties Xcode se trouvent dans `BUILT_PRODUCTS_DIR/Distribution`, et les sorties du script direct dans `build/Distribution` sauf répertoire personnalisé. L’alias est un lien macOS vers `/Applications`, conservé dans le ZIP. Le modèle `INSTALLATION.txt.in` reçoit automatiquement le numéro de version du programme.
