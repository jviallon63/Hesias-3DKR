---
title: "TP 5 - Orchestrer l'application avec Docker Compose"
objective: "Décrire l'application complète (front, back, base PostgreSQL) dans un fichier Compose, maîtriser réseaux, volumes, ports et variables d'environnement, et exploiter la pile avec les commandes docker compose."
---

{% raw %}

# Contexte

Au TP 4, lancer l'application demandait deux commandes `docker run` de plusieurs lignes, dans le bon ordre, avec les bons ports, volumes et variables. Ajoutez une base de données, et l'équipe se retrouve avec un fichier texte de commandes à copier-coller, que personne ne tient à jour.

**Docker Compose** décrit toute l'application dans un fichier YAML versionné : services, réseaux, volumes, configuration. Une commande la démarre, une autre l'arrête.

Pour l'occasion, le back abandonne SQLite pour **PostgreSQL**, avec l'image officielle de Docker Hub. Le back n'est pas reconstruit pour autant : il embarque déjà le driver PostgreSQL, et sa configuration de base de données se remplace par des variables d'environnement.

**Prérequis :**

- TP 4 terminé : le dépôt est dans `~/tp3`, avec les Dockerfiles multi-étapes du back et du front et leurs fichiers annexes.
- Le builder actif est `default` (`docker buildx use default`).

```bash
cd ~/tp3
```

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
docker run -d --name back -p 8081:8081 -v tp4-data:/data localhost:5000/tp/back:2.0.0
docker run -d --name front -p 4200:8080 localhost:5000/tp/front:2.0.0
```

Un fichier Compose a trois sections principales : `services` (les conteneurs), `networks` et `volumes`. Chaque option de `docker run` a son équivalent :

| `docker run` | `compose.yaml` |
| --- | --- |
| `--name back` | le nom du service : `back:` |
| `-p 8081:8081` | `ports: ["8081:8081"]` |
| `-v tp4-data:/data` | `volumes: ["back-data:/data"]`, plus une déclaration dans la section `volumes` |
| `-e VAR=valeur` | `environment: { VAR: valeur }` |
| image construite avec `docker build` | `build:` (contexte, arguments) et `image:` (nom et tag de l'image produite) |

**Ce que vous devez faire :**

- Créez `~/tp3/compose.yaml` qui décrit les services `back` et `front` :
  - le projet s'appelle `tp` (clé `name` en tête de fichier) ;
  - chaque service est construit à partir de son dossier, avec l'argument `APP_VERSION`, et produit l'image `tp/back` ou `tp/front`, taguée avec la variable `APP_VERSION` (valeur par défaut `dev`) ;
  - mêmes ports et même volume qu'au TP 4.
- Démarrez la pile en arrière-plan, listez ses services, puis suivez les logs du back jusqu'à son démarrage complet. Vérifiez l'application sur <http://localhost:4200>.
- Listez les conteneurs, réseaux et volumes créés avec les commandes `docker` habituelles. Comment sont-ils nommés ?
- Depuis le conteneur `front`, résolvez le nom `back`.
- Arrêtez la pile avec `docker compose down`. Que reste-t-il ?

**Questions de réflexion :**

- Vous n'avez déclaré aucun réseau. Comment les conteneurs peuvent-ils se joindre par leur nom ?
- Le navigateur appelle le back sur `localhost:8081`, pas sur `back:8081`. Pourquoi ?

{::nomarkdown}
<details><summary>Solution - Étape 1</summary>
{:/nomarkdown}

`compose.yaml` :

```yaml
name: tp

services:
  back:
    build:
      context: ./back
      args:
        APP_VERSION: ${APP_VERSION:-dev}
    image: tp/back:${APP_VERSION:-dev}
    ports:
      - "8081:8081"
    volumes:
      - back-data:/data

  front:
    build:
      context: ./front
      args:
        APP_VERSION: ${APP_VERSION:-dev}
    image: tp/front:${APP_VERSION:-dev}
    ports:
      - "4200:8080"

volumes:
  back-data:
