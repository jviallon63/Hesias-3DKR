---
title: "TP 6 - Registre privé et sécurité des images"
objective: "Héberger un registre privé authentifié, y publier des images avec et sans gestion de version, détecter vulnérabilités, secrets et mauvaises configurations avec Trivy, corriger les images et durcir leur exécution."
---

{% raw %}

# Contexte

Vos images sont prêtes. Pour être déployées, elles doivent être publiées dans un **registre** accessible aux serveurs, et elles doivent être **sûres** : une image embarque un système, des bibliothèques et parfois, par erreur, des secrets. Chacun de ces éléments peut contenir des vulnérabilités connues, publiées sous forme de **CVE** (*Common Vulnerabilities and Exposures*).

Dans ce TP, vous allez :

- héberger votre propre registre, protégé par mot de passe ;
- constater ce qui se passe quand on publie sans gérer les versions, puis avec ;
- scanner une image volontairement vulnérable avec **Trivy**, la corriger, et appliquer la même démarche aux images de l'application ;
- durcir l'exécution des conteneurs.

**Prérequis :**

- TP 5 terminé : le dépôt est dans `~/tp3`, avec `compose.yaml` et `.env`.
- Le port 5000 de votre machine est libre. Sur macOS, le récepteur AirPlay l'occupe : désactivez-le (Réglages système, Général, AirDrop et Handoff) ou utilisez un autre port partout dans ce TP.

```bash
mkdir -p ~/tp6 && cd ~/tp6
```

> Les commandes sont écrites pour un shell bash ou zsh (Linux, macOS, WSL). Sous PowerShell, remplacez `$PWD` par `${PWD}` et `curl` par `curl.exe`.

---

## Objectifs

<div class="section objective">

1. Déployer un registre privé avec authentification
2. Publier et récupérer des images avec `docker login`, `push` et `pull`
3. Mesurer les conséquences d'une publication sans gestion de version
4. Détecter vulnérabilités, secrets et mauvaises configurations avec Trivy
5. Corriger une image et bloquer les images vulnérables avant publication
6. Durcir l'exécution d'un conteneur

</div>

---

## Étape 1 - Un registre privé

