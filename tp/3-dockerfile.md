---
title: "TP 3 - Écrire ses premiers Dockerfiles"
objective: "Transformer une procédure d'installation manuelle en Dockerfile pour un back Spring Boot et un front Angular, puis optimiser les images obtenues en comprenant les couches, le cache de build et le choix de l'image de base."
---

{% raw %}

# Contexte

Jusqu'ici, vous avez utilisé des images construites par d'autres. Votre équipe vous confie maintenant une application à conteneuriser : un **back** Spring Boot (Java 17, base SQLite) et un **front** Angular, dans un même dépôt.

La démarche est celle d'un projet réel :

1. on part de la procédure d'installation que l'on taperait à la main sur un serveur ;
2. on la traduit telle quelle en `Dockerfile` : c'est la **V1, naïve** ;
3. on mesure le résultat (taille, couches, temps de build) ;
4. on optimise : c'est la **V2**.

Ce TP s'en tient à des Dockerfiles **à une seule étape**. Vous constaterez leurs limites à la fin : le TP suivant, consacré aux builds multi-étapes, les lèvera.

**Prérequis :**

- TP 1 et TP 2 terminés.
- Le dépôt de l'application, cloné dans votre répertoire personnel :

  ```bash
  cd ~
  git clone <URL du dépôt fourni> tp3
  cd tp3
  ```

  Il contient deux dossiers : `back/` (projet Maven) et `front/` (projet Angular). Vous n'avez besoin **ni de Java, ni de Maven, ni de Node.js** sur votre poste : tout se passe dans les images.

> Les commandes sont écrites pour un shell bash ou zsh (Linux, macOS, WSL). Sous PowerShell, remplacez `$PWD` par `${PWD}` et `curl` par `curl.exe`.

---

## Objectifs

<div class="section objective">

1. Lire la structure interne d'une image : index, manifeste, configuration et couches
2. Traduire une procédure d'installation en `Dockerfile` en utilisant les instructions principales
3. Comprendre le cache de build et ordonner les instructions en conséquence
4. Réduire la taille d'une image et éviter d'y laisser des fichiers inutiles ou des secrets
5. Choisir une image de base en connaissant les compromis
6. Construire, versionner et étiqueter ses images

</div>

---

## Étape 1 - Anatomie d'une image

Une image n'est pas un fichier unique. Dans un registre, elle est décrite par trois types de documents :

| Élément | Contenu |
| --- | --- |
| **Index** (ou *manifest list*) | La liste des variantes de l'image, une par plateforme (`linux/amd64`, `linux/arm64`...) |
| **Manifeste** | Pour une plateforme donnée : la référence de la configuration et la liste ordonnée des couches |
| **Configuration** (JSON) | Les métadonnées : architecture, variables d'environnement, commande par défaut, utilisateur, historique de construction, identifiants des couches |
| **Couches** (*layers*) | Des archives tar, chacune contenant les fichiers ajoutés, modifiés ou supprimés par rapport à la précédente |

Chaque élément est identifié par un **digest** (`sha256:...`), l'empreinte de son contenu.

**Ce que vous devez faire :**

- Téléchargez `ubuntu:24.04`, puis affichez son index avec `docker buildx imagetools inspect`. Relevez les plateformes disponibles.
- Affichez le même index au format brut (`--raw`).
- Avec `docker image inspect`, affichez la liste des couches (`RootFS.Layers`) et l'architecture de l'image téléchargée.
- Exportez l'image en archive avec `docker save`, extrayez-la dans un dossier et explorez-la : retrouvez le manifeste, le fichier de configuration et les couches. Listez le contenu d'une couche.

**Questions de réflexion :**

- Combien de couches compte `ubuntu:24.04` ? Que contiennent-elles ?
- Deux images construites `FROM ubuntu:24.04` sont présentes sur votre machine. Combien de fois les couches d'Ubuntu sont-elles stockées sur disque ? Et téléchargées ?

{::nomarkdown}
<details><summary>Solution - Étape 1</summary>
{:/nomarkdown}

```bash
docker pull ubuntu:24.04
docker buildx imagetools inspect ubuntu:24.04
docker buildx imagetools inspect --raw ubuntu:24.04
```

La première commande affiche le digest de l'index puis une entrée par plateforme (`linux/amd64`, `linux/arm64`, `linux/arm/v7`, `linux/ppc64le`, `linux/s390x`...), chacune avec le digest de son propre manifeste. C'est ce mécanisme qui permet au même nom d'image de fonctionner sur un Mac Apple Silicon et sur un serveur x86.

```bash
docker image inspect -f '{{.Architecture}}' ubuntu:24.04
docker image inspect -f '{{json .RootFS.Layers}}' ubuntu:24.04
```

```bash
mkdir -p ~/tp3-anatomie && cd ~/tp3-anatomie
docker save ubuntu:24.04 -o ubuntu.tar
mkdir ubuntu && tar -xf ubuntu.tar -C ubuntu
ls -R ubuntu | head -20
cat ubuntu/manifest.json
```

Les versions récentes de Docker exportent au format OCI : un fichier `index.json`, un fichier `manifest.json` et un dossier `blobs/sha256/` qui contient tous les éléments, chacun nommé par son digest. `manifest.json` indique lequel est la configuration (`Config`) et lesquels sont les couches (`Layers`) :

```bash
cat ubuntu/blobs/sha256/<digest de Config>        # la configuration JSON
tar -tf ubuntu/blobs/sha256/<digest d'une couche> | head    # les fichiers d'une couche
```

