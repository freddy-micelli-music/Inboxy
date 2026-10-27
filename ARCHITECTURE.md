# Architecture — profils Gmail intégrés

## Choix révisé

Le parcours principal répond au besoin Mailplane : saisir une adresse, créer un profil indépendant, afficher Gmail et sa connexion Google directement dans Aeris. L’adresse est un nom de profil et un indice de sélection (`authuser`), pas une preuve d’identité. L’interface ne présente pas un profil créé comme un compte authentifié.

Chaque profil est associé à un UUID persistant, utilisé pour `WKWebsiteDataStore(forIdentifier:)` avant création de la WKWebView. Cette API permet plusieurs stockages persistants depuis macOS 14. Le cache contient trois vues au maximum. Détruire une vue n’efface pas son stockage. La même adresse ne crée pas de doublon local.

Cette organisation ne dépend pas d’un sélecteur Google regroupant tous les comptes dans une seule session. La capacité réelle de Google à connecter ces comptes et la consommation de mémoire doivent néanmoins être mesurées. Les tests de 45 profils portent sur les métadonnées et UUID, pas sur 45 connexions Google.

## Ce que les sources permettent d’affirmer

Mailplane indique, dans son article du 10 septembre 2026, que Mailplane 4 fonctionne encore sur macOS 27 et que Mailplane 5 est en développement. L’éditeur précise que son approche de connexion reste dépendante de Google. Cet article n’expose pas une recette technique suffisante pour reproduire son mécanisme dans WKWebView.

Google interdit de diriger ses autorisations OAuth vers des navigateurs intégrés contrôlés par l’application. Ce fait ne prouve pas que toute page de connexion Gmail de premier niveau sera systématiquement bloquée, mais il empêche de promettre une authentification intégrée universelle. Le prototype affiche la page Gmail telle que Google la sert. `applicationNameForUserAgent` complète l’identification WebKit par `Version/<Safari installée> Safari/605.1.15 Aeris/<version>`, en gardant le préfixe de moteur généré par WebKit. La version de Safari est lue dans son application installée, sans annoncer une version future. Si elle est introuvable, seul Aeris est annoncé. Cette compatibilité de détection ne remplace pas le moteur et ne garantit pas toutes les fonctionnalités de Safari. Les refus de connexion ne sont pas contournés.

Les redirections intégrées reconnaissent aussi les hôtes exacts `accounts.youtube.com` et `accounts.blogger.com`, utilisés par la connexion Google entre services. Cette exception ne s’étend pas aux autres pages YouTube/Blogger ; les stockages restent propres à chaque profil.

Le parcours API reste séparé : navigateur système → OAuth Desktop avec state et PKCE → jetons du Trousseau → Gmail API → lecteur SwiftUI. Un jeton API ne remplace pas un cookie Gmail et une connexion Safari n’authentifie pas une WKWebView.

## Répartition du code

| Fichier | Rôle |
| --- | --- |
| `Models.swift` | Comptes, UUID stables, option `webOnly` compatible avec les anciens fichiers, validation de l’adresse, dépôt JSON et compatibilité des anciens profils. |
| `AppModel.swift` | Création des profils WEB sans OAuth, navigation, persistance, lecture API et relevé borné de tous les compteurs. |
| `WebSessions.swift` | Stockages WebKit par UUID, cache de trois vues, chargement et erreurs réseau, domaine affiché, navigation Gmail et contrôle des liens. |
| `Settings.swift` | Ajout par adresse e-mail, méthode API optionnelle, sélecteur rapide, apparence et gestion des profils. |
| `Views.swift` | Barre latérale, espace Gmail intégré, écran de premier lancement, liste et lecteur API. |
| `GoogleAuth.swift` | Méthode API : loopback limité à `127.0.0.1`, PKCE S256, state aléatoire, échange de code et Trousseau. |
| `GmailAPI.swift` | Lecture, pagination, parsing MIME, renouvellement par compte et révocation. |
| `AerisApp.swift` | Fenêtre, menus, raccourcis et notifications API. |

