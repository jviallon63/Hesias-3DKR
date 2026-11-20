---
title: "QCM 1 - Docker : des bases à Compose"
objective: "30 questions pour vérifier les bases : concepts, CLI, Dockerfile, registry, multi-stage et multi-plateforme, Compose."
---

Une seule bonne réponse par question. Choisissez votre réponse, puis ouvrez « Voir la réponse » : la bonne réponse passe en vert et l'explication s'affiche.

---

## 1. Concepts de base

<p class="qcm-question"><strong>Q1.</strong> Quelle est la différence fondamentale entre un conteneur et une machine virtuelle ?</p>

- **A.** Le conteneur embarque son propre noyau
- {: .correct}**B.** Le conteneur partage le noyau de l'hôte
- **C.** Le conteneur nécessite toujours un hyperviseur
- **D.** Le conteneur ne peut pas être isolé de l'hôte
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : un conteneur est un processus isolé qui partage le noyau de l'hôte, ce qui le rend plus léger et plus rapide à démarrer qu'une VM.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q2.</strong> Quels mécanismes du noyau Linux assurent l'isolation et la limitation des ressources d'un conteneur ?</p>

- **A.** iptables et systemd
- **B.** chroot et LVM
- {: .correct}**C.** Les namespaces et les cgroups
- **D.** SELinux et AppArmor uniquement
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : les namespaces isolent (processus, réseau, fichiers…) et les cgroups limitent les ressources (CPU, mémoire…).

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q3.</strong> Qu'est-ce qu'une image Docker ?</p>

- {: .correct}**A.** Un modèle en lecture seule composé de couches, utilisé pour créer des conteneurs
- **B.** Un conteneur arrêté
- **C.** Un snapshot complet d'une machine virtuelle
- **D.** Un fichier de configuration réseau
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : une image est un empilement de couches en lecture seule. Un conteneur y ajoute une couche inscriptible éphémère.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q4.</strong> Que deviennent les données écrites dans un conteneur (sans volume) lorsqu'il est supprimé ?</p>

- **A.** Elles sont sauvegardées automatiquement dans l'image
- **B.** Elles sont copiées sur l'hôte
- **C.** Elles sont conservées dans le daemon Docker
- {: .correct}**D.** Elles sont perdues
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**D** : la couche inscriptible du conteneur est supprimée avec lui. Pour persister des données, il faut utiliser un volume ou un bind mount.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## 2. La CLI

<p class="qcm-question"><strong>Q5.</strong> Quelle commande lance un conteneur nginx en arrière-plan ?</p>

- {: .correct}**A.** `docker run -d nginx`
- **B.** `docker run -b nginx`
- **C.** `docker start nginx --background`
- **D.** `docker up nginx`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : l'option `-d` (detached) lance le conteneur en arrière-plan.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q6.</strong> Comment publier le port 80 du conteneur sur le port 8080 de l'hôte ?</p>

- **A.** `-p 80:8080`
- {: .correct}**B.** `-p 8080:80`
- **C.** `--expose 8080:80`
- **D.** `-P 8080`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : la syntaxe est `-p PORT_HÔTE:PORT_CONTENEUR`.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q7.</strong> Quelle commande liste tous les conteneurs, y compris ceux à l'arrêt ?</p>

- **A.** `docker ps`
- **B.** `docker ls --all-containers`
- {: .correct}**C.** `docker ps -a`
- **D.** `docker images -a`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : `docker ps` n'affiche que les conteneurs en cours d'exécution ; `-a` affiche aussi les arrêtés.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q8.</strong> Comment ouvrir un shell interactif dans un conteneur déjà en cours d'exécution nommé « web » ?</p>

- **A.** `docker attach web sh`
- **B.** `docker run -it web sh`
- **C.** `docker shell web`
- {: .correct}**D.** `docker exec -it web sh`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**D** : `docker exec` lance une commande dans un conteneur existant ; `-it` fournit un terminal interactif.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q9.</strong> Quelle option supprime automatiquement le conteneur à son arrêt ?</p>

- {: .correct}**A.** `--rm`
- **B.** `--clean`
- **C.** `--autoremove-on-exit`
- **D.** `-d`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : `docker run --rm` est pratique pour les conteneurs jetables (tests, tâches ponctuelles).

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q10.</strong> Quelle commande suit les logs d'un conteneur en temps réel ?</p>

- **A.** `docker logs --tail web`
- {: .correct}**B.** `docker logs -f web`
- **C.** `docker inspect -f web`
- **D.** `docker events web`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : l'option `-f` (follow) fonctionne comme `tail -f`.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## 3. Le Dockerfile

<p class="qcm-question"><strong>Q11.</strong> Quelle est la différence entre CMD et ENTRYPOINT ?</p>

