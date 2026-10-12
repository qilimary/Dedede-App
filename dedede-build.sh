#!/usr/bin/env bash
# Dedede Android build: restore the audited upstream source (immutable git revision)
# and apply strictly bounded corrections before running the normal build.
# This is a single-file GitHub Actions replacement for dedede-build.sh.
set -euo pipefail
BASE_REPO="qilimary/Dedede-App"
BASE_COMMIT="10baa0cb64edc2dcb8add1ac46b22ab234398ff4"
BASE_BLOB_SHA="0e75582a69ad2789c30c11c65827d39f3edf3169"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
BASE_SCRIPT="$WORK_DIR/dedede-build.sh"

# Only for local/CI testing: point to an already downloaded exact source.
if [[ -n "${DEDEDE_BUILD_SOURCE_OVERRIDE:-}" ]]; then
  cp -- "$DEDEDE_BUILD_SOURCE_OVERRIDE" "$BASE_SCRIPT"
else
  curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 \
    "https://raw.githubusercontent.com/${BASE_REPO}/${BASE_COMMIT}/dedede-build.sh" \
    --output "$BASE_SCRIPT"
fi
if [[ -z "${DEDEDE_BUILD_SOURCE_OVERRIDE:-}" ]]; then
  observed_sha="$(git hash-object --no-filters "$BASE_SCRIPT")"
  if [[ "$observed_sha" != "$BASE_BLOB_SHA" ]]; then
    echo "源构建文件的 SHA 校验失败，已中止构建。" >&2
    exit 1
  fi
fi

python3 - "$BASE_SCRIPT" <<'DEDEDE_PATCH_EMBEDDED_PY'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Apply conservative Chinese text correction rules to Dedede Android build source.

Run from the qilimary/Dedede-App repository root:
    python patch_dedede_android.py