Un registre est un serveur HTTP qui stocke des manifestes et des couches, et expose une API standardisée (la *Distribution Specification* de l'OCI). `registry:3` en est l'implémentation de référence, maintenue par le projet CNCF Distribution.

**Ce que vous devez faire :**

- Générez un fichier `~/tp6/registry/auth/htpasswd` contenant un utilisateur `etudiant` avec le mot de passe `Tp6-Registre`, haché avec bcrypt. L'image `registry` ne fournit pas l'outil `htpasswd` : utilisez celui de l'image `httpd:2`.
- Écrivez `~/tp6/registry/compose.yaml` pour un service `registry` basé sur `registry:3` :
  - port 5000 publié ;
  - images stockées dans un volume nommé, monté sur `/var/lib/registry` ;
  - authentification `htpasswd` activée par les variables `REGISTRY_AUTH`, `REGISTRY_AUTH_HTPASSWD_REALM` et `REGISTRY_AUTH_HTPASSWD_PATH`, avec le dossier `auth` monté en lecture seule.
- Démarrez le registre. Interrogez son API sans identifiants, puis avec : `GET /v2/` et `GET /v2/_catalog`.

**Questions de réflexion :**

- Le mot de passe apparaît en clair dans la commande de génération. Où risque-t-il d'être conservé ?
- Pourquoi l'algorithme bcrypt (`-B`) plutôt qu'un simple hachage ?

{::nomarkdown}
<details><summary>Solution - Étape 1</summary>
{:/nomarkdown}

```bash
mkdir -p ~/tp6/registry/auth && cd ~/tp6/registry
docker run --rm --entrypoint htpasswd httpd:2 -Bbn etudiant Tp6-Registre > auth/htpasswd
cat auth/htpasswd       # etudiant:$2y$05$...
```

`compose.yaml` :

```yaml
services:
  registry:
    image: registry:3
    ports:
      - "5000:5000"
    environment:
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: "Registre TP6"
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd
    volumes:
      - registry-data:/var/lib/registry
      - ./auth:/auth:ro

volumes:
  registry-data:
```

```bash
docker compose up -d
curl -i http://localhost:5000/v2/                                   # 401 Unauthorized
curl -u etudiant:Tp6-Registre http://localhost:5000/v2/             # {}
curl -u etudiant:Tp6-Registre http://localhost:5000/v2/_catalog     # {"repositories":[]}
cd ~/tp6
```

La réponse `401` contient un en-tête `WWW-Authenticate: Basic realm="Registre TP6"` : c'est lui qui indique au client Docker comment s'authentifier.

Un mot de passe passé en argument reste dans l'historique du shell (`~/.zsh_history`, `~/.bash_history`) et est visible par les autres utilisateurs de la machine dans la liste des processus pendant l'exécution. En dehors d'un TP, on le saisit de façon interactive (`htpasswd -B` sans `-b`) ou on le lit depuis un fichier.

bcrypt est volontairement **lent** et salé : même si le fichier `htpasswd` fuite, retrouver les mots de passe par force brute coûte très cher. Un hachage rapide comme MD5 ou SHA-1 se casse en quelques secondes pour un mot de passe courant.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 2 - `docker login`, `push` et `pull`

Le nom d'une image indique **où** la pousser : `localhost:5000/site:1.0.0` désigne le dépôt `site` du registre `localhost:5000`. Sans registre dans le nom, c'est Docker Hub.

**Ce que vous devez faire :**

- Créez une petite image de démonstration dans `~/tp6/site` : un `index.html` contenant `<h1>Version 1</h1>`, servi par `nginxinc/nginx-unprivileged:stable-alpine`. Construisez-la sous le nom `localhost:5000/site:latest`.
- Poussez-la **sans** vous être authentifié. Lisez l'erreur.
- Authentifiez-vous auprès du registre sans taper le mot de passe dans la commande, puis poussez à nouveau.
- Trouvez où Docker a enregistré vos identifiants. Sont-ils chiffrés ?
- Simulez un autre serveur : supprimez l'image locale, puis récupérez-la depuis le registre. Vérifiez le catalogue du registre.
- Essayez de récupérer l'image en utilisant l'**adresse IP** de votre machine au lieu de `localhost`. Lisez l'erreur.

**Questions de réflexion :**

- Pourquoi Docker accepte-t-il de parler en HTTP à `localhost:5000`, mais pas à `<votre IP>:5000` ?
- Comment rendre ce registre utilisable par d'autres machines de façon sûre ?

{::nomarkdown}
<details><summary>Solution - Étape 2</summary>
{:/nomarkdown}

```bash
mkdir -p ~/tp6/site
echo '<h1>Version 1</h1>' > site/index.html
cat > site/Dockerfile <<'EOF'
FROM nginxinc/nginx-unprivileged:stable-alpine
COPY index.html /usr/share/nginx/html/index.html
EOF

docker build -t localhost:5000/site:latest site/
docker push localhost:5000/site:latest     # no basic auth credentials
```

```bash
docker login localhost:5000 -u etudiant     # mot de passe demandé
docker push localhost:5000/site:latest
```

Dans un script, on fournit le mot de passe par l'entrée standard : `echo "$REGISTRY_PASSWORD" | docker login localhost:5000 -u etudiant --password-stdin`.

```bash
cat ~/.docker/config.json
```

Deux cas :

- un champ `credsStore` (`desktop`, `osxkeychain`, `wincred`, `pass`...) : les identifiants sont confiés au gestionnaire de secrets du système ;
- un bloc `auths` avec un champ `auth` : ce n'est que `utilisateur:motdepasse` encodé en **base64**, donc en clair (`echo '<valeur>' | base64 -d`). Toute personne qui lit ce fichier obtient l'accès au registre.

```bash
docker rmi localhost:5000/site:latest
docker pull localhost:5000/site:latest
curl -u etudiant:Tp6-Registre http://localhost:5000/v2/_catalog     # {"repositories":["site"]}
```

```bash
IP=$(ipconfig getifaddr en0 2>/dev/null || hostname -I | awk '{print $1}')
docker pull "$IP:5000/site:latest"
# http: server gave HTTP response to HTTPS client
```

Docker exige HTTPS pour tout registre, **sauf** pour les adresses de bouclage (`localhost`, `127.0.0.0/8`). Le registre ne parle qu'HTTP : l'accès par l'IP échoue.

Pour d'autres machines, il faut servir le registre en **HTTPS**, avec un certificat signé par une autorité reconnue (ou interne à l'entreprise et installée sur les clients), soit directement (`REGISTRY_HTTP_TLS_CERTIFICATE` et `REGISTRY_HTTP_TLS_KEY`), soit derrière un reverse proxy. L'option `insecure-registries` de la configuration du daemon permet de forcer HTTP, mais elle expose mots de passe et images à quiconque écoute le réseau : à réserver à un labo isolé.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 3 - Publier sans gérer la version

