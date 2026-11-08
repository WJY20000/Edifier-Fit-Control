#!/usr/bin/env python3
"""把 Android 的 btsnoop_hci.log / HCI .cfa 抓包解成漫步者的收发记录。

用法：
    python3 tool/decode_btsnoop.py BT_HCI_2026_1108_142340.cfa.curf
    python3 tool/decode_btsnoop.py btsnoop_hci.log --from 14:29:30 --to 14:33:57

做法：不做 L2CAP/ATT 分层解析（各家 snoop 封装不一致、ATT handle 也常被记错），
而是按方向把 ACL 载荷累积成字节流，直接在流里按帧头 + 校验和切帧。
校验和是强约束，误判率极低；实测对 Fit900NB Turbo 的抓包能还原全部写命令。

帧格式（Fit900NB Turbo，明文 BES v2）：
    AA EC cmd lenHi lenLo <payload> sum8      # sum8 = 前面所有字节之和 & 0xFF
旧版 v1（部分型号）：
    AA len cmd <data> crcHi crcLo             # crc = 0x2019 + Σ(前面所有字节)
"""

from __future__ import annotations

import argparse
import datetime
import struct
from collections import Counter, defaultdict

HEADS = {0xAA, 0xBB, 0xCC}
V2_MARK = 0xEC


def read_records(path: str):
    """逐条产出 (received, 当天秒数, HCI 包体)。received=True 表示来自耳机。"""
    with open(path, "rb") as fh:
        blob = fh.read()
    if not blob.startswith(b"btsnoop\x00"):
        raise SystemExit(f"{path} 不是 btsnoop 文件（magic 不匹配）")
    offset = 16
    while offset + 24 <= len(blob):
        _orig, incl, flags, _drops, ts = struct.unpack(">IIIIq", blob[offset : offset + 24])
        offset += 24
        payload = blob[offset : offset + incl]
        offset += incl
        if len(payload) < incl:
            break
        yield bool(flags & 1), time_of_day(ts), payload


def time_of_day(ts: int) -> float:
    """返回当天秒数。

    btsnoop 的时间戳是「自 0 年 1 月 1 日 00:00 起的微秒」，日期部分在不同厂商手里
    可能有偏移，但时分秒是准的，用来对齐操作顺序足够。
    """
    try:
        d = datetime.datetime(1, 1, 1) + datetime.timedelta(microseconds=ts)
    except OverflowError:
        return 0.0
    return d.hour * 3600 + d.minute * 60 + d.second + d.microsecond / 1e6


def scan_frames(buf: bytearray, add: bytes, out: list) -> None:
    """把 add 追加到 buf，然后从 buf 里切出所有校验通过的帧。

    切出的帧是 (head, cmd, payload, is_v2)，追加到 out。
    """
    buf += add
    i = 0
    while True:
        while i < len(buf) and buf[i] not in HEADS:
            i += 1
        if i + 2 > len(buf):
            break

        if buf[i + 1] == V2_MARK:
            if i + 5 > len(buf):
                break  # 长度字段还没收全，等下一个包
            n = (buf[i + 3] << 8) | buf[i + 4]
            total = n + 6
            if i + total > len(buf):
                break  # 帧体还没收全
            if (sum(buf[i : i + total - 1]) & 0xFF) != buf[i + total - 1]:
                i += 1
                continue
            out.append((buf[i], buf[i + 2], bytes(buf[i + 5 : i + total - 1]), True))
            i += total
        else:
            ln = buf[i + 1]
            total = ln + 4
            if ln < 1 or i + total > len(buf):
                if ln < 1:
                    i += 1
                    continue
                break
            expect = (0x2019 + sum(buf[i : i + total - 2])) & 0xFFFF
            if (
                buf[i + total - 2] != (expect >> 8)
                or buf[i + total - 1] != (expect & 0xFF)
            ):
                i += 1
                continue
            out.append((buf[i], buf[i + 2], bytes(buf[i + 3 : i + total - 2]), False))
            i += total

    del buf[:i]


def parse_hms(text: str) -> float:
    parts = [float(p) for p in text.split(":")]
    while len(parts) < 3:
        parts.append(0.0)
    return parts[0] * 3600 + parts[1] * 60 + parts[2]


def hexs(b: bytes) -> str:
    return " ".join(f"{x:02X}" for x in b)


def main() -> None:
    parser = argparse.ArgumentParser(description="解码漫步者 BLE 抓包")
    parser.add_argument("path")
    parser.add_argument("--from", dest="start", default=None, help="起始时间 HH:MM:SS")
    parser.add_argument("--to", dest="end", default=None, help="结束时间 HH:MM:SS")
    parser.add_argument(
        "--raw", action="store_true", help="同时打印能切出的 v1 帧（默认只显示校验明细）"
    )
    args = parser.parse_args()

    bufs = {False: bytearray(), True: bytearray()}
    rows = []  # (t, direction, head, cmd, payload, is_v2)
    acl = 0

    for received, ts, data in read_records(args.path):
        if len(data) < 5 or data[0] != 2:  # 只要 HCI ACL 数据包（type=2）
            continue
        acl += 1
        dlen = struct.unpack("<H", data[3:5])[0]
        payload = data[5 : 5 + dlen]

        out: list = []
        scan_frames(bufs[received], payload, out)
        # 一帧可能跨越多个 ACL 包，完成时间记在收完那一刻
        for head, cmd, body, is_v2 in out:
            rows.append((ts, not received, head, cmd, body, is_v2))

    print(
        f"# HCI ACL 包 {acl} 个，切出 "
        f"{sum(1 for r in rows if r[1])} 条 TX / {sum(1 for r in rows if not r[1])} 条 RX"
    )
    if not rows:
        raise SystemExit("没找到漫步者帧：确认抓包里包含与耳机的 BLE 连接")

    rows.sort(key=lambda r: r[0])
    t0 = rows[0][0]
    t_end = rows[-1][0]

    def clock(t: float) -> str:
        """只取当天时分秒。日期部分不可靠，但时分秒能和手机录屏/操作记录对上。"""
        t = t % 86400
        return f"{int(t // 3600):02d}:{int(t % 3600 // 60):02d}:{t % 60:06.3f}"

    lo = parse_hms(args.start) if args.start else -1
    hi = parse_hms(args.end) if args.end else 10**9

    print(f"# 时间跨度 {clock(t0)} → {clock(t_end)}（{t_end - t0:.1f} s）")
    print()
    print("== 时间线（TX = 手机发给耳机） ==")
    for t, tx, head, cmd, body, is_v2 in rows:
        if not (lo <= t <= hi):
            continue
        if not is_v2 and not args.raw:
            continue
        print(
            f"{clock(t)}  {'TX' if tx else 'RX'}  {head:02X} {'v2' if is_v2 else 'v1'}  "
            f"{cmd:02X}  [{hexs(body)}]"
        )

    print()
    print("== 写命令汇总（按 命令字 / payload 去重） ==")
    summary: dict[int, Counter] = defaultdict(Counter)
    for t, tx, head, cmd, body, is_v2 in rows:
        if tx and lo <= t <= hi:
            summary[cmd][hexs(body)] += 1
    for cmd in sorted(summary):
        print(f"0x{cmd:02X}:")
        for body, count in summary[cmd].most_common(12):
            print(f"    {count:4}×  [{body}]")


if __name__ == "__main__":
    main()
