import { Plugin, WorkspaceLeaf } from "obsidian";
import { SPPCommandCenterView, VIEW_TYPE_SPP_COMMAND_CENTER } from "./view";

export default class SPPCommandCenterPlugin extends Plugin {
  async onload(): Promise<void> {
    this.registerView(
      VIEW_TYPE_SPP_COMMAND_CENTER,
      (leaf: WorkspaceLeaf) => new SPPCommandCenterView(leaf, this)
    );

    this.addCommand({
      id: "open-spp-command-center",
      name: "Open SPP Command Center",
      callback: () => this.activatePrimaryView(),
    });

    this.addCommand({
      id: "open-spp-command-center-sidebar",
      name: "Open SPP Command Center in right sidebar",
      callback: () => this.activateSidebarView(),
    });

    this.addRibbonIcon("layout-dashboard", "Open SPP Command Center", () => {
      void this.activatePrimaryView();
    });
  }

  async onunload(): Promise<void> {
    this.app.workspace.detachLeavesOfType(VIEW_TYPE_SPP_COMMAND_CENTER);
  }

  async activatePrimaryView(): Promise<void> {
    const leaf = this.app.workspace.getLeaf(false);
    if (!leaf) return;

    await leaf.setViewState({
      type: VIEW_TYPE_SPP_COMMAND_CENTER,
      active: true,
    });
    this.app.workspace.revealLeaf(leaf);
  }

  async activateSidebarView(): Promise<void> {
    const existing = this.app.workspace.getLeavesOfType(VIEW_TYPE_SPP_COMMAND_CENTER)[0];
    const leaf = existing ?? this.app.workspace.getRightLeaf(false);
    if (!leaf) return;

    await leaf.setViewState({
      type: VIEW_TYPE_SPP_COMMAND_CENTER,
      active: true,
    });
    this.app.workspace.revealLeaf(leaf);
  }
}
