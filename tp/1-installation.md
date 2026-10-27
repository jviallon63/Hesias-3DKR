---
title: "TP 1 - Installer Docker et lancer son premier conteneur"
objective: "Installer Docker sur votre système, vérifier que le client et le daemon communiquent, puis télécharger et exécuter l'image hello-world en comprenant ce qui se passe."
---

# Contexte

Votre équipe veut livrer ses applications sous forme de conteneurs. Avant d'écrire le moindre `Dockerfile`, il faut un poste de travail fonctionnel, et surtout comprendre ce que l'on vient d'installer : sur Windows et macOS, ce n'est pas tout à fait ce que l'on croit.

Ce TP est volontairement court. Il pose les bases sur lesquelles tous les suivants s'appuient.

---

## Objectifs

<div class="section objective">

1. Distinguer Docker Engine, Docker Desktop, le client et le daemon
2. Installer Docker sur votre système (Windows, Linux ou macOS)
3. Vérifier l'installation et lire la sortie de `docker version` et `docker info`
4. Télécharger puis exécuter l'image `hello-world`
5. Inspecter, arrêter et supprimer conteneurs et images

</div>

---

## Étape 1 - Comprendre ce que l'on installe

Le mot « Docker » désigne en pratique plusieurs choses :

| Élément | Rôle |
| --- | --- |
| `docker` (CLI) | Le client en ligne de commande. Il ne fait que parler à une API. |
| `dockerd` (daemon) | Le service qui gère images, conteneurs, réseaux et volumes. Il tourne en arrière-plan, généralement en root. |
| `containerd` + `runc` | Les composants de plus bas niveau, qui créent réellement les processus isolés. |
| Docker Engine | L'ensemble daemon + CLI, disponible nativement sur Linux. |
| Docker Desktop | Une application packagée pour Windows, macOS et Linux : Engine dans une machine virtuelle, interface graphique, Compose, Kubernetes optionnel. |
| Docker Hub | Le registre public par défaut, d'où sont téléchargées les images. |

Les conteneurs s'appuient sur des fonctionnalités du **noyau Linux** (namespaces, cgroups). Il n'existe donc pas de « conteneur Linux » natif sous Windows ou macOS : Docker Desktop démarre une petite VM Linux et y place le daemon.

```mermaid
flowchart LR
    CLI["docker (client)"] -->|API REST via socket| D["dockerd (daemon)"]
    D --> C["containerd / runc"]
    C --> K["Conteneurs"]
    D -->|pull| R["Registre (Docker Hub)"]
```

---

## Étape 2 - Installer Docker

**Ce que vous devez faire :**

- Choisissez la méthode adaptée à votre système.
- Suivez de préférence la documentation officielle : <https://docs.docker.com/engine/install/> pour Docker Engine, <https://docs.docker.com/desktop/> pour Docker Desktop.
- Sous Linux, installez Docker Engine depuis le dépôt officiel de Docker, pas depuis le paquet `docker.io` de votre distribution (souvent en retard de plusieurs versions).