**Ce que vous devez faire :**

- Lancez un conteneur `prod` à partir de `localhost:5000/site:latest`, publié sur le port 8090. C'est votre « production ».
- Relevez le digest de l'image publiée.
- Modifiez `index.html` en `<h1>Version 2 (buguée)</h1>`, reconstruisez sous le même nom `latest` et poussez.
- Listez les tags du dépôt `site` dans le registre, et relevez le nouveau digest.
- Quelle version sert le conteneur `prod` ? Recréez-le comme le ferait un redémarrage de serveur : quelle version sert-il maintenant ?
- La version 2 est buguée. Revenez à la version 1 **en n'utilisant que le registre**.

**Questions de réflexion :**

- Deux serveurs démarrés à une heure d'intervalle exécutent-ils forcément la même version ?
- Qu'est-ce qui vous aurait permis de revenir à la version 1 ?

{::nomarkdown}
<details><summary>Solution - Étape 3</summary>
{:/nomarkdown}

```bash
docker run -d --name prod -p 8090:8080 localhost:5000/site:latest
curl http://localhost:8090                                         # Version 1
docker image inspect -f '{{index .RepoDigests 0}}' localhost:5000/site:latest
```

```bash
echo '<h1>Version 2 (buguée)</h1>' > site/index.html
docker build -t localhost:5000/site:latest site/
docker push localhost:5000/site:latest
curl -u etudiant:Tp6-Registre http://localhost:5000/v2/site/tags/list    # {"name":"site","tags":["latest"]}
docker image inspect -f '{{index .RepoDigests 0}}' localhost:5000/site:latest
```

Le tag `latest` pointe désormais vers un autre digest. Le registre ne connaît qu'**un seul** tag : la version 1 n'a plus de nom. Localement, l'ancienne image apparaît comme `<none>` dans `docker images`.

```bash
curl http://localhost:8090                                         # toujours Version 1
docker rm -f prod
docker run -d --name prod -p 8090:8080 localhost:5000/site:latest
curl http://localhost:8090                                         # Version 2 (buguée)
```

Le conteneur `prod` utilisait l'image présente au moment de sa création. Recréé (redémarrage de serveur, nouvelle machine, mise à l'échelle), il prend ce que `latest` désigne **à cet instant**. Deux serveurs peuvent donc exécuter deux versions différentes avec la même configuration, sans que rien ne l'indique.

Revenir à la version 1 est impossible par un nom : seul quelqu'un qui aurait noté le digest pourrait lancer `localhost:5000/site@sha256:<digest v1>`, tant que le registre n'a pas supprimé les données orphelines lors d'un nettoyage. Il aurait fallu un **tag de version** pour chaque publication.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 4 - Publier en gérant la version

On reprend le schéma du TP 4 : un tag immuable par version (`1.0.0`), des tags mobiles (`1.0`, `1`, `latest`) déplacés à chaque publication.

**Ce que vous devez faire :**

