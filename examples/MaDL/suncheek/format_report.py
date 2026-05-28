#!/usr/bin/env python3
"""
dlockdetect 输出格式化工具
解析 dlockdetect 的 verbose 输出，生成清晰的死锁/活锁报告
"""
import sys
import re
import os

# ANSI 颜色
RED    = "\033[91m"
GREEN  = "\033[92m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
DIM    = "\033[2m"
RESET  = "\033[0m"

def parse_output(raw: str):
    """解析 dlockdetect 的原始输出"""
    result = {
        "queues": 0,
        "components": 0,
        "forks": 0,
        "ctrl_joins": 0,
        "merges": 0,
        "load_balancers": 0,
        "cycles": [],
        "livelocks": False,
        "invariants": [],
        "live_channels": [],
        "dead_channels_count": 0,
        "has_deadlock": False,
        "parse_error": None,
    }

    # 统计信息
    m = re.search(r"#Queues:\s*(\d+)", raw)
    if m:
        result["queues"] = int(m.group(1))
    m = re.search(r"#Components:\s*(\d+)", raw)
    if m:
        result["components"] = int(m.group(1))
    m = re.search(r"#Forks:\s*(\d+)", raw)
    if m:
        result["forks"] = int(m.group(1))
    m = re.search(r"#CtrlJoins:\s*(\d+)", raw)
    if m:
        result["ctrl_joins"] = int(m.group(1))
    m = re.search(r"#Merges:\s*(\d+)", raw)
    if m:
        result["merges"] = int(m.group(1))
    m = re.search(r"#LoadBalancers:\s*(\d+)", raw)
    if m:
        result["load_balancers"] = int(m.group(1))

    # 解析 cycles
    cycle_lines = []
    in_cycles = False
    for line in raw.splitlines():
        if line.strip() == "Cycles:":
            in_cycles = True
            continue
        if in_cycles:
            if line.strip().startswith("["):
                cycle_lines.append(line.strip())
            elif line.strip() and not line.strip().startswith("["):
                in_cycles = False

    for cline in cycle_lines:
        channels = re.findall(r'channelName\s*=\s*"([^"]+)"', cline)
        unique_channels = list(dict.fromkeys(channels))  # 去重保序
        if unique_channels:
            result["cycles"].append(unique_channels)

    # 活锁
    if "possible livelocks found" in raw and "No possible livelocks" not in raw:
        result["livelocks"] = True

    # 不变量
    inv_matches = re.findall(r"^0 = (.+)$", raw, re.MULTILINE)
    result["invariants"] = inv_matches

    # Live channels
    live = re.findall(r"== Channel (\S+) is live\.", raw)
    result["live_channels"] = live

    # Dead channels: 计算 "(model" 出现次数
    model_count = raw.count('"(model"')
    result["dead_channels_count"] = model_count

    # 最终判断
    if model_count > 0:
        result["has_deadlock"] = True
    elif "No deadlock found" in raw:
        result["has_deadlock"] = False
    elif "z3:" in raw and "does not exist" in raw:
        result["parse_error"] = "Z3 solver not found in PATH"

    # 解析错误
    if "Fatal" in raw:
        m = re.search(r"Fatal.*?:\s*(.*?)(?:\n|$)", raw)
        if m:
            result["parse_error"] = m.group(1).strip()

    return result


