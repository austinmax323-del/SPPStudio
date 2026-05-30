import { App, TFile, TFolder, normalizePath } from "obsidian";

export interface QueueSummary {
  counts: Record<string, number>;
  latest: Record<string, string | null>;
}

const QUEUE_ROOT = "40_PromptEngineering/PromptBridge/Queue";

export class FileStateReader {
  constructor(private readonly app: App) {}

  async queueSummary(): Promise<QueueSummary> {
    const lanes = ["queued", "approved", "completed", "failed", "blocked"];
    const counts: Record<string, number> = {};
    const latest: Record<string, string | null> = {};

    for (const lane of lanes) {
      const files = await this.listMarkdown(`${QUEUE_ROOT}/${lane}`);
      counts[lane] = files.length;
      latest[lane] = files[0] ?? null;
    }

    return { counts, latest };
  }

  async latestMarkdown(paths: string[]): Promise<string | null> {
    const files: TFile[] = [];
    for (const path of paths) {
      const folder = this.app.vault.getFolderByPath(normalizePath(path));
      if (!folder) continue;
      this.collectMarkdown(folder, files);
    }

    files.sort((a, b) => b.stat.mtime - a.stat.mtime);
    return files[0]?.path ?? null;
  }

  async exists(path: string): Promise<boolean> {
    return this.app.vault.getAbstractFileByPath(normalizePath(path)) !== null;
  }

  async openPath(path: string): Promise<void> {
    const file = this.app.vault.getAbstractFileByPath(normalizePath(path));
    if (file instanceof TFile) {
      await this.app.workspace.getLeaf(false).openFile(file);
    }
  }

  private async listMarkdown(path: string): Promise<string[]> {
    const folder = this.app.vault.getFolderByPath(normalizePath(path));
    if (!folder) return [];

    return folder.children
      .filter((child): child is TFile => child instanceof TFile && child.extension === "md" && child.name !== "README.md")
      .sort((a, b) => b.stat.mtime - a.stat.mtime)
      .map((file) => file.path);
  }

  private collectMarkdown(folder: TFolder, files: TFile[]): void {
    for (const child of folder.children) {
      if (child instanceof TFile && child.extension === "md" && child.name !== "README.md") {
        files.push(child);
      } else if (child instanceof TFolder) {
        this.collectMarkdown(child, files);
      }
    }
  }
}
