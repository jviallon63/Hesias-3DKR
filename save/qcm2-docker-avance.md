---
title: "QCM 2 - réseaux, sécurité, BuildKit, Compose"
objective: "26 questions pour aller plus loin : réseaux, stockage et volumes, sécurité, BuildKit, Compose avancé, comportement à l'exécution."
---

Une seule bonne réponse par question. Choisissez votre réponse, puis ouvrez « Voir la réponse » : la bonne réponse passe en vert et l'explication s'affiche.

---

## 1. Réseaux

<p class="qcm-question"><strong>Q1.</strong> Quel driver réseau est utilisé par défaut quand on lance un conteneur sur un hôte Docker unique ?</p>

- **A.** `host`
- **B.** `none`
- {: .correct}**C.** `bridge`
- **D.** `overlay`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : sur un hôte unique, le driver `bridge` est celui par défaut. Chaque conteneur reçoit une IP privée et sort via NAT.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q2.</strong> Quelle est la principale différence entre le bridge par défaut et un réseau bridge créé par l'utilisateur ?</p>

- {: .correct}**A.** Le réseau défini par l'utilisateur offre la résolution DNS par nom de conteneur
- **B.** Le réseau par défaut est plus isolé
- **C.** Seul le réseau par défaut permet le NAT
- **D.** Il n'y a aucune différence
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : sur un réseau bridge défini par l'utilisateur, Docker fournit un DNS interne : les conteneurs se joignent par leur nom. Ce n'est pas le cas sur le bridge par défaut (`docker0`).

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q3.</strong> Que provoque l'option `--network host` sous Linux ?</p>

- **A.** Le conteneur reçoit une IP dédiée sur le réseau physique
- {: .correct}**B.** Le conteneur partage la pile réseau de l'hôte, sans isolation réseau
- **C.** Le conteneur n'a aucune interface réseau
- **D.** Le conteneur rejoint automatiquement un cluster Swarm
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : avec `--network host` (sous Linux), le conteneur utilise directement la pile réseau de l'hôte. Il n'y a pas d'isolation réseau et `-p` est sans effet.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q4.</strong> Quel driver permet à des conteneurs répartis sur plusieurs hôtes Docker de communiquer (mode Swarm) ?</p>

- **A.** `bridge`
- **B.** `host`
- **C.** `none`
- {: .correct}**D.** `overlay`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**D** : le driver `overlay` crée un réseau distribué entre plusieurs démons Docker (typiquement avec Swarm), au-dessus du réseau physique.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## 2. Stockage et volumes

<p class="qcm-question"><strong>Q5.</strong> Quelle est la différence entre un volume nommé et un bind mount ?</p>

- **A.** Le volume est stocké en mémoire, le bind mount sur disque
- **B.** Le bind mount est géré par Docker, le volume pointe un dossier de l'hôte
- {: .correct}**C.** Le volume est géré par Docker, le bind mount monte un chemin précis de l'hôte
- **D.** Il n'y a aucune différence fonctionnelle
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : un volume nommé est géré par Docker (dans son répertoire de données). Un bind mount monte un chemin précis de l'hôte, avec une dépendance à sa structure.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q6.</strong> Où sont stockées les données d'un montage `tmpfs` ?</p>

- **A.** Dans `/var/lib/docker/volumes`
- **B.** Dans la couche inscriptible de l'image
- **C.** Sur un stockage distant
- {: .correct}**D.** En mémoire de l'hôte, sans persistance
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**D** : un montage `tmpfs` vit en RAM. C'est rapide et utile pour des données sensibles ou temporaires, mais perdu à l'arrêt du conteneur.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q7.</strong> Quelle syntaxe monte un volume nommé en lecture seule ?</p>

- {: .correct}**A.** `-v data:/app/data:ro`
- **B.** `-v data:/app/data --readonly`
- **C.** `-v ro:data:/app/data`
- **D.** `--mount data:/app/data:r`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : le suffixe `:ro` monte le volume en lecture seule dans le conteneur.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q8.</strong> Un volume nommé vide est monté sur un répertoire contenant déjà des fichiers dans l'image. Que se passe-t-il ?</p>

- **A.** Le contenu de l'image est masqué et inaccessible
- {: .correct}**B.** Le contenu de l'image est copié dans le volume à la première utilisation
- **C.** Docker refuse de démarrer le conteneur
- **D.** Le contenu est supprimé de l'image
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : à la première utilisation, un volume nommé vide est initialisé avec le contenu de l'image à cet emplacement. Pour un bind mount, au contraire, le contenu de l'image est masqué.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## 3. Sécurité

<p class="qcm-question"><strong>Q9.</strong> Pourquoi recommande-t-on d'utiliser l'instruction `USER` avec un utilisateur non-root ?</p>

