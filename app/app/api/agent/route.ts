import { querySnowflakeLongRunning } from "@/lib/snowflake"

export const dynamic = "force-dynamic"

// 前回のハンズオンで作った Agent B（意味づけあり + 業務スキル）
const AGENT = "SNOWLIFE_HANDSON_DB.AI.SALES_AGENT"

type ContentItem = {
  type?: string
  text?: string
  tool_use?: { name?: string }
  tool_result?: { name?: string; content?: { json?: { sql?: string } }[] }
}

export async function POST(req: Request) {
  try {
    const { message } = (await req.json()) as { message?: string }
    if (!message || !message.trim()) {
      return Response.json({ error: "質問を入力してください" }, { status: 400 })
    }

    const body = JSON.stringify({
      messages: [{ role: "user", content: [{ type: "text", text: message }] }],
      stream: false,
    })

    // Agent の実行は1分前後かかるため、非同期実行 + ポーリングの関数を使う
    const rows = await querySnowflakeLongRunning(
      "SELECT TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?)) AS RESPONSE",
      { binds: [AGENT, body] },
    )

    const raw = rows[0]?.RESPONSE
    const response = typeof raw === "string" ? JSON.parse(raw) : raw
    const content: ContentItem[] = response?.content ?? []

    // ツール呼び出しの合間のつぶやき（"Run queries in parallel." など）を除くため、
    // 最後のツール呼び出しより後のテキストだけを回答として使う
    const lastToolIndex = content.reduce(
      (last, c, i) => (c.type === "tool_use" || c.type === "tool_result" ? i : last),
      -1,
    )
    const textAfter = (from: number) =>
      content
        .slice(from)
        .filter((c) => c.type === "text")
        .map((c) => c.text ?? "")
        .join("")
    const answer = textAfter(lastToolIndex + 1) || textAfter(0)
    const tools = content
      .filter((c) => c.type === "tool_use")
      .map((c) => c.tool_use?.name)
      .filter(Boolean)
    const sql = content
      .filter((c) => c.type === "tool_result")
      .flatMap((c) => c.tool_result?.content ?? [])
      .map((r) => r.json?.sql)
      .filter(Boolean)

    return Response.json({ answer, tools, sql })
  } catch (e) {
    console.error("Agent route error:", e)
    return Response.json({ error: "Agent の呼び出しに失敗しました" }, { status: 500 })
  }
}
