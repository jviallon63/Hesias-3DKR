---
title: "TP 4 - Builds multi-étapes et multi-plateformes avec Buildx"
objective: "Réécrire les images du TP 3 avec des builds multi-étapes et les caches BuildKit pour les réduire au strict nécessaire, puis les construire pour plusieurs architectures et les publier avec un schéma de tags versionné."
---

{% raw %}

# Contexte

Le TP 3 s'est terminé sur un constat : avec un Dockerfile à une seule étape, tout ce qui sert à **construire** l'application (JDK, Maven, `~/.m2`, Node.js, `node_modules`, sources) reste dans l'image qui l'**exécute**. Et il fallait choisir entre un build rapide (dépendances en cache dans une couche) et une image légère.

Ce TP lève ces deux limites, puis en aborde une nouvelle : votre équipe déploie à la fois sur des serveurs x86 (`amd64`) et sur des machines ARM (`arm64` : Mac Apple Silicon, instances cloud Graviton, Raspberry Pi). Une seule référence d'image doit fonctionner partout.

L'outil de ce TP est **Buildx**, le client de build de Docker, qui pilote le moteur **BuildKit**.

**Prérequis :**

- TP 3 terminé : le dépôt est cloné dans `~/tp3`, et les `.dockerignore` du back et du front sont en place.
- Les images du TP 3 (`tp3-back:v1`, `tp3-back:v2`, `tp3-front:v1`, `tp3-front:v2`) pour comparer les tailles. Si vous les avez supprimées, reconstruisez au moins les V2.

```bash
cd ~/tp3
```

> Les commandes sont écrites pour un shell bash ou zsh (Linux, macOS, WSL). Sous PowerShell, remplacez `$PWD` par `${PWD}` et `curl` par `curl.exe`.

---

## Objectifs

<div class="section objective">

1. Distinguer les builders et drivers Buildx, et créer un builder dédié
2. Séparer construction et exécution avec un Dockerfile multi-étapes
3. Utiliser les montages de cache BuildKit pour accélérer les builds sans alourdir les images
4. Choisir une image d'exécution minimale et non root
5. Construire et publier une image multi-plateforme sans émulation inutile
6. Appliquer un schéma de tags versionné et traçable

</div>

---

## Étape 1 - Buildx, builders et registre local

`docker build` est aujourd'hui un alias de `docker buildx build`. Buildx envoie le build à un **builder**, une instance de BuildKit, dont le **driver** détermine où et comment il tourne :

| Driver | Où tourne BuildKit | Résultat du build | Multi-plateforme | Cache exportable |
| --- | --- | --- | --- | --- |
| `docker` (builder `default`) | Intégré au daemon Docker | Directement dans les images locales | Uniquement avec le *containerd image store* | Non |
| `docker-container` | Dans un conteneur dédié | À charger (`--load`) ou à pousser (`--push`) | Oui | Oui |

Pour publier des images multi-plateformes sans compte Docker Hub, vous allez utiliser un **registre local**, `registry:3`, l'implémentation de référence d'un registre d'images.

**Ce que vous devez faire :**

- Affichez la version de Buildx et la liste des builders existants. Relevez le driver et les plateformes du builder actif.
- Lancez un registre local `registry` en arrière-plan, publié sur le port 5000.

  > Sur macOS, le récepteur AirPlay occupe déjà le port 5000. Si le lancement échoue avec `address already in use` ou `ports are not available`, désactivez-le (Réglages système, Général, AirDrop et Handoff) ou utilisez un autre port partout dans ce TP.
- Créez un fichier `~/tp3/buildkitd.toml` qui autorise BuildKit à joindre ce registre en HTTP simple :

  ```toml
  [registry."localhost:5000"]
    http = true
  ```

- Créez un builder `tp4` avec le driver `docker-container`, sur le réseau de l'hôte (`--driver-opt network=host`) pour qu'il puisse joindre `localhost:5000`, avec ce fichier de configuration. Faites-en le builder actif.
- Démarrez-le et affichez les plateformes qu'il sait produire. Retrouvez le conteneur qui l'exécute dans `docker ps`.

**Questions de réflexion :**

