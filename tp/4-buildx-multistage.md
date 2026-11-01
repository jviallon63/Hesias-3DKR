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

- TP 3 terminé : le dépôt est cloné localement.
- Les images du TP 3 (`tp3-back:v1`, `tp3-back:v2`, `tp3-front:v1`, `tp3-front:v2`) pour comparer les tailles. Si vous les avez supprimées, reconstruisez au moins les V2.
- le plugin Buildx est installé. Il est fourni par défaut avec Docker Desktop. Si vous utilisez le client Docker installé par Homebrew sur macOS :

  ```bash
  brew install docker-buildx
  mkdir -p "$HOME/.docker/cli-plugins"
  ln -sfn "$(brew --prefix)/opt/docker-buildx/bin/docker-buildx" \
    "$HOME/.docker/cli-plugins/docker-buildx"
  docker buildx version
  ```

---

## Objectifs

<div class="section objective">

1. Séparer construction et exécution avec un Dockerfile multi-étapes
2. Utiliser les montages de cache BuildKit pour accélérer les builds sans alourdir les images
3. Choisir une image d'exécution minimale et non root
4. Construire et publier une image multi-plateforme sans émulation inutile
5. Appliquer un schéma de tags versionné et traçable

</div>

---

## Étape 1 - Le back en multi-étapes

Un Dockerfile multi-étapes contient plusieurs `FROM`. Chacun démarre une **étape** indépendante, que l'on peut nommer avec `AS`. Une étape peut copier des fichiers produits par une autre avec `COPY --from=<étape>`. **Seule la dernière étape** constitue l'image finale : tout le reste est jeté.

**Ce que vous devez faire :**

- Écrivez `back/Dockerfile` avec deux étapes :
  - une étape `build`, basée sur `maven:3-eclipse-temurin-21`, qui compile le jar comme au TP 3.
  - une étape finale, basée sur `eclipse-temurin:21-jre-alpine`, qui ne reçoit **que le jar**, et reprend la configuration de la V2 du TP 3.
- Construisez l'image `tp4-back:1.0.0` . Comparez sa taille avec `tp3-back:v1` et `tp3-back:v2`, et lisez son historique.
- Construisez uniquement l'étape `build` sous le nom `tp4-back:build`, et ouvrez un shell dedans pour retrouver le jar.

**Questions de réflexion :**

- Qu'est-ce qui a disparu de l'image finale par rapport au TP 3 ? Que montre `docker history` des instructions de l'étape `build` ?

{::nomarkdown}
<details><summary>Solution - Étape 1</summary>
{:/nomarkdown}

`back/Dockerfile` :

```dockerfile
FROM maven:3-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn package -DskipTests

FROM eclipse-temurin:21-jre-alpine
RUN apk upgrade --no-cache
RUN addgroup --system app && adduser --system --ingroup app app
WORKDIR /app
COPY --from=build /app/target/openapi-workshop-1.0.0.jar app.jar
RUN mkdir /data && chown ubuntu:ubuntu /data
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
CMD ["--server.port=8081"]
```

```bash
docker buildx build -t tp4-back:1.0.0 back/
docker image ls --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'tp[34]-back'
docker image history tp4-back:1.0.0
```

L'image ne contient plus ni Maven, ni le JDK, ni `~/.m2`, ni les sources : seulement un JRE et le jar. `docker image history` ne montre **aucune** instruction de l'étape `build` : elle n'a laissé aucune trace dans l'image finale.


```bash
docker buildx build --target build -t tp4-back:build back/
docker container run --rm -it tp4-back:build bash
ls -lh target/*.jar
exit
```

`--target` arrête le build à l'étape indiquée. C'est l'outil de débogage du multi-étapes : on inspecte le résultat intermédiaire sans toucher au Dockerfile.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 2 - Le front en multi-étapes

L'exécution du front n'a besoin que du dossier `dist/browser` et d'un serveur web. On utilise `nginxinc/nginx-unprivileged`, variante de l'image nginx officielle qui tourne **sans root**.

Il faut adapter deux éléments du TP 3 :

- l'URL du back, écrite dans `assets/config.js` au démarrage. Le point d'entrée de l'image nginx exécute tous les scripts exécutables du dossier `/docker-entrypoint.d/` avant de lancer nginx : il suffit d'y placer un script.

