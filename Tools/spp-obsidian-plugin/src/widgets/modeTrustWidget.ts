import type { FileStateReader } from "../state/fileStateReader";

export async function renderModeTrustWidget(container: HTMLElement, reader: FileStateReader): Promise<void> {
  const card = container.createDiv({ cls: "spp-native-widget spp-native-card-mode" });
  card.createDiv({ cls: "spp-native-widget-kicker", text: "Operations" });
  card.createDiv({ cls: "spp-native-widget-title", text: "Mode / Trust Zone" });

  const fullAuto = await reader.exists("30_AI_Coordination/Full Auto Mode Protocol.md");
  const trustZones = await reader.exists("30_AI_Coordination/Trust Zones.md");
  const router = await reader.exists("30_AI_Coordination/Mode Router.md");

  const chips = card.createDiv({ cls: "spp-native-chip-row" });
  chips.createSpan({ cls: "spp-native-chip spp-native-safe", text: "SAFE" });
  chips.createSpan({ cls: "spp-native-chip spp-native-warn", text: "SEMI-TRUSTED" });
  chips.createSpan({ cls: "spp-native-chip spp-native-stop", text: "LOCKED" });

  const list = card.createDiv({ cls: "spp-native-state-list" });
  renderState(list, "FULL AUTO", fullAuto ? "bounded docs present" : "missing", fullAuto);
  renderState(list, "TRUST ZONES", trustZones ? "present" : "missing", trustZones);
  renderState(list, "MODE ROUTER", router ? "present" : "missing", router);
}

function renderState(container: HTMLElement, label: string, value: string, ok: boolean): void {
  const row = container.createDiv({ cls: `spp-native-state-row ${ok ? "" : "spp-native-empty"}` });
  row.createSpan({ cls: "spp-native-state-label", text: label });
  row.createSpan({ cls: "spp-native-state-value", text: value });
}
