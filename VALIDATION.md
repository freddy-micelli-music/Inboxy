# Validation du prototype

Date : 22 octobre 2026. Machine de compilation : Mac Apple Silicon ; Xcode 27.1 ; Swift 6.4 en mode langage Swift 5 ; cible macOS 14.

## Résultats

- Compilation du projet `Aeris.xcodeproj`, schéma partagé `Aeris`, configuration Debug : réussie.
- Compilation du même projet en Release avec signature locale : réussie pour arm64 et x86_64 (binaire universel). Vérification de la signature et des fichiers de projet : réussie.
- Script de compilation directe fourni en complément : réussi avant les dernières finitions ; le livrable final est issu du projet Xcode.
- Contrôles automatisés exécutés : **66 réussis**.

Les contrôles couvrent : vecteur PKCE S256 de la RFC 7636 ; longueur du vérificateur cryptographique ; code OAuth encodé ; refus d’un state incorrect, d’un mauvais chemin, d’un state dupliqué, d’un consentement refusé ou d’un code absent ; formulaire contenant `+`, `&`, `=` et Unicode ; aller-retour Base64URL ; MIME multipart avec texte et HTML ; en-têtes insensibles à la casse ; labels et date Gmail ; sauvegarde/restauration de 45 comptes avec conservation des UUID et exclusion des comptes de démonstration ; présence de 36 comptes fictifs ; rattachement des messages à leur compte.

## Ajout intégré par adresse e-mail

Après la correction du parcours principal, le projet Debug a recompilé avec succès. Le formulaire « Un compte. Son propre espace. » a été ouvert dans l’application lancée depuis Xcode. L’activation du bouton avec une adresse synthétique valide, puis sa désactivation après effacement du champ ont été vérifiées. Le champ a été laissé vide, prêt pour l’utilisateur. L’adresse synthétique n’a pas été soumise, aucun profil de test n’a été enregistré et aucun identifiant réel n’a été saisi.

Les cinq nouveaux contrôles couvrent : normalisation et validation des adresses, compatibilité des anciens comptes API sans `webOnly`, sauvegarde/restauration de 45 profils WEB distincts, construction de l’URL Gmail avec l’adresse attendue. Ils ne valident pas le refus ou l’acceptation de la connexion par Google.

## Correctif du bandeau de compatibilité Gmail

La capture fournie par l’utilisateur montrait une boîte Gmail ouverte et un bandeau « Cette version du navigateur n’est plus compatible ». Safari installé était en version 27.0.1. La configuration de WKWebView a été complétée via l’API publique `applicationNameForUserAgent`, avec la version Safari installée et l’identification explicite d’Aeris. Aucun cookie ni stockage de profil n’a été effacé.

Le projet a recompilé en Debug et Release. L’application a été arrêtée puis relancée depuis Xcode. Une inspection complète de l’arbre d’accessibilité a confirmé : boîte Gmail affichée, absence du bandeau, absence de page de connexion et fin du chargement. La session du compte existant a donc été restaurée après relancement. Aucun message n’a été ouvert, modifié ou envoyé pour ce contrôle. Il ne valide ni les autres fonctions Gmail ni 30 comptes simultanés.

## Correction des interruptions lors de l’ajout de compte

Le deuxième profil affichait « Frame load interrupted » et une page de redirection Google `CheckCookie`. Après relancement de diagnostic, sa boîte s’est ouverte ; la trace locale a montré que la politique Aeris annulait aussi des navigations de trames `about:blank` utilisées par Gmail. Cette observation ne prouve pas à elle seule l’origine exacte de l’interruption initiale.

Le correctif autorise les documents internes `about:blank`/`about:srcdoc`, reconnaît les domaines Google régionaux à partir de la liste officielle (avec comparaison de domaines, pas une recherche de sous-chaîne), conserve les explications de refus, ignore les erreurs d’anciennes navigations remplacées et fournit Réessayer depuis Gmail. Une interruption WebKit de code 102 sur le chemin Google `CheckCookie` peut provoquer une seule reprise par durée de vie de la vue ; les autres erreurs ne déclenchent pas cette reprise. Les cookies et UUID restent conservés. Les impressions de diagnostic temporaires ont été retirées.

