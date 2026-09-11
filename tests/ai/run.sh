#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
task_dir=$(mktemp -d "${TMPDIR:-/tmp}/loreweave-ai-test.XXXXXX")
trap 'rm -rf "$task_dir"' EXIT
xcrun swiftc -parse-as-library \
  Loreweave/Services/AI/Models/AICLIType.swift \
  Loreweave/Services/AI/Models/AIMessage.swift \
  Loreweave/Services/AI/Models/AIConnectionState.swift \
  Loreweave/Services/AI/CLI/CLIDetector.swift \
  Loreweave/Services/AI/Auth/ChatGPTAccountService.swift \
  Loreweave/Services/AI/CLI/CLIProcessManager.swift \
  Loreweave/Services/AI/Chat/ChatHistoryManager.swift \
  Loreweave/Services/AI/Prompt/AIPromptTemplateManager.swift \
  Loreweave/Views/MainEditor/AIAssistant/AIAssistantViewModel.swift \
  tests/ai/Regression.swift -o "$task_dir/regression"
"$task_dir/regression"
