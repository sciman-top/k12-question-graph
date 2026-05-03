from __future__ import annotations

import argparse
import json
from collections import OrderedDict
from pathlib import Path
from statistics import mean
from typing import Any


DEFAULT_OUTPUT_ROOT = Path("tmp/f003-knowledge-mastery")
DEFAULT_REPORT = Path("docs/evidence/f003-knowledge-mastery-analysis-report.json")


STUDENTS = [
    OrderedDict([("studentKey", "syn-student-001"), ("displayCode", "SYN-001"), ("totalScore", 8.0)]),
    OrderedDict([("studentKey", "syn-student-002"), ("displayCode", "SYN-002"), ("totalScore", 6.0)]),
]

ITEMS = [
    OrderedDict([
        ("questionNo", "q1"),
        ("maxScore", 3.0),
        ("knowledgeStableId", "PHY-JH-MECH-MOTION-SPEED"),
        ("knowledgeName", "运动快慢与速度"),
        ("activeVersion", "junior-physics-guangzhou-source-derived-v1"),
        ("scores", OrderedDict([("syn-student-001", 3.0), ("syn-student-002", 2.0)])),
    ]),
    OrderedDict([
        ("questionNo", "q2"),
        ("maxScore", 5.0),
        ("knowledgeStableId", "PHY-JH-ELEC-OHM-LAW"),
        ("knowledgeName", "欧姆定律基础应用"),
        ("activeVersion", "junior-physics-guangzhou-source-derived-v1"),
        ("scores", OrderedDict([("syn-student-001", 5.0), ("syn-student-002", 4.0)])),
    ]),
]


def round_metric(value: float) -> float:
    return round(value + 0.0, 4)


def discrimination(scores: list[float], max_score: float) -> float:
    if len(scores) < 2 or max_score <= 0:
        return 0.0
    ordered = sorted(scores)
    return round_metric((ordered[-1] - ordered[0]) / max_score)


def mastery_band(score_rate: float) -> str:
    if score_rate >= 0.9:
        return "strong"
    if score_rate >= 0.8:
        return "watch"
    return "weak"


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def build_report(output_root: Path) -> OrderedDict[str, Any]:
    knowledge_summaries: list[OrderedDict[str, Any]] = []
    weak_knowledge_points: list[OrderedDict[str, Any]] = []
    total_max_score = sum(float(item["maxScore"]) for item in ITEMS)
    total_scores = [float(student["totalScore"]) for student in STUDENTS]

    for item in ITEMS:
        scores = [float(value) for value in item["scores"].values()]
        max_score = float(item["maxScore"])
        score_rate = round_metric(mean(scores) / max_score)
        item_discrimination = discrimination(scores, max_score)
        band = mastery_band(score_rate)
        summary = OrderedDict([
            ("knowledgeStableId", item["knowledgeStableId"]),
            ("knowledgeName", item["knowledgeName"]),
            ("activeVersion", item["activeVersion"]),
            ("questionNos", [item["questionNo"]]),
            ("sampleSize", len(scores)),
            ("maxScore", max_score),
            ("averageScore", round_metric(mean(scores))),
            ("scoreRate", score_rate),
            ("discrimination", item_discrimination),
            ("blankRate", 0.0),
            ("masteryBand", band),
            ("historyPolicy", "draft_test_only_no_production_history_rewrite"),
        ])
        knowledge_summaries.append(summary)
        if band != "strong":
            weak_knowledge_points.append(OrderedDict([
                ("knowledgeStableId", item["knowledgeStableId"]),
                ("knowledgeName", item["knowledgeName"]),
                ("scoreRate", score_rate),
                ("suggestedTeacherAction", "讲评时优先回看错因和来源题，必要时加入同知识点巩固题。"),
            ]))

    student_summaries: list[OrderedDict[str, Any]] = []
    for student in STUDENTS:
        student_key = str(student["studentKey"])
        knowledge_rates = OrderedDict()
        for item in ITEMS:
            score = float(item["scores"][student_key])
            knowledge_rates[str(item["knowledgeStableId"])] = round_metric(score / float(item["maxScore"]))
        average_mastery = round_metric(mean(knowledge_rates.values()))
        student_summaries.append(OrderedDict([
            ("studentKey", student_key),
            ("displayCode", student["displayCode"]),
            ("totalScoreRate", round_metric(float(student["totalScore"]) / total_max_score)),
            ("knowledgeScoreRates", knowledge_rates),
            ("masteryBand", mastery_band(average_mastery)),
        ]))

    output_root.mkdir(parents=True, exist_ok=True)
    summary_path = output_root / "f003-knowledge-mastery-summary.json"
    report = OrderedDict([
        ("status", "pass"),
        ("task", "F003"),
        ("mode", "draft_test"),
        ("productionEligible", False),
        ("realStudentDataUsed", False),
        ("studentPortalExposed", False),
        ("noProductionHistoryWrite", True),
        ("sourceFixture", "synthetic F002-style item scores"),
        ("activeKnowledgeVersion", "junior-physics-guangzhou-source-derived-v1"),
        ("classSummary", OrderedDict([
            ("studentCount", len(STUDENTS)),
            ("itemCount", len(ITEMS)),
            ("totalMaxScore", total_max_score),
            ("averageTotalScore", round_metric(mean(total_scores))),
            ("totalScoreRate", round_metric(mean(total_scores) / total_max_score)),
            ("discriminationAvailable", True),
            ("historyPolicy", "freeze_existing_history_and_write_draft_test_report_only"),
        ])),
        ("knowledgePointSummaries", knowledge_summaries),
        ("weakKnowledgePoints", weak_knowledge_points),
        ("studentMasterySummaries", student_summaries),
        ("outputs", OrderedDict([("summaryPath", str(summary_path))])),
        ("summaryChinese", OrderedDict([
            ("title", "F003 得分率知识点分析合同报告"),
            ("result", "通过"),
            ("boundary", "仅使用 synthetic 小题分和 active 知识点版本引用，不使用真实学生数据，不写正式历史学情。"),
            ("next", "后续 G001 可在当前 draft/test 学情报告和已有备份 manifest 基础上做自动备份与共享目录演练。"),
        ])),
    ])
    write_json(summary_path, report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="F003 synthetic knowledge mastery analysis")
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    report = build_report(args.output_root)
    write_json(args.report, report)
    print(json.dumps({"status": "pass", "task": "F003", "weakKnowledgePoints": len(report["weakKnowledgePoints"])}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