Huit contrôles supplémentaires passent : documents internes, exclusion des autres protocoles de cette exception, domaines régionaux, rejet des domaines ressemblants, reprise ciblée de CheckCookie, absence de reprise d’un formulaire de connexion, distinction des domaines d’erreur et identification exacte des annulations. Debug et Release compilent.

Le contrôle final de l’interface a d’abord rencontré des délais d’expiration du pilotage. Après reprise, les deux boîtes Gmail ont été observées successivement ; leurs identités sont différentes. Le compte concerné n’affichait plus l’erreur d’interruption ni le bandeau de compatibilité. Aucun message n’a été ouvert, modifié ou envoyé pour ce contrôle. Une connexion entièrement nouvelle d’un autre compte et la charge de 30+ comptes restent à tester.

## Renommage et suppression depuis la liste des comptes

Un menu « … » permanent a été ajouté à chaque ligne, avec les mêmes actions au clic droit. Renommer ouvre une feuille contenant le nom actuel, l’adresse en lecture seule, Annuler et Enregistrer. Le modèle met à jour le nom dans le dépôt JSON en conservant l’UUID, l’adresse et les identifiants de session. Un nom vide est refusé. Supprimer ouvre une confirmation qui précise le retrait d’Aeris et la conservation du compte Google et des messages.

Le modèle bloque la sélection et les actions sur un compte en cours de suppression, avec un indicateur de progression. Le retrait du stockage WebKit attend de façon asynchrone le détachement de la vue et effectue au plus quatre tentatives. Les erreurs conservent le compte dans la liste pour permettre une nouvelle tentative.

Debug et Release compilent. Dans l’application lancée depuis Xcode, le menu du premier compte, la feuille Renommer préremplie, son annulation, la confirmation de suppression et son annulation ont été vérifiés. Les trois comptes de l’utilisateur sont restés présents. Aucun nom ni compte réel n’a été modifié ou supprimé pour ce contrôle ; la suppression effective n’a pas été exécutée pendant cet essai.

## Synchronisation du dossier et du compteur Gmail

Le dossier actif est observé par URL et le nombre de non lus par titre/libellé de navigation, dans une vue isolée par compte. Le clic sur un dossier appelle désormais une action explicite : il ne dépend plus d’un changement de la valeur SwiftUI `folder`. Le compteur affiché concerne le compte sélectionné, et les compteurs inconnus restent absents plutôt que devenir zéro.

Neuf contrôles supplémentaires passent : réception dans la liste ou un message, favoris/envoyés, recherche de non lus encodée, dossiers/recherches sans correspondance, exclusion des pages de connexion, nombres français/anglais, zéro d’une boîte prête, exclusion des nombres d’objets de messages, maintien du compteur quand le titre appartient à un autre dossier.

Vérifications dans l’application lancée depuis Xcode : le profil personnel affichait 1 non lu dans Aeris et le même 1 dans le lien Réception de Gmail. Envoyés dans Aeris a ouvert `#sent` sans perdre ce compteur. Un retour à Réception a été effectué depuis le lien de Gmail ; le bouton natif Envoyés a ensuite rouvert `#sent`, bien que l’ancienne valeur native `folder` soit déjà Envoyés. Enfin, le premier profil a retrouvé son propre compteur 0, alors que l’autre profil avait 1 : le chiffre n’était plus un total global. Aucun message n’a été ouvert ni marqué comme lu pour cette vérification.

Les mises à jour sur arrivée réelle d’un nouveau message, les autres langues, toutes les variantes de disposition Gmail et les profils déchargés restent à vérifier. La surveillance système des profils non chargés reste une fonction de la méthode API optionnelle.

