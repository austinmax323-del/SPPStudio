# SPP Command Center Plugin

Read-only native cockpit widgets for the SPPStudio Obsidian command center.

## V1 Scope

This plugin may:

- render a native cockpit view.
- read local vault files and folders.
- show prompt queue counts.
- show latest output and watchdog paths.
- show mode/trust-zone state.
- show verification placeholders.
- open existing notes.
- refresh manually when the user clicks `Refresh`.

This plugin must not:

- run shell commands.
- send prompts.
- approve prompts.
- mutate queue files.
- modify prompt bridge semantics.
- mutate runtime/editor source.
- create background daemons.
- poll in the background.
- fake live telemetry.

## Manual Use

After enabling the plugin in Obsidian, run:

`Open SPP Command Center`

from the command palette, or click the dashboard ribbon icon.

## Build

The source TypeScript lives under `src/`.

The checked-in `main.js` is a read-only runtime build so the plugin can load locally without installing dependencies.

Future rebuild command, after dependencies are installed:

`npm run build`
