import fs from "fs";
import path from "path";

const ROOT = path.resolve(
  path.dirname(new URL(import.meta.url).pathname).replace(/^\/([A-Za-z]:)/, "$1"),
  ".."
);
const CSV = path.join(ROOT, "apps/game/client/translations/strings.csv");

// key: [english, romanian]
const STRINGS = {
  INV_USE_FAILED: ["That cannot be used here.", "Nu poate fi folosit aici."],

  SETTINGS_TITLE: ["Settings", "Setări"],
  SETTINGS_BACK: ["Back", "Înapoi"],
  SETTINGS_HINT_BACK: ["Esc — back", "Esc — înapoi"],
  SETTINGS_RESET_PAGE: ["Reset page", "Resetează pagina"],
  SETTINGS_AUDIO_TEST: ["Test", "Testează"],
  SETTINGS_VALUE_ON: ["On", "Pornit"],
  SETTINGS_VALUE_OFF: ["Off", "Oprit"],

  SETTINGS_PAGE_GAMEPLAY: ["Gameplay", "Joc"],
  SETTINGS_PAGE_DISPLAY: ["Display", "Afișare"],
  SETTINGS_PAGE_AUDIO: ["Audio", "Sunet"],
  SETTINGS_PAGE_CONTROLS: ["Controls", "Comenzi"],
  SETTINGS_PAGE_ACCESSIBILITY: ["Access", "Acces"],
  SETTINGS_PAGE_ADVANCED: ["Advanced", "Avansat"],

  SETTINGS_LANGUAGE_NAME: ["Language", "Limbă"],
  SETTINGS_LANGUAGE_DESC: ["Interface language.", "Limba interfeței."],
  SETTINGS_LANGUAGE_EN: ["English", "Engleză"],
  SETTINGS_LANGUAGE_RO: ["Romanian", "Română"],

  SETTINGS_WINDOW_MODE_NAME: ["Window mode", "Mod fereastră"],
  SETTINGS_WINDOW_MODE_DESC: ["How the game fills the screen.", "Cum umple jocul ecranul."],
  SETTINGS_WINDOW_MODE_WINDOWED: ["Windowed", "Fereastră"],
  SETTINGS_WINDOW_MODE_BORDERLESS: ["Borderless", "Fără margini"],
  SETTINGS_WINDOW_MODE_FULLSCREEN: ["Fullscreen", "Ecran complet"],

  SETTINGS_MONITOR_NAME: ["Monitor", "Monitor"],
  SETTINGS_MONITOR_DESC: ["Which display to use.", "Ce ecran se folosește."],

  SETTINGS_VSYNC_NAME: ["V-Sync", "V-Sync"],
  SETTINGS_VSYNC_DESC: ["Sync frames to the display.", "Sincronizează cadrele cu ecranul."],
  SETTINGS_VSYNC_DISABLED: ["Off", "Oprit"],
  SETTINGS_VSYNC_ENABLED: ["On", "Pornit"],
  SETTINGS_VSYNC_ADAPTIVE: ["Adaptive", "Adaptiv"],

  SETTINGS_MAX_FPS_NAME: ["Frame limit", "Limită cadre"],
  SETTINGS_MAX_FPS_DESC: ["Cap the frame rate.", "Limitează rata de cadre."],
  SETTINGS_MAX_FPS_UNCAPPED: ["Uncapped", "Nelimitat"],
  SETTINGS_MAX_FPS_30: ["30", "30"],
  SETTINGS_MAX_FPS_60: ["60", "60"],
  SETTINGS_MAX_FPS_120: ["120", "120"],
  SETTINGS_MAX_FPS_144: ["144", "144"],
  SETTINGS_MAX_FPS_240: ["240", "240"],

  SETTINGS_UI_SCALE_NAME: ["UI scale", "Scară interfață"],
  SETTINGS_UI_SCALE_DESC: ["Size of menus and text.", "Mărimea meniurilor și a textului."],
  SETTINGS_RENDER_RESOLUTION: ["Render scale", "Scară randare"],
  SETTINGS_LOW_RES_VIEWPORT: ["Pixel viewport", "Vizor pixelat"],

  SETTINGS_PIXEL_SECTION: ["Pixel pipeline", "Pipeline pixel"],
  SETTINGS_PIXEL_ADVANCED: ["Advanced pixel options", "Opțiuni pixel avansate"],
  SETTINGS_PIXEL_HIDE: ["Hide", "Ascunde"],
  SETTINGS_PIXEL_RESTORE: ["Restore defaults", "Revino la implicit"],

  SETTINGS_COLORBLIND_MODE_NAME: ["Colour vision", "Vedere culoare"],
  SETTINGS_COLORBLIND_MODE_DESC: ["Adjust damage and status colours.", "Ajustează culorile pentru daune și stări."],
  SETTINGS_COLORBLIND_DEFAULT: ["Default", "Implicit"],
  SETTINGS_COLORBLIND_PROTANOPIA: ["Protanopia", "Protanopie"],
  SETTINGS_COLORBLIND_DEUTERANOPIA: ["Deuteranopia", "Deuteranopie"],
  SETTINGS_COLORBLIND_TRITANOPIA: ["Tritanopia", "Tritanopie"],

  SETTINGS_LEADERBOARD_OPT_IN_NAME: ["Leaderboards", "Clasamente"],
  SETTINGS_LEADERBOARD_OPT_IN_DESC: ["Submit your runs to online boards.", "Trimite alergările în clasamentele online."],
  SETTINGS_CRASH_REPORTS: ["Crash reports", "Rapoarte de eroare"],

  SETTINGS_BINDING_DESC: ["Rebind an action.", "Reasignează o acțiune."],
  SETTINGS_BINDING_PROMPT: ["Press a key or button.", "Apasă o tastă sau un buton."],
  SETTINGS_BINDING_WAIT: ["Listening…", "Ascult…"],
  SETTINGS_BINDING_CANCEL: ["Cancel", "Anulează"],
  SETTINGS_BINDING_CONFLICT: ["Already bound to %s.", "Deja asignat la %s."],
  SETTINGS_BINDING_SWAP: ["Swap", "Schimbă"],
  SETTINGS_BINDING_RESET: ["Reset", "Resetează"],
  SETTINGS_BINDING_RESET_ALL: ["Reset all bindings", "Resetează toate comenzile"],
  SETTINGS_BINDING_UNBOUND: ["Unbound", "Neasignat"],

  SETTINGS_RESTORE_BACKUP: ["Restore backup", "Restaurează copia"],
  SETTINGS_RESTORE_TITLE: ["Restore backup", "Restaurează copia"],
  SETTINGS_RESTORE_BODY: ["Replace the current save with the last backup?", "Înlocuiești salvarea curentă cu ultima copie?"],
  SETTINGS_RESTORE_CONFIRM: ["Restore", "Restaurează"],
  SETTINGS_NO_BACKUPS: ["No backups found.", "Nicio copie găsită."],
};