```

```bash
docker compose up -d
docker compose ps
docker compose logs -f back         # Ctrl+C une fois « Started ... » affiché
```

Au premier `up`, Compose construit les images absentes avant de créer les conteneurs.

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
docker network ls --filter name=tp
docker volume ls --filter name=tp
docker compose exec front getent hosts back
```

Tout est préfixé par le nom du projet : conteneurs `tp-back-1` et `tp-front-1` (le suffixe numérote les répliques), réseau `tp_default`, volume `tp_back-data`. Sans clé `name`, le projet prendrait le nom du dossier.

Compose crée un réseau `tp_default` et y attache tous les services. Sur un réseau défini par l'utilisateur, Docker fournit un **DNS interne** : chaque service est joignable par son nom, qui se résout vers l'adresse IP de son conteneur. Ce n'est pas le cas sur le réseau `bridge` par défaut utilisé par `docker run`.

Le front est une application Angular exécutée **dans le navigateur**, sur votre poste. C'est votre poste qui appelle le back, et il ne connaît pas le DNS interne de Docker : il passe par le port publié sur `localhost`. Le nom `back` n'est utilisable que d'un conteneur à l'autre.

```bash
docker compose down
docker volume ls --filter name=tp
```

`down` supprime les conteneurs et le réseau, mais **conserve les volumes** et les images.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 2 - Ajouter PostgreSQL

L'image officielle `postgres` se configure par variables d'environnement : `POSTGRES_DB`, `POSTGRES_USER` et `POSTGRES_PASSWORD` créent la base et son propriétaire au premier démarrage. Les données sont stockées dans `/var/lib/postgresql/data`.

Le back est une application Spring Boot : toute propriété de configuration peut être remplacée par une variable d'environnement, en majuscules, avec `_` à la place des points (`spring.datasource.url` devient `SPRING_DATASOURCE_URL`).

**Ce que vous devez faire :**

- Ajoutez un service `db` basé sur `postgres:17-alpine` : base `app`, utilisateur `app`, mot de passe `app` (provisoire), données dans un volume nommé `db-data`.
- Ajoutez au service `db` un `healthcheck` qui utilise `pg_isready`.
- Configurez le back pour qu'il utilise PostgreSQL, avec les variables suivantes :

  | Variable | Valeur |
  | --- | --- |
  | `SPRING_DATASOURCE_URL` | `jdbc:postgresql://db:5432/app` |
  | `SPRING_DATASOURCE_USERNAME` | `app` |
  | `SPRING_DATASOURCE_PASSWORD` | `app` |
  | `SPRING_DATASOURCE_DRIVER_CLASS_NAME` | `org.postgresql.Driver` |
  | `SPRING_JPA_DATABASE_PLATFORM` | `org.hibernate.dialect.PostgreSQLDialect` |

- Faites démarrer le back **seulement quand la base est prête**. Retirez le volume `back-data`, devenu inutile.
- Démarrez la pile et observez l'ordre de démarrage dans `docker compose ps` et dans les logs.
- Créez des données dans l'application. Faites `down` puis `up -d` : les données sont-elles toujours là ? Et après `down -v` ?

**Questions de réflexion :**

- Quelle différence entre `depends_on: [db]` et `depends_on` avec `condition: service_healthy` ?
- Pourquoi n'a-t-il pas fallu reconstruire l'image du back pour changer de base de données ?

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
      POSTGRES_PASSWORD: app
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d app"]
      interval: 5s
      timeout: 3s
      retries: 10

  back:
    build:
      context: ./back
      args:
        APP_VERSION: ${APP_VERSION:-dev}
    image: tp/back:${APP_VERSION:-dev}
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/app
      SPRING_DATASOURCE_USERNAME: app
      SPRING_DATASOURCE_PASSWORD: app
      SPRING_DATASOURCE_DRIVER_CLASS_NAME: org.postgresql.Driver
      SPRING_JPA_DATABASE_PLATFORM: org.hibernate.dialect.PostgreSQLDialect
    ports:
      - "8081:8081"
    depends_on:
      db:
        condition: service_healthy

  front:
    build:
      context: ./front
      args:
        APP_VERSION: ${APP_VERSION:-dev}
    image: tp/front:${APP_VERSION:-dev}
    ports:
      - "4200:8080"