- **A.** Il n'y en a aucune, ce sont des synonymes
- **B.** CMD s'exécute au build, ENTRYPOINT au run
- {: .correct}**C.** CMD définit la commande ou les arguments par défaut, facilement surchargeables ; ENTRYPOINT définit l'exécutable principal du conteneur
- **D.** ENTRYPOINT ne peut pas recevoir d'arguments
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : CMD est remplacé par les arguments passés à `docker run`. ENTRYPOINT fixe l'exécutable, et CMD peut lui fournir des arguments par défaut.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q12.</strong> Quelle instruction permet en plus de copier d'extraire automatiquement une archive tar locale ?</p>

- **A.** `COPY`
- **B.** `EXTRACT`
- **C.** `RUN`
- {: .correct}**D.** `ADD`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**D** : ADD extrait les archives tar locales (et peut télécharger des URL). COPY est préférable dans les autres cas, car plus prévisible.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q13.</strong> Pour tirer parti du cache de build, quel ordre est recommandé ?</p>

- **A.** Copier tout le code source, puis installer les dépendances
- {: .correct}**B.** Copier les fichiers de dépendances, installer les dépendances, puis copier le code source
- **C.** Installer les dépendances à chaque démarrage du conteneur
- **D.** L'ordre n'a aucune influence sur le cache
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : le cache est invalidé à partir de la première couche modifiée. Les dépendances changent moins souvent que le code, donc elles passent avant.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q14.</strong> Que fait l'instruction `EXPOSE 8080` ?</p>

- {: .correct}**A.** Elle documente le port utilisé, sans le publier sur l'hôte
- **B.** Elle publie le port 8080 sur l'hôte
- **C.** Elle ouvre le port dans le pare-feu de l'hôte
- **D.** Elle empêche l'accès au port 8080
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : EXPOSE est purement informatif. Pour publier un port, il faut `-p` ou `-P` au lancement.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q15.</strong> À quoi sert le fichier `.dockerignore` ?</p>

- **A.** À ignorer certaines instructions du Dockerfile
- {: .correct}**B.** À exclure des fichiers du contexte de build
- **C.** À interdire certains conteneurs de démarrer
- **D.** À masquer des images dans `docker images`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : il réduit la taille du contexte envoyé au daemon et évite d'embarquer des fichiers inutiles ou sensibles (`.git`, `node_modules`, `.env`…).

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q16.</strong> Quelle instruction exécute une commande pendant le build et crée une nouvelle couche ?</p>

- **A.** `CMD`
- **B.** `ENTRYPOINT`
- {: .correct}**C.** `RUN`
- **D.** `START`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : RUN s'exécute au moment du build (ex. `apt-get install`). CMD et ENTRYPOINT s'appliquent au démarrage du conteneur.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## 4. La registry

<p class="qcm-question"><strong>Q17.</strong> Depuis quelle registry est téléchargée l'image avec `docker pull nginx` par défaut ?</p>

- **A.** GitHub Container Registry
- **B.** Quay.io
- **C.** Une registry locale sur l'hôte
- {: .correct}**D.** Docker Hub
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**D** : sans préfixe de registry, Docker utilise Docker Hub (`docker.io`) et le namespace `library` pour les images officielles.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q18.</strong> Quelle commande prépare l'image `app:1.0` pour un push vers `registry.example.com/team/app:1.0` ?</p>

- {: .correct}**A.** `docker tag app:1.0 registry.example.com/team/app:1.0`
- **B.** `docker rename app:1.0 registry.example.com/team/app:1.0`
- **C.** `docker push app:1.0 registry.example.com`
- **D.** `docker commit app:1.0 registry.example.com/team/app:1.0`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : `docker tag` ajoute un nom (registry/dépôt:tag) à une image existante ; il faut ensuite la pousser avec `docker push`.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q19.</strong> Quelle est la différence entre un tag et un digest ?</p>

- **A.** Le tag est immuable, le digest peut être déplacé
- **B.** Ils sont strictement équivalents
- {: .correct}**C.** Le tag est mutable, le digest (sha256) identifie un contenu précis et immuable
- **D.** Le digest n'existe que sur Docker Hub
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : un tag comme `latest` peut pointer vers une image différente au fil du temps. Le digest référence exactement un contenu, ce qui garantit la reproductibilité.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q20.</strong> Quelle commande envoie une image taguée vers une registry ?</p>

- **A.** `docker upload`
- **B.** `docker send`
- **C.** `docker publish`
- {: .correct}**D.** `docker push`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**D** : `docker push` envoie l'image vers la registry. Il faut généralement être authentifié au préalable avec `docker login`.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## 5. Multi-stage et multi-plateforme

<p class="qcm-question"><strong>Q21.</strong> Quel est le principal intérêt d'un build multi-stage ?</p>