- Remettez `<h1>Version 1</h1>` dans `index.html`. Construisez l'image avec les tags `1.0.0`, `1.0`, `1` et `latest`, et poussez **tous** les tags du dépôt en une commande.
- Publiez une version `1.0.1` (`<h1>Version 1.0.1</h1>`) en déplaçant les tags mobiles. Listez les tags du registre.
- Déployez `prod` en `1.0.1`. Revenez en `1.0.0`.
- Lancez `prod` en désignant l'image par son **digest** plutôt que par un tag.
- Modifiez `index.html`, reconstruisez sous le tag `1.0.0` **existant**, et poussez. Le registre l'accepte-t-il ?

**Questions de réflexion :**

- Quel tag mettre dans un fichier de déploiement de production ? Et dans un environnement de développement ?
- Comment empêcher l'écrasement d'un tag de version ?

{::nomarkdown}
<details><summary>Solution - Étape 4</summary>
{:/nomarkdown}

```bash
R=localhost:5000/site

echo '<h1>Version 1</h1>' > site/index.html
docker build -t $R:1.0.0 -t $R:1.0 -t $R:1 -t $R:latest site/
docker push --all-tags $R

echo '<h1>Version 1.0.1</h1>' > site/index.html
docker build -t $R:1.0.1 -t $R:1.0 -t $R:1 -t $R:latest site/
docker push --all-tags $R

curl -u etudiant:Tp6-Registre http://localhost:5000/v2/site/tags/list
# {"name":"site","tags":["1","1.0","1.0.0","1.0.1","latest"]}
```

```bash
docker rm -f prod && docker run -d --name prod -p 8090:8080 $R:1.0.1
docker rm -f prod && docker run -d --name prod -p 8090:8080 $R:1.0.0     # retour arrière
curl http://localhost:8090                                                 # Version 1
```

```bash
DIGEST=$(docker image inspect -f '{{index .RepoDigests 0}}' $R:1.0.1)
echo "$DIGEST"                      # localhost:5000/site@sha256:...
docker rm -f prod && docker run -d --name prod -p 8090:8080 "$DIGEST"
```

Un digest est l'empreinte du contenu : il désigne toujours exactement la même image, quoi qu'il arrive aux tags.

```bash
echo '<h1>Version 1.0.0 modifiée en douce</h1>' > site/index.html
docker build -t $R:1.0.0 site/
docker push $R:1.0.0                # accepté
```

`registry:3` accepte l'écrasement : un tag n'est qu'un pointeur, et rien ne l'empêche de bouger. Les registres d'entreprise (Harbor, JFrog Artifactory, GitLab, Amazon ECR, Azure ACR...) proposent des **tags immuables** : une fois `1.0.0` publié, toute nouvelle publication sous ce tag est refusée.

En production : une version complète (`1.0.1`), ou mieux un digest, éventuellement accompagné du tag pour la lisibilité (`site:1.0.1@sha256:...`). En développement, un tag mobile (`1.0`, `latest`) est acceptable pour toujours récupérer la dernière version.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 5 - Scanner une image vulnérable avec Trivy

**Trivy** est un scanner open source. Il compare les paquets du système et les bibliothèques applicatives d'une image à des bases de vulnérabilités, et cherche aussi des secrets et des erreurs de configuration.

Pas besoin de l'installer : on l'exécute dans un conteneur, avec le socket Docker pour accéder à vos images locales et un volume pour conserver sa base de vulnérabilités. Définissez cette fonction dans votre terminal, en remplaçant la version par la dernière publiée sur <https://github.com/aquasecurity/trivy/releases> :

```bash
TRIVY_VERSION=0.XX.X
trivy() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v trivy-cache:/root/.cache \
    -v "$PWD":/work -w /work \
    "aquasec/trivy:$TRIVY_VERSION" "$@"
}
```

> Épinglez toujours la version d'un outil de sécurité. Il a accès à vos images et à votre socket Docker : il est lui-même une cible de choix pour une attaque de la chaîne d'approvisionnement.

Voici l'image d'une « vitrine » écrite à la hâte. Créez-la dans `~/tp6/vitrine` :