volumes:
  db-data:
```

```bash
docker compose up -d
docker compose ps                   # db : (healthy)
docker compose logs db back
```

`up` attend que `db` soit `healthy` avant de créer `back`. Le volume `tp_back-data` de l'étape 1 n'est plus utilisé : supprimez-le avec `docker volume rm tp_back-data`.

```bash
docker compose down && docker compose up -d     # données conservées
docker compose down -v && docker compose up -d  # base vide
```

`down -v` supprime aussi les volumes nommés déclarés dans le fichier : la base repart de zéro.

`depends_on: [db]` n'attend que le **démarrage du conteneur** `db`, pas celui de PostgreSQL, qui met quelques secondes à accepter des connexions. Le back démarrerait trop tôt, échouerait à se connecter et s'arrêterait. Avec `condition: service_healthy`, Compose attend que le `healthcheck` réussisse.

`pg_isready` vérifie que le serveur accepte les connexions. La forme `CMD-SHELL` exécute la commande dans un shell du conteneur ; la forme `CMD` l'exécuterait directement.

Le back n'a pas de `healthcheck` : son image distroless ne contient ni shell ni `curl` pour en écrire un. Pour un service qui dépend du back, on ajouterait un endpoint de santé et un petit binaire de test dans l'image, ou on laisserait l'orchestrateur sonder le port.

Les deux drivers sont dans l'image depuis le TP 3. Les variables d'environnement remplacent la configuration SQLite de `application.yml` au démarrage : même image, configuration différente. C'est le principe qui permet de promouvoir **la même image** du développement à la production.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 3 - Variables d'environnement et secrets

Compose propose trois mécanismes, souvent confondus :

| Mécanisme | Où | Effet |
| --- | --- | --- |
| Fichier `.env` à côté de `compose.yaml` | Lu par Compose | Fournit les valeurs des `${VARIABLE}` **écrites dans le fichier Compose**. N'injecte rien dans les conteneurs |
| `environment:` | Dans un service | Définit des variables **dans le conteneur** |
| `env_file:` | Dans un service | Injecte **dans le conteneur** toutes les variables d'un fichier |

**Ce que vous devez faire :**

- Le mot de passe `app` est écrit deux fois en clair dans un fichier versionné. Déplacez-le dans un fichier `.env`, avec `APP_VERSION=2.0.0`, et faites référence à `${POSTGRES_PASSWORD}` dans le fichier Compose. Faites échouer Compose avec un message clair si la variable n'est pas définie.
- Ajoutez `.env` au `.gitignore` et créez un `.env.example` versionné qui documente les variables attendues.
- Regroupez la configuration Spring du back dans un fichier `back.env`, chargé avec `env_file`. Ajoutez-y `LOGGING_LEVEL_ORG_HIBERNATE_SQL=INFO` pour réduire le bruit des logs.
- Affichez la configuration finale calculée par Compose avec `docker compose config`. Où voyez-vous le mot de passe ?
- Ajoutez une variable `TEST=visible` dans `.env`. Apparaît-elle dans le conteneur du back ?
- Renommez temporairement `.env`, lancez `docker compose config`, puis remettez-le en place.

**Questions de réflexion :**

- Pourquoi `docker compose config` doit-il être utilisé avec précaution dans un pipeline de CI ?
- Le mot de passe n'est plus dans le dépôt. Où est-il encore lisible ?

{::nomarkdown}
<details><summary>Solution - Étape 3</summary>
{:/nomarkdown}

`.env` (non versionné) :

```text
APP_VERSION=2.0.0
POSTGRES_PASSWORD=Ch4ng3-m0i
```

`.env.example` (versionné) :

```text
APP_VERSION=2.0.0
POSTGRES_PASSWORD=
```

`back.env` :

```text
SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/app
SPRING_DATASOURCE_USERNAME=app
SPRING_DATASOURCE_DRIVER_CLASS_NAME=org.postgresql.Driver
SPRING_JPA_DATABASE_PLATFORM=org.hibernate.dialect.PostgreSQLDialect
LOGGING_LEVEL_ORG_HIBERNATE_SQL=INFO
```

Services `db` et `back` :

```yaml
  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?Définissez POSTGRES_PASSWORD dans .env}
    # volumes et healthcheck inchangés

  back:
    # build, image, ports et depends_on inchangés
    env_file: back.env
    environment:
      SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD:?Définissez POSTGRES_PASSWORD dans .env}