> Docker Desktop est gratuit pour un usage personnel, éducatif et pour les petites entreprises. Au-delà (plus de 250 salariés ou plus de 10 M$ de chiffre d'affaires), une licence payante est requise. Vérifiez les conditions en vigueur avant de l'installer sur un poste professionnel.

{::nomarkdown}
<details><summary>Solution - Étape 2, Linux (Ubuntu / Debian)</summary>
{:/nomarkdown}

Supprimer d'abord les paquets susceptibles d'entrer en conflit :

```bash
sudo apt remove docker.io docker-compose docker-doc podman-docker containerd runc
```

Ajouter le dépôt officiel Docker (pour Debian, remplacer `ubuntu` par `debian` dans l'URL du dépôt et de la clé) :

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

Installer Engine et ses plugins :

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Le service est démarré et activé au boot par le paquet. Vérifiez-le :

```bash
systemctl status docker --no-pager
```

Pour Fedora, RHEL et dérivés, la procédure équivaut avec `dnf` ; elle est décrite sur <https://docs.docker.com/engine/install/fedora/>.

{::nomarkdown}
</details>
{:/nomarkdown}

{::nomarkdown}
<details><summary>Solution - Étape 2, Windows</summary>
{:/nomarkdown}

Prérequis : Virtualisation activée dans le BIOS/UEFI (vérifiable dans le Gestionnaire des tâches, onglet Performances, CPU).

Après le redémarrage, installer Docker Desktop (via `winget`, ou depuis l'installeur téléchargeable sur le site de Docker) :

```powershell
winget install -e --id Docker.DockerDesktop
```

Lancer Docker Desktop depuis le menu Démarrer, accepter les conditions d'utilisation, et attendre que l'icône de la barre des tâches indique que le moteur est démarré.

Alternative sans Docker Desktop : installer une distribution Ubuntu dans WSL 2 (`wsl --install -d Ubuntu`), puis suivre la procédure Linux ci-dessus à l'intérieur de cette distribution. Il faut alors activer systemd dans la distribution (`/etc/wsl.conf`, section `[boot]`, `systemd=true`).

{::nomarkdown}
</details>
{:/nomarkdown}

{::nomarkdown}
<details><summary>Solution - Étape 2, macOS</summary>
{:/nomarkdown}

Avec Homebrew, installer Docker Desktop (le paquet `docker` seul, sans `--cask`, n'installe que le client) :

```bash
brew install --cask docker
open -a Docker
```

Au premier lancement, accepter les conditions et autoriser les composants système demandés. Sur Mac Apple Silicon, la VM est en `arm64` ; sur Mac Intel, en `amd64`. Cela aura son importance à l'étape 4.

Alternative libre, sans interface graphique : Colima, qui démarre une VM Lima contenant le daemon.

```bash
brew install colima docker docker-compose
colima start
```

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 3 - Vérifier l'installation

**Ce que vous devez faire :**

- Affichez la version du client **et** celle du serveur : `docker version`
- Affichez les informations détaillées du daemon : nombre de conteneurs et d'images, runtime utilisé, driver de stockage, système d'exploitation et architecture du serveur : `docker info`
- Arrêtez le daemon docker (ou quittez Docker Desktop), et recommencez.

{::nomarkdown}
<details><summary>Solution - Étape 3</summary>
{:/nomarkdown}

Sortie de `docker version` (abrégée, les numéros varient) :

```text
Client:
 Version:           28.x.x
 OS/Arch:           darwin/arm64
 ...

Server: Docker Desktop 4.x.x
 Engine:
  Version:          28.x.x
  OS/Arch:          linux/arm64
 containerd:
  Version:          1.7.x
 runc:
  Version:          1.2.x
```

Sous Linux, client et serveur sont en `linux/<arch>`. Sous Windows et macOS, le client est `windows/amd64` ou `darwin/arm64`, mais le serveur est toujours `linux/...` : c'est la VM.

Si le daemon est arrêté, la partie `Client` s'affiche mais le serveur est remplacé par une erreur :

```text
Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
```

Cela confirme que le client est un simple programme qui interroge une API. Sous Linux, `sudo systemctl start docker` règle le problème.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 4 - Premier conteneur : hello-world

`hello-world` est une image de quelques kilo-octets, dont le seul rôle est d'afficher un message et de s'arrêter. Elle sert à valider toute la chaîne : client, daemon, accès au registre, création et exécution d'un conteneur.

**Ce que vous devez faire :**

- Listez les images disponibles localement : `docker image ls`
- Lancer le conteneur **hello-world** : `docker run hello-world`
- Listez de nouveaux les images.
- Listez les conteneur en execution : `docker container ps`
- Relancer le container, observez les logs cette fois.

{::nomarkdown}
<details><summary>Solution - Étape 4</summary>
{:/nomarkdown}

Sortie attendue du `run` :

```text
Hello from Docker!
This message shows that your installation appears to be working correctly.

To generate this message, Docker took the following steps:
 1. The Docker client contacted the Docker daemon.
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (arm64v8)
 3. The Docker daemon created a new container from that image which runs the
    executable that produces the output you are currently reading.
 4. The Docker daemon streamed that output to the Docker client, which sent it
    to your terminal.
```

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 5 - Observer et nettoyer

Un conteneur qui a terminé son travail n'est pas supprimé automatiquement : il reste dans l'état `Exited` avec son système de fichiers et ses logs, jusqu'à ce que vous le supprimiez.

**Ce que vous devez faire :**

- Listez les conteneurs en cours d'exécution. Pourquoi la liste est-elle vide ?
- Listez **tous** les conteneurs, y compris ceux arrêtés. Relevez l'identifiant, le nom généré et le statut de votre conteneur `hello-world`.
- Relancez `hello-world` deux fois de plus, puis recomptez les conteneurs.
- Supprimez tous ces conteneurs, puis l'image.
- Relancez enfin `hello-world` en faisant en sorte que le conteneur soit supprimé automatiquement dès qu'il se termine, et vérifiez qu'il n'en reste aucune trace.

{::nomarkdown}
<details><summary>Solution - Étape 5</summary>
{:/nomarkdown}

```bash
docker ps          # vide : le conteneur s'est terminé immédiatement
docker ps -a       # affiche les conteneurs arrêtés
```

Exemple de sortie de `docker ps -a` :

```text
CONTAINER ID   IMAGE         COMMAND    CREATED          STATUS                      NAMES
3f2a9c1d7e04   hello-world   "/hello"   12 seconds ago   Exited (0) 11 seconds ago   charming_lovelace
```

Le nom est généré aléatoirement (adjectif + nom de scientifique). Le code `Exited (0)` indique un arrêt sans erreur. Chaque `docker run` crée un **nouveau** conteneur : après deux lancements supplémentaires, il y en a trois.

Nettoyage :

```bash
docker rm $(docker ps -aq)    # supprime tous les conteneurs arrêtés
docker rmi hello-world        # supprime l'image
```

Avec `--rm`, le conteneur est supprimé à sa sortie. Comme l'image a été supprimée, elle est de nouveau téléchargée :

```bash
docker run --rm hello-world
docker ps -a                  # aucun conteneur
```

`docker system prune` supprime en une fois conteneurs arrêtés, réseaux inutilisés et images orphelines. Il demande confirmation, mais lisez ce qu'il propose de supprimer avant de répondre.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Étape 6 - Aller plus loin : un conteneur interactif

`hello-world` ne contient presque rien. Pour voir ce qu'est vraiment un conteneur, lancez un système minimal dans lequel vous pouvez entrer.

**Ce que vous devez faire :**

- Lancez un conteneur `alpine` en mode interactif avec un shell, en le supprimant à la sortie.
- Dans ce conteneur, affichez la version du noyau (`uname -a`), la distribution (`/etc/os-release`) et la liste des processus (`ps`).
- Comparez le noyau affiché avec celui de votre hôte (ou de la VM Docker Desktop).
- Sortez du conteneur.

**Questions de réflexion :**

- Combien de processus voyez-vous dans le conteneur ? Quel est le PID du shell ? Qu'est-ce que cela dit de l'isolation ?
- Alpine pèse environ 5 Mo, une VM Ubuntu plusieurs Go. Qu'est-ce qui explique cet écart ?

{::nomarkdown}
<details><summary>Solution - Étape 6</summary>
{:/nomarkdown}

```bash
docker run --rm -it alpine sh
```

Dans le conteneur :

```bash
uname -a
cat /etc/os-release
ps
exit
```

`uname -a` affiche le noyau de l'**hôte** (ou de la VM sous Windows et macOS), pas un noyau fourni par Alpine : un conteneur n'embarque pas de noyau. `/etc/os-release` indique en revanche Alpine, car c'est le système de fichiers de l'image qui est visible.

`ps` montre une poignée de processus, le shell ayant le PID 1. Le conteneur vit dans son propre espace de noms de processus (namespace PID) : il ne voit pas ceux de l'hôte. Quand le PID 1 se termine, le conteneur s'arrête.

L'écart de taille s'explique par l'absence de noyau et de matériel virtualisé. Une image ne contient que les binaires et bibliothèques de l'espace utilisateur ; le noyau est partagé avec l'hôte. En contrepartie, l'isolation est moins forte qu'avec une VM, puisque tous les conteneurs d'un hôte dépendent du même noyau.

{::nomarkdown}
</details>
{:/nomarkdown}

---

## Dépannage

| Symptôme | Cause probable | Piste |
| --- | --- | --- |
| `permission denied while trying to connect to the Docker daemon socket` | Utilisateur absent du groupe `docker` (Linux) | `sudo usermod -aG docker "$USER"`, puis nouvelle session |
| `Cannot connect to the Docker daemon ... Is the docker daemon running?` | Daemon arrêté, ou Docker Desktop non démarré | `sudo systemctl start docker` ou lancer Docker Desktop |
| `no matching manifest for linux/arm64/v8` | L'image n'est publiée que pour `amd64` | Ajouter `--platform linux/amd64` (émulation, plus lent) |
| `toomanyrequests: You have reached your pull rate limit` | Limite de téléchargements anonymes sur Docker Hub | `docker login` ou attendre |
| Docker Desktop reste bloqué sur « Starting » (Windows) | Virtualisation désactivée ou WSL 2 absent | Activer la virtualisation dans le BIOS, `wsl --update` |
| `docker: command not found` juste après l'installation | `PATH` non rechargé | Ouvrir un nouveau terminal |

---

## Pour résumer

- Le client `docker` dialogue avec un daemon par une API ; les deux peuvent être sur des machines différentes.
- Les conteneurs partagent le noyau Linux de leur hôte, d'où la VM sous Windows et macOS.
- Une image est téléchargée depuis un registre ; un conteneur est une instance en cours d'exécution (ou terminée) de cette image.
- Un conteneur arrêté existe toujours tant qu'il n'a pas été supprimé.
