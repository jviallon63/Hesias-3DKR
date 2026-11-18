---
title: "TP 5 - Builds multi-étapes et multi-plateformes avec Buildx"
objective: "Réécrire les images du TP 3 avec des builds multi-étapes pour les réduire au strict nécessaire, puis les construire pour plusieurs architectures et les publier avec un schéma de tags versionné."
---

# Contexte

Le TP 3 s'est terminé sur un constat : avec un Dockerfile à une seule étape, tout ce qui sert à **construire** l'application (JDK, Maven, `~/.m2`, Node.js, `node_modules`, sources) reste dans l'image qui l'**exécute**. Et il fallait choisir entre un build rapide (dépendances en cache dans une couche) et une image légère.

Ce TP lève ces deux limites, puis en aborde une nouvelle : votre équipe déploie à la fois sur des serveurs x86 (`amd64`) et sur des machines ARM (`arm64` : Mac Apple Silicon, instances cloud Graviton, Raspberry Pi). Une seule référence d'image doit fonctionner partout.

L'outil de ce TP est **Buildx**, le client de build de Docker, qui pilote le moteur **BuildKit**.

**Prérequis :**

- TP 3 terminé : le dépôt est cloné localement.
- Les images du TP 3 (`tp3-back:v1`, `tp3-back:v2`, `tp3-front:v1`, `tp3-front:v2`) pour comparer les tailles. Si vous les avez supprimées, reconstruisez au moins les V2.
- TP 4 terminé : `registry:3` est déployé localement.
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
2. Choisir une image d'exécution minimale et non root
3. Construire et publier une image multi-plateforme sans émulation inutile
4. Appliquer un schéma de tags versionné et traçable

</div>

---

## Étape 1 - Le back en multi-étapes

Un Dockerfile multi-étapes contient plusieurs `FROM`. Chacun démarre une **étape** indépendante, que l'on peut nommer avec `AS`. Une étape peut copier des fichiers produits par une autre avec `COPY --from=<étape>`. **Seule la dernière étape** constitue l'image finale : tout le reste est jeté.

**Ce que vous devez faire :**

- Écrivez `back/Dockerfile` avec deux étapes :
  - une étape `build`, basée sur `maven:3-eclipse-temurin-21`, qui compile le jar comme au TP 3.
  - une étape finale, basée sur `eclipse-temurin:21-jre-alpine`, qui ne reçoit **que le jar**, et reprend la configuration de la V2 du TP 3.
- Construisez l'image `tp5-back:1.0.0` . Comparez sa taille avec `tp3-back:v1` et `tp3-back:v2`, et lisez son historique.
- Construisez uniquement l'étape `build` sous le nom `tp5-back:build`, et ouvrez un shell dedans pour retrouver le jar.

**Questions de réflexion :**

- Qu'est-ce qui a disparu de l'image finale par rapport au TP 3 ? Que montre `docker history` des instructions de l'étape `build` ?