```bash
mkdir -p ~/tp6/vitrine && cd ~/tp6/vitrine
echo '<h1>Vitrine</h1>' > index.html
ssh-keygen -t ed25519 -N '' -q -f id_ed25519     # « clé de déploiement » oubliée là
cat > Dockerfile <<'EOF'
FROM nginx:1.20
COPY id_ed25519 /root/.ssh/id_ed25519
COPY index.html /usr/share/nginx/html/index.html
EOF
docker build -t localhost:5000/vitrine:1.0.0 .
cd ~/tp6
```

**Ce que vous devez faire :**

- Scannez l'image `localhost:5000/vitrine:1.0.0`. Le premier lancement télécharge la base de vulnérabilités.
- Relevez le nombre de vulnérabilités par sévérité, et lisez une ligne du rapport : bibliothèque, CVE, version installée, version corrigée.
- Affichez uniquement les vulnérabilités critiques.
- Trouvez dans le rapport la section consacrée aux **secrets**.
- Analysez le `Dockerfile` lui-même avec `trivy config`.

**Questions de réflexion :**

- Ces vulnérabilités sont-elles dans votre code ? D'où viennent-elles ?
- Une CVE sans « version corrigée » : que peut-on faire ?
- La clé privée a fuité dans l'image. Suffit-il de la retirer du Dockerfile ?

{::nomarkdown}
<details><summary>Solution - Étape 5</summary>
{:/nomarkdown}

```bash
trivy image localhost:5000/vitrine:1.0.0
trivy image --severity CRITICAL localhost:5000/vitrine:1.0.0
trivy config vitrine/
```

Le rapport se découpe en sections :

- les **paquets du système** (`debian 11.x`) : plusieurs centaines de vulnérabilités, dont des critiques, dans `openssl`, `libc`, `curl`, `zlib`... La ligne `Total:` donne le décompte par sévérité. Trivy peut aussi signaler que cette version de Debian n'est plus maintenue ;
- les **secrets** : `/root/.ssh/id_ed25519`, détecté comme clé privée (`AsymmetricPrivateKey`), avec la couche qui l'a ajoutée.

Chaque ligne indique la bibliothèque, l'identifiant CVE, la sévérité, la version installée, la **version corrigée** quand elle existe, et un lien vers la description.

`trivy config` analyse le Dockerfile sans le construire. Il signale notamment l'absence d'instruction `USER` (le conteneur tourne en root) et l'absence de `HEALTHCHECK`.

Aucune de ces vulnérabilités n'est dans votre code : elles viennent de l'**image de base**, `nginx:1.20`, publiée en 2021 et plus jamais mise à jour. Une image ne se corrige pas toute seule : figée au moment de sa construction, elle accumule les CVE découvertes depuis.

Sans version corrigée, on peut : vérifier si la vulnérabilité est réellement exploitable dans votre contexte (composant non utilisé, fonction non appelée), changer d'image de base ou de bibliothèque, réduire la surface (image minimale), ou accepter le risque **de façon documentée** en attendant le correctif.

Retirer la clé du Dockerfile ne suffit pas : elle reste dans l'image `1.0.0`, dans toutes ses copies et dans tous les registres où elle a été poussée. Une clé qui a fuité est **compromise** : il faut la révoquer et en générer une nouvelle. Et elle n'avait rien à faire dans le contexte de build : un `.dockerignore` excluant `id_*`, `*.pem` ou `.ssh` l'aurait arrêtée.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 6 - Corriger, bloquer, publier

**Ce que vous devez faire :**

- Corrigez la vitrine :
  - image de base maintenue, minimale et non root : `nginxinc/nginx-unprivileged:stable-alpine` ;
  - plus de clé (supprimez le fichier et ajoutez un `.dockerignore`) ;
  - instruction `USER` explicite et `HEALTHCHECK`.
- Construisez `localhost:5000/vitrine:1.0.1`, scannez-la, et relancez `trivy config`.
- Écrivez la commande qui servirait de **seuil bloquant** dans un pipeline de CI : elle doit échouer (code de sortie non nul) s'il reste une vulnérabilité `HIGH` ou `CRITICAL` **pour laquelle un correctif existe**. Testez-la sur `1.0.0` et `1.0.1`.
- Une vulnérabilité est jugée non exploitable dans votre contexte : excluez-la du seuil avec un fichier `.trivyignore`.
- Poussez `1.0.1` dans le registre **seulement si** le seuil est franchi, en une seule ligne de commande.

