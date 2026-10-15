# wtlaunch

Lanceur de projets dans Windows Terminal : un onglet nommé et coloré par projet, avec des panneaux et une commande de démarrage au choix.

## Prérequis

- Windows et [Windows Terminal](https://aka.ms/terminal) (`wt` dans le PATH), version récente pour `split-pane` et `focus-pane`.
- [PowerShell 7](https://aka.ms/powershell) ou plus récent : le script utilise `SHA1.HashData`, absent de Windows PowerShell 5.
- Des projets à ouvrir. Laragon est facultatif : `C:\laragon\www` n'est que le dossier du scan par défaut, et `projects.json` accepte des projets rangés n'importe où.

## Installation

```powershell
git clone https://gitlab.com/windy6191/wtlaunch.git
cd wtlaunch
.\wtlaunch.ps1
```

Pour le lancer de n'importe où, ajouter un alias au profil PowerShell (`notepad $PROFILE`) :

```powershell
Set-Alias wtl C:\chemin\vers\wtlaunch\wtlaunch.ps1
```

`wtl -Only devwatch,mediabox` fonctionne alors depuis n'importe quel dossier.

## Utilisation

| Paramètre | Rôle |
|---|---|
| `-Only a,b` | Ne lance que les projets nommés |
| `-Exclude a,b` | Lance tous les projets sauf ceux nommés |
| `-Root a,b` | Dossiers à scanner pour trouver les projets (voir plus bas) |
| `-NoBranch` | N'affiche pas la branche git dans le titre des onglets |
| `-StartEnv` | Exécutable ou commande de l'environnement local à démarrer s'il ne tourne pas (voir plus bas) |
| `-EnvProcess` | Nom du processus à surveiller, par défaut le nom de l'exécutable de `-StartEnv` |
| `-Open` | Ouvre dans le navigateur le champ `url` des projets lancés |
| `-Window nom` | Ajoute les onglets à la fenêtre Windows Terminal nommée, créée si elle n'existe pas |
| `-ConfigPath` | Chemin du fichier de configuration (par défaut `projects.json` à côté du script) |
| `-WhatIf` | Affiche la commande `wt` sans rien ouvrir |

```powershell
.\wtlaunch.ps1 -Only devwatch,mediabox
.\wtlaunch.ps1 -Exclude windy619.github.io
.\wtlaunch.ps1 -Root D:\code,E:\clients
.\wtlaunch.ps1 -WhatIf
```

Avec `pwsh -File`, une liste séparée par des virgules n'est pas découpée : passer par `pwsh -Command ".\wtlaunch.ps1 -Only a,b"`.

## Sélection des projets

- **Sans `projects.json`** : le script scanne des dossiers racines et ouvre les sous-dossiers qui contiennent un `.git`. Les racines viennent, dans cet ordre, de `-Root`, de la variable d'environnement `WTLAUNCH_ROOT` (liste séparée par `;`), puis de `C:\laragon\www` s'il existe. Sans aucune racine, le script avertit et s'arrête. Une racine introuvable est signalée sans bloquer les autres.
- **Avec `projects.json`** : seuls les projets listés sont ouverts, où qu'ils soient sur le disque, et les racines sont ignorées. Le fichier est local et non versionné.

Pour fixer les racines une fois pour toutes :

```powershell
[Environment]::SetEnvironmentVariable("WTLAUNCH_ROOT", "D:\code;E:\clients", "User")
```

Copier l'exemple puis l'adapter :

```powershell
Copy-Item projects.json.example projects.json
```

| Champ | Obligatoire | Rôle |
|---|---|---|
| `name` | oui | Nom du projet, utilisé pour le titre de l'onglet et par `-Only` / `-Exclude` |
| `path` | oui | Dossier du projet, aussi dossier de départ de chaque panneau |
| `color` | non | Couleur de l'onglet au format `#RRGGBB`, sinon dérivée du nom |
| `command` | non | Commande lancée dans l'onglet, le shell reste ouvert ensuite |
| `url` | non | Adresse `http://` ou `https://` du projet, ouverte avec `-Open` |
| `panes` | non | Liste de panneaux ajoutés à l'onglet |

Chaque entrée de `panes` accepte `split` (`vertical` ou `horizontal`, obligatoire) et `command` (optionnel).

```json
{
    "name": "pilotage",
    "path": "C:\\laragon\\www\\pilotage",
    "command": "php artisan serve",
    "panes": [
        { "split": "vertical", "command": "npm run dev" },
        { "split": "horizontal" }
    ]
}
```

Les commandes sont exécutées telles quelles : ne pointer `-ConfigPath` que vers un fichier de confiance.

## Réutiliser une fenêtre

Par défaut, chaque lancement ouvre une nouvelle fenêtre. Avec `-Window projets`, les onglets rejoignent la fenêtre nommée `projets`, ou la créent si elle n'existe pas :

```powershell
.\wtlaunch.ps1 -Window projets
```

Les projets déjà ouverts dans cette fenêtre ne sont pas dédupliqués : relancer le script ajoute de nouveaux onglets. Le premier onglet n'est refocalisé que dans une nouvelle fenêtre.

## Environnement local et URL

Si vos projets web demandent un environnement local (Laragon, XAMPP, un serveur maison...), `-StartEnv` le démarre avant l'ouverture des onglets, uniquement si son processus ne tourne pas déjà. La variable d'environnement `WTLAUNCH_ENV` joue le même rôle quand le paramètre est absent. Rien n'est supposé : sans configuration, le script ne démarre rien, et un exécutable introuvable donne un avertissement sans bloquer les onglets.

```powershell
.\wtlaunch.ps1 -StartEnv C:\laragon\laragon.exe -Open
.\wtlaunch.ps1 -StartEnv C:\outils\serveur.exe -EnvProcess serveur-web
```

Le champ `url` d'un projet n'est utilisé qu'avec `-Open`. Avec `-WhatIf`, rien n'est démarré ni ouvert.

## Branche dans le titre

Le titre de chaque onglet affiche la branche courante, lue une seule fois au lancement : `MEDIABOX (feat/6-demo)`. Sur `develop`, `staging` ou `main`, le titre ajoute `PROTEGEE` (`MEDIABOX (main) PROTEGEE`), un signal en texte qui ne dépend pas de la couleur. Un dossier sans `.git`, ou en HEAD détaché, garde le titre simple. `-NoBranch` désactive tout cela.

## Couleurs et contraste

Sans `color`, la couleur vient d'une palette sombre (7:1 minimum avec du texte blanc), choisie à partir du nom : un projet garde donc sa couleur d'un lancement à l'autre. Une couleur déclarée dont le texte tombe sous 4,5:1 déclenche un avertissement.

## Développement

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning,Error
pwsh -File tests/pester.ps1
pwsh -File tests/smoke.ps1
```

Les tests utilisent Pester 5.7.1 et PSScriptAnalyzer. La CI GitLab lance les mêmes trois étapes sur chaque merge request.
