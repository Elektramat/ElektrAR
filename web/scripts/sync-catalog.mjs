// Copies the cable catalog and photos from the iPhone app (the single source of truth)
// into the web app before every build and dev start. Fails loudly when neither the
// source nor an earlier copy exists.
import { cpSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const web = join(dirname(fileURLToPath(import.meta.url)), "..");
const source = join(web, "..", "Kabelmeter", "Resources");
const catalogOut = join(web, "lib", "cables.json");
const imagesOut = join(web, "public", "cables");

if (existsSync(join(source, "cables.json"))) {
  cpSync(join(source, "cables.json"), catalogOut);
  mkdirSync(imagesOut, { recursive: true });
  for (const file of readdirSync(join(source, "CableImages"))) {
    if (file.endsWith(".jpg")) cpSync(join(source, "CableImages", file), join(imagesOut, file));
  }
  console.log("sync-catalog: copied cables.json and photos from Kabelmeter/Resources");
} else if (existsSync(catalogOut)) {
  console.warn("sync-catalog: Kabelmeter/Resources not found, using the committed copy in web/lib/cables.json");
} else {
  console.error("sync-catalog: no cable catalog found (Kabelmeter/Resources/cables.json is missing)");
  process.exit(1);
}