**Questions de réflexion :**

- Pourquoi ignorer les vulnérabilités sans correctif dans un seuil bloquant ?
- L'image `1.0.1` est saine aujourd'hui. Le sera-t-elle dans trois mois ?

{::nomarkdown}
<details><summary>Solution - Étape 6</summary>
{:/nomarkdown}

```bash
cd ~/tp6/vitrine
rm -f id_ed25519 id_ed25519.pub
printf 'id_*\n*.pem\n.ssh\n.git\n' > .dockerignore
cat > Dockerfile <<'EOF'
FROM nginxinc/nginx-unprivileged:stable-alpine
COPY index.html /usr/share/nginx/html/index.html
USER 101
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1
EOF
docker build -t localhost:5000/vitrine:1.0.1 .
cd ~/tp6

trivy image localhost:5000/vitrine:1.0.1
trivy config vitrine/
```

Le nombre de vulnérabilités chute : Alpine contient très peu de paquets, tous à jour. Le secret a disparu, et `trivy config` ne signale plus l'utilisateur root ni l'absence de `HEALTHCHECK`. L'image de base définit déjà l'utilisateur 101, mais le rendre explicite documente l'intention et satisfait les analyses statiques.

Seuil bloquant :

```bash
trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed localhost:5000/vitrine:1.0.0; echo "code: $?"   # 1
trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed localhost:5000/vitrine:1.0.1; echo "code: $?"   # 0 en général
```

`.trivyignore`, dans le dossier courant (monté dans `/work`, où Trivy le cherche par défaut) :

```text
# CVE-AAAA-NNNNN : fonction vulnérable non utilisée par nginx, revue le 2026-10-04 par <nom>, à réexaminer au 2027-01-04
CVE-AAAA-NNNNN
```

Chaque exclusion doit être justifiée, datée, attribuée et revue : sinon le fichier devient le moyen de faire taire le scanner.

```bash
trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed localhost:5000/vitrine:1.0.1 \
  && docker push localhost:5000/vitrine:1.0.1
```

Une vulnérabilité sans correctif bloquerait toutes les publications sans que l'équipe puisse rien y faire. On la suit (rapport complet, revue régulière) sans en faire un critère bloquant.

L'image `1.0.1` ne changera pas, mais de nouvelles CVE seront publiées sur ses paquets : elle sera vulnérable dans trois mois. Il faut **rescanner régulièrement** les images publiées (Harbor et la plupart des registres d'entreprise intègrent Trivy pour cela), et **reconstruire régulièrement** avec `--pull` pour récupérer les correctifs de l'image de base, même sans modification du code.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 7 - Scanner et corriger les images de l'application

**Ce que vous devez faire :**

- Reconstruisez les images de l'application du TP 5 en version `2.0.0` (`docker compose build` dans `~/tp3`, avec `APP_VERSION=2.0.0` dans `.env`).
- Scannez `tp/back:2.0.0` et `tp/front:2.0.0`. Dans quelles sections se trouvent les vulnérabilités du back ? Quelles bibliothèques sont concernées ?
- Corrigez le back : mettez à jour la version de Spring Boot dans `back/pom.xml` vers la dernière version corrective disponible (`spring-boot-starter-parent`), puis reconstruisez les deux images en version `2.0.1` en forçant la récupération des images de base à jour.
- Rescannez, appliquez le seuil bloquant de l'étape 6, et publiez les deux images en `2.0.1` dans votre registre (`localhost:5000/tp/back` et `localhost:5000/tp/front`), avec les tags mobiles.
- Générez l'inventaire logiciel (SBOM) du back au format CycloneDX, puis scannez ce fichier au lieu de l'image.

**Questions de réflexion :**

- La mise à jour de Spring Boot justifie-t-elle une version `2.0.1`, `2.1.0` ou `3.0.0` ?
- À quoi sert un SBOM, si l'on peut scanner l'image directement ?