def print_report(result: dict, filename: str):
    """打印格式化报告"""
    basename = os.path.basename(filename)

    print(f"\n{BOLD}{'='*70}{RESET}")
    print(f"{BOLD}  MaDL 死锁检测报告{RESET}")
    print(f"{BOLD}{'='*70}{RESET}")
    print(f"  文件: {CYAN}{basename}{RESET}")
    print(f"{'─'*70}")

    # 解析错误
    if result["parse_error"]:
        print(f"\n  {RED}{BOLD}✘ 错误: {result['parse_error']}{RESET}")
        print(f"{'='*70}\n")
        return

    # 网络统计
    print(f"\n  {BOLD}▎ 网络拓扑统计{RESET}")
    print(f"  ├── Queues:        {result['queues']}")
    print(f"  ├── Components:    {result['components']}")
    print(f"  ├── Forks:         {result['forks']}")
    print(f"  ├── CtrlJoins:     {result['ctrl_joins']}")
    print(f"  ├── Merges:        {result['merges']}")
    print(f"  └── LoadBalancers: {result['load_balancers']}")

    # Cycles
    print(f"\n  {BOLD}▎ 循环依赖分析{RESET}")
    if result["cycles"]:
        print(f"  发现 {YELLOW}{BOLD}{len(result['cycles'])} 个循环依赖{RESET}:")
        for i, cycle in enumerate(result["cycles"]):
            arrow_chain = f" → ".join(cycle) + f" → {cycle[0]}"
            print(f"  {YELLOW}  [{i+1}]{RESET} {arrow_chain}")
    else:
        print(f"  {GREEN}✓ 无循环依赖{RESET}")

    # 活锁
    print(f"\n  {BOLD}▎ 活锁检测{RESET}")
    if result["livelocks"]:
        print(f"  {RED}✘ 检测到潜在活锁!{RESET}")
    else:
        print(f"  {GREEN}✓ 未检测到活锁{RESET}")

    # 不变量
    print(f"\n  {BOLD}▎ 网络不变量{RESET}")
    if result["invariants"]:
        print(f"  发现 {CYAN}{len(result['invariants'])} 个守恒不变量{RESET}:")
        for inv in result["invariants"]:
            print(f"  {DIM}  0 = {inv}{RESET}")
    else:
        print(f"  {DIM}  无不变量 (网络中存在不守恒的资源竞争){RESET}")

    # 死锁结果 (核心)
    print(f"\n{'━'*70}")
    total_checked = len(result["live_channels"]) + result["dead_channels_count"]
    live_count = len(result["live_channels"])
    dead_count = result["dead_channels_count"]

    if result["has_deadlock"]:
        print(f"\n  {RED}{BOLD}██ 检测结果: 发现死锁 (DEADLOCK DETECTED){RESET}")
        print(f"  {RED}{BOLD}██ Z3 SAT — 存在使系统永久阻塞的状态{RESET}")
        print()
        print(f"  Channel 检测统计:")
        print(f"    总检测:   {total_checked} 个 channel")
        print(f"    {GREEN}存活:     {live_count} 个 channel{RESET}")
        print(f"    {RED}死锁:     {dead_count} 个 channel{RESET}")
        print()

        if live_count > 0:
            print(f"  {GREEN}存活的 channel (不受死锁影响):{RESET}")
            for ch in result["live_channels"]:
                print(f"    {GREEN}✓{RESET} {ch}")
            print()

        if dead_count > 0:
            print(f"  {RED}被阻塞的 channel (死锁涉及):{RESET}")
            # dlockdetect 不直接输出死锁 channel 名称，只输出 (model)
            # 被阻塞的 = 所有 channel - 存活的
            print(f"    {RED}✘{RESET} {dead_count} 个 channel 被 Z3 证明存在永久阻塞状态")
            print(f"    {DIM}(dlockdetect 未输出具体名称，可通过 --keep-smt-model 查看){RESET}")

    else:
        print(f"\n  {GREEN}{BOLD}██ 检测结果: 未发现死锁 (NO DEADLOCK){RESET}")
        print(f"  {GREEN}{BOLD}██ Z3 UNSAT — 所有 channel 均可持续工作{RESET}")
        print()
        print(f"  Channel 检测统计:")
        print(f"    总检测:   {total_checked} 个 channel")
        print(f"    {GREEN}全部存活: {live_count} 个 channel ✓{RESET}")

    print(f"\n{'='*70}\n")


def main():
    if len(sys.argv) < 2:
        print(f"Usage: python3 {sys.argv[0]} <raw_output_file> [madl_filename]")
        print(f"  or pipe: dlockdetect ... | python3 {sys.argv[0]} - [madl_filename]")
        sys.exit(1)

    input_arg = sys.argv[1]
    filename = sys.argv[2] if len(sys.argv) > 2 else input_arg

    if input_arg == "-":
        raw = sys.stdin.read()
    else:
        with open(input_arg, "r") as f:
            raw = f.read()

    result = parse_output(raw)
    print_report(result, filename)


if __name__ == "__main__":
    main()
