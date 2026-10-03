# TP Docker

Série de travaux pratiques pour apprendre Docker, de l'installation jusqu'à la construction et l'exécution d'applications conteneurisées. Public visé : étudiants bac+5.

## Accès

Le site est publié via GitHub Pages à partir de la branche `main`.

## Structure

- `tp/` : les énoncés des TP, un fichier Markdown par TP
- `_layouts/` et `_includes/` : templates Jekyll
- `assets/` : feuille de style

## Ajouter un TP

Créer un fichier dans `tp/` dont le nom commence par un numéro (l'ordre du menu suit l'ordre alphabétique des fichiers), avec un front matter :

```yaml
---
title: "TP X - Titre"
objective: "Objectif pédagogique en une phrase"
---
```

Le layout `tp` est appliqué automatiquement. Seule la partie du titre située avant le premier ` -` est affichée dans le menu.

Les solutions se placent dans un bloc repliable :

```markdown
{::nomarkdown}
<details><summary>Solution - Étape 1</summary>
{:/nomarkdown}

Contenu de la solution.

{::nomarkdown}
</details>
{:/nomarkdown}
```

## Prévisualiser en local

```bash
bundle install
bundle exec jekyll serve
```

Le site est alors disponible sur <http://localhost:4000/>. La commande doit être lancée depuis ce dossier.
