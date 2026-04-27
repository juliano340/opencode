import { useDialog } from "@tui/ui/dialog"
import { useSDK } from "@tui/context/sdk"
import { useSync } from "@tui/context/sync"
import { DialogPrompt } from "@tui/ui/dialog-prompt"
import { useTheme } from "@tui/context/theme"
import { useToast } from "@tui/ui/toast"

function maskKey(key: string): string {
  if (!key) return ""
  if (key.length <= 12) return "***"
  return key.slice(0, 7) + "•••••••••••" + key.slice(-4)
}

export function DialogVoice() {
  const dialog = useDialog()
  const sdk = useSDK()
  const sync = useSync()
  const { theme } = useTheme()
  const toast = useToast()

  const savedKey = sync.data.config.voice?.groq_api_key ?? process.env.GROQ_API_KEY ?? ""
  const masked = maskKey(savedKey)

  return (
    <DialogPrompt
      title="Voice — Groq API Key"
      placeholder={masked ? "Enter new key to replace..." : "gsk_..."}
      description={
        <box gap={1}>
          <text fg={theme.textMuted}>Groq provides free Whisper transcription. Get your key at:</text>
          <text fg={theme.primary}>https://console.groq.com</text>
          {masked ? (
            <box flexDirection="row" gap={1}>
              <text fg={theme.textMuted}>Current key:</text>
              <text fg={theme.warning}>{masked}</text>
            </box>
          ) : undefined}
        </box>
      }
      onConfirm={(value) => {
        const key = value.trim()
        // If blank and a key already exists, just close
        if (!key && savedKey) {
          dialog.clear()
          return
        }
        if (!key) return
        // Available immediately in current session
        process.env.GROQ_API_KEY = key
        // Persist to config for future sessions
        fetch(`${sdk.url}/config`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ voice: { groq_api_key: key } }),
        }).catch(() => {
          toast.show({ message: "Voice: failed to persist key to config", variant: "error" })
        })
        dialog.clear()
      }}
    />
  )
}