{::nomarkdown}
<details><summary>Solution - Étape 7</summary>
{:/nomarkdown}

```bash
cd ~/tp3
docker compose build
cd ~/tp6
trivy image tp/back:2.0.0
trivy image tp/front:2.0.0
```

Pour le back, la section des paquets système (`debian 12`, image distroless) est presque vide. L'essentiel est dans la section **Java** : Trivy a trouvé les jars de `BOOT-INF/lib` et signale des CVE dans les dépendances apportées par Spring Boot (`tomcat-embed-core`, `spring-web`, `spring-security`, `jackson`...). Le front, sur Alpine, en a très peu.

Ces vulnérabilités viennent de la version de Spring Boot figée dans `pom.xml`. Après mise à jour du parent :

```bash
cd ~/tp3
sed -i.bak 's/^APP_VERSION=.*/APP_VERSION=2.0.1/' .env
docker compose build --pull
cd ~/tp6

for app in back front; do
  trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed tp/$app:2.0.1 || echo "$app bloqué"
done
```

Si la nouvelle version de Spring Boot signale l'extraction `layertools` comme obsolète, utilisez la commande indiquée au TP 4 (`-Djarmode=tools ... extract --layers --launcher`).

```bash
for app in back front; do
  for tag in 2.0.1 2.0 2 latest; do
    docker tag tp/$app:2.0.1 localhost:5000/tp/$app:$tag
  done
  docker push --all-tags localhost:5000/tp/$app
done
curl -u etudiant:Tp6-Registre http://localhost:5000/v2/_catalog
```

Mettre à jour une dépendance sans changer le comportement ni l'interface de l'application est un **correctif** : `2.0.1`. On réserve `2.1.0` aux nouvelles fonctionnalités compatibles, `3.0.0` aux ruptures.

```bash
trivy image --format cyclonedx --output back-2.0.1.cdx.json tp/back:2.0.1
trivy sbom back-2.0.1.cdx.json
```

Le SBOM (*Software Bill of Materials*) est l'inventaire de tout ce que contient l'image : paquets, bibliothèques, versions, licences. On le génère une fois, au build, et on le publie avec l'image. Quand une nouvelle vulnérabilité est annoncée, on interroge les SBOM de toutes les images en production pour savoir lesquelles sont touchées, sans avoir à les télécharger ni les rescanner. Les réglementations (Cyber Resilience Act européen, exigences fédérales américaines) le rendent progressivement obligatoire.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 8 - Durcir l'exécution

Une image saine peut encore être exécutée avec trop de privilèges. Docker offre plusieurs protections, désactivées par défaut :

| Option | Effet |
| --- | --- |
| `--read-only` | Système de fichiers du conteneur en lecture seule |
| `--tmpfs /tmp` | Dossier temporaire en mémoire, inscriptible, pour compenser `--read-only` |
| `--cap-drop ALL` | Retire toutes les *capabilities* Linux (fragments des privilèges de root) |
| `--security-opt no-new-privileges:true` | Interdit de gagner des privilèges (binaires setuid, `sudo`...) |
| `--user` | Force un utilisateur, si l'image n'en définit pas |

**Ce que vous devez faire :**

- Lancez `localhost:5000/vitrine:1.0.1` sous le nom `durci`, publié sur le port 8091, avec toutes les protections du tableau. Vérifiez que le site répond.
- Essayez d'écrire un fichier dans `/usr/share/nginx/html` depuis le conteneur.
- Comparez l'ensemble limite des *capabilities* du processus principal (ligne `CapBnd` de `/proc/1/status`) entre `durci` et un conteneur lancé sans option.
- Traduisez ces protections dans le service `front` du `compose.yaml` du TP 5.
- Lancez un conteneur `docker:cli` qui monte le socket Docker, et listez depuis ce conteneur les conteneurs de votre machine.

**Questions de réflexion :**

- Pourquoi `--read-only` est-il efficace contre un attaquant qui aurait pris le contrôle de l'application ?
- Vous avez monté le socket Docker dans le conteneur Trivy et dans `docker:cli`. Qu'est-ce que cela implique ?

