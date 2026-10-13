"""sql/ 以下のファイルを catchup.sql に 1 本にまとめる。

使い方: python3 tools/build_catchup.py
sql/ を直したら、このスクリプトを実行して catchup.sql を作り直してください。
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARTS = [
    ("01_setup.sql", "データ基盤（CRM・PDF・Cortex Search・営業職員ロール）"),
    ("02_semantic_view.sql", "セマンティックビュー AI.SV_SALES_ANALYTICS"),
    ("03_agents.sql", "Cortex Agent（SALES_AGENT / SALES_AGENT_BASIC）"),
    ("04_skills.sql", "Agent の業務スキル 3 件"),
    ("05_app.sql", "アプリの置き場所（APP スキーマ）"),
]

HEADER = """/*
================================================================================
スノー生命 法人営業 AI アプリ ハンズオン - 環境の一括構築（catchup.sql）
================================================================================
前回のハンズオン（snowlife-corporate-sales-handson）の Part 1〜4 の到達点を
まとめて作ります。setup_win.bat / setup_mac.command が自動で実行します。

  {parts}

【前提条件】ACCOUNTADMIN ロール / AI 機能が有効なアカウント
【所要時間】約 5 分
【再実行】何度実行しても同じ状態になります

このファイルは tools/build_catchup.py で生成しています。直接編集せず、sql/ を直してください。
================================================================================
*/
"""

FOOTER = """

-- ============================================================================
-- 完了
-- ============================================================================

SELECT '
 環境の構築が完了しました
  - データ        : SNOWLIFE_HANDSON_DB（RAW / MART / AI / SECURITY / APP）
  - Cortex Agent  : SNOWLIFE_HANDSON_DB.AI.SALES_AGENT
  - アプリの置き場: SNOWLIFE_HANDSON_DB.APP
' AS "セットアップ完了";
"""


def main() -> None:
    listing = "\n  ".join(f"{i}. {desc}（sql/{name}）" for i, (name, desc) in enumerate(PARTS, 1))
    chunks = [HEADER.format(parts=listing)]
    for name, desc in PARTS:
        body = (ROOT / "sql" / name).read_text(encoding="utf-8").strip()
        bar = "#" * 80
        chunks.append(f"\n\n-- {bar}\n-- sql/{name}: {desc}\n-- {bar}\n\n{body}\n")
    chunks.append(FOOTER)
    out = ROOT / "catchup.sql"
    out.write_text("".join(chunks), encoding="utf-8")
    print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