- Votre builder annonce des plateformes différentes de celle de votre machine. Comment peut-il produire une image `arm64` sur un processeur x86, ou l'inverse ?
- Pourquoi BuildKit a-t-il besoin du réseau de l'hôte pour joindre `localhost:5000` ?

{::nomarkdown}
<details><summary>Solution - Étape 1</summary>
{:/nomarkdown}

```bash
docker buildx version
docker buildx ls
```

Le builder `default` utilise le driver `docker`. L'astérisque indique le builder actif.

```bash
docker run -d --name registry -p 5000:5000 registry:3

cat > buildkitd.toml <<'EOF'
[registry."localhost:5000"]
  http = true
EOF

docker buildx create --name tp4 --driver docker-container \
  --driver-opt network=host --buildkitd-config buildkitd.toml --use
docker buildx inspect --bootstrap
docker ps --filter name=buildx_buildkit
```

`inspect --bootstrap` démarre le conteneur `buildx_buildkit_tp40` et affiche la ligne `Platforms`, par exemple `linux/arm64, linux/amd64, linux/amd64/v2, linux/riscv64, linux/ppc64le, linux/s390x, linux/386, linux/arm/v7...`.

Les plateformes étrangères sont exécutées par **émulation** : QEMU, enregistré dans le noyau via *binfmt_misc*, traduit à la volée les instructions d'une autre architecture. Docker Desktop l'installe d'office. Si votre builder n'annonce que votre plateforme native (Linux, Colima), installez-le :

```bash
docker run --privileged --rm tonistiigi/binfmt --install all
```

L'émulation fonctionne pour tout, mais elle est lente, souvent 5 à 20 fois plus qu'en natif. Vous verrez à l'étape 5 comment l'éviter.

BuildKit tourne dans son propre conteneur : `localhost` y désigne le conteneur lui-même, pas la machine où le port 5000 est publié. Avec `network=host`, le conteneur partage la pile réseau de l'hôte (ou de la VM Docker sous Windows et macOS), où le registre est joignable.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 2 - Le back en multi-étapes

Un Dockerfile multi-étapes contient plusieurs `FROM`. Chacun démarre une **étape** indépendante, que l'on peut nommer avec `AS`. Une étape peut copier des fichiers produits par une autre avec `COPY --from=<étape>`. **Seule la dernière étape** constitue l'image finale : tout le reste est jeté.

**Ce que vous devez faire :**

- Écrivez `back/Dockerfile` avec deux étapes :
  - une étape `build`, basée sur `maven:3-eclipse-temurin-17`, qui compile le jar comme au TP 3 ;
  - une étape finale, basée sur `eclipse-temurin:17-jre`, qui ne reçoit **que le jar**, et reprend la configuration de la V2 du TP 3 (`/data`, `VOLUME`, `DB_PATH`, utilisateur `ubuntu`, `EXPOSE`, `ENTRYPOINT` + `CMD`).
- Construisez l'image `tp4-back:simple` et chargez-la dans vos images locales. Comparez sa taille avec `tp3-back:v1` et `tp3-back:v2`, et lisez son historique.
- Construisez uniquement l'étape `build` sous le nom `tp4-back:build`, et ouvrez un shell dedans pour retrouver le jar.

**Questions de réflexion :**

- Qu'est-ce qui a disparu de l'image finale par rapport au TP 3 ? Que montre `docker history` des instructions de l'étape `build` ?
- Pourquoi faut-il ajouter `--load` alors que ce n'était pas nécessaire au TP 3 ?

{::nomarkdown}
<details><summary>Solution - Étape 2</summary>
{:/nomarkdown}

`back/Dockerfile` :

```dockerfile
FROM maven:3-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src ./src
RUN mvn -B package -DskipTests

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /app/target/openapi-workshop-1.0.0.jar app.jar
RUN mkdir /data && chown ubuntu:ubuntu /data
VOLUME /data
ENV DB_PATH=/data/app.db
USER ubuntu
EXPOSE 8081
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
CMD ["--server.port=8081"]
```

```bash
docker buildx build --load -t tp4-back:simple back/
docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'tp[34]-back'
docker history tp4-back:simple
```