{::nomarkdown}
<details><summary>Solution - Étape 8</summary>
{:/nomarkdown}

```bash
docker run -d --name durci -p 8091:8080 \
  --read-only --tmpfs /tmp \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  localhost:5000/vitrine:1.0.1

curl http://localhost:8091
docker exec durci touch /usr/share/nginx/html/pirate      # Read-only file system

docker exec durci grep CapBnd /proc/1/status                                          # 0000000000000000
docker run --rm localhost:5000/vitrine:1.0.1 grep CapBnd /proc/1/status               # valeur non nulle
```

`CapBnd` est l'ensemble maximal de *capabilities* qu'un processus du conteneur pourra jamais obtenir. L'image tournant déjà avec un utilisateur non root, ses *capabilities* effectives (`CapEff`) sont vides dans les deux cas ; `--cap-drop ALL` retire en plus toute possibilité d'en récupérer, par exemple via un binaire setuid.

`nginx-unprivileged` écrit son PID et ses fichiers temporaires dans `/tmp` : le `tmpfs` suffit. Écoutant sur le port 8080, il n'a besoin d'aucune *capability*. Certaines applications en exigent une ou deux (`NET_BIND_SERVICE` pour un port inférieur à 1024) : on les rajoute une à une avec `--cap-add`.

Dans `compose.yaml` :

```yaml
  front:
    # ...
    read_only: true
    tmpfs:
      - /tmp
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
```

Avec `--read-only`, un attaquant qui exécute du code dans le conteneur ne peut ni déposer d'outil, ni modifier l'application (page défigurée, script malveillant injecté), ni persister. Il ne peut écrire que dans `/tmp`, en mémoire, effacé au redémarrage.

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock docker:cli docker ps
```

Le conteneur voit et pilote **tous** les conteneurs de la machine. Accéder au socket Docker, c'est pouvoir lancer n'importe quel conteneur, y compris un conteneur privilégié qui monte la racine de l'hôte : c'est l'équivalent d'un accès root à la machine (ou à la VM Docker sous Windows et macOS), comme l'appartenance au groupe `docker` vue au TP 1. On ne monte le socket que dans des outils de confiance, à la version épinglée, et jamais dans une application exposée. En CI, on préfère des scanners qui lisent une archive d'image (`trivy image --input image.tar`) ou interrogent le registre directement.

```bash
docker rm -f durci
```

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 9 - Ménage

**Ce que vous devez faire :**

- Supprimez le conteneur `prod`, le registre et son volume.
- Déconnectez-vous du registre, et vérifiez que les identifiants ont disparu de `~/.docker/config.json`.
- Supprimez les images de ce TP et le cache de Trivy.

{::nomarkdown}
<details><summary>Solution - Étape 9</summary>
{:/nomarkdown}

```bash
docker rm -f prod
cd ~/tp6/registry && docker compose down -v && cd ~/tp6
docker logout localhost:5000
cat ~/.docker/config.json

docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^localhost:5000/' | xargs docker rmi
docker volume rm trivy-cache
docker image prune
```

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Récapitulatif

| Thème | Bonne pratique |
| --- | --- |
| Registre | HTTPS obligatoire hors `localhost`, authentification, tags immuables activés si le registre le permet |
| Identifiants | `--password-stdin` dans les scripts, gestionnaire d'identifiants plutôt que `config.json` en base64, `docker logout` sur les machines partagées |
| Versions | Un tag de version par publication, tags mobiles déplacés explicitement, déploiement par version complète ou par digest |
| Images de base | Maintenues, minimales, reconstruites régulièrement avec `--pull` |
| Secrets | Jamais dans le contexte de build (`.dockerignore`), jamais dans une couche ; une clé qui a fuité est révoquée |
| Scan | Avant publication, avec un seuil bloquant sur les vulnérabilités corrigibles ; exceptions justifiées et datées ; rescan régulier des images publiées |
| SBOM | Généré au build et publié avec l'image |
| Exécution | Utilisateur non root, `--read-only`, `--cap-drop ALL`, `no-new-privileges`, socket Docker jamais monté dans une application |

{% endraw %}
