import type { FileStateReader } from "../state/fileStateReader";

export async function renderVerificationWidget(container: HTMLElement, reader: FileStateReader): Promise<void> {
  const card = container.createDiv({ cls: "spp-native-widget spp-native-card-verify" });
  card.createDiv({ cls: "spp-native-widget-kicker", text: "Verification" });
  card.createDiv({ cls: "spp-native-widget-title", text: "Manual Proof" });

  const verificationFlows = await reader.exists("60_DeliveryValidation/VerificationFlows/README.md");
  const latestArtifact = await reader.latestMarkdown(["60_DeliveryValidation/VerificationArtifacts"]);
  const list = card.createDiv({ cls: "spp-native-state-list" });

  const flows = list.createDiv({ cls: `spp-native-state-row ${verificationFlows ? "" : "spp-native-empty"}` });
  flows.createSpan({ cls: "spp-native-state-label", text: "FLOWS" });
  flows.createSpan({ cls: "spp-native-state-value", text: verificationFlows ? "Verification flows present" : "Missing verification flows" });

  const artifacts = list.createDiv({ cls: `spp-native-state-row ${latestArtifact ? "spp-native-clickable" : "spp-native-empty"}` });
  artifacts.createSpan({ cls: "spp-native-state-label", text: "ARTIFACT" });
  artifacts.createSpan({ cls: "spp-native-state-value", text: latestArtifact ?? "No verification artifact surfaced" });
  if (latestArtifact) artifacts.addEventListener("click", () => void reader.openPath(latestArtifact));

  card.createDiv({ cls: "spp-native-readonly-note", text: "Read-only panel. Run doctor/build manually outside this plugin." });
}