L'image ne contient plus ni Maven, ni le JDK, ni `~/.m2`, ni les sources : seulement un JRE et le jar. `docker history` ne montre **aucune** instruction de l'étape `build` : elle n'a laissé aucune trace dans l'image finale.

Avec le driver `docker-container`, le résultat du build reste dans le cache du builder, à l'intérieur de son conteneur. `--load` l'exporte vers les images du daemon Docker. Sans `--load` ni `--push`, Buildx affiche un avertissement : l'image est construite mais inutilisable.

```bash
docker buildx build --target build --load -t tp4-back:build back/
docker run --rm -it tp4-back:build bash
ls -lh target/*.jar
exit
```

`--target` arrête le build à l'étape indiquée. C'est l'outil de débogage du multi-étapes : on inspecte le résultat intermédiaire sans toucher au Dockerfile.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 3 - Le back, optimisé au maximum

Trois leviers pour aller plus loin :

1. **Le montage de cache** : `RUN --mount=type=cache,target=<dossier>` monte un dossier conservé par BuildKit **d'un build à l'autre**, mais jamais écrit dans une couche. Idéal pour `~/.m2`.
2. **Le jar découpé en couches** : un jar Spring Boot regroupe les dépendances (lourdes, qui changent rarement) et votre code (léger, qui change à chaque version). Spring Boot sait l'extraire en quatre dossiers : `dependencies`, `spring-boot-loader`, `snapshot-dependencies` et `application`. Copiés dans quatre couches distinctes, ils permettent de ne republier et retélécharger que la couche `application` quand seul le code change.
3. **Une image d'exécution distroless** : `gcr.io/distroless/java17-debian12:nonroot` ne contient qu'un JRE et ses bibliothèques, sans shell ni gestionnaire de paquets, et tourne avec l'utilisateur `nonroot` (UID 65532).

**Ce que vous devez faire :**

- Ajoutez en première ligne du Dockerfile la directive `# syntax=docker/dockerfile:1`.
- Dans l'étape `build` :
  - supprimez le `dependency:go-offline` et compilez avec un montage de cache sur `/root/.m2` ;
  - dans la même instruction, extrayez le jar en couches avec `java -Djarmode=layertools -jar <jar> extract --destination /out/app` ;
  - préparez un dossier vide `/out/data`, qui deviendra `/data`.
- Dans l'étape finale, basée sur l'image distroless :
  - copiez les quatre dossiers extraits dans `/app`, du moins changeant au plus changeant, avec une instruction `COPY` chacun ;
  - créez `/data` pour l'utilisateur `nonroot`, **sans shell** ;
  - lancez l'application avec `ENTRYPOINT ["/usr/bin/java", "org.springframework.boot.loader.launch.JarLauncher"]`.
- Ajoutez les `LABEL` OCI de version et de révision Git, alimentés par `ARG APP_VERSION` et `ARG VCS_REF`.
- Construisez `tp4-back:distroless`. Comparez sa taille et son historique.
- Modifiez un fichier Java, reconstruisez, et observez : Maven retélécharge-t-il les dépendances ? Quelles couches de l'image finale ont changé ?
- Lancez un conteneur et essayez d'y ouvrir un shell.

**Questions de réflexion :**

- Pourquoi `dependency:go-offline` n'est-il plus utile ?
- Pourquoi `RUN mkdir /data` est-il impossible dans l'étape finale ?
- Comment déboguer un conteneur qui n'a pas de shell ?

{::nomarkdown}
<details><summary>Solution - Étape 3</summary>
{:/nomarkdown}

`back/Dockerfile` :

```dockerfile
# syntax=docker/dockerfile:1

FROM maven:3-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B package -DskipTests \
 && java -Djarmode=layertools -jar target/openapi-workshop-1.0.0.jar extract --destination /out/app \
 && mkdir -p /out/data

FROM gcr.io/distroless/java17-debian12:nonroot
ARG APP_VERSION=dev
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="tp-back" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

WORKDIR /app
COPY --from=build /out/app/dependencies/ ./
COPY --from=build /out/app/spring-boot-loader/ ./
COPY --from=build /out/app/snapshot-dependencies/ ./
COPY --from=build /out/app/application/ ./
COPY --from=build --chown=65532:65532 /out/data /data

VOLUME /data
ENV DB_PATH=/data/app.db
EXPOSE 8081
ENTRYPOINT ["/usr/bin/java", "org.springframework.boot.loader.launch.JarLauncher"]
CMD ["--server.port=8081"]
```