## Stockage et identité

`~/Library/Application Support/Aeris/accounts.json` conserve noms, adresses, groupes, couleurs, options et UUID, avec écriture atomique et permissions `0600`. Les éventuels anciens profils marqués fictifs sont exclus à la lecture et à l’écriture. Les cookies des profils WEB sont gérés par les stockages persistants de WebKit, sans copie manuelle.

Les comptes API utilisent des entrées de Trousseau distinctes, service `fr.aeris.mail.oauth`, clé UUID. L’API utilise une URLSession éphémère sans cookies ni cache disque. Les messages natifs restent en mémoire. L’ancien format sans `webOnly` reste interprété comme un compte API.

L’isolation est logique à l’intérieur d’une application macOS ; elle ne protège pas contre un compromis de cette application. L’identité active doit être contrôlée dans Gmail. Les mots de passe ne sont pas saisis dans des champs natifs contrôlés par Aeris. Le prototype n’injecte aucun script dans les pages de connexion.

Le retrait d’un profil WEB ne réclame ni jeton ni appel API : il détache la vue, retire le stockage WebKit et les métadonnées. Un compte API révoque d’abord ses jetons Google. Un échec laisse le compte disponible pour réessayer.

## Limites et prochaines validations

- Une première connexion Google dans WKWebView est visible sur la capture fournie par l’utilisateur. La persistance est vérifiée séparément après le correctif de compatibilité. Cela ne valide pas les 30+ comptes ni tous les parcours MFA/SSO. Refus Google possible ; SSO externe non pris en charge.
- Les compteurs WEB suivent les vues Gmail chargées et un relevé autonome de tous les profils vise un cycle de 60 secondes. Deux vues temporaires au maximum s’ajoutent au cache interactif de trois vues ; les notifications système restent liées à la méthode API optionnelle.
- Connexion persistante après relancement, déchargement/rechargement de vues et charge de 30+ comptes à tester avec des comptes autorisés.
- La signature est locale. Developer ID, hardened runtime, sandbox adaptée et notarisation restent à préparer pour une diffusion.
- Pour une version complète : confirmer d’abord une méthode de connexion durable, puis traiter les notifications web et/ou API, les téléchargements, l’accessibilité et les campagnes de stabilité.

## Sources vérifiées le 22 octobre 2026

