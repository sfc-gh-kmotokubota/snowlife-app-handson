"""Plan B: Snowsight の Workspaces で動かす、Cortex Agent のチャットアプリ（参考実装）

当日 CoCo in Snowsight がうまく作れなかったときの「答え」です。
- コンテナランタイムで動かしてください（ウェアハウスランタイムからは Cortex Agent を呼べません）
- Agent は SQL 関数 SNOWFLAKE.CORTEX.DATA_AGENT_RUN をバインド変数で呼び出します
"""

import json

import pandas as pd
import streamlit as st

AGENT = "SNOWLIFE_HANDSON_DB.AI.SALES_AGENT"
SAMPLES = [
    "進行中の商談のうち、見込みランクがAの商談の見込み金額合計を支社別に円で教えて",
    "KDDIの訪問準備をして",
    "GLTDの引受条件を教えて",
]

st.set_page_config(page_title="スノー生命 法人営業アシスタント", layout="wide")
session = st.connection("snowflake").session()


def ask_agent(question: str) -> dict:
    """Agent に質問し、回答の文章・表・使ったツール・SQL を返す"""
    body = json.dumps(
        {"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}], "stream": False},
        ensure_ascii=False,
    )
    row = session.sql(
        "SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?) AS RESPONSE", params=[AGENT, body]
    ).collect()[0]
    content = json.loads(row["RESPONSE"]).get("content", [])

    # ツール呼び出し・思考の合間のつぶやきを除くため、最後のツール呼び出し・思考より後だけを回答にする
    last_step = max(
        (i for i, c in enumerate(content) if c.get("type") in ("tool_use", "tool_result", "thinking")),
        default=-1,
    )
    parts = []
    for c in content[last_step + 1 :]:
        if c.get("type") == "text":
            parts.append(("text", c.get("text", "")))
        elif c.get("type") == "table":
            table = c.get("table", {})
            rs = table.get("result_set", {})
            cols = [col.get("name") for col in rs.get("resultSetMetaData", {}).get("rowType", [])]
            parts.append(("table", (table.get("title", ""), pd.DataFrame(rs.get("data", []), columns=cols))))
    if not parts:
        parts = [("text", "".join(c.get("text", "") for c in content if c.get("type") == "text"))]

    tools = [c["tool_use"].get("name") for c in content if c.get("type") == "tool_use"]
    sqls = [
        r["json"]["sql"]
        for c in content
        if c.get("type") == "tool_result"
        for r in c["tool_result"].get("content", [])
        if r.get("json", {}).get("sql")
    ]
    return {"parts": parts, "tools": tools, "sql": sqls}


def show_answer(answer: dict) -> None:
    for kind, value in answer["parts"]:
        if kind == "text":
            st.markdown(value)
        else:
            title, df = value
            if title:
                st.caption(title)
            st.dataframe(df, hide_index=True)
    if answer["tools"]:
        st.caption("使ったツール: " + "、".join(answer["tools"]))
    if answer["sql"]:
        with st.expander("実行された SQL を見る"):
            for q in answer["sql"]:
                st.code(q, language="sql")


st.title("スノー生命 法人営業アシスタント")
st.caption("Cortex Agent（SALES_AGENT）に質問します。回答には 1 分ほどかかります。")

if "messages" not in st.session_state:
    st.session_state.messages = []

cols = st.columns(len(SAMPLES))
clicked = None
for col, sample in zip(cols, SAMPLES):
    if col.button(sample, use_container_width=True):
        clicked = sample

for m in st.session_state.messages:
    with st.chat_message(m["role"]):
        if m["role"] == "user":
            st.markdown(m["text"])
        else:
            show_answer(m["answer"])

question = st.chat_input("質問を入力") or clicked
if question:
    st.session_state.messages.append({"role": "user", "text": question})
    with st.chat_message("user"):
        st.markdown(question)
    with st.chat_message("assistant"):
        with st.spinner("Agent が考えています…"):
            try:
                answer = ask_agent(question)
            except Exception as e:  # noqa: BLE001 - 画面にエラー内容を出して参加者が CoCo に貼れるようにする
                answer = {"parts": [("text", f"Agent の呼び出しに失敗しました: {e}")], "tools": [], "sql": []}
        show_answer(answer)
    st.session_state.messages.append({"role": "assistant", "answer": answer})
