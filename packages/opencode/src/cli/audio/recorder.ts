import { tmpdir } from "os"
import { join } from "path"
import { unlink } from "fs/promises"

export type VoiceHandle = {
  stop: () => Promise<string>
  abort: () => void
}

async function findFfmpeg(): Promise<string> {
  // Try PATH first — check exit code, not just spawn success
  try {
    const proc = Bun.spawn(["ffmpeg", "-version"], { stdin: "ignore", stdout: "ignore", stderr: "ignore" })
    const code = await proc.exited
    if (code === 0) return "ffmpeg"
  } catch {}

  // Common install locations per platform
  const candidates =
    process.platform === "win32"
      ? [
          join(process.env.USERPROFILE ?? "", "scoop", "shims", "ffmpeg.exe"),
          "C:\\ProgramData\\chocolatey\\bin\\ffmpeg.exe",
          "C:\\ffmpeg\\bin\\ffmpeg.exe",
        ]
      : process.platform === "darwin"
        ? ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        : ["/usr/bin/ffmpeg", "/usr/local/bin/ffmpeg"]

  for (const p of candidates) {
    if (await Bun.file(p).exists()) return p
  }

  const hint =
    process.platform === "win32"
      ? "scoop install ffmpeg"
      : process.platform === "darwin"
        ? "brew install ffmpeg"
        : "sudo apt install ffmpeg"

  throw new Error(`ffmpeg not found. Install it with: ${hint}`)
}

async function getWindowsAudioDevice(ffmpeg: string): Promise<string> {
  const proc = Bun.spawn([ffmpeg, "-list_devices", "true", "-f", "dshow", "-i", "dummy"], {
    stdin: "ignore",
    stdout: "ignore",
    stderr: "pipe",
  })
  const stderr = await new Response(proc.stderr).text()
  await proc.exited
  // Format: "Device Name" (audio)
  const match = stderr.match(/"([^"]+)"\s*\(audio\)/)
  if (!match) throw new Error("No audio input device found. Run: ffmpeg -list_devices true -f dshow -i dummy")
  return match[1]
}

function buildArgs(device: string | undefined, outPath: string): string[] {
  if (process.platform === "win32") return ["-y", "-f", "dshow", "-i", `audio=${device}`, "-ar", "16000", "-ac", "1", "-f", "wav", outPath]
  if (process.platform === "darwin") return ["-y", "-f", "avfoundation", "-i", ":0", "-ar", "16000", "-ac", "1", outPath]
  return ["-y", "-f", "alsa", "-i", "default", "-ar", "16000", "-ac", "1", outPath]
}

export async function startRecording(apiKey?: string): Promise<VoiceHandle> {
  const outPath = join(tmpdir(), `opencode-voice-${Date.now()}.wav`)
  const ffmpeg = await findFfmpeg()
  const device = process.platform === "win32" ? await getWindowsAudioDevice(ffmpeg) : undefined

  const proc = Bun.spawn([ffmpeg, ...buildArgs(device, outPath)], {
    stdin: "pipe",
    stdout: "ignore",
    stderr: "ignore",
  })

  return {
    stop: async () => {
      proc.stdin.write("q\n")
      proc.stdin.end()
      await proc.exited
      try {
        return await transcribe(outPath, apiKey)
      } finally {
        await unlink(outPath).catch(() => {})
      }
    },
    abort: () => {
      proc.kill()
      unlink(outPath).catch(() => {})
    },
  }
}

async function transcribe(filePath: string, apiKey?: string): Promise<string> {
  const key = apiKey ?? process.env.GROQ_API_KEY
  if (!key) throw new Error("Groq API key not configured. Press Alt+V to configure.")

  const bytes = await Bun.file(filePath).arrayBuffer()
  const formData = new FormData()
  formData.append("file", new File([bytes], "audio.wav", { type: "audio/wav" }))
  formData.append("model", "whisper-large-v3-turbo")

  const res = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}` },
    body: formData,
  })

  if (!res.ok) throw new Error(`Groq Whisper error: ${res.status}`)
  const { text } = (await res.json()) as { text: string }
  return text.trim()
}