// Anything still missing gets a readable title-cased fallback derived from the key.
function fallback(key) {
  let base = key
    .replace(/^SETTINGS_/, "")
    .replace(/_(NAME)$/, "")
    .replace(/_(DESC)$/, "");
  const isDesc = /_DESC$/.test(key);
  const words = base.split("_").filter(Boolean).map((w) => w.toLowerCase());
  if (words.length === 0) return null;
  let text = words.join(" ");
  text = text.charAt(0).toUpperCase() + text.slice(1);
  return isDesc ? [text + ".", text + "."] : [text, text];
}

const missingPath = process.argv[2];
const wanted = fs
  .readFileSync(missingPath, "utf8")
  .split(/\r?\n/)
  .map((s) => s.trim())
  .filter(Boolean);

const raw = fs.readFileSync(CSV, "utf8");
const eol = raw.includes("\r\n") ? "\r\n" : "\n";
const lines = raw.split(/\r?\n/).filter((l) => l.length > 0);
const existing = new Set(
  lines.slice(1).map((l) => (l.startsWith('"') ? (l.match(/^"((?:[^"]|"")*)"/) || [])[1] : l.split(",")[0]))
);

function esc(v) {
  return /[",]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v;
}

let added = 0;
let derived = 0;
for (const key of wanted) {
  if (existing.has(key)) continue;
  let pair = STRINGS[key];
  if (!pair) {
    pair = fallback(key);
    if (!pair) continue;
    derived++;
  }
  lines.push([key, esc(pair[0]), esc(pair[1])].join(","));
  existing.add(key);
  added++;
}

fs.writeFileSync(CSV, lines.join(eol) + eol);
console.log("rows added:", added, " (authored:", added - derived, " derived-from-key:", derived + ")");
console.log("total rows now:", lines.length - 1);