Dans la configuration, on retrouve notamment `architecture`, `os`, `config.Cmd` (`["/bin/bash"]`), `rootfs.diff_ids` (une entrée par couche) et `history` (une entrée par instruction de construction).

`ubuntu:24.04` ne compte qu'**une** couche : tout le système de fichiers de base. Les images que vous allez construire en ajouteront une par instruction qui modifie des fichiers.

Les couches sont **partagées** : deux images construites sur `ubuntu:24.04` réutilisent les mêmes couches de base, stockées et téléchargées une seule fois. C'est pourquoi standardiser les images de base d'une équipe économise disque et bande passante.

```bash
cd ~/tp3
```

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 2 - Du shell au Dockerfile : le back, V1

Voici la procédure qu'un administrateur suivrait pour installer le back sur un serveur **Ubuntu 24.04 vierge**, connecté en root :

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y openjdk-17-jdk-headless maven

mkdir -p /app
cp -r <dossier back du dépôt>/. /app/
cd /app
mvn package -DskipTests

mkdir -p /data
java -jar target/openapi-workshop-1.0.0.jar
```

L'application écoute sur le port `8081`, sous le chemin `/api`, et stocke sa base SQLite dans `/data/app.db`.

Les instructions principales d'un Dockerfile :

| Instruction | Rôle |
| --- | --- |
| `FROM` | Image de départ |
| `RUN` | Exécuter une commande pendant la construction (crée une couche) |
| `COPY` | Copier des fichiers du contexte de build vers l'image |
| `ADD` | Comme `COPY`, avec en plus l'extraction automatique des archives tar locales et le téléchargement d'URL |
| `WORKDIR` | Définir (et créer si besoin) le répertoire courant des instructions suivantes et du conteneur |
| `ENV` | Définir une variable d'environnement, présente pendant le build **et** dans le conteneur |
| `ARG` | Définir une variable disponible **uniquement pendant le build**, modifiable avec `--build-arg` |
| `EXPOSE` | Documenter le port d'écoute |
| `CMD` | Commande par défaut du conteneur, remplaçable au `docker run` |
| `ENTRYPOINT` | Programme principal du conteneur, auquel `CMD` est passé en arguments |
| `USER` | Utilisateur des instructions suivantes et du conteneur |
| `LABEL` | Métadonnées libres (auteur, version, source...) |
| `VOLUME` | Déclarer un dossier dont les données doivent vivre hors du conteneur |

**Ce que vous devez faire :**

- Écrivez `back/Dockerfile` en traduisant la procédure **le plus directement possible**, une commande par instruction. Ne cherchez pas encore à optimiser.
- Construisez l'image `tp3-back:v1` en utilisant `back/` comme contexte de build. Notez le temps de construction.
- Lancez un conteneur `back` en publiant le port 8081, puis ouvrez <http://localhost:8081/api/swagger-ui.html>.
- Relevez la taille de l'image et affichez son historique avec `docker history`. Repérez les couches les plus lourdes.

**Questions de réflexion :**

- Comment avez-vous traduit `export DEBIAN_FRONTEND=noninteractive` ? Avec `ENV` ou avec `ARG` ? Quelle conséquence pour le conteneur final ?
- Comment avez-vous traduit `cd /app` ? Pourquoi un `RUN cd /app` ne fonctionnerait-il pas ?
- Pourquoi utiliser `COPY` plutôt que `ADD` pour copier le code source ?
- Que contient l'image en plus du jar nécessaire à l'exécution ?

{::nomarkdown}
<details><summary>Solution - Étape 2</summary>
{:/nomarkdown}

`back/Dockerfile`, V1 :

```dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update
RUN apt-get install -y openjdk-17-jdk-headless maven

WORKDIR /app
COPY . .
RUN mvn package -DskipTests

RUN mkdir -p /data
CMD ["java", "-jar", "target/openapi-workshop-1.0.0.jar"]
```

```bash
time docker build -t tp3-back:v1 back/
docker run -d --name back -p 8081:8081 tp3-back:v1
docker logs -f back                 # attendre « Started OpenapiWorkshopApplication »
docker images tp3-back
docker history tp3-back:v1
```

Le dernier argument de `docker build` est le **contexte de build** : le dossier envoyé au daemon, seul endroit où `COPY` peut aller chercher des fichiers. Par défaut, le Dockerfile est cherché à sa racine.

Chaque instruction `RUN`, `COPY` ou `ADD` crée une couche. `docker history` montre que l'image pèse plusieurs centaines de Mo, répartis entre :

- la couche `apt-get install` : JDK complet (compilateur compris), Maven et leurs dépendances ;
- la couche `apt-get update` : les index de paquets, inutiles une fois l'installation faite ;
- la couche `mvn package` : le dépôt local Maven (`/root/.m2`, toutes les dépendances téléchargées) et le dossier `target/` avec les classes compilées ;
- la couche `COPY` : tout le code source.

Seul le jar et un environnement d'exécution Java sont nécessaires pour faire tourner l'application.

`ENV DEBIAN_FRONTEND=noninteractive` fonctionne, mais la variable reste définie dans tous les conteneurs lancés à partir de l'image, où elle n'a rien à faire. `ARG DEBIAN_FRONTEND=noninteractive` limite sa portée au build : c'est la bonne traduction d'un réglage qui ne concerne que l'installation.

Chaque `RUN` s'exécute dans un nouveau shell : un `RUN cd /app` n'aurait aucun effet sur l'instruction suivante. `WORKDIR` est l'instruction prévue pour cela, et elle définit aussi le répertoire courant du conteneur.

`ADD` extrait automatiquement les archives tar et peut télécharger des URL. Ces comportements implicites surprennent : un fichier `.tar.gz` copié avec `ADD` arrive décompressé, et un téléchargement par URL échappe au cache et à la vérification d'intégrité si l'on ne précise pas `--checksum`. On réserve donc `ADD` aux cas où l'on veut explicitement l'extraction, et on utilise `COPY` partout ailleurs.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 3 - Du shell au Dockerfile : le front, V1

Voici la procédure d'installation du front, sur une machine où **Node.js 22** est déjà installé (image officielle `node:22`), en root :

```bash
mkdir -p /app
cp -r <dossier front du dépôt>/. /app/
cd /app
npm install
npm install -g @angular/cli
ng build
npm install -g serve