{% comment %}
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
CMD ["--server.port=8080"]
```

```bash
docker buildx build -t tp5-back:1.0.0 back/
docker image ls --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'tp[34]-back'
docker image history tp5-back:1.0.0
```

L'image ne contient plus ni Maven, ni le JDK, ni `~/.m2`, ni les sources : seulement un JRE et le jar. `docker image history` ne montre **aucune** instruction de l'étape `build` : elle n'a laissé aucune trace dans l'image finale.


```bash
docker buildx build --target build -t tp5-back:build back/
docker container run --rm -it tp5-back:build bash
ls -l target/*.jar
```

`--target` arrête le build à l'étape indiquée. C'est l'outil de débogage du multi-étapes : on inspecte le résultat intermédiaire sans toucher au Dockerfile.

{::nomarkdown}
</details>
{:/nomarkdown}
{% endcomment %}

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

- le routage d'Angular : avec une configuration nginx classique.

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
- Construisez `tp5-front-nginx:1.0.0`, comparez sa taille avec celles du TP 3, et lancez-le en publiant le port 8080 du conteneur sur le port 4200 de l'hôte. Vérifiez le fonctionnement de l'application avec le back.

**Questions de réflexion :**

- L'étape finale ne contient ni `ENTRYPOINT` ni `CMD`. Comment le conteneur sait-il quoi lancer ?

{% comment %}
{::nomarkdown}
<details><summary>Solution - Étape 2</summary>
{:/nomarkdown}

`front/Dockerfile` :

```dockerfile
FROM node:22-alpine AS build
WORKDIR /app
COPY --chown=node:node . .
RUN npm ci && npm cache clean --force
RUN npx ng build

FROM nginxinc/nginx-unprivileged:stable-alpine

COPY docker/default.conf /etc/nginx/conf.d/default.conf
COPY --chmod=755 docker/40-backend-url.sh /docker-entrypoint.d/40-backend-url.sh
COPY --from=build --chown=101:101 /app/dist/browser /usr/share/nginx/html

ENV BACKEND_URL=http://localhost:8080
EXPOSE 4200
```

```bash
docker buildx build -t tp5-front-nginx:1.0.0 front/
docker image ls --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}'

docker container run -d --name back -p 8080:8080 -v ./data/:/data/ tp5-back:1.0.0
docker container run -d --name front -p 4200:4200 tp5-front-nginx:1.0.0
```

L'étape finale **hérite** de l'`ENTRYPOINT` (`/docker-entrypoint.sh`) et du `CMD` (`nginx -g daemon off;`) de son image de base. Le point d'entrée exécute les scripts de `/docker-entrypoint.d/` dans l'ordre alphabétique (d'où le préfixe `40-`), puis lance nginx avec `exec`.

{::nomarkdown}
</details>
{:/nomarkdown}
{% endcomment %}

---

## Étape 3 - Construire pour plusieurs plateformes

Par défaut, **chaque étape** est exécutée pour la plateforme cible, donc sous émulation pour les plateformes étrangères. Or un jar et un dossier `dist/` sont identiques quelle que soit l'architecture. BuildKit fournit des variables pour en tirer parti :

| Variable | Valeur |
| --- | --- |
| `BUILDPLATFORM` | Plateforme de la machine qui construit (par exemple `linux/arm64` sur un Mac M1) |
| `TARGETPLATFORM` | Plateforme de l'image en cours de production |
| `TARGETOS`, `TARGETARCH` | Les deux composantes de `TARGETPLATFORM` |

**Ce que vous devez faire :**

- Pour mesurer précisément les temps d'exécution, videz le cache de Buildx avec la commande `docker buildx prune -a`.
- Avec l'option `--platform`, construisez le back pour `linux/amd64` et `linux/arm64`. Notez le temps de build.
- Videz le cache de Buildx de nouveau !
- Dans le Dockerfile, ajoutez `--platform=$BUILDPLATFORM` sur le `FROM` de l'étape `build` du back et du front.  Notez le temps de build.


- Démarrer la registry du TP4 (avec l'UI si possible).
- Poussez la dernière image du back avec le multi-arch sur la registry.
- Affichez l'index des deux images avec `docker buildx imagetools inspect <votre_image>`. Combien d'entrées comptez-vous ?
- Comparez avec une image du TP3.

**Questions de réflexion :**

- Pourquoi le second build est plus rapide (presque divisé par 2) ?
- Dans quel cas `--platform=linux/amd64,linux/arm64` ne suffirait-il pas sur la commande de build ?
- Quelle différence entre `docker image inspect` et `docker buildx imagetools inspect`?

{% comment %}
{::nomarkdown}
<details><summary>Solution - Étape 3</summary>
{:/nomarkdown}

Premier build, sans `$BUILDPLATFORM` :

```bash
time docker buildx build --platform linux/amd64,linux/arm64 \
  -t localhost:5000/sample-app/back:1.0.0 back/
```
L'étape `build` est exécutée deux fois, dont une sous émulation : Maven tourne sur un processeur virtuel, et le build est nettement plus long.

Étape `build` du back après modification :

```dockerfile
FROM --platform=$BUILDPLATFORM maven:3-eclipse-temurin-21 AS build
...
```

```bash
time docker buildx build --platform linux/amd64,linux/arm64 \
  -t localhost:5000/sample-app/back:1.0.0 back/
```

L'étape `build` n'est exécutée qu'un fois, avec l'architecture de l'hôte. La secondes étape créé les 2 images en récupérant le jar qui n'est pas dépendant de l'architecture. Avec Go par exemple le build devra être fait 2 fois car le binaire compilé par Go est lié à l'architecture.

```dockerfile
RUN GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build
```

```bash
docker buildx imagetools inspect localhost:5000/sample-app/back:1.0.0
docker buildx imagetools inspect localhost:5000/sample-app/back:0.0.0
```

L'index contient une entrée par plateforme, plus une entrée `unknown/unknown` par plateforme : ce sont des **attestations de provenance**, ajoutées par défaut par Buildx. Elles décrivent comment l'image a été construite (Dockerfile, images de base, paramètres) et servent à vérifier la chaîne d'approvisionnement. `--provenance=false` les désactive.

- `docker image inspect <image>` examine une image présente dans le stockage local de Docker. Il affiche ses détails de configuration, comme l’architecture, les variables d’environnement et la commande de démarrage.
- `docker buildx imagetools inspect <image>` consulte *l'index* de l’image dans un registre et affiche ses manifestes.

```bash
docker pull localhost:5001/sample-app/back:1.0.0@sha256:f3c586170991eb9cf6e7bff593d1eb70a28ce79691877747631d22fcd1874aab
docker image inspect localhost:5001/sample-app/back:1.0.0@sha256:f3c586170991eb9cf6e7bff593d1eb70a28ce79691877747631d22fcd1874aab

docker container run --rm -d --name back_amd -p 8089:8080 localhost:5001/sample-app/back:1.0.0@sha256:f3c586170991eb9cf6e7bff593d1eb70a28ce79691877747631d22fcd1874aab
docker exec -it back_amd uname -a 

docker container run --rm -d --name back -p 8088:8080 localhost:5001/sample-app/back:1.0.0
docker exec -it back uname -a 
```

{::nomarkdown}
</details>
{:/nomarkdown}
{% endcomment %}

---

## Étape 4 - Build & push : tout-en-un

Nous disposons maintenant d'une image multi-plateforme à publier dans la registry sous trois tags : `1.0.1`, `1.0` et `latest`. Les tags de version permettent d'identifier les versions publiées, tandis que `latest` est un tag mobile. La construction de l'image, l'ajout de ses tags et sa publication peuvent nécessiter plusieurs commandes, mais Buildx permet de regrouper ces opérations en une seule.

**Ce que vous devez faire :**

- Construisez et publiez l'image du back pour les architectures `amd64` et `arm64` dans la registry `localhost:5000`, sous les tags `1.0.1`, `1.0` et `latest`, à l'aide d'une seule commande `docker buildx build`.

{% comment %}
{::nomarkdown}
<details><summary>Solution - Étape 4</summary>
{:/nomarkdown}

```bash
VERSION="1.0.1"
docker buildx build --platform linux/amd64,linux/arm64 \
  -t "localhost:5000/sample-app/back:${VERSION}" \
  -t "localhost:5000/sample-app/back:${VERSION%.*}" \
  -t "localhost:5000/sample-app/back:latest" \
  --push \
  sample-app/back
```

```bash
curl -u etudiant:tp4-Registre http://localhost:5000/v2/sample-app/back/tags/list
```

{::nomarkdown}
</details>
{:/nomarkdown}
{% endcomment %}

---

## Étape 5 - Scanner l'image multi-étapes

Au TP 4, Trivy a scanné l'image du back construite en une seule étape : Ubuntu, JDK, Maven, le dépôt `~/.m2` et le jar. L'image multi-étapes ne garde qu'un JRE et le jar. Reste à mesurer ce que cela change pour la sécurité.

**Ce que vous devez faire :**

- Scannez `back:0.0.0` (l'image complète du TP 4) et `back:1.0.0` (l'image construite dans ce TP).
- Refaites les deux scans en séparant les vulnérabilités des **paquets du système** (`--pkg-types os`) de celles des **bibliothèques applicatives** (`--pkg-types library`).

{% comment %}
{::nomarkdown}
<details><summary>Solution - Étape 5</summary>
{:/nomarkdown}

```bash
trivy() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v trivy-cache:/root/.cache \
    -v "$PWD":/work -w /work \
    "aquasec/trivy:0.76.1" "$@"
}

trivy image --format template --template "@/work/html.tpl" -o report_0.0.0.html localhost:5001/sample-app/back:0.0.0
trivy image --format template --template "@/work/html.tpl" -o report_1.0.0.html localhost:5001/sample-app/back:1.0.0

trivy image --format template --template "@/work/html.tpl" -o report_1.0.0.html --pkg-types os localhost:5001/sample-app/back:1.0.0
trivy image --format template --template "@/work/html.tpl" -o report_1.0.0.html --pkg-types library localhost:5001/sample-app/back:1.0.0
```

Les chiffres exacts dépendent de la date du scan, mais la tendance est nette :

- **paquets du système** : l'image complète embarque Ubuntu et tous les paquets tirés par `openjdk-21-jdk-headless` et `maven`. L'image multi-étapes ne contient qu'Alpine et le JRE, mis à jour par `apk upgrade` : il ne reste que peu de vulnérabilités, souvent aucune critique ;
- **bibliothèques** : dans l'image complète, Trivy analyse aussi les jars de Maven (`/usr/share/maven/lib`) et tout le dépôt `/root/.m2` (plugins et dépendances de build). Ces cibles disparaissent : il ne reste que `/app/app.jar` et les bibliothèques qu'il embarque ;

Less vulnérabilités du jar applicatif sont **identiques** dans les deux images : le build multi-étapes retire les outils de construction, pas les dépendances de l'application. Pour les corriger, il faut monter leur version dans `pom.xml` et reconstruire.

{::nomarkdown}
</details>
{:/nomarkdown}
{% endcomment %}

---

## Étape 6 - Ménage

**Ce que vous devez faire :**

- Faites le ménage : conteneurs, volume, builder.
