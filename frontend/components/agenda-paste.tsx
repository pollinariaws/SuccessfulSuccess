"use client"

import { Loader2, Sparkles } from "lucide-react"
import { useRef, useState } from "react"

import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { AgendaError, MAX_CHARS, parseAgenda } from "@/lib/agenda"
import type { AgendaSuggestion } from "@/lib/types"

/** Paste text, get a suggestion. The buttons are type="button": they must not submit the form. */
export function AgendaPaste({ onParsed }: { onParsed: (suggestion: AgendaSuggestion) => void }) {
  const [text, setText] = useState("")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const controller = useRef<AbortController | null>(null)

  async function run() {
    setError(null)
    setBusy(true)
    const current = new AbortController()
    controller.current = current
    try {
      onParsed(await parseAgenda(text, current.signal))
    } catch (e) {
      if (!(e instanceof AgendaError && e.kind === "aborted")) {
        setError(e instanceof AgendaError ? e.message : "Something went wrong.")
      }
    } finally {
      setBusy(false)
      controller.current = null
    }
  }

  return (
    <div className="space-y-2 rounded-2xl border border-dashed p-3">
      <Label htmlFor="paste-agenda" className="flex items-center gap-2">
        <Sparkles className="size-4" aria-hidden />
        Paste an agenda
      </Label>
      <Textarea
        id="paste-agenda"
        rows={4}
        value={text}
        onChange={(event) => setText(event.target.value)}
        placeholder="An email, a chat message or a few lines of notes…"
        disabled={busy}
      />
      <div className="flex items-center gap-2">
        <Button
          type="button"
          size="sm"
          onClick={() => void run()}
          disabled={busy || text.trim() === "" || text.length > MAX_CHARS}
        >
          Parse
        </Button>
        {busy ? (
          <>
            <Loader2 className="size-4 animate-spin" aria-hidden />
            <span className="text-muted-foreground text-sm">Reading your text… (2–8 s)</span>
            <Button
              type="button"
              size="sm"
              variant="ghost"
              onClick={() => controller.current?.abort()}
            >
              Cancel
            </Button>
          </>
        ) : null}
        {text.length > MAX_CHARS ? (
          <span className="text-destructive text-sm">
            Too long ({text.length}/{MAX_CHARS})
          </span>
        ) : null}
      </div>
      {error ? <p className="text-destructive text-sm">{error}</p> : null}
      <p className="text-muted-foreground text-xs">
        The suggestion fills the form below. Check it, fix what is wrong, then save.
      </p>
    </div>
  )
}