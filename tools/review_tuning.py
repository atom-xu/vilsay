#!/usr/bin/env python3
"""
Vilsay 调优结果人工复查工具

用法：
    python3 tools/review_tuning.py [报告JSON路径]

默认读取最新的报告文件。逐条展示 LLM 评分结果，你输入：
    1 = 同意（LLM 评分正确）
    2 = 不同意（LLM 评分有问题）
    s = 跳过
    q = 退出并保存

完成后生成人工复查报告。
"""

import json
import os
import sys
import glob
from datetime import datetime


def find_latest_report():
    """查找最新的 JSON 报告文件"""
    patterns = [
        os.path.expanduser("~/Desktop/VilsayTuningReports/*.json"),
        os.path.expanduser("~/Desktop/Vilsay/reports/*.json"),
    ]
    files = []
    for p in patterns:
        files.extend(glob.glob(p))
    if not files:
        return None
    return max(files, key=os.path.getmtime)


def colorize(text, color):
    """终端颜色"""
    colors = {
        "red": "\033[91m",
        "green": "\033[92m",
        "yellow": "\033[93m",
        "blue": "\033[94m",
        "cyan": "\033[96m",
        "bold": "\033[1m",
        "dim": "\033[2m",
        "reset": "\033[0m",
    }
    return f"{colors.get(color, '')}{text}{colors['reset']}"


def score_bar(score, max_score=5):
    """可视化分数条"""
    filled = int(score)
    bar = "█" * filled + "░" * (max_score - filled)
    if score >= 4.5:
        return colorize(bar, "green")
    elif score >= 3.0:
        return colorize(bar, "yellow")
    else:
        return colorize(bar, "red")


def dim_score(label, value, max_val=5):
    """带颜色的单维度分数"""
    if value >= 4:
        color = "green"
    elif value >= 3:
        color = "yellow"
    else:
        color = "red"
    return f"{label}={colorize(str(value), color)}"


def main():
    # 找报告文件
    if len(sys.argv) > 1:
        report_path = sys.argv[1]
    else:
        report_path = find_latest_report()

    if not report_path or not os.path.exists(report_path):
        print("❌ 未找到报告文件。用法: python3 review_tuning.py [报告.json]")
        print("   报告通常在 ~/Desktop/VilsayTuningReports/ 下")
        sys.exit(1)

    with open(report_path, "r") as f:
        report = json.load(f)

    results = report["results"]
    variant = report.get("variant", "unknown")
    total = len(results)

    print()
    print(colorize("═" * 60, "bold"))
    print(colorize(f"  Vilsay 调优结果人工复查", "bold"))
    print(colorize(f"  版本: {variant}  |  用例数: {total}", "dim"))
    print(colorize(f"  报告: {os.path.basename(report_path)}", "dim"))
    print(colorize("═" * 60, "bold"))
    print()
    print("  操作说明:")
    print(f"    {colorize('1', 'green')} = 同意 LLM 评分（正确）")
    print(f"    {colorize('2', 'red')} = 不同意（评分有问题）")
    print(f"    {colorize('s', 'yellow')} = 跳过")
    print(f"    {colorize('q', 'dim')} = 退出并保存")
    print(f"    {colorize('n', 'dim')} = 添加备注")
    print()

    reviews = []  # {"caseID", "agree", "note", ...}
    agree_count = 0
    disagree_count = 0
    skip_count = 0

    for i, r in enumerate(results):
        case_id = r["caseID"]
        score = r["weightedScore"]
        inp = r["input"]
        out = r["output"]
        commentary = r["commentary"]

        print(colorize(f"━━━ [{i+1}/{total}] {case_id} ━━━", "bold"))
        print()
        print(f"  {colorize('输入:', 'cyan')} {inp[:120]}")
        if len(inp) > 120:
            print(f"        {inp[120:240]}")
        print()
        print(f"  {colorize('输出:', 'cyan')} {out[:120]}")
        if len(out) > 120:
            print(f"        {out[120:240]}")
        print()

        # 分数
        dims = [
            dim_score("忠实", r["faithfulness"]),
            dim_score("干预", r["minimalEdit"]),
            dim_score("风格", r["styleMatch"]),
            dim_score("流畅", r["fluency"]),
            dim_score("格式", r["formatting"]),
        ]
        print(f"  {score_bar(score)} {colorize(f'{score:.1f}', 'bold')}/5  {' '.join(dims)}")
        print(f"  {colorize('评语:', 'dim')} {commentary}")
        print()

        while True:
            try:
                choice = input(f"  你的判断 [1=同意 2=不同意 s=跳过 q=退出]: ").strip().lower()
            except (EOFError, KeyboardInterrupt):
                choice = "q"

            if choice == "1":
                agree_count += 1
                review = {"caseID": case_id, "agree": True, "score": score}
                reviews.append(review)
                print(f"  → {colorize('✓ 同意', 'green')}")
                break
            elif choice == "2":
                disagree_count += 1
                note = input(f"  备注（为何不同意，回车跳过）: ").strip()
                review = {"caseID": case_id, "agree": False, "score": score, "note": note}
                reviews.append(review)
                print(f"  → {colorize('✗ 不同意', 'red')} {note if note else ''}")
                break
            elif choice == "s":
                skip_count += 1
                reviews.append({"caseID": case_id, "agree": None, "score": score})
                print(f"  → {colorize('- 跳过', 'yellow')}")
                break
            elif choice == "q":
                break
            else:
                print("  请输入 1、2、s 或 q")

        print()

        if choice == "q":
            break

    # 保存结果
    reviewed = agree_count + disagree_count
    accuracy = (agree_count / reviewed * 100) if reviewed > 0 else 0

    print()
    print(colorize("═" * 60, "bold"))
    print(colorize("  复查结果汇总", "bold"))
    print(colorize("═" * 60, "bold"))
    print(f"  已复查: {reviewed}/{total}")
    print(f"  同意:   {colorize(str(agree_count), 'green')} ({accuracy:.0f}%)")
    print(f"  不同意: {colorize(str(disagree_count), 'red')}")
    print(f"  跳过:   {colorize(str(skip_count), 'yellow')}")

    # LLM Judge 准确率
    if reviewed > 0:
        print()
        if accuracy >= 90:
            print(f"  {colorize('→ LLM Judge 准确率良好', 'green')}")
        elif accuracy >= 70:
            print(f"  {colorize('→ LLM Judge 准确率一般，需关注不同意项', 'yellow')}")
        else:
            print(f"  {colorize('→ LLM Judge 准确率偏低，需调整评估 prompt', 'red')}")

    # 列出不同意项
    disagreed = [r for r in reviews if r.get("agree") is False]
    if disagreed:
        print()
        print(colorize("  需关注的用例:", "red"))
        for d in disagreed:
            note = d.get("note", "")
            print(f"    - {d['caseID']} (LLM给分{d['score']:.1f}) {note}")

    # 保存到文件
    output = {
        "variant": variant,
        "reviewedAt": datetime.now().isoformat(),
        "sourceReport": os.path.basename(report_path),
        "summary": {
            "total": total,
            "reviewed": reviewed,
            "agreed": agree_count,
            "disagreed": disagree_count,
            "skipped": skip_count,
            "judgeAccuracy": round(accuracy, 1),
        },
        "reviews": reviews,
        "disagreedCases": disagreed,
    }

    out_dir = os.path.dirname(report_path)
    out_name = f"human_review_{variant}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    out_path = os.path.join(out_dir, out_name)
    with open(out_path, "w") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    print()
    print(f"  {colorize('已保存:', 'dim')} {out_path}")
    print()


if __name__ == "__main__":
    main()
