# wtlaunch

Lanceur de projets Laragon dans Windows Terminal : un onglet nommé et coloré par projet, avec des panneaux et une commande de démarrage au choix.

## Prérequis

- Windows et [Windows Terminal](https://aka.ms/terminal) (`wt` dans le PATH), version récente pour `split-pane` et `focus-pane`.
- [PowerShell 7](https://aka.ms/powershell) ou plus récent : le script utilise `SHA1.HashData`, absent de Windows PowerShell 5.
- Laragon, dont le dossier `C:\laragon\www` sert au scan par défaut.

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
| `-ConfigPath` | Chemin du fichier de configuration (par défaut `projects.json` à côté du script) |
| `-WhatIf` | Affiche la commande `wt` sans rien ouvrir |

```powershell
.\wtlaunch.ps1 -Only devwatch,mediabox
.\wtlaunch.ps1 -Exclude windy619.github.io
.\wtlaunch.ps1 -WhatIf
```

Avec `pwsh -File`, une liste séparée par des virgules n'est pas découpée : passer par `pwsh -Command ".\wtlaunch.ps1 -Only a,b"`.

## Sélection des projets

- **Sans `projects.json`** : le script ouvre les dossiers de `C:\laragon\www` qui contiennent un `.git`.
- **Avec `projects.json`** : seuls les projets listés sont ouverts. Le fichier est local et non versionné.

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

## Couleurs et contraste

Sans `color`, la couleur vient d'une palette sombre (7:1 minimum avec du texte blanc), choisie à partir du nom : un projet garde donc sa couleur d'un lancement à l'autre. Une couleur déclarée dont le texte tombe sous 4,5:1 déclenche un avertissement.

## Développement

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning,Error
pwsh -File tests/pester.ps1
pwsh -File tests/smoke.ps1
```

Les tests utilisent Pester 5.7.1 et PSScriptAnalyzer. La CI GitLab lance les mêmes trois étapes sur chaque merge request.