```

```bash
echo ".env" >> .gitignore
docker compose config
docker compose down -v && docker compose up -d
docker compose exec db env | grep POSTGRES
```

Le mot de passe ayant changé, il faut recréer la base avec `down -v` : vous comprendrez pourquoi à l'étape 5.

`TEST=visible` n'apparaît dans aucun conteneur : `.env` ne sert qu'à la substitution des `${...}` du fichier Compose. Pour qu'une variable arrive dans un conteneur, il faut qu'un service la référence dans `environment` ou qu'elle soit dans un `env_file`.

`${VAR:?message}` fait échouer Compose avec le message si la variable est absente ou vide. `${VAR:-défaut}` fournit une valeur par défaut.

`docker compose config` affiche le fichier **avec les variables remplacées**, donc les secrets en clair. Dans un pipeline, sa sortie finit dans les logs de build, souvent lisibles par beaucoup de monde.

Le mot de passe reste lisible dans le fichier `.env` sur le poste, et dans la configuration des conteneurs : `docker inspect tp-back-1` l'affiche, comme vu au TP 2. Pour aller plus loin, Compose propose une section `secrets:` qui monte le secret en fichier dans `/run/secrets/`. L'image `postgres` le lit avec `POSTGRES_PASSWORD_FILE=/run/secrets/db_password`, et Spring Boot avec `spring.config.import=configtree:/run/secrets/`.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 4 - Isoler les services avec des réseaux

Pour l'instant, les trois services partagent le réseau `tp_default` : le front pourrait joindre la base directement. Seul le back en a besoin.

**Ce que vous devez faire :**

- Déclarez deux réseaux :
  - `backend`, **interne** (`internal: true`), pour la base et le back ;
  - `frontend`, pour le back et le front.
- Attachez chaque service aux seuls réseaux dont il a besoin.
- Relancez la pile. Depuis le conteneur `front`, essayez de résoudre `db` puis `back`. Depuis `db`, essayez de joindre Internet.
- Vérifiez que l'application fonctionne toujours depuis votre navigateur.
- Essayez de publier le port 5432 de la base sur `127.0.0.1` pour y connecter un client depuis votre poste. Que se passe-t-il ?

**Questions de réflexion :**

- Qu'apporte `internal: true` par rapport à un réseau classique ?
- Le back est publié sur le port 8081 alors qu'il est relié au réseau interne. Pourquoi cela fonctionne-t-il ?

{::nomarkdown}
<details><summary>Solution - Étape 4</summary>
{:/nomarkdown}

```yaml
services:
  db:
    # ...
    networks: [backend]

  back:
    # ...
    networks: [backend, frontend]

  front:
    # ...
    networks: [frontend]

networks:
  backend:
    internal: true
  frontend:
```

```bash
docker compose up -d
docker compose exec front getent hosts db       # aucun résultat
docker compose exec front getent hosts back     # une adresse IP
docker compose exec db wget -q -T 3 -O /dev/null https://example.com   # échec
```

Compose détecte le changement de configuration et recrée les conteneurs concernés. Le réseau `tp_default` n'est plus utilisé.

Le DNS interne ne répond que pour les services présents sur un réseau commun : le front ne voit même pas l'existence de `db`. Sur un réseau `internal`, les conteneurs ne peuvent pas non plus sortir vers l'extérieur : une base compromise ne peut ni télécharger d'outil ni exfiltrer de données.

Le back est aussi sur `frontend`, un réseau classique : c'est par lui que passe son port publié. À l'inverse, un service relié **uniquement** à un réseau interne ne peut pas publier de port : `ports: ["127.0.0.1:5432:5432"]` sur `db` n'a aucun effet tant qu'il n'est relié qu'à `backend`. Pour administrer la base depuis votre poste, on passe par `docker compose exec` (étape 6) ou par un outil placé sur les deux réseaux (étape 7).

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 5 - Volumes et montages : initialiser la base

L'image `postgres` exécute, **au premier démarrage uniquement**, les scripts `.sql` et `.sh` présents dans `/docker-entrypoint-initdb.d/`. On s'en sert pour préparer la base : rôles, extensions, schémas.

**Ce que vous devez faire :**

- Créez `~/tp3/db/init/01-lecteur.sql`, qui crée un rôle `lecteur` en lecture seule, capable de lire les tables que le back créera plus tard :

  ```sql
  CREATE ROLE lecteur LOGIN PASSWORD 'lecteur';
  GRANT CONNECT ON DATABASE app TO lecteur;
  GRANT USAGE ON SCHEMA public TO lecteur;
  ALTER DEFAULT PRIVILEGES FOR ROLE app IN SCHEMA public GRANT SELECT ON TABLES TO lecteur;
  ```

- Montez le dossier `db/init` dans `/docker-entrypoint-initdb.d`, en lecture seule.
- Relancez avec `docker compose up -d`. Le rôle `lecteur` existe-t-il ? Lisez les logs de `db`.
- Trouvez comment faire exécuter le script, puis vérifiez que `lecteur` peut lire les tables du back, mais pas y écrire.
- Changez `POSTGRES_PASSWORD` dans `.env` sans supprimer le volume, et relancez. Que devient le back ?

**Questions de réflexion :**

- Pourquoi le script ne s'est-il pas exécuté au premier essai ?
- Quel problème pose le mot de passe écrit dans `01-lecteur.sql` ?

{::nomarkdown}
<details><summary>Solution - Étape 5</summary>
{:/nomarkdown}

```yaml
  db:
    # ...
    volumes:
      - db-data:/var/lib/postgresql/data
      - ./db/init:/docker-entrypoint-initdb.d:ro