export BACKEND_URL=http://localhost:8081
./docker-entrypoint.sh
```

Le script `docker-entrypoint.sh` écrit l'URL du back dans `/app/dist/browser/assets/config.js`, que le navigateur charge au démarrage de l'application, puis lance le serveur web `serve` sur le port 4200 avec `exec`.

**Ce que vous devez faire :**

- Écrivez `front/Dockerfile` en traduisant la procédure le plus directement possible.
- Construisez l'image `tp3-front:v1`, lancez un conteneur `front` en publiant le port 4200 et en définissant `BACKEND_URL`. Vérifiez que l'application s'affiche sur <http://localhost:4200> et qu'elle affiche les données du back.
- Relevez la taille de l'image et lisez son historique.
- Le script doit-il être lancé par `CMD` ou par `ENTRYPOINT` ? Testez la différence : lancez un conteneur `tp3-front:v1` en ajoutant `sh` à la fin de la commande `docker run -it --rm`.

**Questions de réflexion :**

- Quelle est la différence entre `CMD` et `ENTRYPOINT` ? Que se passe-t-il quand on combine les deux ?
- Pourquoi la forme `["...", "..."]` (dite *exec*) est-elle préférable à la forme `CMD commande arguments` (dite *shell*) ?
- Pourquoi le script se termine-t-il par `exec serve ...` plutôt que par `serve ...` ?

{::nomarkdown}
<details><summary>Solution - Étape 3</summary>
{:/nomarkdown}

`front/Dockerfile`, V1 :

```dockerfile
FROM node:22

WORKDIR /app
COPY . .
RUN npm install
RUN npm install -g @angular/cli
RUN ng build
RUN npm install -g serve

