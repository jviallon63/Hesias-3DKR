---
title: "TP 6 - Orchestrer l'application avec Docker Compose"
objective: "Décrire l'application complète (front, back, base PostgreSQL) dans un fichier Compose, maîtriser réseaux, volumes, ports et variables d'environnement, et exploiter la pile avec les commandes docker compose."
---

{% raw %}

# Contexte

Au TP 4, lancer l'application demandait deux commandes `docker run` de plusieurs lignes, dans le bon ordre, avec les bons ports, volumes et variables. Ajoutez une base de données, et l'équipe se retrouve avec un fichier texte de commandes à copier-coller, que personne ne tient à jour.

**Docker Compose** décrit toute l'application dans un fichier YAML versionné : services, réseaux, volumes, configuration. Une commande la démarre, une autre l'arrête.

Pour l'occasion, le back abandonne SQLite pour **PostgreSQL**, avec l'image officielle de Docker Hub. Le back n'est pas reconstruit pour autant : il embarque déjà le driver PostgreSQL, et sa configuration de base de données se remplace par des variables d'environnement.

**Prérequis :**

- TP 5 terminé, avec les Dockerfiles multi-étapes du back et du front et leurs fichiers annexes.

> Compose v2 s'utilise avec `docker compose` (avec une espace). L'ancien `docker-compose` (avec un tiret), écrit en Python, n'est plus maintenu.

---

## Objectifs

<div class="section objective">

1. Traduire des commandes `docker run` en services Compose
2. Ajouter une base PostgreSQL avec persistance et contrôle de santé
3. Distinguer les mécanismes de variables d'environnement de Compose et protéger les secrets
4. Isoler les services avec plusieurs réseaux
5. Utiliser volumes nommés et montages pour initialiser une base
6. Exploiter une pile avec les commandes `docker compose`

</div>

---

## Étape 1 - Du `docker run` au `compose.yaml`

Rappel des commandes de lancement du TP 4 :

```bash
docker container run -d --name back -p 8080:8080 -v ./data/:/data/ tp5-back:1.0.0
docker container run -d --name front -p 4200:4200 tp5-front-nginx:1.0.0
```

**Ce que vous devez faire :**

- Créez `compose.yaml` qui décrit les services `back` et `front` :
  - le projet s'appelle `tp` (clé `name` en tête de fichier).
  - chaque service est construit (`build`dans compose) à partir de son dossier.
  - appliquez les ports et les volumes comme précédement.
- Démarrez la pile en arrière-plan, listez ses services, puis suivez les logs du back jusqu'à son démarrage complet. Vérifiez l'application sur <http://localhost:4200>.
- Depuis le conteneur `front`, résolvez le nom `back` (`nc -zv back 8080`). Recommencez avec localhost.
- Arrêtez la pile avec `docker compose down`. Que reste-t-il ?

**Questions de réflexion :**

- Comment sont nommés les conteneurs, réseaux et volumes ? 
- Vous n'avez déclaré aucun réseau. Comment les conteneurs peuvent-ils se joindre par leur nom ?

{::nomarkdown}
<details><summary>Solution - Étape 1</summary>
{:/nomarkdown}

`compose.yaml` :

```yaml
name: tp

services:
  back:
    build:
      context: ../sample-app/back
      dockerfile: ../../tp5/back/multi_v2.Dockerfile
    image: tp/back:1.0.0
    ports:
      - "8080:8080"
    volumes:
      - back-data:/data

  front:
    build:
      context: ../sample-app/front
      dockerfile: ../../tp5/front/multi.Dockerfile
    image: tp/front:1.0.0
    ports:
      - "4200:4200"

volumes:
  back-data:
```

```bash
BUILDX_BAKE_ENTITLEMENTS_FS=0 docker compose up -d
docker compose ps
docker compose logs -f back         # Ctrl+C une fois « Started ... » affiché
```

Au premier `up`, Compose construit les images absentes avant de créer les conteneurs.

```bash
docker container ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
docker network ls --filter name=tp
docker volume ls --filter name=tp
docker compose exec front nc -zv back 8080
```

Tout est préfixé par le nom du projet : conteneurs `tp-back-1` et `tp-front-1` (le suffixe numérote les répliques), réseau `tp_default`, volume `tp_back-data`. Sans clé `name`, le projet prendrait le nom du dossier.

Compose crée un réseau `tp_default` et y attache tous les services. Sur un réseau défini par l'utilisateur, Docker fournit un **DNS interne** : chaque service est joignable par son nom, qui se résout vers l'adresse IP de son conteneur. Ce n'est pas le cas sur le réseau `bridge` par défaut utilisé par `docker run`.

```bash
docker compose down
docker container ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
docker network ls --filter name=tp
docker volume ls --filter name=tp
```

`down` supprime les conteneurs et le réseau, mais **conserve les volumes** et les images.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 2 - Ajouter PostgreSQL