`/docker-entrypoint.d/40-backend-url.sh` :

```sh
#!/bin/sh
set -eu
cat > /usr/share/nginx/html/assets/config.js <<EOF
window.dynamicConf = {
  BACKEND_URL: "${BACKEND_URL}"
};
EOF
```

- le routage d'Angular : avec une configuration ngonx classique.

`/etc/nginx/conf.d/default.conf` :

```nginx
server {
    listen 4200;
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

**Ce que vous devez faire :**

- Écrivez `front/Dockerfile` avec :
  - une étape `build` sur `node:22-alpine`.
  - une étape finale sur `nginxinc/nginx-unprivileged:stable-alpine` qui reçoit la configuration, le script (exécutable, avec `COPY --chmod`) et le contenu de `dist/browser`, appartenant à l'utilisateur `nginx`.
  - Supprimez la ligne `ENTRYPOINT` du Dockerfile.
- Construisez `tp4-front-nginx:1.0.0`, comparez sa taille avec celles du TP 3, et lancez-le en publiant le port 8080 du conteneur sur le port 4200 de l'hôte. Vérifiez le fonctionnement de l'application avec le back.

**Questions de réflexion :**

- L'étape finale ne contient ni `ENTRYPOINT` ni `CMD`. Comment le conteneur sait-il quoi lancer ?

{::nomarkdown}
<details><summary>Solution - Étape 4</summary>
{:/nomarkdown}

`front/Dockerfile` :

```dockerfile
FROM node:22-alpine AS build
WORKDIR /app
COPY --chown=node:node . .
RUN npm ci && npm cache clean --force
RUN npx ng build

FROM nginxinc/nginx-unprivileged:stable-alpine
ARG APP_VERSION=dev

COPY docker/default.conf /etc/nginx/conf.d/default.conf
COPY --chmod=755 docker/40-backend-url.sh /docker-entrypoint.d/40-backend-url.sh
COPY --from=build --chown=101:101 /app/dist/browser /usr/share/nginx/html

ENV BACKEND_URL=http://localhost:8080
EXPOSE 4200
```

```bash
docker buildx build -t tp4-front-nginx:1.0.0 front/
docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'tp[34]-front'

docker run -d --name back -p 8080:8080 tp4-back:1.0.0
docker run -d --name front -p 4200:8080 tp4-front-nginx:1.0.0
curl http://localhost:4200/assets/config.js
```

L'étape finale **hérite** de l'`ENTRYPOINT` (`/docker-entrypoint.sh`) et du `CMD` (`nginx -g daemon off;`) de son image de base. Le point d'entrée exécute les scripts de `/docker-entrypoint.d/` dans l'ordre alphabétique (d'où le préfixe `40-`), puis lance nginx avec `exec`.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 3 - Construire pour plusieurs plateformes

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
<details><summary>Solution - Étape 3</summary>
{:/nomarkdown}

Premier build, sans `$BUILDPLATFORM` :

```bash
time docker buildx build --platform linux/amd64,linux/arm64 \
  -t localhost:5000/tp/back:test --push back/
```

L'étape `build` est exécutée deux fois, dont une sous émulation : Maven tourne sur un processeur virtuel, et le build est nettement plus long.

Début de l'étape `build` du back après modification :

```dockerfile
FROM --platform=$BUILDPLATFORM maven:3-eclipse-temurin-21 AS build
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

## Étape 4 - Nouveaux tags pour les builds

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

- Pourquoi un tag `sha-...` en plus du tag de version ?

{::nomarkdown}
<details><summary>Solution - Étape 4</summary>
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

## Étape 5 - Ménage

**Ce que vous devez faire :**

- Faites le ménage : conteneurs, volume, registre, builder.

**Question de réflexion :**

- `docker images` affiche la taille **décompressée** de l'image. Ce qui transite sur le réseau lors d'un `pull` est-il plus gros ou plus petit ?

{::nomarkdown}
<details><summary>Solution - Étape 5</summary>
{:/nomarkdown}

```bash
docker container rm -f ...
docker image rm ...
docker image prune -a
docker buildx prune
docker system df
(docker system prune)
```

{::nomarkdown}
</details>
{:/nomarkdown}

{% endraw %}