EXPOSE 4200
ENTRYPOINT ["/app/docker-entrypoint.sh"]
```

```bash
time docker build -t tp3-front:v1 front/
docker run -d --name front -p 4200:4200 -e BACKEND_URL=http://localhost:8081 tp3-front:v1
docker images tp3-front
docker history tp3-front:v1
```

C'est le navigateur, sur votre poste, qui appelle le back : `BACKEND_URL` doit donc être une adresse joignable depuis votre machine (`localhost:8081`, le port publié du back), pas depuis le conteneur du front.

L'image dépasse le Go : `node:22` est basée sur une Debian complète, et `node_modules` contient tout l'outillage de build d'Angular, inutile pour servir des fichiers statiques.

Combinaison de `ENTRYPOINT` et `CMD` :

| `ENTRYPOINT` | `CMD` | Commande exécutée | `docker run image xyz` exécute |
| --- | --- | --- | --- |
| absent | `["serve", "-l", "4200"]` | `serve -l 4200` | `xyz` |
| `["/app/docker-entrypoint.sh"]` | absent | `/app/docker-entrypoint.sh` | `/app/docker-entrypoint.sh xyz` |
| `["java", "-jar", "app.jar"]` | `["--server.port=8081"]` | `java -jar app.jar --server.port=8081` | `java -jar app.jar xyz` |

`CMD` est une valeur par défaut que les arguments de `docker run` remplacent. `ENTRYPOINT` est le programme à lancer quoi qu'il arrive ; `CMD` lui fournit alors des arguments par défaut. Avec `docker run -it --rm tp3-front:v1 sh`, `sh` est passé en argument au script, qui l'ignore et lance `serve` quand même. Pour remplacer le point d'entrée, il faut `--entrypoint` :

```bash
docker run -it --rm --entrypoint sh tp3-front:v1
```

La forme *shell* (`CMD serve -l 4200`) lance en réalité `/bin/sh -c "serve -l 4200"` : c'est `sh` qui reçoit le PID 1, et les signaux envoyés par `docker stop` (`SIGTERM`) ne parviennent pas à l'application, qui est tuée brutalement au bout de 10 secondes. La forme *exec* lance directement le programme.

Pour la même raison, `exec serve ...` **remplace** le processus du script par `serve`, qui devient le PID 1 et reçoit les signaux. Sans `exec`, le script resterait PID 1 et `serve` un simple processus enfant.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 4 - L'ordre des instructions et le cache de build

À chaque instruction, le builder vérifie s'il possède déjà une couche produite par **la même instruction, sur la même couche parente**. Pour `COPY` et `ADD`, il compare aussi le contenu des fichiers copiés. Si tout correspond, il réutilise la couche (`CACHED`). Dès qu'une instruction est invalidée, **toutes les suivantes** sont reconstruites.

**Ce que vous devez faire :**

- Reconstruisez `tp3-back:v1` sans rien modifier, avec `--progress=plain`. Notez le temps et les lignes `CACHED`.
- Modifiez un fichier Java du back (un commentaire suffit), puis reconstruisez. Quelles étapes sont rejouées ? Que télécharge Maven ?
- Proposez un ordre d'instructions qui évite de retélécharger toutes les dépendances Maven à chaque modification du code. Indice : `mvn dependency:go-offline` télécharge les dépendances déclarées dans `pom.xml` sans compiler.
- Appliquez le même raisonnement au front.

**Questions de réflexion :**

- Pourquoi `apt-get update` dans une instruction et `apt-get install` dans la suivante pose-t-il un problème de cache, indépendamment de la taille ?
- Quelles parties d'un projet changent souvent, lesquelles rarement ? Comment en déduire l'ordre des instructions ?

{::nomarkdown}
<details><summary>Solution - Étape 4</summary>
{:/nomarkdown}

```bash
time docker build --progress=plain -t tp3-back:v1 back/
```

Sans modification, toutes les étapes sont `CACHED` et le build dure quelques secondes.

Après modification d'un fichier Java, le contenu du contexte change : le `COPY . .` est invalidé, ainsi que tout ce qui suit. `mvn package` repart d'un dépôt Maven vide et retélécharge **toutes** les dépendances, alors que `pom.xml` n'a pas changé.

En copiant d'abord `pom.xml` seul, les dépendances sont téléchargées dans une couche qui ne dépend que de lui :

```dockerfile
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn package -DskipTests
```

Une modification du code n'invalide plus que les deux dernières instructions. `go-offline` ne récupère pas absolument tout (certains plugins ne sont résolus qu'au moment de `package`), mais l'essentiel est en cache.

Pour le front, même principe avec `package.json` et `package-lock.json` :

```dockerfile
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npx ng build
```

Avec `apt-get update` seul dans une couche en cache, un `apt-get install` ajouté plus tard réutiliserait des index de paquets vieux de plusieurs semaines : versions obsolètes, voire paquets introuvables. En les regroupant dans le même `RUN`, toute modification de la liste des paquets relance aussi la mise à jour des index.

Règle générale : du plus stable au plus changeant. Image de base, puis paquets système, puis dépendances de l'application, puis code source, puis métadonnées.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 5 - `.dockerignore` et secrets

### Le contexte de build

**Ce que vous devez faire :**

- Si ce n'est pas déjà fait, lancez `npm install` dans `front/` via un conteneur jetable, pour simuler un développeur qui travaille sur son poste :

  ```bash
  docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD/front":/app -w /app node:22 npm install
  ```

  `--user` évite que, sous Linux, les fichiers créés appartiennent à root sur votre poste.

- Reconstruisez `tp3-front:v1` avec `--progress=plain` et relevez la taille du contexte transféré (`transferring context`).
- Créez un fichier `front/.dockerignore` et un fichier `back/.dockerignore` qui excluent ce qui n'a rien à faire dans l'image. Reconstruisez et comparez.

### Les secrets

Imaginons que le back ait besoin d'un mot de passe pendant le build, pour accéder à un dépôt Maven privé.

- Ajoutez temporairement au `Dockerfile` du back une instruction `ARG REPO_PASSWORD` suivie d'un `RUN echo "connexion au dépôt..."` qui l'utilise, puis construisez avec `--build-arg REPO_PASSWORD=Sup3rS3cret`.
- Cherchez le mot de passe dans `docker history --no-trunc`.
- Remplacez `ARG` par `ENV REPO_PASSWORD=Sup3rS3cret`, reconstruisez, et cherchez le mot de passe avec `docker image inspect`.
- Ouvrez `back/src/main/java/com/workshop/openapi/config/SecurityConfig.java` et cherchez un autre secret.

**Questions de réflexion :**

- Pourquoi exclure `node_modules` et `target` du contexte, alors qu'ils seront de toute façon recréés dans l'image ?
- Un fichier copié par une instruction puis supprimé par une instruction suivante est-il encore lisible dans l'image ?
- Comment fournir correctement un secret au build ? Et à l'exécution ?

{::nomarkdown}
<details><summary>Solution - Étape 5</summary>
{:/nomarkdown}

Avec `node_modules` présent, le contexte du front passe de quelques Mo à plusieurs centaines. Le transfert ralentit chaque build, et `COPY . .` place dans l'image un `node_modules` construit **pour votre poste**, qui peut contenir des binaires compilés pour la mauvaise plateforme (macOS au lieu de Linux, par exemple).

`front/.dockerignore` :

```text
node_modules
dist
.angular
.git
Dockerfile
.dockerignore
*.md
```

`back/.dockerignore` :

```text
target
*.db
.git
.idea
Dockerfile
.dockerignore
*.md
```

Exclure `*.db` évite d'embarquer dans l'image une base SQLite locale, qui peut contenir des données personnelles.

Secrets : avec `ARG`, la valeur apparaît dans `docker history --no-trunc`, sur la ligne de chaque `RUN` qui suit sa déclaration (`|1 REPO_PASSWORD=Sup3rS3cret /bin/sh -c echo ...`). Avec `ENV`, elle est écrite dans la configuration de l'image :

```bash
docker image inspect -f '{{json .Config.Env}}' tp3-back:v1
```

Quiconque peut télécharger l'image peut lire ces secrets. De même, un fichier ajouté dans une couche puis supprimé dans une couche suivante reste présent dans la première : il suffit d'extraire l'archive, comme à l'étape 1. Retirez ces instructions de test avant de continuer.

`SecurityConfig.java` contient le mot de passe `admin123` de l'utilisateur administrateur, écrit en dur. Il se retrouve dans le dépôt Git, dans l'image et dans tous ses environnements. Il devrait être lu depuis une variable d'environnement ou un fichier fourni au lancement.

Les bonnes pratiques :

- **au build** : `RUN --mount=type=secret,id=repo_password ...` avec `docker build --secret id=repo_password,src=<fichier>`. Le secret est monté le temps d'une seule instruction et n'est écrit dans aucune couche ;
- **à l'exécution** : variable d'environnement (`docker run -e`) ou fichier monté en lecture seule, fournis par l'orchestrateur, jamais dans l'image.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 6 - Le back, V2 : optimiser les commandes et les couches

**Ce que vous devez faire :**

Repartez de votre V1 et appliquez les règles suivantes, puis construisez `tp3-back:v2` :

- regroupez `apt-get update` et `apt-get install` dans un seul `RUN`, sans les paquets recommandés (`--no-install-recommends`), et supprimez les index de paquets (`/var/lib/apt/lists/*`) **dans la même instruction** ;
- utilisez `ARG` pour ce qui ne concerne que le build ;
- ordonnez les instructions pour le cache (étape 4) ;
- dans l'instruction qui compile, copiez le jar vers `/app/app.jar` et supprimez `target/` ;
- préparez `/data`, déclarez-le comme `VOLUME`, et définissez son chemin avec `ENV DB_PATH=/data/app.db` ;
- faites tourner l'application avec l'utilisateur non root `ubuntu`, déjà présent dans l'image de base ;
- documentez le port avec `EXPOSE` ;
- lancez Java avec `ENTRYPOINT`, et passez le port par défaut avec `CMD` ;
- ajoutez des `LABEL` au format standard OCI (`org.opencontainers.image.*`), dont la version, fournie par un `ARG APP_VERSION`.

Ensuite :

- Comparez les tailles de V1 et V2, et leurs `docker history`.
- **Expérience :** déplacez le `rm -rf /var/lib/apt/lists/*` dans un `RUN` séparé, reconstruisez, et comparez la taille.
- Lancez la V2 sur le port 9090 **sans modifier l'image**, en profitant de la combinaison `ENTRYPOINT` + `CMD`.
- Vérifiez avec quel utilisateur tourne l'application.

**Questions de réflexion :**

- Pourquoi supprimer des fichiers dans un `RUN` séparé ne réduit-il pas la taille de l'image ?
- Le dépôt Maven `/root/.m2` est toujours dans l'image V2. Peut-on le supprimer sans perdre l'avantage du cache de l'étape 4 ?
- Pourquoi faire tourner l'application avec un utilisateur non root ?

{::nomarkdown}
<details><summary>Solution - Étape 6</summary>
{:/nomarkdown}

`back/Dockerfile`, V2 :

```dockerfile
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG APP_VERSION=dev

LABEL org.opencontainers.image.title="tp3-back" \
      org.opencontainers.image.description="API Spring Boot du TP 3" \
      org.opencontainers.image.version="${APP_VERSION}"

RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-17-jdk-headless maven \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pom.xml .
RUN mvn -B dependency:go-offline

COPY src ./src
RUN mvn -B package -DskipTests \
 && cp target/openapi-workshop-*.jar /app/app.jar \
 && rm -rf target

RUN mkdir /data && chown ubuntu:ubuntu /data
VOLUME /data
ENV DB_PATH=/data/app.db

USER ubuntu
EXPOSE 8081
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
CMD ["--server.port=8081"]
```

```bash
docker build -t tp3-back:v2 back/
docker images tp3-back
docker history tp3-back:v2
```

Une couche ne contient que les **différences** par rapport à la précédente. Un `RUN rm` séparé ajoute une couche qui marque les fichiers comme supprimés (des fichiers spéciaux appelés *whiteouts*), mais la couche précédente, qui les contient, est toujours téléchargée et stockée. Le nettoyage doit avoir lieu dans l'instruction qui crée les fichiers. C'est la raison d'être des longues chaînes de commandes reliées par `&&`.

Les gains de la V2 viennent des index `apt` supprimés, des paquets recommandés évités, du dossier `target/` supprimé et du code source réduit au strict nécessaire. Le cache est aussi bien plus efficace.

Lancement sur un autre port :

```bash
docker rm -f back
docker run -d --name back -p 9090:9090 tp3-back:v2 --server.port=9090
curl -sL -o /dev/null -w '%{http_code}\n' http://localhost:9090/api/swagger-ui.html    # 200
docker exec back id                 # uid=1000(ubuntu)
```

L'argument `--server.port=9090` remplace le `CMD` et est ajouté après l'`ENTRYPOINT`.

Le `chown` de `/data` doit être fait **avant** `VOLUME` : les modifications apportées à un dossier après sa déclaration en volume peuvent être ignorées. Comme vu au TP 2, un volume nommé vide reprend le contenu et les permissions de ce dossier au premier lancement, et l'utilisateur `ubuntu` peut y écrire.

`/root/.m2` pèse lourd, mais il est créé par la couche `dependency:go-offline`, que l'on veut justement garder en cache. Le supprimer dans la couche suivante ne réduirait pas la taille, et le supprimer dans la même couche ferait perdre le cache. Avec une seule étape, il faut choisir entre build rapide et image légère. Le JDK et Maven, nécessaires à la compilation et inutiles à l'exécution, posent le même problème : c'est exactement ce que résolvent les builds multi-étapes du TP suivant.

Un processus root dans un conteneur est root sur le noyau partagé avec l'hôte. En cas de faille dans l'application ou dans le runtime, l'attaquant dispose d'emblée des privilèges maximum. Avec un utilisateur sans privilèges, il est bien plus limité. De nombreuses plateformes (Kubernetes avec des politiques de sécurité, OpenShift) refusent d'ailleurs les conteneurs root.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 7 - Le front, V2

**Ce que vous devez faire :**

Repartez de votre V1 du front et construisez `tp3-front:v2` en appliquant :

- une image de base `node:22-alpine`, dont la version de Node est fournie par un `ARG NODE_VERSION` placé **avant** `FROM` ;
- `npm ci` au lieu de `npm install`, et `npx ng build` au lieu d'une installation globale d'Angular CLI ;
- le nettoyage du cache npm et du cache de build Angular (dossier `.angular`) dans les instructions qui les créent ;
- l'ordre des instructions de l'étape 4 ;
- l'utilisateur non root `node`, déjà présent dans l'image, avec `COPY --chown` pour lui donner les fichiers ;
- une valeur par défaut pour `BACKEND_URL` ;
- des `LABEL` OCI, comme pour le back.

Comparez ensuite les tailles et les historiques de V1 et V2.

**Questions de réflexion :**

- Quelle différence entre `npm install` et `npm ci` ?
- Pourquoi `COPY --chown=node:node` plutôt que `COPY` suivi de `RUN chown -R node:node /app` ?
- Un `ARG` déclaré avant `FROM` est-il utilisable dans les instructions qui suivent `FROM` ?
- Que reste-t-il dans l'image qui ne sert pas à l'exécution ?

{::nomarkdown}
<details><summary>Solution - Étape 7</summary>
{:/nomarkdown}

`front/Dockerfile`, V2 :

```dockerfile
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-alpine

ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="tp3-front" \
      org.opencontainers.image.description="Front Angular du TP 3" \
      org.opencontainers.image.version="${APP_VERSION}"

RUN npm install -g serve && npm cache clean --force

WORKDIR /app
RUN chown node:node /app
USER node

COPY --chown=node:node package.json package-lock.json ./
RUN npm ci && npm cache clean --force

COPY --chown=node:node . .
RUN npx ng build && rm -rf .angular

ENV BACKEND_URL=http://localhost:8081
EXPOSE 4200
ENTRYPOINT ["/app/docker-entrypoint.sh"]
```

```bash
docker build -t tp3-front:v2 front/
docker images tp3-front
docker history tp3-front:v2
```

`serve` est installé globalement **avant** `USER node`, car l'installation globale écrit dans `/usr/local`, réservé à root.

`npm install` résout les versions à partir des plages de `package.json` et peut mettre à jour `package-lock.json` : deux builds à une semaine d'intervalle peuvent produire des `node_modules` différents. `npm ci` installe **exactement** les versions de `package-lock.json`, échoue si les deux fichiers sont incohérents et repart d'un `node_modules` vide. C'est la commande des builds reproductibles.

`RUN chown -R` modifie les métadonnées de chaque fichier : il les **recopie tous** dans une nouvelle couche, ce qui peut doubler la taille d'un `node_modules`. `COPY --chown` attribue le propriétaire au moment de la copie, sans couche supplémentaire.

Un `ARG` déclaré avant `FROM` n'est visible que dans les lignes `FROM`. Pour l'utiliser plus loin, il faut le redéclarer (sans valeur) après `FROM` : `ARG NODE_VERSION`.

Le passage à `alpine` et le nettoyage des caches réduisent nettement la taille. Mais `node_modules` (tout l'outillage de compilation Angular), Node.js lui-même et les sources restent dans l'image, alors que l'exécution n'a besoin que du dossier `dist/browser` et d'un serveur web. Supprimer `node_modules` dans une couche suivante ne servirait à rien (étape 6), et le supprimer dans la couche de `npm ci` casserait le build. Là encore, le build multi-étapes est la solution.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 8 - Choisir son image de base

| Famille | Exemples | Taille | Débogage | Compatibilité |
| --- | --- | --- | --- | --- |
| Debian / Ubuntu | `ubuntu:24.04`, `debian:bookworm`, `eclipse-temurin:17-jdk` | La plus grosse | Shell, gestionnaire de paquets, outils courants | glibc : compatible avec quasiment tous les binaires Linux |
| `-slim` | `debian:bookworm-slim`, `node:22-slim` | Moyenne | Shell et `apt`, peu d'outils | glibc |
| Alpine | `alpine:3`, `node:22-alpine`, `eclipse-temurin:17-jdk-alpine` | Très petite | Shell `ash` (BusyBox), `apk` | **musl** au lieu de glibc : certains binaires précompilés ne fonctionnent pas, comportements parfois différents (DNS, performances) |
| Distroless | `gcr.io/distroless/java17-debian12` | Petite | **Aucun shell**, aucun gestionnaire de paquets | glibc |

**Ce que vous devez faire :**

- Téléchargez les images suivantes et comparez leurs tailles : `eclipse-temurin:17-jdk`, `eclipse-temurin:17-jre`, `eclipse-temurin:17-jre-alpine`, `gcr.io/distroless/java17-debian12`.
- Lancez un shell dans `eclipse-temurin:17-jre`, puis dans l'image distroless. Que se passe-t-il ?
- Affichez la liste des outils présents dans le JDK et dans le JRE (`ls /opt/java/openjdk/bin`). Lequel contient `javac` ?
- Réécrivez le back V2 en partant de l'image officielle `maven:3-eclipse-temurin-17` au lieu d'installer Java et Maven avec `apt`. Comparez la taille et la lisibilité du Dockerfile.

**Questions de réflexion :**

- Peut-on construire le back V2 à partir de `eclipse-temurin:17-jre` ? Et à partir de l'image distroless ?
- Quelle image choisiriez-vous pour la production ? Pour déboguer un problème en recette ?

> Sur un Mac Apple Silicon ou une machine ARM, si un `docker pull` échoue avec `no matching manifest`, l'image n'existe pas pour votre architecture. Vérifiez-le avec `docker buildx imagetools inspect`, comme à l'étape 1.

{::nomarkdown}
<details><summary>Solution - Étape 8</summary>
{:/nomarkdown}

```bash
docker pull eclipse-temurin:17-jdk
docker pull eclipse-temurin:17-jre
docker pull eclipse-temurin:17-jre-alpine
docker pull gcr.io/distroless/java17-debian12
docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'temurin|distroless'
```

Le JRE est sensiblement plus petit que le JDK, et la variante alpine encore plus. Le JDK contient le compilateur `javac`, les outils de diagnostic (`jcmd`, `jmap`...) et `jlink` ; le JRE ne contient que de quoi **exécuter** du bytecode (`java`).

```bash
docker run --rm -it eclipse-temurin:17-jre sh          # fonctionne
docker run --rm -it gcr.io/distroless/java17-debian12 sh
```

L'image distroless a pour point d'entrée `java -jar` : `sh` est interprété comme le nom d'un jar, et Java échoue. Avec `--entrypoint sh`, Docker indique que l'exécutable est introuvable. Pas de shell, donc pas de `docker exec ... sh` pour déboguer, mais aussi beaucoup moins d'outils exploitables par un attaquant et moins de vulnérabilités signalées par les scanners.

Back V2 sur l'image Maven officielle :

```dockerfile
FROM maven:3-eclipse-temurin-17

ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="tp3-back" \
      org.opencontainers.image.version="${APP_VERSION}"

WORKDIR /app
COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src ./src
RUN mvn -B package -DskipTests \
 && cp target/openapi-workshop-*.jar /app/app.jar \
 && rm -rf target

RUN mkdir /data && chown ubuntu:ubuntu /data
VOLUME /data
ENV DB_PATH=/data/app.db

USER ubuntu
EXPOSE 8081
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
CMD ["--server.port=8081"]
```

Plus besoin d'`apt` : Java et Maven sont fournis, maintenus et mis à jour par leurs éditeurs. Vérifiez que l'utilisateur `ubuntu` existe dans cette image (`docker run --rm maven:3-eclipse-temurin-17 id ubuntu`) ; sinon, créez un utilisateur dédié avec `useradd`.

On ne peut pas compiler à partir du JRE (pas de `javac`), ni à partir de distroless (pas de shell pour exécuter `RUN`, pas de Maven). Avec un Dockerfile à une étape, l'image qui compile est aussi celle qui s'exécute : on est condamné au JDK. Le build multi-étapes permet de compiler dans une image JDK, puis de ne copier que le jar dans une image JRE ou distroless.

En production, on privilégie une image minimale : distroless ou JRE alpine, si la compatibilité musl est vérifiée. Pour déboguer, une image avec shell est plus pratique, ou un conteneur de débogage attaché temporairement au conteneur de production (`docker debug`, `kubectl debug`).

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 9 - Options de build, tags et versions

Un nom d'image complet a la forme `registre/espace/nom:tag`, par exemple `ghcr.io/mon-equipe/tp3-back:1.0.0`. Sans registre, Docker Hub est utilisé ; sans tag, `latest`.

Le **versionnage sémantique** (`MAJEUR.MINEUR.CORRECTIF`) indique la nature des changements : `1.0.1` corrige un bug, `1.1.0` ajoute une fonctionnalité compatible, `2.0.0` casse la compatibilité.

**Ce que vous devez faire :**

- Construisez le back V2 en version `1.0.0`, en injectant cette version dans le `LABEL` avec `--build-arg`. Vérifiez le label avec `docker image inspect`.
- Ajoutez à la même image les tags `1.0`, `1` et `latest`. Listez les images : combien d'images distinctes avez-vous réellement ?
- Reconstruisez **sans utiliser le cache**, et comparez le temps de build avec un build avec cache.
- Construisez une version `1.0.1` après une petite modification du code. Vers quelle image pointent maintenant `1.0`, `1` et `latest` ? Que faut-il faire pour les mettre à jour ?

**Questions de réflexion :**

- Quel tag utiliser dans un fichier de déploiement de production ? Pourquoi pas `latest` ?
- Pourquoi ne faut-il jamais republier une image différente sous un tag déjà publié comme `1.0.0` ?

{::nomarkdown}
<details><summary>Solution - Étape 9</summary>
{:/nomarkdown}

```bash
docker build --build-arg APP_VERSION=1.0.0 -t tp3-back:1.0.0 back/
docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' tp3-back:1.0.0

docker tag tp3-back:1.0.0 tp3-back:1.0
docker tag tp3-back:1.0.0 tp3-back:1
docker tag tp3-back:1.0.0 tp3-back:latest
docker images tp3-back
```

Les quatre tags affichent le même `IMAGE ID` : un tag n'est qu'une étiquette qui pointe vers une image, et il n'y a qu'une image. On peut aussi poser plusieurs tags dès le build : `docker build -t tp3-back:1.0.0 -t tp3-back:1.0 ...`.

```bash
time docker build --no-cache --build-arg APP_VERSION=1.0.0 -t tp3-back:1.0.0 back/
```

`--no-cache` reconstruit toutes les étapes. On l'utilise pour forcer la récupération des dernières mises à jour de paquets (correctifs de sécurité) ou pour écarter un problème de cache. `--pull` force en plus le téléchargement de la dernière version de l'image de base.

Après le build de `1.0.1`, les tags `1.0`, `1` et `latest` pointent toujours vers `1.0.0` : un tag ne bouge jamais tout seul. Il faut les déplacer explicitement avec `docker tag tp3-back:1.0.1 tp3-back:1.0`, et ainsi de suite. C'est le travail du pipeline de CI à chaque publication.

En production, on déploie une version **immuable** (`1.0.1`), ou mieux, un digest. `latest` ne dit pas quelle version tourne, change sans prévenir au prochain `pull`, et rend un retour arrière impossible à garantir. Republier un tag déjà publié produit le même problème : deux serveurs qui ont téléchargé `1.0.0` à des moments différents exécutent des codes différents. Les registres d'entreprise interdisent souvent cette pratique (tags immuables).

> **Pour aller plus loin : `--target`.** Un Dockerfile peut contenir plusieurs `FROM`, chacun ouvrant une **étape** que l'on peut nommer (`FROM maven:3-eclipse-temurin-17 AS build`). `docker build --target build` s'arrête à l'étape indiquée. Cette option n'a de sens qu'avec un Dockerfile multi-étapes : ce sera l'objet du TP suivant.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 10 - Tout lancer et faire le bilan

**Ce que vous devez faire :**

- Supprimez les conteneurs `back` et `front` existants.
- Lancez le back V2 avec un volume nommé `back-data` pour la base SQLite, puis le front V2 sur le port 4200.
- Dans l'application, créez quelques données. Supprimez le conteneur du back, relancez-le avec le même volume, et vérifiez que les données sont toujours là.
- Remplissez le tableau suivant avec `docker images` :

| Image | Taille |
| --- | --- |
| `tp3-back:v1` (Ubuntu + apt, naïve) | |
| `tp3-back:v2` (Ubuntu + apt, optimisée) | |
| back V2 sur `maven:3-eclipse-temurin-17` | |
| `eclipse-temurin:17-jre` seule (pour comparaison) | |
| `tp3-front:v1` (`node:22`, naïve) | |
| `tp3-front:v2` (`node:22-alpine`, optimisée) | |

- Faites le ménage : conteneurs, volume et images de ce TP.

**Question de réflexion :**

- Pour chaque image V2, estimez la part de la taille réellement nécessaire à l'exécution. Qu'est-ce qui vous empêche de supprimer le reste ?

{::nomarkdown}
<details><summary>Solution - Étape 10</summary>
{:/nomarkdown}

```bash
docker rm -f back front

docker run -d --name back -p 8081:8081 -v back-data:/data tp3-back:v2
docker run -d --name front -p 4200:4200 tp3-front:v2
```

`BACKEND_URL` a désormais une valeur par défaut dans l'image (`http://localhost:8081`) : inutile de la préciser.

```bash
docker rm -f back
docker run -d --name back -p 8081:8081 -v back-data:/data tp3-back:v2
```

Les données créées sont toujours présentes : la base SQLite vit dans le volume, pas dans le conteneur.

Ménage :

```bash
docker rm -f back front
docker volume rm back-data
docker rmi tp3-back:v1 tp3-back:v2 tp3-back:1.0.0 tp3-back:1.0.1 tp3-back:1.0 tp3-back:1 tp3-back:latest tp3-front:v1 tp3-front:v2
docker image prune
docker system df
```

Adaptez la liste des tags à ceux que vous avez réellement créés. Les images de base (`ubuntu`, `node`, `eclipse-temurin`...) peuvent être conservées pour le TP suivant.

Pour le back, seuls le jar (quelques dizaines de Mo) et un JRE sont nécessaires : le JDK, Maven, le dépôt `~/.m2` et les sources représentent la majorité de l'image. Pour le front, seul `dist/browser` (quelques Mo) et un serveur web sont nécessaires : Node.js, `node_modules` et les sources sont superflus. Avec une seule étape, tout ce qui sert à construire reste dans l'image qui s'exécute. Le TP suivant sépare les deux.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Récapitulatif des bonnes pratiques

| Pratique | Pourquoi |
| --- | --- |
| Ordonner les instructions du plus stable au plus changeant | Maximiser la réutilisation du cache |
| Copier les fichiers de dépendances avant le code | Ne pas retélécharger les dépendances à chaque modification du code |
| `apt-get update && apt-get install --no-install-recommends ... && rm -rf /var/lib/apt/lists/*` dans un seul `RUN` | Index à jour, pas de paquets superflus, pas d'index dans l'image |
| `apk add --no-cache`, `npm ci && npm cache clean --force` | Pas de cache de gestionnaire de paquets dans l'image |
| Nettoyer dans la même instruction que celle qui crée les fichiers | Une suppression dans une couche suivante ne réduit pas la taille |
| `.dockerignore` | Contexte léger, pas de fichiers locaux ni de données dans l'image |
| `COPY` plutôt que `ADD` | Pas d'extraction ni de téléchargement implicites |
| `COPY --chown` plutôt que `RUN chown -R` | Pas de duplication des fichiers dans une nouvelle couche |
| `ARG` pour le build, `ENV` pour l'exécution | Ne pas polluer l'environnement du conteneur |
| Aucun secret dans `ARG`, `ENV`, `COPY` ou dans le code | Tout ce qui est dans l'image est lisible par qui peut la télécharger |
| Forme *exec* pour `CMD` et `ENTRYPOINT`, `exec` dans les scripts | L'application reçoit les signaux d'arrêt |
| `USER` non root | Limiter l'impact d'une compromission |
| `LABEL` OCI | Traçabilité : version, source, description |
| Tags immuables et versionnage sémantique | Savoir ce qui tourne, pouvoir revenir en arrière |

{% endraw %}
