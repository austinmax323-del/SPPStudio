import type { FileStateReader } from "../state/fileStateReader";

export async function renderWatchdogWidget(container: HTMLElement, reader: FileStateReader): Promise<void> {
  const latestWatchdog = await reader.latestMarkdown([
    "40_PromptEngineering/PromptBridge/Watchdog",
  ]);
  const latestOutput = await reader.latestMarkdown([
    "40_PromptEngineering/PromptBridge/SessionNotes",
  ]);

  const card = container.createDiv({ cls: "spp-native-widget spp-native-card-watchdog" });
  card.createDiv({ cls: "spp-native-widget-kicker", text: "Output" });
  card.createDiv({ cls: "spp-native-widget-title", text: "Capture / Watchdog" });

  const list = card.createDiv({ cls: "spp-native-state-list" });
  const watchdog = list.createDiv({ cls: `spp-native-state-row ${latestWatchdog ? "spp-native-clickable" : "spp-native-empty"}` });
  watchdog.createSpan({ cls: "spp-native-state-label", text: "WATCHDOG" });
  watchdog.createSpan({ cls: "spp-native-state-value", text: latestWatchdog ?? "Missing watchdog summary" });
  if (latestWatchdog) watchdog.addEventListener("click", () => void reader.openPath(latestWatchdog));

  const output = list.createDiv({ cls: `spp-native-state-row ${latestOutput ? "spp-native-clickable" : "spp-native-empty"}` });
  output.createSpan({ cls: "spp-native-state-label", text: "OUTPUT" });
  output.createSpan({ cls: "spp-native-state-value", text: latestOutput ?? "Missing output capture" });
  if (latestOutput) output.addEventListener("click", () => void reader.openPath(latestOutput));
}
