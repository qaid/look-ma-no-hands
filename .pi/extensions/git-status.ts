/**
 * git-status -- Show uncommitted file count in the Pi status bar
 *
 * Runs `git status --porcelain` after every LLM turn and on session start.
 * Shows nothing when the working tree is clean; shows "✎ N uncommitted"
 * when there are modified or untracked files. Silently clears if the cwd
 * is not a git repo or git is unavailable.
 *
 * Usage: pi -e extensions/git-status.ts
 */

import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  async function updateGitStatus(_event: unknown, ctx: ExtensionContext) {
    if (!ctx.hasUI) return;
    try {
      const result = await pi.exec("git", ["status", "--porcelain"], {
        cwd: ctx.cwd,
        timeout: 3000,
      });
      const lines = result.stdout
        .split("\n")
        .filter((l: string) => l.trim().length > 0);
      const count = lines.length;
      if (count === 0) {
        ctx.ui.setStatus("git-dirty", "");
      } else {
        ctx.ui.setStatus("git-dirty", `✎ ${count} uncommitted`);
      }
    } catch {
      // not a git repo or git not available -- clear silently
      ctx.ui.setStatus("git-dirty", "");
    }
  }

  pi.on("session_start", updateGitStatus);
  pi.on("turn_end", updateGitStatus);
}