```

Les chemins relatifs d'un montage sont résolus par rapport au dossier du fichier Compose.

```bash
docker compose up -d
docker compose exec db psql -U app -d app -c '\du'    # pas de rôle lecteur
docker compose logs db | grep -i "skipping initialization"
```

Le volume `db-data` contient déjà une base : l'image ignore alors `/docker-entrypoint-initdb.d`, ainsi que `POSTGRES_USER` et `POSTGRES_PASSWORD`. Il faut repartir d'un volume vide :

```bash
docker compose down -v
docker compose up -d
docker compose logs db | grep 01-lecteur.sql
```

Après avoir créé des données dans l'application (le back crée les tables à son démarrage) :

```bash
docker compose exec db psql -U lecteur -d app -c '\dt'
docker compose exec db psql -U lecteur -d app -c 'SELECT count(*) FROM <une table listée>'
docker compose exec db psql -U lecteur -d app -c 'DELETE FROM <une table listée>'   # permission denied
```

Les connexions locales à l'intérieur du conteneur ne demandent pas de mot de passe (méthode `trust` sur le socket Unix, configurée par l'image). Les connexions réseau, comme celle du back, en exigent un.

Changer `POSTGRES_PASSWORD` sur une base existante ne change **pas** le mot de passe de l'utilisateur `app`, défini une fois pour toutes à l'initialisation. Le back, lui, reçoit le nouveau mot de passe : ses logs affichent `password authentication failed for user "app"`, et il s'arrête. Il faut changer le mot de passe dans la base (`ALTER ROLE app PASSWORD '...'`), ou repartir d'un volume vide en développement. Remettez l'ancien mot de passe avant de continuer.

Le mot de passe de `lecteur` est en clair dans un fichier versionné, comme le `admin123` du TP 3. Un script `.sh` d'initialisation pourrait le lire depuis une variable d'environnement ou un secret.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 6 - Exploiter la pile

**Ce que vous devez faire :**

- Listez les services et leur état, puis uniquement le nom des services.
- Affichez les 20 dernières lignes de logs de tous les services avec leur horodatage, puis suivez uniquement ceux du back.
- Ouvrez une session `psql` interactive dans le service `db` et listez les tables. Essayez d'ouvrir un shell dans le service `back`.
- Lancez un conteneur **ponctuel** basé sur le service `db` pour exécuter `psql` en se connectant au serveur `db` par le réseau, sans démarrer de second serveur PostgreSQL.
- Affichez les processus de chaque service, et le port de l'hôte associé au port 8081 du back.
- Arrêtez puis redémarrez uniquement le front. Redémarrez le back.
- Ajoutez `SPRING_JPA_SHOW_SQL=true` dans `back.env` et relancez `docker compose up -d`. Quels services sont recréés ?
- Modifiez un fichier Java du back, puis reconstruisez et relancez uniquement ce service en une commande.
- Essayez de lancer deux répliques du back avec `--scale back=2`. Lisez l'erreur.

**Questions de réflexion :**

- Quelle différence entre `docker compose exec` et `docker compose run` ?
- Pourquoi `docker compose up -d` ne recrée-t-il pas tous les conteneurs à chaque fois ?

{::nomarkdown}
<details><summary>Solution - Étape 6</summary>
{:/nomarkdown}

```bash
docker compose ps
docker compose ps --services
docker compose logs --tail 20 -t
docker compose logs -f back
```

```bash
docker compose exec db psql -U app -d app     # \dt pour lister, \q pour quitter
docker compose exec back sh                   # échec : image distroless
```

```bash
docker compose run --rm --no-deps -e PGPASSWORD="$(grep POSTGRES_PASSWORD .env | cut -d= -f2)" \
  db psql -h db -U app -d app -c 'SELECT now()'
