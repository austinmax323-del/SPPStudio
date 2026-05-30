import type { FileStateReader } from "../state/fileStateReader";

export async function renderQueueWidget(container: HTMLElement, reader: FileStateReader): Promise<void> {
  const summary = await reader.queueSummary();
  const card = container.createDiv({ cls: "spp-native-widget spp-native-card-queue" });
  card.createDiv({ cls: "spp-native-widget-kicker", text: "Queue" });
  card.createDiv({ cls: "spp-native-widget-title", text: "Prompt Bridge State" });

  const counts = card.createDiv({ cls: "spp-native-count-grid" });
  for (const lane of ["queued", "approved", "completed", "failed", "blocked"]) {
    const item = counts.createDiv({ cls: `spp-native-count spp-native-${lane}` });
    item.createSpan({ cls: "spp-native-count-label", text: lane.toUpperCase() });
    item.createSpan({ cls: "spp-native-count-value", text: String(summary.counts[lane] ?? 0) });
  }

  const latest = card.createDiv({ cls: "spp-native-state-list" });
  for (const lane of ["queued", "approved", "completed", "failed", "blocked"]) {
    const value = summary.latest[lane];
    const row = latest.createDiv({ cls: `spp-native-state-row ${value ? "spp-native-clickable" : "spp-native-empty"}` });
    row.createSpan({ cls: "spp-native-state-label", text: lane.toUpperCase() });
    row.createSpan({
      cls: "spp-native-state-value",
      text: value ?? emptyQueueText(lane),
    });
    if (value) row.addEventListener("click", () => void reader.openPath(value));
  }
}

function emptyQueueText(lane: string): string {
  if (lane === "approved") return "No approved prompt waiting";
  if (lane === "completed") return "No completed prompt captured";
  if (lane === "blocked") return "No blocked prompt";
  if (lane === "failed") return "No failed prompt";
  return "No queued prompt";
}
