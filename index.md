---
title: "3DKR - TPs Docker"
layout: home
---

Travaux pratiques autour de Docker : installer l'outil, comprendre ce qu'il fait réellement sur votre machine, puis construire et faire tourner vos propres conteneurs.

Chaque TP propose des consignes, des questions de réflexion et une solution repliable. Essayez avant d'ouvrir la solution.

---

## Liste des TP

{% assign tp_pages = site.pages | where_exp: "p", "p.dir == '/tp/'" | sort: "name" %}
{% for tp in tp_pages %}
- [{{ tp.title }}]({{ tp.url | relative_url }})
{% endfor %}