```bash
docker buildx build --load -t tp4-back:distroless back/
docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'tp[34]-back'
docker history tp4-back:distroless
```

La directive `# syntax` indique quelle version du frontend Dockerfile utiliser : BuildKit la télécharge au besoin, ce qui garantit l'accès aux fonctionnalités récentes (`--mount`, `--chmod`...) quelle que soit la version de Docker installée.

Le cache `/root/.m2` survit aux builds suivants, même quand `COPY src` est invalidé : Maven ne retélécharge plus rien après une modification du code. `go-offline` servait à placer les dépendances dans une couche en cache ; le montage de cache rend ce contournement inutile, et le dépôt Maven n'est plus dans aucune image.

Après une modification du code, seule la couche `application` (quelques Ko) change. Les couches `dependencies` (plusieurs dizaines de Mo) sont identiques, octet pour octet, à celles de la version précédente : un serveur qui met à jour l'image ne télécharge que la nouvelle couche.

Le lanceur `JarLauncher` reconstitue le classpath à partir des dossiers extraits. Avec Spring Boot 3.3 et suivants, l'extraction s'écrit `java -Djarmode=tools -jar <jar> extract --layers --launcher --destination /out/app`.

L'image distroless n'a pas de shell : `RUN mkdir` y est impossible. On crée le dossier dans l'étape `build`, où les outils existent, et on le copie avec le bon propriétaire.

```bash
docker run -d --name back -p 8081:8081 tp4-back:distroless
docker exec -it back sh             # executable file not found
```

Pour déboguer, plusieurs options :

- la variante `:debug-nonroot` de l'image distroless, qui embarque un shell BusyBox, à utiliser temporairement ;
- un conteneur d'outils qui partage les namespaces du conteneur cible : `docker run --rm -it --pid=container:back --network=container:back alpine sh` ;
- `docker debug back` (Docker Desktop) ou `kubectl debug` en Kubernetes.

```bash
docker rm -f back
```

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 4 - Le front en multi-étapes

L'exécution du front n'a besoin que du dossier `dist/browser` et d'un serveur web. On utilise `nginxinc/nginx-unprivileged`, variante de l'image nginx officielle qui tourne **sans root** et écoute donc sur le port **8080** (les ports inférieurs à 1024 sont réservés à root).

Il faut adapter deux éléments du TP 3 :

- l'URL du back, écrite dans `assets/config.js` au démarrage. Le point d'entrée de l'image nginx exécute tous les scripts exécutables du dossier `/docker-entrypoint.d/` avant de lancer nginx : il suffit d'y placer un script ;
- le routage d'Angular : une URL comme `/products/12` n'existe pas sur le disque, nginx doit renvoyer `index.html` et laisser Angular gérer la route.

**Ce que vous devez faire :**

- Créez `front/docker/40-backend-url.sh`, qui écrit `/usr/share/nginx/html/assets/config.js` à partir de `BACKEND_URL` (inspirez-vous de `docker-entrypoint.sh`, sans le lancement du serveur).
- Créez `front/docker/default.conf` : un serveur qui écoute sur 8080, sert `/usr/share/nginx/html` et renvoie `index.html` pour les chemins inconnus.
- Écrivez `front/Dockerfile` avec :
  - une étape `build` sur `node:22-alpine`, avec un montage de cache pour le cache npm (`/root/.npm`) et un autre pour le cache Angular (`/app/.angular/cache`) ;
  - une étape finale sur `nginxinc/nginx-unprivileged:stable-alpine` qui reçoit la configuration, le script (exécutable, avec `COPY --chmod`) et le contenu de `dist/browser`, appartenant à l'utilisateur `nginx` (UID 101) pour que le script puisse écrire `config.js` ;
  - une valeur par défaut pour `BACKEND_URL`, les `LABEL` OCI et `EXPOSE 8080`.