- [WebKit — Building Profiles with new WebKit API](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/).
- [Mailplane — Five years later: Mailplane is still flying](https://mailplaneapp.com/blog/entry/mailplane_is_still_flying.html).
- [Google — OAuth 2.0 Policies](https://developers.google.com/identity/protocols/oauth2/policies).
- [Google — OAuth 2.0 for Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app).
- [Google — Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes).

- [Apple — applicationNameForUserAgent](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/applicationnameforuseragent).
- [Google — Navigateurs compatibles avec Gmail](https://support.google.com/mail/answer/6557?hl=fr).

## Navigation Google et reprise des interruptions

La liste officielle des domaines Google régionaux est intégrée au contrôle des navigations HTTPS. La comparaison exige le domaine exact ou un sous-domaine avec un point séparateur ; un nom comme `accounts.google.com.evil.test` ne passe pas ce contrôle. Les documents internes `about:blank` et `about:srcdoc` sont permis pour les trames utilisées par Gmail. Les autres protocoles n’héritent pas de cette exception.

Les callbacks de navigation anciens sont exclus des erreurs du chargement courant. Une explication de refus de politique n’est plus remplacée par l’erreur générique WebKit 102. Une seule reprise automatique est autorisée lorsque cette erreur concerne précisément un chemin Google `CheckCookie` ; elle repart vers la boîte Gmail et ne renvoie pas le formulaire de connexion. Les reprises manuelles utilisent la même session persistante. Les fenêtres Google routées dans la vue courante conservent l’objet URLRequest, y compris sa méthode, au lieu de reconstruire un GET à partir de la seule URL.

- [Google — Liste officielle des domaines pris en charge](https://www.google.com/supported_domains).
- [Apple — Frame load interrupted by policy change](https://developer.apple.com/documentation/webkit/webkiterrorframeloadinterruptedbypolicychange).

## Synchronisation de la barre latérale avec Gmail

Chaque WKWebView possède un `GmailMailboxTracker`, rattaché à l’UUID de son compte. Il observe les propriétés publiques URL et titre par KVO. Après chargement d’une page Gmail HTTPS, un observateur DOM est installé dans un WKContentWorld isolé : il lit seulement le libellé et le compteur de navigation de la boîte de réception, puis transmet un entier au handler associé à ce compte. Le handler exige la frame principale et l’origine `https://mail.google.com`. Les documents de connexion ne reçoivent pas cet observateur. Aucun corps de message ni champ de saisie n’est lu par le script.

Les changements de hash/navigation et les mutations du libellé mettent à jour le dossier et le compteur ; les lectures sont regroupées sur 180 ms, avec une vérification de rattrapage toutes les 15 secondes dans le document chargé. Le titre Gmail peut fournir un compteur de secours pour la réception en français/anglais. Une valeur inconnue reste optionnelle et s’affiche « — » au lieu d’un zéro inventé. Le compteur global de l’application n’est plus utilisé à côté du dossier Réception : ce nombre concerne le compte choisi.

Un clic Aeris sur un dossier déclenche explicitement la navigation, y compris si le dossier avait déjà été choisi auparavant. Les changements provenant de Gmail mettent seulement à jour l’état natif et ne déclenchent pas une seconde navigation. Les recherches et dossiers sans équivalent natif ne sont pas présentés comme Réception. Le rechargement conserve le dossier courant lorsque l’URL est encore dans Gmail.

Ces compteurs restent des métadonnées de l’interface Gmail et dépendent de son DOM, qui peut évoluer. Ils ne constituent pas une synchronisation API exhaustive. Tous les profils sont relevés indépendamment du cache interactif par le mécanisme décrit ci-dessous ; une lenteur Google peut prolonger le cycle au-delà d’une minute.

- [Apple — WKWebView.title et observation KVO](https://developer.apple.com/documentation/webkit/wkwebview/title).
- [Apple — WKContentWorld et messages isolés, WWDC20](https://developer.apple.com/videos/play/wwdc2020/10188/).

## Relevé périodique des comptes et pastilles

`AppModel.pollBadges()` parcourt les comptes réels, avec deux tâches simultanées au maximum et sans chevauchement de cycles. Le délai de 60 secondes est mesuré depuis le début du cycle précédent. Les profils WEB utilisent `WebSessions.checkUnread` et une `GmailUnreadProbe` temporaire ; les profils API lisent leur label INBOX. Une génération permet d’invalider les résultats devenus obsolètes. Les retraits annulent la sonde associée et ignorent ses résultats.

Chaque sonde WKWebView réutilise uniquement `WKWebsiteDataStore(forIdentifier: account.id)`, le même nom de compatibilité Safari et le même tracker de métadonnées. Elle charge la réception sans entrer dans un message, sans héberger ni modifier la vue visible et sans accéder aux champs de connexion. Les cookies restent dans WebKit : aucun transfert vers URLSession, un autre navigateur ou un dépôt applicatif. Le résultat, une erreur ou l’expiration de 20 secondes détache les handlers/délégués et libère la vue temporaire. Les sondes ne figurent pas dans le cache des trois vues interactives.

Les résultats sont attachés à leur UUID. Une mise à jour de la vue active reçue pendant une sonde prévaut sur celle-ci. Le dernier résultat valide reste affiché en cas d’erreur, avec avertissement et heure de contrôle ; un résultat inconnu n’est jamais interprété comme zéro. La pastille remplace les initiales dans la liste : rouge si le compteur est positif, neutre à zéro, progression ou tiret avant le premier relevé. Le Dock reprend la somme des derniers résultats connus. La vérification exige qu’Aeris tourne et que le Mac soit éveillé.