- **A.** Pour accélérer le démarrage du conteneur
- {: .correct}**B.** Pour réduire l'impact d'une compromission du conteneur
- **C.** Parce que Docker interdit root
- **D.** Pour réduire la taille de l'image
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : en cas de compromission du processus, un utilisateur non privilégié limite l'impact (écritures, accès, escalade vers l'hôte).

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q10.</strong> Que fait `--cap-drop=ALL` ?</p>

- {: .correct}**A.** Retire toutes les capabilities Linux du conteneur
- **B.** Supprime tous les volumes
- **C.** Supprime toutes les images inutilisées
- **D.** Retire tous les utilisateurs du conteneur
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : on applique le moindre privilège. On retire toutes les capabilities, puis on ajoute uniquement celles nécessaires avec `--cap-add`.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q11.</strong> Pourquoi faut-il éviter `--privileged` ?</p>

- **A.** Il ralentit fortement le conteneur
- **B.** Il interdit les volumes
- {: .correct}**C.** Il donne un accès étendu aux périphériques de l'hôte et désactive de nombreuses protections
- **D.** Il empêche l'accès au réseau
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : `--privileged` donne accès à presque tous les périphériques de l'hôte et désactive de nombreuses protections (seccomp, etc.). À réserver à des cas très précis.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q12.</strong> Quel risque présente le montage de `/var/run/docker.sock` dans un conteneur ?</p>

- **A.** Aucun, c'est un fichier en lecture seule
- {: .correct}**B.** Le conteneur peut piloter le daemon Docker, ce qui équivaut à un accès root à l'hôte
- **C.** Cela casse le DNS interne
- **D.** Cela empêche de supprimer le conteneur
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : qui contrôle le daemon peut lancer des conteneurs privilégiés montant le système de fichiers de l'hôte. C'est de fait un accès root à l'hôte.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q13.</strong> Pourquoi ne faut-il pas passer un secret via `ARG` ou `ENV` dans un Dockerfile ?</p>

- **A.** Ils sont ignorés par Docker
- **B.** Ils ralentissent le build
- **C.** Ils sont automatiquement chiffrés puis perdus
- {: .correct}**D.** Ils restent visibles dans l'historique et les métadonnées de l'image
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**D** : les valeurs d'`ARG` et d'`ENV` restent dans les métadonnées de l'image (`docker history`, `docker inspect`). Pour un secret de build, on utilise `RUN --mount=type=secret`.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## 4. Build avancé (BuildKit)

<p class="qcm-question"><strong>Q14.</strong> Avec `RUN --mount=type=secret`, comment est exposé le secret pendant le build ?</p>

- **A.** Il est stocké dans une variable `ENV` de l'image
- **B.** Il est copié dans la dernière couche
- {: .correct}**C.** Il est disponible seulement pendant l'instruction `RUN`, sans être écrit dans une couche
- **D.** Il est chiffré dans le registry
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : le secret est monté temporairement (dans `/run/secrets` par défaut) pendant l'instruction `RUN`, sans être écrit dans une couche ni dans l'historique.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q15.</strong> Que fait `docker build --target test .` ?</p>

- **A.** Définit la plateforme cible (amd64, arm64)
- {: .correct}**B.** Construit l'image en s'arrêtant à l'étape nommée « test »
- **C.** Définit le tag de l'image
- **D.** Pousse l'image vers la cible « test »
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : `--target` arrête le build à l'étape indiquée (par ex. `test`, `dev`). C'est pratique pour réutiliser un même Dockerfile pour plusieurs usages.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q16.</strong> Pourquoi installer des paquets et nettoyer le cache dans le même `RUN` ?</p>

- **A.** Pour accélérer l'exécution des commandes
- **B.** Parce que Docker limite le nombre de `RUN`
- **C.** Pour chiffrer la couche
- {: .correct}**D.** Parce qu'un fichier supprimé dans une couche ultérieure reste présent dans la couche précédente
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**D** : les couches sont immuables. Supprimer un fichier dans une couche suivante ne réduit pas la taille, car il reste dans la couche précédente. Il faut nettoyer dans la même instruction `RUN`.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q17.</strong> Que représente `FROM scratch` ?</p>

- {: .correct}**A.** Une image totalement vide, utile pour des binaires statiques
- **B.** Une image Alpine minimale
- **C.** L'image par défaut de Docker Hub
- **D.** Une image contenant uniquement un shell
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : `scratch` est une image vide, idéale pour un binaire statique (Go par exemple). L'image finale est minimale, sans shell ni outils.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q18.</strong> Quelle est la différence entre `ARG` et `ENV` ?</p>

