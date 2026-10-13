"use client"

import { useState } from "react"
import { Send } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"

type Message = {
  role: "user" | "agent"
  text: string
  tools?: string[]
  sql?: string[]
}

const SAMPLES = [
  "進行中の商談のうち、見込みランクがAの商談の見込み金額合計を支社別に円で教えて",
  "KDDIの訪問準備をして",
  "GLTDの引受条件を教えて",
]

export function AgentChat() {
  const [messages, setMessages] = useState<Message[]>([])
  const [input, setInput] = useState("")
  const [loading, setLoading] = useState(false)

  async function send(text: string) {
    if (!text.trim() || loading) return
    setMessages((m) => [...m, { role: "user", text }])
    setInput("")
    setLoading(true)
    try {
      const res = await fetch("/api/agent", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: text }),
      })
      const json = await res.json()
      setMessages((m) => [
        ...m,
        json.error
          ? { role: "agent", text: json.error }
          : { role: "agent", text: json.answer, tools: json.tools, sql: json.sql },
      ])
    } catch {
      setMessages((m) => [...m, { role: "agent", text: "通信に失敗しました" }])
    } finally {
      setLoading(false)
    }
  }

  return (
    <Card className="max-w-3xl mx-auto">
      <CardHeader>
        <CardTitle>法人営業アシスタント</CardTitle>
        <CardDescription>
          Cortex Agent（SALES_AGENT）に質問します。回答には1分ほどかかります。
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap gap-2">
          {SAMPLES.map((s) => (
            <Button key={s} variant="outline" size="sm" onClick={() => send(s)} disabled={loading}>
              {s}
            </Button>
          ))}
        </div>

        <div className="space-y-3">
          {messages.map((m, i) => (
            <div
              key={i}
              className={m.role === "user" ? "rounded-md bg-muted p-3" : "rounded-md border p-3"}
            >
              <p className="whitespace-pre-wrap text-sm">{m.text}</p>
              {m.tools && m.tools.length > 0 && (
                <div className="mt-2 flex gap-1">
                  {m.tools.map((t, j) => (
                    <Badge key={j} variant="secondary">{t}</Badge>
                  ))}
                </div>
              )}
              {m.sql && m.sql.length > 0 && (
                <details className="mt-2">
                  <summary className="cursor-pointer text-xs text-muted-foreground">
                    実行された SQL を見る
                  </summary>
                  {m.sql.map((q, j) => (
                    <pre key={j} className="mt-1 overflow-x-auto rounded bg-muted p-2 text-xs">{q}</pre>
                  ))}
                </details>
              )}
            </div>
          ))}
          {loading && <p className="text-sm text-muted-foreground">Agent が考えています…</p>}
        </div>

        <form
          className="flex gap-2"
          onSubmit={(e) => {
            e.preventDefault()
            send(input)
          }}
        >
          <input
            className="flex-1 rounded-md border bg-background px-3 py-2 text-sm"
            placeholder="質問を入力"
            value={input}
            onChange={(e) => setInput(e.target.value)}
          />
          <Button type="submit" disabled={loading} aria-label="送信">
            <Send className="h-4 w-4" />
          </Button>
        </form>
      </CardContent>
    </Card>
  )
}
