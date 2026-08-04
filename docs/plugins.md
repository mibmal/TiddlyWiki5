# Using the baked-in plugins

This image ships TiddlyWiki with a set of plugins baked in at build time
(see the Dockerfile `TW5_PLUGINS` ARG and the chart's `imageBuild` block).

## How activation works

On every pod start, the `activate-baked-plugins` init container walks
`/usr/src/app/baked-plugins`, reads each `plugin.info`, and **adds its title to
`tiddlywiki.info[].plugins`**. This is idempotent, so the plugins are
effectively always-on once the image is deployed:

```sh
# Verify the bundles are present (expect 12)
kubectl exec -n <namespace> deploy/<tiddlywiki> -- \
  sh -c 'find /usr/src/app/baked-plugins -name plugin.info | wc -l'
```

To confirm they are active, open the wiki → **Control Panel → Extensions** and
look at the plugin list, or check the pod logs:

```sh
kubectl logs -n <namespace> -l app.kubernetes.io/name=tiddlywiki -c tiddlywiki | grep -i activate
```

> **Important:** because the init container re-adds titles on every restart,
> baked plugins are effectively always-on. To disable one you must NOT bake it
> (edit `imageBuild.plugins` / `TW5_PLUGINS` and rebuild); deleting it from
> `tiddlywiki.info` will be undone on the next pod start.

## Per-plugin usage

### ⌨️ Command Palette + Autocomplete
`$:/plugins/linonetwo/commandpalette`, `$:/plugins/linonetwo/autocomplete`
- Press **`Ctrl/Cmd + P`** to open the palette; type to search tiddlers and
  commands, Enter to run.
- Autocomplete surfaces suggestions as you type in search and editors.

### 🔗 Relink (and companions)
`$:/plugins/flibbles/relink`, `relink-fieldnames`, `relink-markdown`,
`relink-titles`, `relink-variables`
- Works automatically: **rename a tiddler** (or change a field) and Relink fixes
  backlinks inside body text, `list`/`list-before`, markdown links, titles, and
  variables.
- Options: `$:/plugins/flibbles/relink/settings`.

### 🕸️ Graph + vis-network engine
`$:/plugins/flibbles/graph`, `$:/plugins/flibbles/vis-network`
- tw5-graph is a widget toolkit; `vis-network` is the rendering engine it
  needs, so both are baked together.
- Quick start: add a graph widget to a tiddler body, e.g.
  `<$graph [all[tiddlers]] />` (parameters vary by version — see the demo and
  docs at <http://flibbles.github.io/tw5-graph/>).
- Settings: `$:/plugins/flibbles/graph/settings`.

### 🧬 Kin Filter
`$:/plugins/bimlas/kin-filter`
- Adds the `kin` filter operator to traverse tiddler "kinship" (defaults to the
  `tags` field, recursive):
  - `[kin[MyTiddler]]` → all tiddlers kin to `MyTiddler`.
  - Rich form `[kin:tags:from:1[MyTiddler]]` →
    `field:direction:depth`, where direction is `from`/`to` and depth is the
    number of hops.

### 🎨 Krystal theme
`$:/plugins/rmnvsl/krystal`
- A UI/theme plugin. Activate by setting **`$:/config/Theme`** to
  **`$:/themes/rmnvsl/krystal`** (Control Panel → Appearance → Theme).

### 🧠 TiddlyRemember
`$:/plugins/sobjornstad/TiddlyRemember`
- TiddlyWiki ⇄ Anki sync. Turn notes into question/answer blocks and push them
  to Anki (requires the AnkiConnect add-on). Use its command-palette
  entry or toolbar; docs at <https://github.com/sobjornstad/TiddlyRemember>.

---

See also: [`docs/mws-argocd.md`](./mws-argocd.md) for the ArgoCD deployment,
and the Dockerfile/`values.yaml` `imageBuild` block to control which plugins are
baked.