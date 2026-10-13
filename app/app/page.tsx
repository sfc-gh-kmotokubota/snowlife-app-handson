import { AgentChat } from "@/components/agent-chat"

// Required: Snowflake is not reachable during docker build.
export const dynamic = "force-dynamic"

export default function Home() {
  return (
    <main className="w-full py-12 px-4">
      <AgentChat />
    </main>
  )
}