Edits only dedede-build.sh. No runtime/model/dictionary dependencies are added.
The script checks upstream anchors, runs built-in positive/negative tests, and
writes a .bak backup before modifying. Re-running is idempotent.
"""
from __future__ import annotations
import json
import re
from pathlib import Path
import sys

TARGET = Path(sys.argv[1])

# Independent, conservative adaptations of conditional patterns in LanguageTool's
# Chinese grammar.xml. We use the existing Android Java regex correction engine.
# (name, Java regex, replacement for capture group 1, replacement for group 3,
#  positive examples, negative examples)
RULES = [
    (
        "二＋限定普通量词",
        r"(?<![第零〇一二两三四五六七八九十百千万亿0-9A-Za-z])(二)()((?:个(?=孩子|人|苹果|问题|办法|包子))|(?:本(?=书|小说|教材|杂志|漫画|字典))|(?:部(?=电影|电视剧|小说|作品))|(?:辆(?=车|汽车|自行车|卡车|轿车))|(?:只(?=猫|狗|鸟|鸡|鸭|鹅|兔子))|(?:张(?=桌子|纸|照片|车票|门票))|(?:台(?=电脑|电视|机器|设备)))",
        "两", None,
        ["二本书", "我买了二只猫", "二辆汽车", "二张照片", "二台电脑", "二个孩子"],
        ["第二本书", "二本大学", "二斤苹果", "二十个人", "二次函数", "一二本书"],
    ),
    (
        "二三＋普通数量单位",
        r"(?<![第零〇一二两三四五六七八九十百千万亿0-9A-Za-z])(二)()(三)(?=个|只|本|位|人|辆|台|条|件|次|天|周|小时|分钟|岁|公里|千米|米|斤|公斤|元)",
        "两", None,
        ["二三天", "去二三次", "有二三个人"],
        ["二三十岁", "第二三章", "二三月", "二三年", "二三点钟"],
    ),
    (
        "被＋明确施事＋当选为",
        r"(被)([ 　]*(?:大家|同学们|同事们|老师们|选民|代表们|股东|股东们|董事会|委员会|评委|网友们|学生们|人们)[ 　]*)(当选为)(?=[^，,。；;！？!?：:\n]{1,16}(?:[，,。；;！？!?：:\n]|$))",
        None, "选为",
        ["他被大家当选为新班长。", "他被股东们当选为董事长。"],
        ["他当选为班长。", "他被大家选为班长。", "他被证明可以当选为班长。"],
    ),
    (
        "由＋明确身份＋为首的",
        r"(由)([ 　]*(?:他|她|他们|她们|大家|我们|你们|负责人|领导|班长|队长|老师|经理|校长|主席|主任|委员|将军|首领|组长|代表|专家|成员|学生|学者)(?:等人)?[ 　]*)(为首)(?=的)",
        "以", None,
        ["由他为首的团队", "由老师为首的队伍"],
        ["以他为首的团队", "由此为首", "由谁为首尚未确定"],
    ),
    (
        "片＋文章类名词",
        r"(?<=[一二两三四五六七八九十几这那])(片)([ 　]*)(文章|论文|作文|散文|报告)(?=$|[的了呀呢吧。，,；;！？!?:：\n])",
        "篇", None,
        ["一片文章。", "这片论文，", "写了两片作文。"],
        ["一片树林。", "一片文章海洋", "一片文章里的光"],
    ),
    (
        "所＋房间名词",
        r"(?<=[一二两三四五六七八九十几这那])(所)([ 　]*)(教室|卧室|厨房|厕所|浴室|客厅)(?=$|(?:很|又|真|挺|非常)|[的里内中是也。，,；;！？!?：:\n])",
        "间", None,
        ["这所教室很好。", "一所卧室里", "那所厨房是"],
        ["这所大学教室", "这所学校", "这所实验室"],
    ),
    (
        "必需＋明确动作动词",
        r"(必需)([ 　]*)(完成|参加|检查|遵守|学习|处理|解决|说明|办理|提交|回答|执行|落实)(?!品|率|度|量|物|件)",
        "必须", None,
        ["你必需完成任务。", "你必需检查的", "必需参加，"],
        ["生活必需品", "必需的材料", "这是必需完成品", "他有必需工作经验"],
    ),
]

BOUND_UNITS = r"(?:元|人|名|个|岁|天|年|米|公里|千克|公斤|吨|次|台|辆|本|%|％)?"
BOUND_NUMBER = r"(?:[0-9]+(?:\.[0-9]+)?|[零〇一二两三四五六七八九十百千万亿]+)"
BOUND_MIDDLE = r"[ 　]*" + BOUND_NUMBER + r"[ 　]*" + BOUND_UNITS + r"[ 　]*"
BOUND_END = r"(?=$|[的，,。；;！？!?：:\n])"
HIGH_BOUND = r"(?<!不)(超过|高于|高过|高达|多达)(" + BOUND_MIDDLE + r")(以上)" + BOUND_END
LOW_BOUND = r"(?<!不)(低于|少于|不足)(" + BOUND_MIDDLE + r")(以下)" + BOUND_END
GUARD_REGEX = r"期待(地)(?=搓手手)"


def jstr(value: str) -> str:
    """Serialize regex as a safely escaped Java string literal."""
    return json.dumps(value, ensure_ascii=False)


def verify():
    total = 0
    for title, regex, change1, change3, positives, negatives in RULES:
        compiled = re.compile(regex)
        if compiled.groups != 3:
            raise AssertionError(f"{title} has {compiled.groups} capture groups, expected 3")
        for sample in positives:
            if not compiled.search(sample):
                raise AssertionError(f"{title}: missed {sample!r}")
            total += 1
        for sample in negatives:
            if compiled.search(sample):
                raise AssertionError(f"{title}: false positive {sample!r}")
            total += 1
    for rx, sample, expected in [
        (HIGH_BOUND, "超过100元以上。", True),
        (HIGH_BOUND, "高于一百人以上", True),
        (HIGH_BOUND, "超过标准。100元以上", False),
        (HIGH_BOUND, "不超过100元以上。", False),
        (LOW_BOUND, "低于50元以下。", True),
        (LOW_BOUND, "少于三十人以下。", True),
        (LOW_BOUND, "不低于50元以下。", False),
    ]:
        if (re.search(rx, sample) is not None) != expected:
            raise AssertionError(f"Bounds false result: {sample}")
        total += 1
    if re.search(GUARD_REGEX, "期待地搓手手") is None:
        raise AssertionError("The expected target character was not protected")
    for example in ["期待的搓手手", "期待地搓手"]:
        if re.search(GUARD_REGEX, example):
            raise AssertionError(f"Accidental protection: {example}")
    return total + 3


def add_rule_line(regex, first, third, description="条件用词纠错"):
    return "            addRule(" + jstr(regex) + ", new String[][]{{" + (
        "null" if first is None else jstr(first)
    ) + ", " + ("null" if third is None else jstr(third)) + ", " + jstr(description) + "}});"


def main():
    num_tests = verify()
    if not TARGET.is_file():
        raise SystemExit("Please run this script in the Dedede-App repository root (dedede-build.sh not found).")
    source = TARGET.read_text(encoding="utf-8")
    if jstr(GUARD_REGEX) in source and "Chinese conditional correction" in source:
        print("Already patched: no change.")
        return

    protector = '            addProtectedTargetPattern("([做作])(?=的(?:判断|决定))");'
    if source.count(protector) != 1:
        raise SystemExit("Protection anchor has changed. Stopped without modifying the source.")
    source = source.replace(
        protector,
        "            // Prevent HCAM from changing 期待地搓手手 into 期待的搓手手.\n"
        + "            addProtectedTargetPattern(" + jstr(GUARD_REGEX) + ");\n"
        + protector,
        1,
    )

    matches = [line for line in source.splitlines() if 'addRule("(仨)([ 　]*)(' in line]
    if len(matches) != 1:
        raise SystemExit("Quantifier anchor has changed. Stopped without modifying the source.")
    rule_lines = "\n\n            // Chinese conditional correction; context restrictions based on LanguageTool zh rules.\n"
    rule_lines += "            // Only matched grammar spans are changed; fixed typo replacements stay in 错别字.txt.\n"
    for title, rx, first, third, _, _ in RULES:
        rule_lines += add_rule_line(rx, first, third) + "\n"
    source = source.replace(matches[0], matches[0] + rule_lines.rstrip("\n"), 1)

    # Existing bounds rules are overly broad and can match unrelated text across
    # several words. Tighten them to explicit, same-clause numeric expressions.
    lines = source.splitlines(keepends=True)
    for fragment, replacement in [
        ('addRule("(超过|高达|多达)(', add_rule_line(HIGH_BOUND, None, "")),
        ('addRule("(低于|少于|不足)(', add_rule_line(LOW_BOUND, None, "")),
    ]:
        indexes = [i for i, line in enumerate(lines) if fragment in line]
        if len(indexes) != 1:
            raise SystemExit(f"Old bounds rule not found uniquely: {fragment!r}. No file written.")
        lines[indexes[0]] = replacement + "\n"
    source = "".join(lines)

    # Make sure this is the Android source generator, not a different project.
    for required in [
        'cat > "app/src/main/java/com/app/dedede/CorrectionCore.java"',
        'cat > "app/src/main/java/com/app/dedede/MainActivity.java"',
        'python3 protect_rules.py',
        '期待(地)(?=搓手手)',
    ]:
        if required not in source:
            # Last regex is Java-string serialized: it contains no extra backslashes.
            raise SystemExit(f"Expected build marker missing: {required!r}; no file written.")

    backup = TARGET.with_name("dedede-build.sh.before-rules.bak")
    if backup.exists():
        raise SystemExit(f"Backup already exists: {backup}; refusing to overwrite it.")
    backup.write_text(TARGET.read_text(encoding="utf-8"), encoding="utf-8")
    TARGET.write_text(source, encoding="utf-8")
    print(f"Updated {TARGET} ({len(RULES)} new rule groups, 2 tightened bounds rules, 1 model guard).")
    print(f"Passed {num_tests} positive/negative regex assertions. Original saved as {backup}.")
    print("This tests the rules only: compile and device tests still require your GitHub Actions build.")


if __name__ == "__main__":
    main()

DEDEDE_PATCH_EMBEDDED_PY

# Run the full original build (all existing UI, thresholds, assets, and signing flow).
bash "$BASE_SCRIPT" "$@"