- Construisez `tp4-front:nginx`, comparez sa taille avec celles du TP 3, et lancez-le en publiant le port 8080 du conteneur sur le port 4200 de l'hôte. Vérifiez le contenu de `/assets/config.js` et le fonctionnement de l'application avec le back.

**Questions de réflexion :**

- L'étape finale ne contient ni `ENTRYPOINT` ni `CMD`. Comment le conteneur sait-il quoi lancer ?
- Pourquoi publier sur le port 4200 de l'hôte, et non sur 8080 ?

{::nomarkdown}
<details><summary>Solution - Étape 4</summary>
{:/nomarkdown}

`front/docker/40-backend-url.sh` :

```sh
#!/bin/sh
set -eu
cat > /usr/share/nginx/html/assets/config.js <<EOF
window.dynamicConf = {
  BACKEND_URL: "${BACKEND_URL}"
};
EOF
```

`front/docker/default.conf` :

```nginx
server {
    listen 8080;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location = /assets/config.js {
        add_header Cache-Control "no-store";
    }
}
```

`front/Dockerfile` :

```dockerfile
# syntax=docker/dockerfile:1

FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
RUN --mount=type=cache,target=/app/.angular/cache npx ng build

FROM nginxinc/nginx-unprivileged:stable-alpine
ARG APP_VERSION=dev
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="tp-front" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

COPY docker/default.conf /etc/nginx/conf.d/default.conf
COPY --chmod=755 docker/40-backend-url.sh /docker-entrypoint.d/40-backend-url.sh
COPY --from=build --chown=101:101 /app/dist/browser /usr/share/nginx/html

ENV BACKEND_URL=http://localhost:8081
EXPOSE 8080
```

```bash
docker buildx build --load -t tp4-front:nginx front/
docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'tp[34]-front'

docker run -d --name back -p 8081:8081 tp4-back:distroless
docker run -d --name front -p 4200:8080 tp4-front:nginx
curl http://localhost:4200/assets/config.js
```

L'image passe de plusieurs centaines de Mo à quelques dizaines : nginx sur Alpine et quelques Mo de fichiers statiques. Node.js, `node_modules` et les sources sont restés dans l'étape `build`.