- **A.** Construire plusieurs images en parallèle sur plusieurs machines
- {: .correct}**B.** Obtenir une image finale plus légère, sans les outils de build
- **C.** Exécuter plusieurs processus dans un même conteneur
- **D.** Avoir plusieurs Dockerfile dans un même projet
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : on compile dans une étape avec tous les outils, puis on ne copie que le résultat dans une image finale minimale. Cela réduit aussi la surface d'attaque.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q22.</strong> Comment copier un binaire produit par l'étape « build » vers l'étape finale ?</p>

- {: .correct}**A.** `COPY --from=build /app/bin /app/bin`
- **B.** `COPY build:/app/bin /app/bin`
- **C.** `IMPORT build /app/bin`
- **D.** `ADD --stage=build /app/bin /app/bin`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : `COPY --from=<nom ou index d'étape>` récupère des fichiers produits par une étape précédente.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q23.</strong> Comment nomme-t-on une étape dans un Dockerfile multi-stage ?</p>

- **A.** `STAGE build FROM golang:1.23`
- **B.** `FROM golang:1.23 NAME build`
- {: .correct}**C.** `FROM golang:1.23 AS build`
- **D.** `LABEL stage=build`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : `FROM <image> AS <nom>` nomme l'étape, ce qui permet de la référencer avec `COPY --from` ou `--target`.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q24.</strong> Quelle commande construit une image pour plusieurs architectures ?</p>

- **A.** `docker build --arch amd64,arm64 .`
- **B.** `docker run --platform all`
- **C.** `docker multi-build .`
- {: .correct}**D.** `docker buildx build --platform linux/amd64,linux/arm64 .`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**D** : BuildKit via `buildx` permet de construire pour plusieurs plateformes en une seule commande, avec `--push` pour publier le résultat.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q25.</strong> Comment un même tag peut-il fonctionner à la fois sur amd64 et arm64 ?</p>

- **A.** Le tag contient les deux binaires dans la même couche
- **B.** Docker émule toujours l'architecture manquante
- **C.** Il faut un tag différent par architecture, sans exception
- {: .correct}**D.** Le tag pointe vers un manifest list (image index) qui référence une image par architecture
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**D** : le manifest list permet au client de récupérer automatiquement l'image correspondant à son architecture.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## 6. Docker Compose

<p class="qcm-question"><strong>Q26.</strong> Quel est le nom de fichier recommandé pour un projet Docker Compose ?</p>

- {: .correct}**A.** `compose.yaml`
- **B.** `docker.yaml`
- **C.** `Composefile`
- **D.** `services.json`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : `compose.yaml` est le nom préféré par la spécification Compose actuelle. `docker-compose.yml` reste reconnu.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q27.</strong> Quelle commande démarre tous les services d'un projet Compose en arrière-plan ?</p>

- **A.** `docker compose start --all`
- **B.** `docker compose run -d`
- {: .correct}**C.** `docker compose up -d`
- **D.** `docker compose deploy`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : `docker compose up` crée et démarre les services ; `-d` les lance en arrière-plan.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q28.</strong> Comment un service « web » joint-il un service « db » défini dans le même fichier Compose ?</p>

- {: .correct}**A.** Via le nom du service (`db`) grâce au DNS du réseau créé par Compose
- **B.** Uniquement via l'adresse IP du conteneur
- **C.** Uniquement via `localhost`
- **D.** Il faut obligatoirement publier le port de `db` sur l'hôte
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**A** : Compose crée un réseau par défaut où chaque service est résolu par son nom. Aucune publication de port n'est nécessaire entre services.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q29.</strong> Que garantit réellement `depends_on` dans sa forme simple ?</p>

- **A.** Que le service dépendant est prêt à recevoir des connexions
- {: .correct}**B.** L'ordre de démarrage des conteneurs, pas leur disponibilité
- **C.** Le redémarrage automatique en cas d'échec
- **D.** Le partage du même réseau uniquement
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**B** : `depends_on` ordonne le démarrage. Pour attendre qu'un service soit réellement prêt, on combine un `healthcheck` avec `condition: service_healthy`.

{::nomarkdown}
</details>
{:/nomarkdown}

<p class="qcm-question"><strong>Q30.</strong> Quelle commande arrête et supprime conteneurs et réseaux du projet, et aussi les volumes avec une option ?</p>

- **A.** `docker compose stop -v`
- **B.** `docker compose rm --all`
- {: .correct}**C.** `docker compose down -v`
- **D.** `docker compose prune`
{: .qcm}

{::nomarkdown}
<details class="qcm-answer"><summary>Voir la réponse</summary>
{:/nomarkdown}

**C** : `docker compose down` supprime conteneurs et réseaux. L'option `-v` supprime aussi les volumes nommés déclarés dans le fichier.

{::nomarkdown}
</details>
{:/nomarkdown}
