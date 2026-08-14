import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as vscode from "vscode";

const COMMAND_ID = "opencode.open";
const TERMINAL_NAME = "OpenCode";
const OPEN_LABEL = "OpenCode에서 열기";

export function activate(context: vscode.ExtensionContext): void {
  context.subscriptions.push(
    vscode.commands.registerCommand(COMMAND_ID, async (resource?: vscode.Uri) => {
      try {
        await openInOpenCode(resource);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        void vscode.window.showErrorMessage(message);
      }
    })
  );

  const statusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Left,
    100
  );
  statusBarItem.text = `$(terminal) ${OPEN_LABEL}`;
  statusBarItem.tooltip = OPEN_LABEL;
  statusBarItem.command = COMMAND_ID;
  statusBarItem.show();
  context.subscriptions.push(statusBarItem);
}

export function deactivate(): void {}

async function openInOpenCode(resource?: vscode.Uri): Promise<void> {
  const targetDir = await resolveTargetDirectory(resource);
  if (!targetDir) {
    return;
  }

  const attachPath = getAttachScriptPath();
  if (!fs.existsSync(attachPath)) {
    throw new Error(
      "OpenCode attach 래퍼가 없습니다. install-opencode-server 스크립트를 먼저 실행하세요."
    );
  }

  const terminal = vscode.window.createTerminal(
    buildTerminalOptions(targetDir, attachPath)
  );
  terminal.show(true);
}

async function resolveTargetDirectory(
  resource?: vscode.Uri
): Promise<string | undefined> {
  if (resource?.scheme === "file") {
    const stat = await vscode.workspace.fs.stat(resource);
    if (stat.type & vscode.FileType.Directory) {
      return resource.fsPath;
    }
    return path.dirname(resource.fsPath);
  }

  const folders = vscode.workspace.workspaceFolders;
  if (!folders || folders.length === 0) {
    throw new Error("폴더를 연 다음 OpenCode에서 열어 주세요.");
  }

  if (folders.length === 1) {
    return folders[0].uri.fsPath;
  }

  const activeUri = vscode.window.activeTextEditor?.document.uri;
  if (activeUri) {
    const folder = vscode.workspace.getWorkspaceFolder(activeUri);
    if (folder) {
      return folder.uri.fsPath;
    }
  }

  const picked = await vscode.window.showWorkspaceFolderPick({
    placeHolder: "OpenCode에서 열 폴더를 선택하세요.",
  });
  return picked?.uri.fsPath;
}

function getAttachScriptPath(): string {
  if (process.platform === "win32") {
    const localAppData = process.env.LOCALAPPDATA;
    if (!localAppData) {
      throw new Error("LOCALAPPDATA 환경 변수가 없습니다.");
    }
    return path.join(localAppData, "OpenCode", "bin", "opencode-attach.ps1");
  }

  return path.join(os.homedir(), ".local", "bin", "opencode-attach");
}

function buildTerminalOptions(
  targetDir: string,
  attachPath: string
): vscode.TerminalOptions {
  const common: vscode.TerminalOptions = {
    name: TERMINAL_NAME,
    cwd: targetDir,
    iconPath: new vscode.ThemeIcon("terminal"),
    isTransient: true,
  };

  if (process.platform === "win32") {
    const powerShell = path.join(
      process.env.SystemRoot || "C:\\Windows",
      "System32",
      "WindowsPowerShell",
      "v1.0",
      "powershell.exe"
    );
    return {
      ...common,
      shellPath: powerShell,
      shellArgs: [
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        attachPath,
        "-Dir",
        targetDir,
      ],
    };
  }

  return {
    ...common,
    shellPath: attachPath,
    shellArgs: [targetDir],
  };
}
