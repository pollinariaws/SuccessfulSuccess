"use client"

import { zodResolver } from "@hookform/resolvers/zod"
import { CalendarIcon } from "lucide-react"
import { useEffect, useState } from "react"
import { Controller, useForm } from "react-hook-form"
import { toast } from "sonner"
import { z } from "zod"

import { AgendaPaste } from "@/components/agenda-paste"
import { ParticipantsInput } from "@/components/participants-input"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Calendar } from "@/components/ui/calendar"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Textarea } from "@/components/ui/textarea"
import { useCreateMeeting, useUpdateMeeting } from "@/hooks/use-meetings"
import { ApiError } from "@/lib/api"
import {
  PARSER_URL,
  addMinutes,
  describeAgenda,
  participantsFrom,
  wallClockDate,
} from "@/lib/agenda"
import { formatTime, parseIsoDay, toIsoDate, toIsoWithOffset } from "@/lib/datetime"
import type { AgendaSuggestion, Meeting } from "@/lib/types"

const timePattern = /^([01]\d|2[0-3]):([0-5]\d)$/

const participantSchema = z.object({
  name: z.string().trim().min(1, "Name is required").max(120, "Name is too long"),
  email: z
    .string()
    .trim()
    .max(255)
    .refine((value) => value === "" || z.email().safeParse(value).success, {
      message: "Enter a valid email address",
    })
    .optional(),
})

const formSchema = z
  .object({
    name: z.string().trim().min(1, "Name is required").max(200, "Name is too long"),
    description: z.string().trim().max(2000, "Description is too long").optional(),
    location: z.string().trim().max(200, "Location is too long").optional(),
    date: z.date(),
    startTime: z.string().regex(timePattern, "Use HH:mm"),
    endTime: z.string().regex(timePattern, "Use HH:mm"),
    participants: z.array(participantSchema).max(50, "At most 50 participants"),
  })
  .refine((data) => data.endTime > data.startTime, {
    message: "The meeting must end after it starts",
    path: ["endTime"],
  })
  .refine(
    (data) => {
      const keys = data.participants.map(
        (p) => `${p.name.trim().toLowerCase()}|${(p.email ?? "").trim().toLowerCase()}`,
      )
      return new Set(keys).size === keys.length
    },
    { message: "Participants must be unique", path: ["participants"] },
  )

type FormValues = z.infer<typeof formSchema>

type ParticipantErrors = { name?: { message?: string }; email?: { message?: string } }

type SuggestedField = "name" | "description" | "date" | "startTime" | "endTime" | "participants"

function Suggested() {
  return (
    <Badge variant="secondary" className="ml-2">
      suggested
    </Badge>
  )
}

/** Flattens react-hook-form's per-row participant errors into { rowIndex: message }. */
function participantErrors(
  rows: unknown,
): Record<number, string | undefined> {
  if (!Array.isArray(rows)) return {}
  return Object.fromEntries(
    rows.map((row: ParticipantErrors | undefined, index: number) => [
      index,
      row?.name?.message ?? row?.email?.message,
    ]),
  )
}

/** Blank form for a new meeting, or the meeting's current values when editing. */
function defaultValues(meeting?: Meeting): FormValues {
  if (!meeting) {
    return {
      name: "",
      description: "",
      location: "",
      date: new Date(),
      startTime: "10:00",
      endTime: "11:00",
      participants: [{ name: "", email: "" }],
    }
  }
  return {
    name: meeting.name,
    description: meeting.description ?? "",
    location: meeting.location ?? "",
    date: parseIsoDay(meeting.starts_at),
    startTime: formatTime(meeting.starts_at),
    endTime: formatTime(meeting.ends_at),
    participants:
      meeting.participants.length > 0
        ? meeting.participants.map((p) => ({ name: p.name, email: p.email ?? "" }))
        : [{ name: "", email: "" }],
  }
}

