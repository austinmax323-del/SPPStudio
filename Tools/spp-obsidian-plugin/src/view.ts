import { ItemView, WorkspaceLeaf } from "obsidian";
import type SPPCommandCenterPlugin from "./main";
import { FileStateReader } from "./state/fileStateReader";
import { renderAgentStateWidget } from "./widgets/agentStateWidget";
import { renderModeTrustWidget } from "./widgets/modeTrustWidget";
import { renderQueueWidget } from "./widgets/queueWidget";
import { renderVerificationWidget } from "./widgets/verificationWidget";
import { renderWatchdogWidget } from "./widgets/watchdogWidget";

export const VIEW_TYPE_SPP_COMMAND_CENTER = "spp-command-center-view";

export class SPPCommandCenterView extends ItemView {
  private readonly plugin: SPPCommandCenterPlugin;
  private readonly reader: FileStateReader;

  constructor(leaf: WorkspaceLeaf, plugin: SPPCommandCenterPlugin) {
    super(leaf);
    this.plugin = plugin;
    this.reader = new FileStateReader(plugin.app);
  }

  getViewType(): string {
    return VIEW_TYPE_SPP_COMMAND_CENTER;
  }

  getDisplayText(): string {
    return "SPP Command Center";
  }

  getIcon(): string {
    return "layout-dashboard";
  }

  async onOpen(): Promise<void> {
    await this.render();
  }

  async render(): Promise<void> {
    const root = this.contentEl;
    root.empty();
    root.addClass("spp-native-cockpit");
    const renderedAt = new Date();
    const queue = await this.reader.queueSummary();
    const hasFailure = (queue.counts.failed ?? 0) > 0 || (queue.counts.blocked ?? 0) > 0;

    const header = root.createDiv({ cls: "spp-native-header" });
    const identity = header.createDiv({ cls: "spp-native-identity" });
    identity.createDiv({ cls: "spp-native-title", text: "SPP Command Center" });
    identity.createDiv({ cls: "spp-native-subtitle", text: "Read-only cockpit · manual refresh · note navigation only" });
    const refresh = header.createEl("button", { cls: "spp-native-refresh", text: "Refresh" });
    refresh.addEventListener("click", () => void this.render());

    this.renderTopStrip(root.createDiv({ cls: "spp-native-status-strip" }), queue, hasFailure, renderedAt);

    const shell = root.createDiv({ cls: "spp-native-shell" });
    this.renderRail(shell.createDiv({ cls: "spp-native-rail" }));

    const workspace = shell.createDiv({ cls: "spp-native-workspace" });
    const primary = workspace.createDiv({ cls: "spp-native-primary" });
    this.renderOperationsPanel(primary.createDiv({ cls: "spp-native-mission" }), queue, hasFailure);
    await renderQueueWidget(primary, this.reader);
    await renderWatchdogWidget(primary, this.reader);

    const context = workspace.createDiv({ cls: "spp-native-context" });
    await renderModeTrustWidget(context, this.reader);
    await renderAgentStateWidget(context, this.reader);
    await renderVerificationWidget(context, this.reader);
    this.renderRecoveryPanel(context.createDiv({ cls: "spp-native-widget spp-native-card-recovery" }));
  }

  private renderRail(container: HTMLElement): void {
    container.createDiv({ cls: "spp-native-rail-title", text: "NAV" });
    const links = [
      ["GUI", "00_CommandCenter/GUI Command Center.md"],
      ["MISSION", "00_CommandCenter/Orchestration Cockpit.md"],
      ["CODEX", "30_AI_Coordination/Codex Command Center.md"],
      ["CLAUDE", "30_AI_Coordination/Claude Command Center.md"],
      ["QUEUE", "40_PromptEngineering/PromptBridge/Bridge Status.md"],
      ["WATCHDOG", "40_PromptEngineering/PromptBridge/Watchdog/README.md"],
      ["RECOVER", "70_SessionContinuity/Tactical Recovery.md"],
    ];

    for (const [label, path] of links) {
      const button = container.createEl("button", { cls: "spp-native-nav", text: label });
      button.addEventListener("click", () => void this.reader.openPath(path));
    }
  }

  private renderTopStrip(container: HTMLElement, queue: Awaited<ReturnType<FileStateReader["queueSummary"]>>, hasFailure: boolean, renderedAt: Date): void {
    this.renderStatus(container, "MODE", "FULL AUTO", "spp-native-warn");
    this.renderStatus(container, "TRUST", "SAFE", "spp-native-safe");
    this.renderStatus(container, "QUEUE", `${queue.counts.queued ?? 0}Q / ${queue.counts.approved ?? 0}A`, "spp-native-neutral");
    this.renderStatus(container, "RISK", hasFailure ? "REVIEW" : "LOW", hasFailure ? "spp-native-warn" : "spp-native-safe");
    this.renderStatus(container, "VERIFY", "MANUAL", "spp-native-neutral");
    this.renderStatus(container, "LAST REFRESH", renderedAt.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" }), "spp-native-neutral");
  }

  private renderStatus(container: HTMLElement, label: string, value: string, stateClass: string): void {
    const chip = container.createDiv({ cls: `spp-native-status ${stateClass}` });
    chip.createSpan({ cls: "spp-native-status-label", text: label });
    chip.createSpan({ cls: "spp-native-status-value", text: value });
  }

  private renderOperationsPanel(container: HTMLElement, queue: Awaited<ReturnType<FileStateReader["queueSummary"]>>, hasFailure: boolean): void {
    container.createDiv({ cls: "spp-native-widget-kicker", text: "Operations" });
    container.createDiv({ cls: "spp-native-mission-title", text: hasFailure ? "Review queue failure before next run" : "Read state, then choose one manual action" });
    const actions = container.createDiv({ cls: "spp-native-action-grid" });
    this.renderAction(actions, "NEXT", queue.latest.queued ?? "No queued prompt waiting", queue.latest.queued ? "spp-native-neutral" : "spp-native-empty", queue.latest.queued);
    this.renderAction(actions, "APPROVAL", queue.latest.approved ?? "No approved prompt waiting", queue.latest.approved ? "spp-native-safe" : "spp-native-empty", queue.latest.approved);
    this.renderAction(actions, "STOP", hasFailure ? "Failed/blocked lane needs review" : "Locked systems remain off limits", hasFailure ? "spp-native-warn" : "spp-native-stop");
  }

  private renderAction(container: HTMLElement, label: string, value: string, stateClass: string, path?: string | null): void {
    const item = container.createDiv({ cls: `spp-native-action ${stateClass} ${path ? "spp-native-clickable" : ""}` });
    item.createDiv({ cls: "spp-native-action-label", text: label });
    item.createDiv({ cls: "spp-native-action-value", text: value });
    if (path) item.addEventListener("click", () => void this.reader.openPath(path));
  }

  private renderRecoveryPanel(container: HTMLElement): void {
    container.createDiv({ cls: "spp-native-widget-kicker", text: "Recovery" });
    container.createDiv({ cls: "spp-native-widget-title", text: "Operator Re-entry" });
    const list = container.createDiv({ cls: "spp-native-state-list" });
    const rows = [
      ["RECOVER", "Open Tactical Recovery"],
      ["BRIDGE", "Check Bridge Status"],
      ["OUTPUT", "Review latest capture"],
    ];
    for (const [label, value] of rows) {
      const row = list.createDiv({ cls: "spp-native-state-row" });
      row.createSpan({ cls: "spp-native-state-label", text: label });
      row.createSpan({ cls: "spp-native-state-value", text: value });
    }
  }
}
