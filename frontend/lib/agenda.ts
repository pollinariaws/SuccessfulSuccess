import { getAccessToken } from "@/lib/auth"
import type { AgendaSuggestion, ParsedAgenda } from "@/lib/types"

export const PARSER_URL = process.env.NEXT_PUBLIC_AGENDA_PARSER_URL ?? ""
export const MAX_CHARS = 10_000

export type AgendaErrorKind =
  | "too_long"
  | "no_agenda"
  | "busy"
  | "auth"
  | "network"
  | "aborted"
  | "other"

const MESSAGES: Record<AgendaErrorKind, string> = {
  too_long: `That text is longer than ${MAX_CHARS} characters.`,
  no_agenda: "I could not find an agenda in that text. You can fill the form in by hand.",
  busy: "The service is busy. Try again in a minute, or fill the form in by hand.",
  auth: "Your session has expired. Sign in again.",
  network: "Could not reach the parser. Fill the form in by hand.",
  aborted: "Cancelled.",
  other: "Something went wrong. Fill the form in by hand.",
}

export class AgendaError extends Error {
  readonly kind: AgendaErrorKind

  constructor(kind: AgendaErrorKind) {
    super(MESSAGES[kind])
    this.name = "AgendaError"
    this.kind = kind
  }
}

function localToday(): string {
  const now = new Date()
  const pad = (n: number) => String(n).padStart(2, "0")
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`
}

/** Asks the parser function for a suggested agenda. It never saves anything. */
export async function parseAgenda(text: string, signal: AbortSignal): Promise<AgendaSuggestion> {
  if (text.length > MAX_CHARS) throw new AgendaError("too_long")
  const token = await getAccessToken()
  if (!token) throw new AgendaError("auth")

  let response: Response
  try {
    response = await fetch(PARSER_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({
        text,
        today: localToday(),
        tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
      }),
      signal,
    })
  } catch (error) {
    const aborted = error instanceof DOMException && error.name === "AbortError"
    throw new AgendaError(aborted ? "aborted" : "network")
  }

  if (response.ok) return (await response.json()) as AgendaSuggestion
  if (response.status === 401) throw new AgendaError("auth")
  if (response.status === 413) throw new AgendaError("too_long")
  if (response.status === 422) throw new AgendaError("no_agenda")
  if (response.status === 503) throw new AgendaError("busy")
  throw new AgendaError("other")
}

/** "2026-11-02T10:00+02:00" or "2026-11-03" -> the calendar day, as written. */
export function wallClockDate(iso: string): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso)
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : null
}

export function addMinutes(hhmm: string, minutes: number): string {
  const [h, m] = hhmm.split(":").map(Number)
  const total = Math.min((h ?? 0) * 60 + (m ?? 0) + minutes, 23 * 60 + 59)
  const pad = (n: number) => String(n).padStart(2, "0")
  return `${pad(Math.floor(total / 60))}:${pad(total % 60)}`
}

/** The agenda items and action items, as plain text for the description field. */
export function describeAgenda(agenda: ParsedAgenda): string {
  const lines = agenda.items.map((item, i) => {
    const extra = [item.owner, item.minutes ? `${item.minutes} min` : null]
      .filter(Boolean)
      .join(", ")
    return `${i + 1}. ${item.topic}${extra ? ` (${extra})` : ""}`
  })
  if (agenda.action_items.length > 0) {
    lines.push("", "Action items:")
    for (const task of agenda.action_items) {
      const owner = task.owner ? ` (${task.owner})` : ""
      const due = task.due ? `, by ${task.due}` : ""
      lines.push(`- ${task.task}${owner}${due}`)
    }
  }
  return lines.join("\n").slice(0, 2000)
}

/** Everyone named as an owner, once each. An owner written as an email keeps it. */
export function participantsFrom(agenda: ParsedAgenda): { name: string; email: string }[] {
  const owners = [...agenda.items.map((i) => i.owner), ...agenda.action_items.map((a) => a.owner)]
  const seen = new Set<string>()
  const people: { name: string; email: string }[] = []
  for (const raw of owners) {
    const owner = raw?.trim()
    if (!owner || seen.has(owner.toLowerCase())) continue
    seen.add(owner.toLowerCase())
    people.push(
      owner.includes("@")
        ? { name: owner.split("@")[0] || owner, email: owner }
        : { name: owner, email: "" },
    )
  }
  return people.slice(0, 50)
}