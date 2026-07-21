import { build } from "esbuild";
import { fileURLToPath } from "node:url";
import path from "node:path";

const directory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(directory, "../..");

await build({
  entryPoints: [path.join(directory, "editor.ts")],
  outfile: path.join(root, "Sources/NotionPiP/Resources/QuickCapture/editor.js"),
  bundle: true,
  format: "iife",
  platform: "browser",
  target: ["safari17"],
  supported: { "template-literal": false },
  minify: true,
  sourcemap: false,
  legalComments: "none",
  logLevel: "info",
});
