import { querySnowflakeLongRunning } from "@/lib/snowflake"

export const dynamic = "force-dynamic"

// 前回のハンズオンで作った Agent B（意味づけあり + 業務スキル）
const AGENT = "SNOWLIFE_HANDSON_DB.AI.SALES_AGENT"

// Agent の回答には 1 分以上かかることがある。デプロイ先の入口は約 90 秒で接続を切るため、
// 1 回のリクエストで待たずに「受付（POST）→ 結果の確認（GET）」の 2 段階にしている。
// アプリは 1 インスタンスで動くので、受付中の質問はサーバーのメモリに置く。
type AgentResult = { answer: string; tools: string[]; sql: string[] }
type Job =
  | { status: "running"; startedAt: number }
  | { status: "done"; startedAt: number; result: AgentResult }
  | { status: "error"; startedAt: number; error: string }

const JOB_TTL_MS = 15 * 60 * 1000
const globalForJobs = globalThis as unknown as { agentJobs?: Map<string, Job> }
const jobs = (globalForJobs.agentJobs ??= new Map<string, Job>())

type AgentTable = {
  title?: string
  result_set?: {
    data?: (string | null)[][]
    resultSetMetaData?: { rowType?: { name?: string; type?: string }[] }
  }
}

type ContentItem = {
  type?: string
  text?: string
  table?: AgentTable
  tool_use?: { name?: string }
  tool_result?: { name?: string; content?: { json?: { sql?: string } }[] }
}

// Agent が返す表（type: "table"）を、チャットにそのまま表示できる文字の表にする
function tableToText(table?: AgentTable): string {
  const cols = table?.result_set?.resultSetMetaData?.rowType ?? []
  const rows = table?.result_set?.data ?? []
  if (cols.length === 0) return ""
  const cell = (v: string | null, i: number) =>
    v == null ? "" : cols[i]?.type === "fixed" && v !== "" && !isNaN(Number(v)) ? Number(v).toLocaleString("ja-JP") : v
  const line = (vals: string[]) => `| ${vals.join(" | ")} |`
  return [
    "",
    table?.title ? `【${table.title}】` : "",
    line(cols.map((c) => c.name ?? "")),
    ...rows.map((r) => line(r.map(cell))),
    "",
  ].join("\n")
}

async function runAgent(message: string): Promise<AgentResult> {
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

  // ツール呼び出しの合間や回答直前のつぶやき（"Run queries in parallel." など）を除くため、
  // 最後のツール呼び出し・思考より後にあるテキストと表だけを、順番どおりにつないで回答にする
  const lastStepIndex = content.reduce(
    (last, c, i) =>
      c.type === "tool_use" || c.type === "tool_result" || c.type === "thinking" ? i : last,
    -1,
  )
  const toText = (c: ContentItem) =>
    c.type === "text" ? (c.text ?? "") : c.type === "table" ? tableToText(c.table) : ""
  const answer =
    content.slice(lastStepIndex + 1).map(toText).join("") ||
    content.filter((c) => c.type === "text").map(toText).join("")
  const tools = content
    .filter((c) => c.type === "tool_use")
    .map((c) => c.tool_use?.name)
    .filter((t): t is string => Boolean(t))
  const sql = content
    .filter((c) => c.type === "tool_result")
    .flatMap((c) => c.tool_result?.content ?? [])
    .map((r) => r.json?.sql)
    .filter((s): s is string => Boolean(s))

  return { answer, tools, sql }
}

function removeOldJobs() {
  const now = Date.now()
  for (const [id, job] of jobs) {
    if (now - job.startedAt > JOB_TTL_MS) jobs.delete(id)
  }
}

// 質問を受け付けて、受付番号（jobId）をすぐに返す
export async function POST(req: Request) {
  const { message } = (await req.json().catch(() => ({}))) as { message?: string }
  if (!message || !message.trim()) {
    return Response.json({ error: "質問を入力してください" }, { status: 400 })
  }

  removeOldJobs()
  const jobId = crypto.randomUUID()
  const startedAt = Date.now()
  jobs.set(jobId, { status: "running", startedAt })

  runAgent(message)
    .then((result) => jobs.set(jobId, { status: "done", startedAt, result }))
    .catch((e) => {
      console.error("Agent route error:", e)
      jobs.set(jobId, { status: "error", startedAt, error: "Agent の呼び出しに失敗しました" })
    })

  return Response.json({ jobId }, { status: 202 })
}

// 受付番号の結果を返す。終わっていなければ { status: "running" }
export async function GET(req: Request) {
  const jobId = new URL(req.url).searchParams.get("jobId") ?? ""
  const job = jobs.get(jobId)
  if (!job) {
    return Response.json(
      { status: "error", error: "質問が見つかりません。もう一度送ってください" },
      { status: 404 },
    )
  }
  if (job.status === "running") {
    return Response.json({ status: "running" })
  }
  jobs.delete(jobId)
  return job.status === "done"
    ? Response.json({ status: "done", ...job.result })
    : Response.json({ status: "error", error: job.error }, { status: 500 })
}