```

`exec` lance un processus dans un conteneur **existant**. `run` crée un **nouveau** conteneur à partir de la définition du service (image, réseaux, volumes, variables), avec une autre commande : ici `psql` au lieu du serveur. `--rm` le supprime à la fin, `--no-deps` évite de démarrer les dépendances. Ce conteneur ponctuel monte aussi le volume `db-data`, mais `psql` n'y touche pas.

```bash
docker compose top
docker compose port back 8081
docker compose stop front && docker compose start front
docker compose restart back
```

```bash
docker compose up -d                # seul back est recréé
docker compose up -d --build back   # reconstruit l'image puis recrée le service
```

Compose calcule une empreinte de la configuration de chaque service et la compare à celle des conteneurs existants. Seuls les services dont la configuration (ou l'image) a changé sont recréés ; les autres restent `Running`. `restart` ne relit pas la configuration : pour appliquer une modification de `back.env`, il faut `up -d`.

`--scale back=2` échoue : les deux répliques veulent publier le port 8081 de l'hôte, déjà pris par la première. Pour monter en charge, on retire la publication du port fixe et on place un répartiteur de charge devant les répliques, ou on passe à un orchestrateur comme Kubernetes.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 7 - Profils : des outils à la demande

Certains services ne servent qu'occasionnellement : outils d'administration, jeux de données de test, outils de débogage. Un **profil** les exclut du démarrage par défaut.

**Ce que vous devez faire :**

- Ajoutez un service `adminer` (image `adminer:4` de Docker Hub, une interface web d'administration de bases de données) :
  - dans le profil `tools` ;
  - publié sur le port 8082 de l'hôte, **uniquement en local** ;
  - avec `db` comme serveur par défaut (variable `ADMINER_DEFAULT_SERVER`) ;
  - relié aux réseaux nécessaires pour joindre la base et être publié.
- Lancez `docker compose up -d` : `adminer` démarre-t-il ? Démarrez-le avec son profil.
- Connectez-vous sur <http://127.0.0.1:8082> (système PostgreSQL, utilisateur `lecteur`) et parcourez les tables.
- Arrêtez la pile avec `docker compose down`, sans préciser de profil. Que devient `adminer` ?

**Question de réflexion :**

- Pourquoi `adminer` doit-il être relié à deux réseaux ?

{::nomarkdown}
<details><summary>Solution - Étape 7</summary>
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
docker compose up -d                       # adminer ignoré
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

## Étape 8 - Ménage

**Ce que vous devez faire :**

- Arrêtez et supprimez toute la pile, profils compris, avec ses volumes.
- Supprimez les images construites par Compose.
- Vérifiez qu'il ne reste ni conteneur, ni réseau, ni volume du projet `tp`.

{::nomarkdown}
<details><summary>Solution - Étape 8</summary>
{:/nomarkdown}

```bash
docker compose --profile tools down -v --rmi all
docker ps -a --filter name=tp-
docker network ls --filter name=tp_
docker volume ls --filter name=tp_
```

`--rmi local` ne supprime que les images **sans nom personnalisé**. Les images du back et du front ont un nom défini par `image:` (`tp/back:2.0.0`) : il faut `--rmi all`, qui supprime aussi les images téléchargées (`postgres`, `adminer`).

> **Pour aller plus loin.**
>
> - `compose.override.yaml` est fusionné automatiquement avec `compose.yaml` : on y place les réglages de développement (ports de débogage, outils) sans toucher au fichier principal. `-f` permet de combiner explicitement plusieurs fichiers, par exemple `-f compose.yaml -f compose.prod.yaml`.
> - `docker compose watch` surveille les sources et resynchronise ou reconstruit les services à chaque modification, selon une section `develop.watch` du fichier Compose.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Fichier final

```yaml
name: tp

services:
  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?Définissez POSTGRES_PASSWORD dans .env}
    volumes:
      - db-data:/var/lib/postgresql/data
      - ./db/init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d app"]
      interval: 5s
      timeout: 3s
      retries: 10
    networks: [backend]

  back:
    build:
      context: ./back
      args:
        APP_VERSION: ${APP_VERSION:-dev}
    image: tp/back:${APP_VERSION:-dev}
    env_file: back.env
    environment:
      SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD:?Définissez POSTGRES_PASSWORD dans .env}
    ports:
      - "8081:8081"
    depends_on:
      db:
        condition: service_healthy
    networks: [backend, frontend]

  front:
    build:
      context: ./front
      args:
        APP_VERSION: ${APP_VERSION:-dev}
    image: tp/front:${APP_VERSION:-dev}
    ports:
      - "4200:8080"
    networks: [frontend]

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

networks:
  backend:
    internal: true
  frontend:

volumes:
  db-data:
```

## Récapitulatif des commandes

| Commande | Rôle |
| --- | --- |
| `docker compose up -d` | Construire si besoin, créer et démarrer la pile en arrière-plan |
| `docker compose up -d --build <service>` | Reconstruire l'image d'un service et le recréer |
| `docker compose down [-v] [--rmi all]` | Supprimer conteneurs et réseaux (et volumes, et images) |
| `docker compose ps [--services]` | Lister les services et leur état |
| `docker compose logs [-f] [--tail N] [-t] [service]` | Lire les logs |
| `docker compose exec <service> <cmd>` | Exécuter une commande dans un conteneur existant |
| `docker compose run --rm <service> <cmd>` | Lancer un conteneur ponctuel à partir d'un service |
| `docker compose stop` / `start` / `restart <service>` | Piloter un service sans le recréer |
| `docker compose top` / `port` | Processus d'un service, port publié |
| `docker compose config` | Afficher la configuration calculée (attention aux secrets) |
| `docker compose build` / `pull` | Construire ou télécharger les images |
| `docker compose --profile <nom> ...` | Inclure les services d'un profil |

{% endraw %}