/** Creates a meeting, or edits `meeting` when one is passed. */
export function MeetingFormDialog({
  open,
  onOpenChange,
  meeting,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  meeting?: Meeting
}) {
  const createMeeting = useCreateMeeting()
  const updateMeeting = useUpdateMeeting()
  const [datePickerOpen, setDatePickerOpen] = useState(false)
  const [suggestion, setSuggestion] = useState<AgendaSuggestion | null>(null)
  const [suggested, setSuggested] = useState<Set<SuggestedField>>(new Set())
  const isEdit = !!meeting

  const form = useForm<FormValues>({
    resolver: zodResolver(formSchema),
    defaultValues: defaultValues(meeting),
  })

  const {
    register,
    handleSubmit,
    control,
    reset,
    setError,
    setValue,
    formState: { errors, isSubmitting },
  } = form

  // Refill the form each time it opens, so edits start from the meeting's current values.
  useEffect(() => {
    if (open) reset(defaultValues(meeting))
  }, [open, meeting, reset])

  // A field stops being "suggested" as soon as the person touches it.
  const unmark = (field: SuggestedField) =>
    setSuggested((prev) => {
      if (!prev.has(field)) return prev
      const next = new Set(prev)
      next.delete(field)
      return next
    })

  const handleOpenChange = (next: boolean) => {
    if (!next) {
      setSuggestion(null)
      setSuggested(new Set())
    }
    onOpenChange(next)
  }

  function applySuggestion(result: AgendaSuggestion) {
    const agenda = result.agenda
    const filled = new Set<SuggestedField>()
    const options = { shouldDirty: true, shouldValidate: true }

    if (agenda.title) {
      setValue("name", agenda.title, options)
      filled.add("name")
    }
    const description = describeAgenda(agenda)
    if (description) {
      setValue("description", description, options)
      filled.add("description")
    }
    const day = agenda.starts_at ? wallClockDate(agenda.starts_at) : null
    if (day) {
      setValue("date", day, options)
      filled.add("date")
    }
    // The clock time is taken as the person wrote it, without a UTC offset.
    const start =
      agenda.starts_at && agenda.starts_at.length > 10 ? agenda.starts_at.slice(11, 16) : null
    if (start) {
      setValue("startTime", start, options)
      filled.add("startTime")
      setValue("endTime", addMinutes(start, agenda.duration_minutes ?? 60), options)
      if (agenda.duration_minutes) filled.add("endTime")
    }
    const people = participantsFrom(agenda)
    if (people.length > 0) {
      setValue("participants", people, options)
      filled.add("participants")
    }
    setSuggestion(result)
    setSuggested(filled)
  }

  const onSubmit = handleSubmit(async (values) => {
    const participants = values.participants
      .filter((participant) => participant.name.trim() !== "")
      .map((participant) => ({
        name: participant.name.trim(),
        email: participant.email?.trim() ? participant.email.trim() : null,
      }))

    const payload = {
      name: values.name.trim(),
      description: values.description?.trim() || null,
      location: values.location?.trim() || null,
      starts_at: toIsoWithOffset(values.date, values.startTime),
      ends_at: toIsoWithOffset(values.date, values.endTime),
      participants,
      ...(suggestion && !meeting ? { ai_suggestion: suggestion } : {}),
    }

    try {
      if (meeting) {
        await updateMeeting.mutateAsync({ id: meeting.id, payload })
        toast.success("Meeting updated")
      } else {
        await createMeeting.mutateAsync(payload)
        toast.success("Meeting created")
      }
      handleOpenChange(false)
    } catch (error) {
      if (error instanceof ApiError) {
        // Map server-side field errors back onto the matching inputs.
        const fieldMap: Record<string, keyof FormValues> = {
          name: "name",
          description: "description",
          location: "location",
          starts_at: "startTime",
          ends_at: "endTime",
          participants: "participants",
        }
        for (const detail of error.details) {
          const target = fieldMap[detail.field.split(".")[0] ?? ""]
          if (target) setError(target, { message: detail.message })
        }
        toast.error(error.message)
      } else {
        toast.error(isEdit ? "Could not update the meeting." : "Could not create the meeting.")
      }
    }
  })

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="max-h-[90svh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{isEdit ? "Edit meeting" : "New meeting"}</DialogTitle>
          <DialogDescription>
            {isEdit
              ? "Change the details, time slot or participants."
              : "Give it a name, a time slot and the people who should be there."}
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={onSubmit} className="space-y-4">
          {!isEdit && PARSER_URL ? <AgendaPaste onParsed={applySuggestion} /> : null}

          <div className="space-y-2">
            <Label htmlFor="name">
              Name
              {suggested.has("name") ? <Suggested /> : null}
            </Label>
            <Input
              id="name"
              placeholder="Sprint planning"
              aria-invalid={!!errors.name}
              aria-describedby={errors.name ? "name-error" : undefined}
              {...register("name", { onChange: () => unmark("name") })}
            />
            {errors.name ? (
              <p id="name-error" className="text-destructive text-sm">
                {errors.name.message}
              </p>
            ) : null}
          </div>

          <div className="space-y-2">
            <Label htmlFor="description">
              Description
              {suggested.has("description") ? <Suggested /> : null}
            </Label>
            <Textarea
              id="description"
              rows={3}
              placeholder="What is this meeting about?"
              {...register("description", { onChange: () => unmark("description") })}
            />
            {errors.description ? (
              <p className="text-destructive text-sm">{errors.description.message}</p>
            ) : null}
          </div>

          <div className="space-y-2">
            <Label htmlFor="location">Location</Label>
            <Input id="location" placeholder="Room 3 or a meeting link" {...register("location")} />
          </div>

          <div className="grid gap-4 sm:grid-cols-3">
            <div className="space-y-2 sm:col-span-1">
              <Label>
                Date
                {suggested.has("date") ? <Suggested /> : null}
              </Label>
              <Controller
                control={control}
                name="date"
                render={({ field }) => (
                  <Popover open={datePickerOpen} onOpenChange={setDatePickerOpen}>
                    <PopoverTrigger asChild>
                      <Button
                        type="button"
                        variant="outline"
                        className="w-full justify-start font-normal"
                      >
                        <CalendarIcon className="size-4" aria-hidden />
                        {toIsoDate(field.value)}
                      </Button>
                    </PopoverTrigger>
                    <PopoverContent className="w-auto p-0" align="start">
                      <Calendar
                        mode="single"
                        selected={field.value}
                        onSelect={(date) => {
                          if (date) field.onChange(date)
                          unmark("date")
                          setDatePickerOpen(false)
                        }}
                        autoFocus
                      />
                    </PopoverContent>
                  </Popover>
                )}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="startTime">
                Start
                {suggested.has("startTime") ? <Suggested /> : null}
              </Label>
              <Input
                id="startTime"
                type="time"
                step={900}
                {...register("startTime", { onChange: () => unmark("startTime") })}
              />
              {errors.startTime ? (
                <p className="text-destructive text-sm">{errors.startTime.message}</p>
              ) : null}
            </div>

            <div className="space-y-2">
              <Label htmlFor="endTime">
                End
                {suggested.has("endTime") ? <Suggested /> : null}
              </Label>
              <Input
                id="endTime"
                type="time"
                step={900}
                {...register("endTime", { onChange: () => unmark("endTime") })}
              />
              {errors.endTime ? (
                <p className="text-destructive text-sm">{errors.endTime.message}</p>
              ) : null}
            </div>
          </div>

          {suggested.has("participants") ? (
            <p className="text-muted-foreground text-sm">
              Participants <Suggested />
            </p>
          ) : null}
          <Controller
            control={control}
            name="participants"
            render={({ field }) => (
              <ParticipantsInput
                value={field.value}
                onChange={(next) => {
                  field.onChange(next)
                  unmark("participants")
                }}
                errors={participantErrors(errors.participants)}
              />
            )}
          />
          {errors.participants?.message ? (
            <p className="text-destructive text-sm">{errors.participants.message}</p>
          ) : null}

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={isSubmitting}>
              {isEdit
                ? isSubmitting
                  ? "Saving…"
                  : "Save changes"
                : isSubmitting
                  ? "Creating…"
                  : "Create meeting"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}