- **A.** `ARG` existe à l'exécution, `ENV` seulement au build
- **B.** Ils sont identiques
- {: .correct}**C.** `ARG` n'existe qu'au build, `ENV` est conservé dans l'image et disponible à l'exécution
- **D.** `ENV` ne peut pas avoir de valeur par défaut
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : `ARG` n'existe que pendant le build (sauf si recopié dans un `ENV`). `ENV` est persisté dans l'image et visible à l'exécution.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## 5. Compose avancé

<p class="qcm-question"><strong>Q19.</strong> À quoi servent les `profiles` dans Docker Compose ?</p>

- **A.** Ils définissent les utilisateurs autorisés à lancer le service
- {: .correct}**B.** Ils permettent de n'activer certains services (debug, tests) que sur demande
- **C.** Ils définissent le profil CPU du conteneur
- **D.** Ils servent à charger plusieurs fichiers `.env`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : les services avec un `profile` ne démarrent que si le profile est activé (`--profile` ou `COMPOSE_PROFILES`). C'est idéal pour des outils de debug ou de test.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q20.</strong> Comment faire attendre à un service que sa base de données soit réellement prête ?</p>

- **A.** `depends_on: [db]`
- **B.** `links: [db]`
- **C.** `wait_for: db`
- {: .correct}**D.** `depends_on` avec `condition: service_healthy`, associé à un `healthcheck`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**D** : avec un `healthcheck` sur le service dont on dépend, `condition: service_healthy` fait attendre que celui-ci soit réellement sain (par exemple une base prête à accepter des connexions).

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q21.</strong> Que fait le fichier `compose.override.yaml` ?</p>

- {: .correct}**A.** Il est fusionné automatiquement avec `compose.yaml` et surcharge sa configuration
- **B.** Il remplace complètement `compose.yaml`
- **C.** Il est ignoré sauf avec l'option `-o`
- **D.** Il sert uniquement à définir des variables d'environnement
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : `compose.override.yaml` est lu et fusionné automatiquement avec `compose.yaml`. On peut ainsi ajouter des réglages de développement sans toucher au fichier principal.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q22.</strong> Quelle commande valide un fichier Compose et affiche la configuration finale (fusion et variables résolues) ?</p>

- **A.** `docker compose ps`
- **B.** `docker compose inspect`
- {: .correct}**C.** `docker compose config`
- **D.** `docker compose top`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : `docker compose config` valide le fichier et affiche la configuration finale après fusion des fichiers et interpolation des variables. Très utile pour déboguer.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## 6. Comportement à l'exécution

<p class="qcm-question"><strong>Q23.</strong> Un conteneur lancé avec `--memory=512m` dépasse cette limite. Que se passe-t-il ?</p>

- **A.** Docker augmente automatiquement la limite
- {: .correct}**B.** L'OOM killer peut tuer le processus et le conteneur s'arrête
- **C.** Le conteneur est mis en pause
- **D.** Le conteneur est migré sur un autre hôte
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : au-delà de la limite, le noyau déclenche l'OOM killer et le processus est tué. Le conteneur s'arrête (souvent avec le code 137).

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q24.</strong> Un conteneur se termine avec le code de sortie 137. Que signifie-t-il le plus souvent ?</p>

- **A.** Une sortie normale avec succès
- **B.** Une erreur de syntaxe dans le Dockerfile
- **C.** Un problème de réseau
- {: .correct}**D.** Le processus a été tué par SIGKILL (128 + 9), souvent un OOM kill
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**D** : 137 = 128 + 9. Le processus a reçu SIGKILL (signal 9), souvent à cause de l'OOM killer, d'un `docker kill` ou d'un timeout de `docker stop`.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q25.</strong> Que fait `docker stop` sur un conteneur en cours d'exécution ?</p>

- {: .correct}**A.** Il envoie SIGTERM, puis SIGKILL après un délai (10 s par défaut)
- **B.** Il envoie directement SIGKILL
- **C.** Il met le conteneur en pause
- **D.** Il envoie SIGHUP puis SIGINT
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : `docker stop` envoie SIGTERM pour un arrêt propre, puis SIGKILL après un délai (10 secondes par défaut, modifiable avec `-t`).

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q26.</strong> Pourquoi préférer `CMD ["node", "app.js"]` (forme exec) à `CMD node app.js` (forme shell) ?</p>

- **A.** Elle est plus rapide à construire
- **B.** Elle permet d'utiliser des variables d'environnement
- {: .correct}**C.** Le processus est lancé directement et reçoit les signaux (SIGTERM) sans passer par un shell
- **D.** Elle est obligatoire avec `ENTRYPOINT`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : la forme shell lance la commande via `/bin/sh -c`. Le shell devient PID 1 et peut ne pas relayer SIGTERM à l'application. La forme exec lance directement le processus, qui reçoit les signaux.

{::nomarkdown}
</details>
{:/nomarkdown}