L'étape finale **hérite** de l'`ENTRYPOINT` (`/docker-entrypoint.sh`) et du `CMD` (`nginx -g daemon off;`) de son image de base. Le point d'entrée exécute les scripts de `/docker-entrypoint.d/` dans l'ordre alphabétique (d'où le préfixe `40-`), puis lance nginx avec `exec`.

Le back n'autorise (CORS) que les appels venant de l'origine `http://localhost:4200`. Publier le front sur le port 4200 de l'hôte conserve cette origine, quel que soit le port interne du conteneur.

```bash
docker rm -f back front
```

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 5 - Construire pour plusieurs plateformes

Buildx construit une image par plateforme demandée, puis les regroupe sous un **index** (vu à l'étape 1 du TP 3). Le résultat ne peut pas être chargé tel quel dans les images locales classiques : on le pousse dans un registre.

Par défaut, **chaque étape** est exécutée pour la plateforme cible, donc sous émulation pour les plateformes étrangères. Or un jar et un dossier `dist/` sont identiques quelle que soit l'architecture. BuildKit fournit des variables pour en tirer parti :

| Variable | Valeur |
| --- | --- |
| `BUILDPLATFORM` | Plateforme de la machine qui construit (par exemple `linux/arm64` sur un Mac M1) |
| `TARGETPLATFORM` | Plateforme de l'image en cours de production |
| `TARGETOS`, `TARGETARCH` | Les deux composantes de `TARGETPLATFORM` |

**Ce que vous devez faire :**

- Construisez le back pour `linux/amd64` et `linux/arm64`, et poussez-le sous `localhost:5000/tp/back:test`. Notez le temps de build.
- Ajoutez `--platform=$BUILDPLATFORM` sur le `FROM` de l'étape `build` du back et du front. Ajoutez dans l'étape `build` du back, juste après `FROM`, les lignes suivantes :

  ```dockerfile
  ARG BUILDPLATFORM
  ARG TARGETPLATFORM
  RUN echo "Construit sur $BUILDPLATFORM pour $TARGETPLATFORM"
  ```

- Reconstruisez les deux images pour les deux plateformes avec `--progress=plain`, poussez-les sous `localhost:5000/tp/back:test` et `localhost:5000/tp/front:test`. Comparez le temps de build du back et lisez les lignes produites par `echo`.
- Affichez l'index des deux images avec `docker buildx imagetools inspect`. Combien d'entrées comptez-vous ? À quoi correspondent les entrées `unknown/unknown` ?
- Lancez le front en forçant l'architecture qui **n'est pas** celle de votre machine, en lui faisant afficher `uname -m` au lieu de démarrer nginx.

**Questions de réflexion :**

- Pourquoi l'étape finale peut-elle être produite pour une architecture étrangère sans émulation coûteuse, alors qu'elle est basée sur une image `arm64` ou `amd64` ?
- Le jar du back embarque le driver SQLite, qui contient du code natif. Pourquoi fonctionne-t-il sur les deux architectures alors qu'il a été compilé une seule fois ?
- Dans quel cas `--platform=$BUILDPLATFORM` ne suffirait-il pas ?

{::nomarkdown}
<details><summary>Solution - Étape 5</summary>
{:/nomarkdown}

Premier build, sans `$BUILDPLATFORM` :

```bash
time docker buildx build --platform linux/amd64,linux/arm64 \
  -t localhost:5000/tp/back:test --push back/
```

L'étape `build` est exécutée deux fois, dont une sous émulation : Maven tourne sur un processeur virtuel, et le build est nettement plus long.

Début de l'étape `build` du back après modification :

```dockerfile
FROM --platform=$BUILDPLATFORM maven:3-eclipse-temurin-17 AS build
ARG BUILDPLATFORM
ARG TARGETPLATFORM
RUN echo "Construit sur $BUILDPLATFORM pour $TARGETPLATFORM"
WORKDIR /app
```

Et pour le front : `FROM --platform=$BUILDPLATFORM node:22-alpine AS build`.

```bash
time docker buildx build --progress=plain --platform linux/amd64,linux/arm64 \
  -t localhost:5000/tp/back:test --push back/
docker buildx build --platform linux/amd64,linux/arm64 \
  -t localhost:5000/tp/front:test --push front/
```

Les deux lignes `echo` affichent la même plateforme de construction (la vôtre) et les deux plateformes cibles : l'étape `build` tourne en natif pour chaque cible, et produit le même jar. Le build est presque aussi rapide qu'un build mono-plateforme.

```bash
docker buildx imagetools inspect localhost:5000/tp/back:test
docker buildx imagetools inspect localhost:5000/tp/front:test
```

L'index contient une entrée par plateforme, plus une entrée `unknown/unknown` par plateforme : ce sont des **attestations de provenance**, ajoutées par défaut par Buildx. Elles décrivent comment l'image a été construite (Dockerfile, images de base, paramètres) et servent à vérifier la chaîne d'approvisionnement. `--provenance=false` les désactive, `--sbom=true` ajoute en plus l'inventaire des paquets de l'image (SBOM).

```bash
docker run --rm --platform linux/amd64 localhost:5000/tp/front:test uname -m   # x86_64
docker run --rm --platform linux/arm64 localhost:5000/tp/front:test uname -m   # aarch64
```

Le point d'entrée de nginx n'exécute ses scripts et nginx que si la commande est `nginx` ; sinon, il exécute la commande demandée. L'architecture étrangère tourne sous émulation, de façon transparente.

L'étape finale ne contient aucun `RUN` : elle ne fait que **copier** des fichiers sur une image de base déjà construite pour la bonne architecture. Rien n'est exécuté, donc rien n'est émulé. C'est une raison de plus pour éviter les `RUN` dans l'étape finale.

Le driver SQLite (`sqlite-jdbc`) embarque ses bibliothèques natives pour toutes les plateformes courantes, et charge la bonne au démarrage. Le jar est donc réellement indépendant de l'architecture.

`--platform=$BUILDPLATFORM` ne suffit plus quand le build produit du **code natif** : un binaire Go, Rust ou C compilé pour la machine de build ne tournerait pas sur l'autre architecture. Il faut alors faire de la **compilation croisée**, en passant `TARGETOS` et `TARGETARCH` au compilateur (par exemple `GOOS=$TARGETOS GOARCH=$TARGETARCH go build`).

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 6 - Nouveaux tags pour les builds

Au TP 3, les images s'appelaient `tp3-back:v2` : un nom local, une étiquette informelle. Une image destinée à être déployée doit avoir un nom complet (registre, espace, nom) et des tags qui disent **quelle version** et **quel code** elle contient.

Schéma adopté pour la suite :

| Tag | Exemple | Rôle |
| --- | --- | --- |
| Version complète | `2.0.0` | Immuable : identifie exactement une version publiée |
| Version mineure | `2.0` | Mobile : dernière version corrective de la 2.0 |
| Version majeure | `2` | Mobile : dernière version de la 2 |
| `latest` | `latest` | Mobile : dernière version publiée |
| Révision Git | `sha-1a2b3c4` | Immuable : relie l'image au commit qui l'a produite |

**Ce que vous devez faire :**

- Récupérez la version courte du dernier commit du dépôt dans une variable `VCS_REF`, et définissez `VERSION=2.0.0`.
- Construisez et poussez le back et le front pour les deux plateformes sous `localhost:5000/tp/back` et `localhost:5000/tp/front`, avec les cinq tags du tableau en une seule commande chacun, en injectant `APP_VERSION` et `VCS_REF`.
- Listez les tags présents dans le registre grâce à son API (`/v2/<nom>/tags/list`).
- Téléchargez `localhost:5000/tp/back:2.0.0` et vérifiez ses labels.

**Questions de réflexion :**

- Ces images sont publiées en version `2.0.0`, et non `1.1.0`. Qu'est-ce qui, dans les changements de ce TP, casse la compatibilité pour quelqu'un qui déployait les images du TP 3 ? Pensez aux ports, et à l'utilisateur qui écrit dans le volume.
- Pourquoi un tag `sha-...` en plus du tag de version ?

{::nomarkdown}
<details><summary>Solution - Étape 6</summary>
{:/nomarkdown}

```bash
VERSION=2.0.0
VCS_REF=$(git rev-parse --short HEAD)
REGISTRY=localhost:5000/tp

for app in back front; do
  docker buildx build --platform linux/amd64,linux/arm64 \
    --build-arg APP_VERSION="$VERSION" \
    --build-arg VCS_REF="$VCS_REF" \
    -t "$REGISTRY/$app:$VERSION" \
    -t "$REGISTRY/$app:${VERSION%.*}" \
    -t "$REGISTRY/$app:${VERSION%%.*}" \
    -t "$REGISTRY/$app:latest" \
    -t "$REGISTRY/$app:sha-$VCS_REF" \
    --push "$app/"
done
```

`${VERSION%.*}` retire le dernier composant (`2.0`), `${VERSION%%.*}` ne garde que le premier (`2`). Les deux plateformes sont construites une seule fois, et les cinq tags pointent vers le même index.

```bash
curl http://localhost:5000/v2/tp/back/tags/list
curl http://localhost:5000/v2/tp/front/tags/list

docker pull localhost:5000/tp/back:2.0.0
docker image inspect -f '{{json .Config.Labels}}' localhost:5000/tp/back:2.0.0
```

`docker pull` récupère automatiquement la variante de votre architecture dans l'index.

Ruptures de compatibilité par rapport au TP 3 :

- le front écoute désormais sur le port **8080** au lieu de 4200 : toute commande `docker run -p 4200:4200` ou tout fichier de déploiement existant ne fonctionne plus ;
- le back tourne avec l'utilisateur `nonroot` (UID **65532**) au lieu de `ubuntu` (UID 1000) : un volume créé par les images du TP 3 appartient à l'UID 1000, et le nouveau back ne peut plus y écrire sa base ;
- le back n'a plus de shell : les scripts d'exploitation qui faisaient `docker exec ... sh` échouent.

En versionnage sémantique, c'est une nouvelle version **majeure**.

Le tag de version dit ce que l'équipe a voulu publier ; le tag `sha-...` dit exactement quel code a été construit. En cas d'incident, il permet de retrouver le commit, et donc le diff, sans ambiguïté. Le label `org.opencontainers.image.revision` porte la même information dans l'image elle-même.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 7 - Bilan et ménage

**Ce que vous devez faire :**

- Lancez le back et le front en version `2.0.0` depuis le registre, avec un **nouveau** volume `tp4-data` pour la base. Créez des données, recréez le conteneur du back avec le même volume, et vérifiez la persistance.
- Téléchargez `localhost:5000/tp/front:2.0.0` et complétez le tableau des tailles (`docker images`) :

| Image | TP 3 V1 | TP 3 V2 | TP 4 |
| --- | --- | --- | --- |
| back | | | |
| front | | | |

- Faites le ménage : conteneurs, volume, registre, builder `tp4` et son cache, images de ce TP. Revenez au builder `default`.

**Question de réflexion :**

- `docker images` affiche la taille **décompressée** de l'image. Ce qui transite sur le réseau lors d'un `pull` est-il plus gros ou plus petit ?

{::nomarkdown}
<details><summary>Solution - Étape 7</summary>
{:/nomarkdown}

```bash
docker run -d --name back -p 8081:8081 -v tp4-data:/data localhost:5000/tp/back:2.0.0
docker run -d --name front -p 4200:8080 localhost:5000/tp/front:2.0.0
# créer des données sur http://localhost:4200
docker rm -f back
docker run -d --name back -p 8081:8081 -v tp4-data:/data localhost:5000/tp/back:2.0.0

docker pull localhost:5000/tp/front:2.0.0
docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'tp[34]-|tp/'
```

Le back passe d'une image comprenant un système Ubuntu complet, un JDK, Maven et des centaines de Mo de dépendances à une image distroless contenant un JRE et l'application. Le front passe de plus d'un Go à quelques dizaines de Mo.

Ménage :

```bash
docker rm -f back front registry
docker volume rm tp4-data
docker buildx use default
docker buildx rm tp4                # supprime le builder, son conteneur et son cache
docker rmi tp4-back:simple tp4-back:build tp4-back:distroless tp4-front:nginx \
  localhost:5000/tp/back:2.0.0 localhost:5000/tp/front:2.0.0
docker buildx prune                 # cache du builder default
docker system df
```

Les couches sont compressées (gzip par défaut) dans le registre et pendant le transfert : un `pull` transfère moins que la taille affichée par `docker images`, et seulement les couches absentes de la machine. C'est là que le découpage en couches du back prend tout son sens : à chaque nouvelle version, seule la couche `application` transite.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Récapitulatif

| Pratique | Pourquoi |
| --- | --- |
| Étape de build et étape d'exécution séparées | Outils de compilation, caches et sources absents de l'image finale |
| `--target` | Construire et inspecter une étape intermédiaire |
| `RUN --mount=type=cache` | Caches de dépendances conservés entre les builds, jamais écrits dans l'image |
| Jar découpé en couches | Seule la couche du code change d'une version à l'autre |
| Image finale distroless ou spécialisée non root | Surface d'attaque minimale, pas de privilèges |
| Pas de `RUN` dans l'étape finale | Image minimale, et pas d'émulation en multi-plateforme |
| `FROM --platform=$BUILDPLATFORM` pour l'étape de build | Compiler une seule fois, en natif, ce qui ne dépend pas de l'architecture |
| Compilation croisée avec `TARGETOS` / `TARGETARCH` | Produire du code natif pour chaque architecture sans émulation |
| Builder `docker-container` + `--push` | Construire et publier un index multi-plateforme |
| Tags `X.Y.Z`, `X.Y`, `X`, `latest`, `sha-<commit>` | Version immuable, tags mobiles pratiques, traçabilité jusqu'au commit |
| Labels OCI `version` et `revision` | Retrouver l'origine d'une image à partir de l'image elle-même |

{% endraw %}
