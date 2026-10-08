"use client"

import { signInWithRedirect } from "aws-amplify/auth"
import { useRouter } from "next/navigation"
import { useEffect, useRef } from "react"

import { useAuth } from "@/components/auth-provider"
import { configureAuth } from "@/lib/auth"

// Starts the login in the browser and hands over to Cognito's managed login,
// which shows the email + password form and "Continue with Google" together.
export default function LoginPage() {
  const { status } = useAuth()
  const router = useRouter()
  const started = useRef(false)

  useEffect(() => {
    if (status === "signedIn") {
      router.replace("/today/")
      return
    }
    if (status !== "signedOut" || started.current) return
    started.current = true
    configureAuth()
    void signInWithRedirect()
  }, [status, router])

  return <p className="p-8 text-center text-muted-foreground">Redirecting to sign-in…</p>
}