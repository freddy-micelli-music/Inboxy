# Validation Inboxy 0.3.12

## Compilation et distribution

- macOS 14 minimum ; compilation Release Intel et Apple Silicon.
- Signature locale du bundle vérifiée après extraction du ZIP ; absence de notarisation Apple.
- Installateur contenant Inboxy.app, Applications et MISE-A-JOUR.txt.
- Aucun compte, cookie de session, sauvegarde privée ou clé de signature privée dans les fichiers distribués.

## Pièces jointes

110 contrôles automatiques réussis. Les dix contrôles ajoutés couvrent les URL d’attachement et blobs, le refus des hôtes ressemblants, les réponses HTTP, les noms de fichiers dangereux, les limites UTF-8, les collisions sans écrasement et le nettoyage des téléchargements incomplets.

Une application distincte réutilisant le pilote de production a confirmé par clic : fichier blob, nouvelle fenêtre, réponse serveur attachment, doublon et interruption réseau. Les fichiers complets conservaient exactement les octets synthétiques attendus ; le transfert interrompu affichait une erreur sans fichier final trompeur. Un serveur local exigeant un cookie de session synthétique a confirmé sa présence pendant le téléchargement. Aucun compte Google réel n’était utilisé.

La pièce jointe réelle de l’utilisateur, l’enregistrement sur un autre Mac, le choix manuel d’un emplacement de secours et le bouton de révélation dans le Finder restent à confirmer.

## Autres limites

Les profils et réglages restent en dehors du bundle d’application. La sauvegarde des sessions ne garantit pas une reconnexion automatique sur un autre appareil : Google peut demander une vérification. Le relevé des compteurs et de l’Agenda dépend des pages Google chargées. Les limites de charge au-delà de 30 comptes n’ont pas fait l’objet d’une campagne prolongée.

Le parcours Sparkle de téléchargement, vérification, remplacement et relancement a réussi dans une application de test isolée, et une archive modifiée a été refusée. Le flux signé de production n’étant pas publié, l’installation de cette release reste manuelle.