## Correction des redirections de connexion YouTube et Blogger

La capture de l’utilisateur montrait un refus Aeris de `accounts.youtube.com`, classé à tort comme fournisseur SSO externe. La liste des hôtes de connexion reconnaît maintenant exactement `accounts.youtube.com` et `accounts.blogger.com`, en plus des domaines Google déjà reconnus. Google répertorie le premier dans sa [liste officielle des hôtes](https://support.google.com/chrome/a/answer/6334001) ; le [code Chromium de connexion](https://chromium.googlesource.com/chromium/chromium/+/HEAD/chrome/browser/ui/sync/one_click_signin_helper.cc) documente ces deux étapes intermédiaires. Les sous-domaines supplémentaires, domaines ressemblants et pages YouTube/Blogger ordinaires ne bénéficient pas de cette exception. HTTPS et le stockage propre au profil sont conservés.

Deux contrôles supplémentaires passent : reconnaissance des hôtes pour SetSID/CheckConnection, rejet des adresses ressemblantes et des pages ordinaires. Debug et Release compilent. Après arrêt et relancement depuis Xcode, le compte concerné affiche sa propre boîte Gmail et 1 non lu dans Gmail comme dans Aeris. L’erreur de fournisseur externe et l’interruption sont absentes ; les quatre profils sont présents. Aucun identifiant n’a été saisi et aucun message n’a été ouvert ou modifié. Ce contrôle confirme la reprise de la session existante, pas une connexion entièrement nouvelle à partir d’un profil vierge.

## Contrôles non validés dans cet environnement

Le test des cookies WebKit a été tenté. L’environnement de l’agent a interdit l’écriture dans `~/Library/WebKit/CoreChecks`, ce qui a empêché la création des profils de test. Cette tentative ne valide donc pas l’isolation à l’exécution. Le test est conservé derrière l’option `./check.sh --webkit` pour être exécuté dans un Terminal normal. Il vérifie deux stockages distincts, la réouverture par UUID et le plafond du cache. Il ne vérifie pas un relancement complet de l’application.

Après autorisation de pilotage du Mac par l’utilisateur, le projet a été ouvert dans Xcode et lancé avec le schéma Aeris / My Mac. La fenêtre native, les listes et le lecteur ont été inspectés à l’écran. Le changement vers Atelier créatif, l’ouverture du sélecteur avec ⌘K, la recherche « Laboratoire » et la sélection du 36e compte avec Entrée ont été vérifiés avec succès. Le thème sombre était affiché. Les autres parcours manuels restent à vérifier.

L’utilisateur a connecté lui-même un premier compte Google réel. Aucun identifiant n’a été saisi par l’agent, aucun consentement Google n’a été accepté par l’agent et aucun message n’a été envoyé. Le parcours OAuth, les renouvellements de jetons, la réception réelle de notifications et les quotas doivent encore être validés avec le client OAuth et les comptes de test de l’utilisateur.

## Parcours manuel conseillé dans Xcode

1. Ouvrir le projet, choisir Aeris / My Mac, puis ▶︎. Vérifier les 36 comptes fictifs et le message de démonstration sélectionné.
2. Basculer entre plusieurs comptes, notamment ceux tout en bas de la liste ; filtrer les comptes par nom.
3. Essayer les dossiers, la recherche de message, ⌘K, ⌘1–9 et les raccourcis de changement de compte.
4. Tester les thèmes clair, sombre et automatique ; réduire la fenêtre à sa taille minimale ; parcourir les réglages.
5. Importer un JSON OAuth Desktop de test, autoriser un premier compte dans le navigateur, puis un second compte différent.
6. Vérifier qu’un changement de compte ne montre pas les messages du compte précédent, y compris pendant une recherche et un changement rapide.
7. Quitter et relancer : vérifier la restauration des comptes, des identités et des autorisations.
8. Activer les notifications ; attendre le relevé initial ; recevoir un nouveau message ; vérifier badge et alerte au cycle suivant. Tester un refus de notifications.
9. Couper le réseau, actualiser, rétablir le réseau et réessayer. Tester la révocation depuis Google et la reconnexion dans Aeris.
10. Dans un environnement de test, vérifier le retrait d’un compte, puis relancer et confirmer que ses données locales et son profil web ont disparu.
11. Si l’espace web est utilisé, vérifier séparément si Google accepte sa connexion intégrée. Une réussite OAuth API ne suffit pas à cette vérification.
12. Avant un usage quotidien avec 30+ comptes réels, mesurer mémoire, temps de changement de compte, durée des relevés et erreurs de quota.

## Classement par glisser-déposer — 23 octobre 2026

Le glisser-déposer transporte uniquement un UUID via un type de données propre à Aeris. Le dépôt insère avant ou après la ligne visée et adopte son groupe. L’écriture atomique du dépôt précède la publication de la nouvelle liste ; une erreur conserve l’ordre précédent. La sélection, les UUID et les sessions restent inchangés. La recherche ne réduit pas la liste utilisée pour enregistrer le mouvement.

Quatre contrôles supplémentaires couvrent les déplacements dans les deux sens, la conservation après sauvegarde/restauration, le changement de groupe sans changement d’identité et les dépôts sans effet sur soi-même ou avec un identifiant absent.

La surface de glissement utilise NSView/NSDraggingSource au-dessus du bouton de compte, avec un type de presse-papiers propre à Aeris et un rejet des sources externes. Le clic sélectionne le compte ; le déplacement commence après 4 points. Une ligne verte indique la destination et le défilement automatique est pris en charge par AppKit. Les vues et UUID de session ne sont pas recréés lors du réordonnancement.

Le contrôle dans l’application a été exécuté avec 17 comptes présents : filtrage de la liste, déplacement d’un compte du début à la fin des résultats puis retour au début, retour d’un compte depuis Personnel vers sa position initiale dans Travail. L’ordre initial a été rétabli et la recherche vidée. Aucun compte n’a été ajouté/supprimé ; aucun message n’a été ouvert ou envoyé. Les premiers essais via SwiftUI ont été remplacés par la surface AppKit. Debug et Release compilent pour cette version finale.

## Pastilles et relevé de tous les comptes — 23 octobre 2026

La liste affiche désormais des pastilles à la place des initiales, rouges pour les compteurs positifs et neutres à zéro. Le relevé autonome couvre tous les comptes réels avec deux sondes temporaires au maximum, dans leur stockage respectif, indépendamment de la vue affichée. L’horloge vise 60 secondes entre débuts de cycle ; un cycle lent termine avant le suivant. Chaque sonde expire après 20 secondes. Les erreurs préservent le dernier résultat connu et sont signalées dans la ligne et l’infobulle. Les résultats arrivés après retrait/basculement de mode sont ignorés.

Vérification dans l’application lancée depuis Xcode : 17 comptes sur 17 ont reçu un compteur et une heure de relevé, sans compte en attente ni erreur observée. Le premier cycle observé va de 00:26:28 à 00:26:40 ; le cycle suivant s’exécute automatiquement de 00:27:28 à 00:27:40, sans action manuelle. Les valeurs incluent 0, 1, 3, 4 et 151. La capture confirme les pastilles rouges et la suppression des compteurs redondants à droite. La boîte affichée est restée celle du premier compte. Aucun message n’a été ouvert, marqué comme lu ou envoyé par l’agent, aucun identifiant n’a été saisi et aucun compte n’a été ajouté ou supprimé pour ce contrôle.

Les 51 contrôles existants passent ; ils couvrent notamment l’extraction française/anglaise des compteurs, l’exclusion des titres de messages et les règles de navigation. Debug et Release compilent. Les pannes réseau, l’expiration réelle d’une session au milieu d’un cycle, la suppression pendant un relevé et la charge de plus de 30 comptes restent à éprouver en conditions réelles. La surveillance ne fonctionne pas après avoir quitté Aeris ni pendant la veille du Mac.

## Nom et icône Inboxy — 23 octobre 2026

Le produit, l’exécutable, CFBundleName/DisplayName, la fenêtre, la marque dans la barre latérale, les alertes et textes visibles portent désormais le nom Inboxy. Les tokens de compatibilité WebKit identifient aussi Inboxy. L’identifiant de bundle `fr.aeris.mail.prototype`, le service du Trousseau, le dossier de données historique et les UUID des comptes sont conservés.

L’image utilisateur 2048 × 2048 est conservée à l’identique comme source. Elle est redimensionnée pour les tailles 16 à 1024 et encapsulée dans un fichier ICNS avec les représentations Retina. L’outil iconutil a refusé le jeu d’icônes dans cet environnement ; le conteneur ICNS a donc été assemblé à partir des PNG et redécodé avec sips pour vérifier le résultat. Aucune nouvelle illustration n’a été générée.

Debug et Release compilent avec le produit `Inboxy.app`. Après relancement depuis Xcode : fenêtre et menu Inboxy, 17 comptes restaurés avec leurs compteurs et leurs sessions Gmail. La fenêtre À propos affiche Inboxy, version 0.1.0 (1), et l’icône fournie ; son aperçu a été inspecté visuellement. Aucun compte ni message n’a été modifié pour ce contrôle.

## Fenêtre À propos personnalisée

Le menu À propos d’Inboxy ouvre une fenêtre dédiée avec l’icône, le titre Inboxy en gras, la signature « LA BOITE À GMAIL. » en italique, l’éditeur Frédéric Fantino, le texte d’indépendance vis-à-vis de Google LLC, les remerciements et « © 2027 Fantino. Tous droits réservés. », selon le texte fourni par l’utilisateur. Le copyright du bundle est mis à jour avec le même libellé. La fenêtre est réutilisée entre les ouvertures.

Debug et Release compilent. Dans l’application relancée depuis Xcode, le menu français ouvre la fenêtre dédiée ; tous les paragraphes et le copyright ont été vérifiés par accessibilité et sur capture, sans texte coupé.

## Version 0.2.0 — 24 octobre 2026

51 contrôles passent (43 précédents et 8 nouveaux). Les nouveaux couvrent Corbeille ; les liens Google publics ; HTTP et redirections ; le maintien des dossiers et étapes de connexion dans le profil ; l’exclusion des protocoles exécutables ; mailto avec caractères spéciaux et rejet des pièces jointes locales par URL ; déduplication des fichiers ; refus des dossiers et faux mailto. Debug et Release compilent.

Dans l’application lancée depuis Xcode avec 20 comptes : Corbeille ouvre #trash et Gmail affiche in:trash. Haut, bas et droite ont été inspectés à l’écran, puis la barre a été remise à gauche. Le zoom natif a ramené la fenêtre à la largeur de l’écran vertical (1080 points). La limite configurée est 760 × 520 ; le pilotage du coin n’a pas réduit davantage la fenêtre pendant l’essai.

Le lien public Conditions d’utilisation a ouvert policies.google.com/terms dans Opera, navigateur par défaut du Mac, sans remplacer Gmail ni afficher d’erreur dans Inboxy. Aucun message n’a été ouvert ou marqué comme lu pour ce contrôle.

Après ajout de l’enregistrement LaunchServices au démarrage, le service Envoyer avec Inboxy apparaît dans le menu contextuel du Finder. Le fichier synthétique Inboxy-test.txt, sans donnée personnelle, ouvre le choix du compte et apparaît dans le bandeau des fichiers en attente du brouillon Gmail du compte choisi. Il a ensuite été retiré de l’attente. Le trombone Gmail ouvre un NSOpenPanel avec Joindre/Cancel, annulé sans sélection ni téléversement. Aucun e-mail n’a été envoyé, aucun fichier utilisateur n’a été transmis. Le téléversement effectif des fichiers en attente, les gros fichiers et le changement de gestionnaire mailto restent à éprouver. Le service Inboxy ne remplace pas le bouton Partager → Mail d’Apple.

Les 20 comptes restent présents ; la réception est affichée avec la barre à gauche. Les identifiants des stockages et le bundle historique sont conservés.

## Version 0.3.0 — bandeau, photo, disposition, Agenda et zoom (24 octobre 2026)

Release compilée pour arm64 et x86_64. 56 contrôles réussis, dont les bornes du zoom, sa stabilité décimale, le filtrage des hôtes des photos et l’adresse du compte dans l’URL Agenda. Les scripts temporaires de diagnostic ont été retirés.

Contrôle visuel du livrable Release : bandeau noir, véritable photo du compte identique à celle de Gmail, bouton Agenda à côté de l’identité, sélecteur sombre de quatre aperçus avec position droite sélectionnée. Les 20 profils existants sont retrouvés. Le zoom par les commandes du menu a été observé à 90 et 110 %, puis remis à 100 % par le bouton de pourcentage ; la restauration du niveau au lancement a été observée à 90 %. Les raccourcis sont déclarés dans les commandes macOS ; leur injection par l’outil de pilotage n’a pas permis de confirmer les touches sur cette disposition de clavier.

Google Agenda s’est ouvert dans une fenêtre Inboxy avec la session et l’identité du compte affiché, sans nouvelle connexion. La fenêtre a été fermée ensuite. Aucun événement créé, aucun message ouvert ni envoyé. Cette vérification ne couvre pas tous les comptes ni tous les types de comptes Workspace.

La photo est une capture limitée au rectangle de l’image de profil déjà rendue par Gmail, après validation de son URL Google HTTPS ; aucun nouveau téléchargement authentifié n’est effectué par un client réseau séparé. Silhouette de remplacement lorsque l’image est absente ou pas encore chargée. La photo reste en mémoire du processus, séparée par UUID de compte.

## Version 0.3.1 — harmonisation et curseur de zoom (24 octobre 2026)

Compilation Release universelle réussie. Inspection visuelle du livrable : fond identique aux deux bandeaux et à la navigation, textes de profil absents, loupe/pourcentage et curseur visibles, icône Agenda agrandie et colorée. Le curseur a fait passer le contenu de 80 à 110 %, puis le réglage utilisateur a été restauré à 80 %. Vérification de l’onglet Général : ni bouton ni explication de démonstration. Les 20 comptes sont retrouvés ; aucun message ouvert ou envoyé. Les contrôles automatiques ne sont pas relancés pour ces seuls changements d’interface.

## Version 0.3.2 — navigation Gmail masquée à la demande (24 octobre 2026)

Release universelle compilée ; 56 contrôles automatiques réussis. Vérification sur un profil Gmail réel : navigation Gmail et libellés absents initialement de l’affichage ; bouton + visible à droite de Corbeille dans Inboxy. Le + réaffiche les menus et libellés et devient − ; le − les masque à nouveau. Une actualisation conserve l’état masqué. Les 20 comptes sont retrouvés, le zoom du profil reste à 80 %, et le compteur connu du profil testé reste à zéro. Aucun message ouvert, modifié ou envoyé. Le parcours horizontal du nouveau bouton n’a pas été vérifié visuellement ; il réutilise la même action. Les sondes de compteur temporaires ne masquent pas leur navigation. Le relevé de la vue visible autorise uniquement dans ce mode les éléments de navigation masqués par Inboxy, afin de conserver l’accès à leur compteur DOM.

## Version 0.3.3 — dossiers sous Corbeille et largeur récupérée (24 octobre 2026)

Compilation Release universelle réussie. 59 contrôles automatiques passent, dont la validation des liens des dossiers, la déduplication, l’exclusion des doublons des dossiers natifs, l’exclusion des hôtes externes/protocoles exécutables et la conservation d’un fragment de libellé encodé avec accents et signe + tout en ciblant le compte sélectionné.

Le diagnostic de géométrie a identifié une marge gauche de 72 pixels CSS sur le conteneur Gmail .bkK. Après suppression de cette marge et rétablissement de largeurs automatiques, la capture du livrable à zoom 80 % confirme que les lignes de messages commencent au bord gauche, au lieu d’environ 58 points plus loin. La liste récupère donc réellement la largeur, sans conserver une bande vide. Les traces de diagnostic temporaires ont été retirées du code.

Contrôle du volet natif sous Corbeille : dossiers standards affichés, libellé existant retrouvé par la recherche, ouverture de sa route Gmail dans le même compte, puis retour à la réception. Le − replie le volet Inboxy ; le + le déplie ; la barre Gmail reste absente dans les deux cas. Réouverture de l’application avec le volet déplié confirmée. Les 20 comptes et le zoom de 80 % restent présents. Aucun message ouvert, modifié ou envoyé, aucun libellé créé ni supprimé. Le parcours de volet contextuel en barre horizontale n’a pas été testé visuellement. Les catégories/libellés repris dépendent des liens chargés par Gmail dans sa navigation.

## Version 0.3.5 — raccourci SwissTransfer (26 octobre 2026)

Compilation Release réussie pour Intel et Apple Silicon. Vérification visuelle : icône de transfert rouge à côté du calendrier, tuile aux mêmes dimensions de 34 × 36 points. Un clic a ouvert le navigateur par défaut Opera : titre SwissTransfer et adresse exacte https://www.swisstransfer.com/fr confirmés. Aucun fichier téléversé, aucun formulaire soumis, aucun message envoyé. Les tests automatisés ne sont pas relancés pour cet ajout de bouton et d’icône ; compilation et parcours de clic constituent la vérification ciblée.

## Version 0.3.6 — prochain rendez-vous défilant (26 octobre 2026)

Compilation Release universelle réussie ; 66 contrôles automatiques passent. Les sept nouveaux contrôles couvrent le classement chronologique et l’exclusion des événements passés/annulés, la déduplication, le décodage et la validation des dates du planning, les journées entières, les heures AM/PM, les métadonnées invalides et les conversions explicites UTC/Europe-Paris. Le scénario automatisé optionnel d’isolation WebKit n’a pas été relancé.

Contrôle réel de l’application : bandeau immédiatement après SwissTransfer, mouvement de droite à gauche observé, clic ouvrant la fiche exacte de l’événement annoncé. L’heure a été comparée à celle de la fiche Agenda. Une première interprétation erronée du fuseau a été corrigée : le paramètre d’URL ctz n’était pas appliqué par Google ; la lecture utilise maintenant le fuseau du navigateur. Deux profils réels ont été sélectionnés successivement : chacun affiche un événement différent, dont une journée entière, et le retour au premier retrouve son propre rendez-vous. Les 20 comptes, leur ordre, le zoom à 80 % et la navigation à droite sont conservés. La version finale incluant le contrôle d’identité lisible a de nouveau affiché le rendez-vous à la bonne heure.

Aucun événement créé, modifié ou supprimé, aucun message envoyé et aucun identifiant saisi. Les titres privés des rendez-vous ne sont pas consignés dans cette documentation. Les sondes temporaires de diagnostic ont été retirées du code et leur fichier local supprimé.

Limites : lecture du planning chargé, sans pagination de tout le futur ni récupération des calendriers masqués. Le fuseau affiché par Google Agenda doit correspondre à celui du Mac ; les réglages de fuseau divergents n’ont pas été validés. Le renouvellement d’une minute est programmé pour le compte actif, mais un essai prolongé sur plusieurs heures n’a pas été réalisé. La pause au survol, le mode de réduction des animations et le bandeau sur deux lignes à faible largeur sont implémentés sans contrôle visuel spécifique de ces variantes. La structure du site Google peut nécessiter des adaptations ultérieures.
