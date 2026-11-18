---
title: "TP 4 - Registre privé et sécurité des images"
objective: "Héberger un registre privé authentifié, y publier des images avec et sans gestion de version, détecter vulnérabilités, secrets et mauvaises configurations avec Trivy, corriger les images et durcir leur exécution."
---

# Contexte

Vos images sont prêtes. Pour être déployées, elles doivent être publiées dans un **registre** accessible aux serveurs, et elles doivent être **sûres** : une image embarque un système, des bibliothèques et parfois, par erreur, des secrets. Chacun de ces éléments peut contenir des vulnérabilités connues, publiées sous forme de **CVE** (*Common Vulnerabilities and Exposures*).

---

## Objectifs

<div class="section objective">

1. Déployer un registre privé avec authentification
2. Publier et récupérer des images avec `docker login`, `push` et `pull`
3. Mesurer les conséquences d'une publication sans gestion de version
4. Détecter vulnérabilités, secrets et mauvaises configurations avec Trivy

</div>

---

## Étape 1 - Un registre privé

Un registre est un serveur HTTP qui stocke des manifestes et des couches, et expose une API standardisée (la *Distribution Specification* de l'OCI). `registry:3` en est l'implémentation de référence, maintenue par le projet CNCF Distribution.

**Ce que vous devez faire :**

- Générez un fichier `auth/htpasswd` contenant un utilisateur `etudiant` avec le mot de passe de votre choix, à l'aide de la commande `htpasswd -Bbn etudiant <my-password> > auth/htpasswd`. Pas besoin d'installer htpasswd, utilisez l'image `httpd:2` pour se faire !
- Créer un volume nommé registry-data pour stocker les images du registre.
- Demarrez un conteneur `registry` depuis l'image `registry:3` :
  - port 5000 publié.
  - images stockées dans le volume nommé `registry-data`, monté sur `/var/lib/registry`.
  - authentification `htpasswd` activée par les variables `REGISTRY_AUTH = htpasswd`, `REGISTRY_AUTH_HTPASSWD_REALM = "Registre local"` et `REGISTRY_AUTH_HTPASSWD_PATH = /auth/htpasswd`, avec le dossier `auth`.
- Interrogez son API `GET /v2/` sans et avec authentification (`curl -u <user>:<password>`). Essayez avec `GET /v2/_catalog`.

**Questions de réflexion :**

- Comment gérer plus facilement les multiples variables d'environnements ?
- Une UI existe pour `registry:3`, essayez de la démarrer à coté : [docker-registry-ui](https://github.com/joxit/docker-registry-ui)
  - Vous devez utiliser les réseaux docker pour avoir `registry` et `registry-ui` sur le même réseau. `registry-ui` accède à `registry` avec `http://registry:5000`

{% comment %}
{::nomarkdown}
<details><summary>Solution - Étape 1</summary>
{:/nomarkdown}

```bash
mkdir auth
docker run --rm httpd:2 htpasswd -Bbn etudiant tp4-Registre > auth/htpasswd
cat auth/htpasswd       # etudiant:$2y$05$...

docker volume create registry-data
docker container run --name registry -d -p 5001:5000 -v registry-data:/var/lib/registry -e REGISTRY_AUTH=htpasswd -e REGISTRY_AUTH_HTPASSWD_REALM="Registre local" -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd -v ./tp4/auth:/auth registry:3 # Port 5001 sur Mac car 5000 déjà occupé.

curl http://localhost:5001/v2/                                      # 401 Unauthorized
curl -u etudiant:tp4-Registre http://localhost:5001/v2/             # {}
curl -u etudiant:tp4-Registre http://localhost:5001/v2/_catalog     # {"repositories":[]}
```

`docker-registry-ui`

```bash
docker network create registry-net
docker network connect registry-net registry
docker container run -d --name registry-ui \
  --network registry-net \
  -p 8080:80 \
  -e SINGLE_REGISTRY=true \
  -e NGINX_PROXY_PASS_URL=http://registry:5000 \
  joxit/docker-registry-ui:latest
```

{::nomarkdown}
</details>
{:/nomarkdown}
{% endcomment %}

---

## Étape 2 - `docker login`, `push` et `pull`

Le nom d'une image indique **où** la pousser : `localhost:5000/sample-app/back:0.0.0` désigne le dépôt `sample-app/back` du registre `localhost:5000`. Sans registre dans le nom, c'est Docker Hub.

**Ce que vous devez faire :**

- Authentifiez-vous auprès du registre avec `docker login` sans taper le mot de passe dans la commande, puis poussez à nouveau.
- Trouvez où Docker a enregistré vos identifiants. Sont-ils chiffrés ?
- Tagguez une des images du TP3 avec `docker tag` et pousser la dans la registry avec `docker push`.
- Simulez un autre serveur : supprimez l'image locale, puis récupérez-la depuis le registre. Vérifiez le catalogue du registre.
- Parcourez la registry avec l'API, poussez d'autres images et d'autres version de la même image.
  - Listez les dêpots : `GET /v2/_catalog`
  - Lister les images d'un dêpot : `GET /v2/<depot>/tags/list`

**Questions de réflexion :**

- Est-ce qu'une image avec plusieurs tag augmente la volumétrie sur le disque ? Pourquoi ?

{% comment %}
{::nomarkdown}
<details><summary>Solution - Étape 2</summary>
{:/nomarkdown}

```bash
docker login localhost:5000 -u etudiant     # mot de passe demandé
cat ~/.docker/config.json

docker tag tp4-back:0.0.0 localhost:5000/sample-app/back:0.0.0
docker push localhost:5000/sample-app/back:0.0.0

docker image rm tp4-back:0.0.0
docker image rm localhost:5000/sample-app/back:0.0.0

docker pull localhost:5000/sample-app/back:0.0.0

curl -u etudiant:tp4-Registre http://localhost:5000/v2/_catalog
curl -u etudiant:tp4-Registre http://localhost:5000/v2/sample-app/back/tags/list
```

{::nomarkdown}
</details>
{:/nomarkdown}
{% endcomment %}

---

## Étape 3 - Publier en gérant les versions

On souhaite publier plusiers tag de la même image pour permettre une gestion flexible de notre application. Un tag immuable par version (`0.0.0`), des tags mobiles (`0.0`, `0`, `latest`) déplacés à chaque publication

**Ce que vous devez faire :**

- Poussez sur la registry l'image précédentes avec des tag "mobiles" `latest`et `1.0`.
- Observez `/tags/list` de votre dêpot sur la registre.

**Questions de réflexion :**

- Quel tag mettre dans un fichier de déploiement de production ? Et dans un environnement de développement ?

{% comment %}
{::nomarkdown}
<details><summary>Solution - Étape 3</summary>
{:/nomarkdown}

```bash
docker tag localhost:5001/sample-app/back:0.0.0 localhost:5001/sample-app/back:latest
docker tag localhost:5001/sample-app/back:0.0.0 localhost:5001/sample-app/back:0.0
docker push --all-tags localhost:5001/sample-app/back

curl -u etudiant:tp4-Registre http://localhost:5000/v2/sample-app/back/tags/list
```

{::nomarkdown}
</details>
{:/nomarkdown}
{% endcomment %}

---

## Étape 4 - Scanner une image avec Trivy

**Trivy** est un scanner open source. Il compare les paquets du système et les bibliothèques applicatives d'une image à des bases de vulnérabilités, et cherche aussi des secrets et des erreurs de configuration.

Pas besoin de l'installer : on l'exécute dans un conteneur, avec le socket Docker pour accéder à vos images locales et un volume pour conserver sa base de vulnérabilités.

**Ce que vous devez faire :**

- Scannez l'image que vous avez poussez sur la registry.

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v trivy-cache:/root/.cache \
  -v "$PWD":/work -w /work \
  "aquasec/trivy:0.76.1" image localhost:5000/.....
```

- Lisez et comprenez la log !
- Relevez le nombre de vulnérabilités par sévérité
- Simplifier le résultat du scan pour n'affichez que les vulnérabilités `CRITICAL` ou plus avec `--severity CRITICAL`
- Analysez le `Dockerfile` lui-même avec `trivy config`.
- Le rapport dans le terminal n'est pas trés user friendly. Adaptez la sortie pour générer un format html : [Trivy configuration](https://trivy.dev/docs/latest/configuration/reporting/#html)
  - Téléchargez le template [html.tpl](https://raw.githubusercontent.com/aquasecurity/trivy/v0.76.1/contrib/html.tpl)
  - Le template doit être monté dans le conteneur sous /work.
  - Ajouter les options trivy pour générer `report.html`

**Questions de réflexion :**

- Ces vulnérabilités sont-elles dans votre code ? D'où viennent-elles ?
- Qu'implique le volume `docker.sock` ?
- Une CVE sans « version corrigée » : que peut-on faire ?
- Le lancement de `trivy` est complexe, dans votre terminal créez une fonction, et rééxecutez les commandes.

```bash
trivy() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v trivy-cache:/root/.cache \
    -v "$PWD":/work -w /work \
    "aquasec/trivy:0.76.1" "$@"
}
```

{% comment %}
{::nomarkdown}
<details><summary>Solution - Étape 4</summary>
{:/nomarkdown}

```bash
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v trivy-cache:/root/.cache \
    -v "$PWD":/work -w /work \
    "aquasec/trivy:0.76.1" image localhost:5001/sample-app/back:0.0.0

docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v trivy-cache:/root/.cache \
    -v "$PWD":/work -w /work \
    "aquasec/trivy:0.76.1" image --severity CRITICAL localhost:5001/sample-app/back:0.0.0

docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v trivy-cache:/root/.cache \
    -v "$PWD":/work -w /work \
    "aquasec/trivy:0.76.1" config tp/tp3/back/v2.Dockerfile

curl -o html.tpl https://raw.githubusercontent.com/aquasecurity/trivy/v0.76.1/contrib/html.tpl

docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v trivy-cache:/root/.cache \
    -v "$PWD":/work -w /work \
    "aquasec/trivy:0.76.1" image \
    --format template \
    --template "@/work/html.tpl" \
    -o report.html \
    localhost:5001/sample-app/back:0.0.0
```

Le rapport se découpe en sections :

- les **paquets du système** (`debian 11.x`) : plusieurs centaines de vulnérabilités, dont des critiques, dans `openssl`, `libc`, `curl`, `zlib`... La ligne `Total:` donne le décompte par sévérité. Trivy peut aussi signaler que cette version de Debian n'est plus maintenue ;
- les **secrets** : `/root/.ssh/id_ed25519`, détecté comme clé privée (`AsymmetricPrivateKey`), avec la couche qui l'a ajoutée.

Chaque ligne indique la bibliothèque, l'identifiant CVE, la sévérité, la version installée, la **version corrigée** quand elle existe, et un lien vers la description.

`trivy config` analyse le Dockerfile sans le construire. Il signale notamment l'absence d'instruction `HEALTHCHECK`.

Sans version corrigée, on peut : vérifier si la vulnérabilité est réellement exploitable dans votre contexte (composant non utilisé, fonction non appelée), changer d'image de base ou de bibliothèque, réduire la surface (image minimale), ou accepter le risque **de façon documentée** en attendant le correctif.

{::nomarkdown}
</details>
{:/nomarkdown}
{% endcomment %}

---