**Informations utiles :**

- L'image officielle `postgres` se configure par variables d'environnement : `POSTGRES_DB`, `POSTGRES_USER` et `POSTGRES_PASSWORD` créent la base et son propriétaire au premier démarrage. Les données sont stockées dans `/var/lib/postgresql/data`.
- La commande `pg_isready -U app -d app`, exécutée dans le conteneur, indique si PostgreSQL accepte les connexions.
- Le back est une application Spring Boot : toute propriété de configuration peut être remplacée par une variable d'environnement, en majuscules, avec `_` à la place des points (`spring.datasource.url` devient `SPRING_DATASOURCE_URL`).
- Le back propose deux profiles : `local` (par défaut), avec SQLite, et `dev`, avec PostgreSQL. Le profile `dev` s'active avec l'argument `--spring.profiles.active=dev`.

**Ce que vous devez faire :**

Écrivez un fichier `compose-postgre.yaml` qui répond aux besoins suivants :

- Une base de données PostgreSQL :
  - basée sur l'image `postgres:17-alpine`.
  - la base et l'utilisateur s'appellent `app`, le mot de passe est libre.
  - les données sont stockées dans un volume `db-data`.
  - son état de santé est contrôlé régulièrement avec `pg_isready`.
- Le back :
  - se connecte à la base PostgreSQL avec les variables `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME` et `SPRING_DATASOURCE_PASSWORD`.
  - démarre avec le profile `dev` en argument (**pas besoin de reconstruire l'image**).
  - ne démarre **que lorsque la base accepte les connexions**.
  - n'a plus besoin du volume `back-data`.
- Le front ne change pas.

Démarrez la pile et observez l'ordre de démarrage dans `docker compose ps` et dans les logs.

Depuis chaque conteneur, vérifiez avec `nc -zv` que les autres services sont joignables.

{::nomarkdown}
<details><summary>Solution - Étape 2</summary>
{:/nomarkdown}

```yaml
name: tp

services:
  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: azerty9876
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d app"]
      interval: 5s
      timeout: 3s
      retries: 10

  back:
    build:
      context: ../sample-app/back
      dockerfile: ../../tp5/back/multi_v2.Dockerfile
    image: tp/back:1.0.0
    command: ["--spring.profiles.active=dev"]
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/app
      SPRING_DATASOURCE_USERNAME: app
      SPRING_DATASOURCE_PASSWORD: azerty9876
    ports:
      - "8080:8080"
    depends_on:
      db:
        condition: service_healthy

  front:
    build:
      context: ../sample-app/front
      dockerfile: ../../tp5/front/multi.Dockerfile
    image: tp/front:1.0.0
    ports:
      - "4200:4200"

volumes:
  db-data:
```

```bash
BUILDX_BAKE_ENTITLEMENTS_FS=0 docker compose -f compose-postgre.yaml up -d
docker compose -f compose-postgre.yaml ps                   # db : (healthy)
docker compose -f compose-postgre.yaml logs db back
```

`up` attend que `db` soit `healthy` avant de créer `back`. Le volume `tp_back-data` de l'étape 1 n'est plus utilisé : supprimez-le avec `docker volume rm tp_back-data`.

```bash
docker compose -f compose-postgre.yaml down
docker compose -f compose-postgre.yaml down -v && docker compose -f compose-postgre.yaml up -d  # base vide
```

`down -v` supprime aussi les volumes nommés déclarés dans le fichier : la base repart de zéro.

Le mot de passe de la base apparaît ici en clair dans le fichier Compose. En pratique, ce fichier est versionné dans un gestionnaire de code source comme Git : le mot de passe doit en sortir, par exemple vers un fichier `.env` ajouté au `.gitignore`. Compose charge les variables du fichier avec `env_file: .env`.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 3 - Isoler les services avec des réseaux

Pour l'instant, les trois services partagent le réseau `tp_default` : le front pourrait joindre la base directement. Seul le back en a besoin.

**Ce que vous devez faire :**

- Déclarez deux réseaux :
  - `backend`, réseau **interne** (`internal: true`) pour la base et le back.
  - `frontend`, pour le back et le front.
- Attachez chaque service aux seuls réseaux dont il a besoin.
- Relancez la pile.
- Depuis chaque conteneur, testez la connexion avec `nc -zv`. Essayez de sortir sur internet `ping google.com`
- Vérifiez que l'application fonctionne toujours depuis votre navigateur.

**Questions de réflexion :**

- Que signifie `internal: true` sur le réseau `backend` ?

{::nomarkdown}
<details><summary>Solution - Étape 3</summary>
{:/nomarkdown}

```yaml
services:
  db:
    # ...
    networks:
      - backend

  back:
    # ...
    networks:
      - backend
      - frontend

  front:
    # ...
    networks:
     - frontend

networks:
  backend:
    internal: true
  frontend:
```

```bash
BUILDX_BAKE_ENTITLEMENTS_FS=0 docker compose up -d

docker container exec tp-front-1 nc -zv back 8080
docker container exec tp-front-1 nc -zv db 5432

docker container exec tp-back-1 nc -zv front 4200
docker container exec tp-back-1 nc -zv db 5432

docker container exec tp-db-1 nc -zv back 8080
docker container exec tp-db-1 nc -zv front 4200

docker container exec tp-front-1 ping google.com
docker container exec tp-back-1 ping google.com
docker container exec tp-db-1 ping google.com
```

Compose détecte le changement de configuration et recrée les conteneurs concernés. Le réseau `tp_default` n'est plus utilisé.

Le DNS interne ne répond que pour les services présents sur un réseau commun : le front ne voit même pas l'existence de `db`. Sur un réseau `internal`, les conteneurs ne peuvent pas non plus sortir vers l'extérieur : une base compromise ne peut ni télécharger d'outil ni exfiltrer de données.

Le back est aussi sur `frontend`, un réseau classique : c'est par lui que passe son port publié. À l'inverse, un service relié **uniquement** à un réseau interne ne peut pas publier de port : `ports: ["5432:5432"]` sur `db` n'a aucun effet tant qu'il n'est relié qu'à `backend`.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 4 - Profils : des outils à la demande

Certains services ne servent qu'occasionnellement : outils d'administration, jeux de données de test, outils de débogage. Un **profil** les exclut du démarrage par défaut.

**Ce que vous devez faire :**

- Ajoutez un service `adminer` (image `adminer:4`, une interface web d'administration de bases de données) :
  - dans le profil `tools` ;
  - publié sur le port 8082 de l'hôte, **uniquement en local** ;
  - avec le service `db` comme serveur par défaut (variable `ADMINER_DEFAULT_SERVER`) ;
  - relié aux réseaux nécessaires pour joindre la base et être publié.
- Lancez `docker compose up -d` : `adminer` démarre-t-il ? Démarrez-le avec son profil.
- Connectez-vous sur <http://127.0.0.1:8082> (système PostgreSQL, utilisateur `lecteur`) et parcourez les tables.
- Arrêtez la pile avec `docker compose down`, sans préciser de profil. Que devient `adminer` ?

**Question de réflexion :**

- Pourquoi `adminer` doit-il être relié à deux réseaux ?

{::nomarkdown}
<details><summary>Solution - Étape 4</summary>
{:/nomarkdown}

```yaml
  adminer:
    image: adminer:4
    profiles: [tools]
    environment:
      ADMINER_DEFAULT_SERVER: db
    ports:
      - "127.0.0.1:8082:8080"
    networks: [backend, frontend]
    depends_on:
      db:
        condition: service_healthy
```

```bash
BUILDX_BAKE_ENTITLEMENTS_FS=0 docker compose up -d                       # adminer ignoré
docker compose --profile tools up -d       # adminer démarré
docker compose down                        # observez la liste des conteneurs supprimés
docker compose --profile tools down
```

Sans profil actif, les services profilés sont ignorés. On active un profil avec `--profile` ou la variable `COMPOSE_PROFILES=tools`. Selon la version de Compose, un `down` sans le profil peut laisser `adminer` tourner, et le réseau qu'il utilise avec lui : précisez le profil pour arrêter aussi ses services.

`adminer` doit joindre `db`, uniquement présente sur `backend`, et être publié sur l'hôte, ce qui est impossible depuis un réseau interne seul : il lui faut aussi `frontend`. Le port n'est publié que sur `127.0.0.1` : un outil d'administration n'a pas à être exposé sur le réseau local.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Fichier final

```yaml
name: tp

services:
  adminer:
    image: adminer:4
    profiles: [tools]
    environment:
      ADMINER_DEFAULT_SERVER: db
    ports:
      - "127.0.0.1:8082:8080"
    networks: [backend, frontend]
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: azerty9876
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d app"]
      interval: 5s
      timeout: 3s
      retries: 10
    networks: 
      - backend

  back:
    build:
      context: ../sample-app/back
      dockerfile: ../../tp5/back/multi_v2.Dockerfile
    image: tp/back:1.0.0
    command: ["--spring.profiles.active=dev"]
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/app
      SPRING_DATASOURCE_USERNAME: app
      SPRING_DATASOURCE_PASSWORD: azerty9876
    ports:
      - "8080:8080"
    depends_on:
      db:
        condition: service_healthy
    networks:
      - backend
      - frontend

  front:
    build:
      context: ../sample-app/front
      dockerfile: ../../tp5/front/multi.Dockerfile
    image: tp/front:1.0.0
    ports:
      - "4200:4200"
    networks: 
      - frontend

volumes:
  db-data:

networks:
  backend:
    internal: true
  frontend:
```

{% endraw %}
