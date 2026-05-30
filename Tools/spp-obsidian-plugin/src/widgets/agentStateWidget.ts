import type { FileStateReader } from "../state/fileStateReader";

export async function renderAgentStateWidget(container: HTMLElement, reader: FileStateReader): Promise<void> {
  const card = container.createDiv({ cls: "spp-native-widget spp-native-card-agents" });
  card.createDiv({ cls: "spp-native-widget-kicker", text: "Agents" });
  card.createDiv({ cls: "spp-native-widget-title", text: "Ownership / Lanes" });

  const codex = await reader.exists("30_AI_Coordination/Codex Command Center.md");
  const claude = await reader.exists("30_AI_Coordination/Claude Command Center.md");
  const lanes = await reader.exists("30_AI_Coordination/Swarm Work Lanes.md");

  const grid = card.createDiv({ cls: "spp-native-agent-grid" });
  renderAgent(grid, "CODEX", codex ? "review / supervise" : "missing", codex);
  renderAgent(grid, "CLAUDE", claude ? "build / verify" : "missing", claude);
  renderAgent(grid, "LANES", lanes ? "declared" : "undeclared", lanes);
}

function renderAgent(container: HTMLElement, label: string, value: string, ok: boolean): void {
  const item = container.createDiv({ cls: `spp-native-agent ${ok ? "" : "spp-native-empty"}` });
  item.createDiv({ cls: "spp-native-agent-label", text: label });
  item.createDiv({ cls: "spp-native-agent-value", text: value });
}
