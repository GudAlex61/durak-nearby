#!/usr/bin/env python3
"""Drive the installed Android app using actual taps and UI Automator semantics.
Requires a running Android emulator/device and adb on PATH or --adb.
No Flutter SDK or direct calls into the game engine are used.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import struct
import zlib
import time
import xml.etree.ElementTree as ET

class AndroidUi:
    def __init__(self, adb="adb", serial=None, output="android-qa", wait_system_ui=False):
        self.base = [adb] + (["-s", serial] if serial else [])
        self.output = Path(output)
        self.output.mkdir(parents=True, exist_ok=True)
        self.steps = []
        self.sequence = 0
        self.wait_system_ui = wait_system_ui
        self.system_waits = 0

    def run(self, *args, timeout=90, binary=False):
        result = subprocess.run(self.base + list(args), capture_output=True,
                                timeout=timeout, text=not binary, stdin=subprocess.DEVNULL)
        if result.returncode:
            error = result.stderr if not binary else result.stderr.decode(errors="replace")
            raise RuntimeError(f"adb {args!r}: {error}")
        return result.stdout

    def record(self, action, **details):
        self.steps.append({"step": len(self.steps) + 1, "action": action, **details})
        (self.output / "steps.json").write_text(
            json.dumps(self.steps, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(self.steps[-1], ensure_ascii=False), flush=True)

    @staticmethod
    def raw_to_png(raw):
        width, height, fmt = struct.unpack_from("<III", raw)
        if fmt not in (1, 2) or not (1 <= width <= 8192 and 1 <= height <= 8192):
            raise ValueError(f"Unsupported screenshot format: {width}x{height}, {fmt}")
        length = width * height * 4
        offset = len(raw) - length
        if offset not in (12, 16):
            raise ValueError(f"Incomplete raw screenshot: {len(raw)} bytes")
        pixels = bytearray(raw[offset:])
        pixels[3::4] = b"\xff" * (width * height)
        rows = b"".join(b"\0" + pixels[y * width * 4:(y + 1) * width * 4] for y in range(height))
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))

    def screenshot(self, name):
        # Encode PNG on the host; guest-side compression is very slow with TCG.
        path = self.output / (name + ".png")
        raw = self.run("exec-out", "screencap", binary=True, timeout=45)
        path.write_bytes(self.raw_to_png(raw))
        return str(path)

    def tree(self):
        self.run("shell", "uiautomator", "dump", "--compressed", "/sdcard/durak-qa.xml", timeout=45)
        xml = self.run("exec-out", "cat", "/sdcard/durak-qa.xml")
        root = ET.fromstring(xml)
        self.sequence += 1
        (self.output / "latest-ui.xml").write_text(xml, encoding="utf-8")
        return root

    @staticmethod
    def label(node):
        return (node.get("text", "") + "\n" + node.get("content-desc", "")).strip()

    @staticmethod
    def center(node):
        coords = list(map(int, re.findall(r"-?\d+", node.get("bounds", ""))))
        if len(coords) != 4:
            raise ValueError("No bounds: " + str(node.attrib))
        return (coords[0] + coords[2]) // 2, (coords[1] + coords[3]) // 2

    def node(self, root, text, enabled=None):
        matches = [n for n in root.iter("node") if text in self.label(n)
                   and (enabled is None or (n.get("enabled") == "true") == enabled)]
        if not matches:
            return None
        # Prefer the tightest leaf label over a merged parent containing the whole screen.
        return min(matches, key=lambda n: len(self.label(n)))

    def tap(self, node):
        if node is None:
            raise AssertionError("Required UI element not found")
        x, y = self.center(node)
        self.run("shell", "input", "tap", str(x), str(y), timeout=120)
        self.record("tap", label=self.label(node), x=x, y=y)

    def wait(self, text, timeout=90, enabled=None):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                root = self.tree()
                if self.node(root, "System UI isn't responding") is not None and self.wait_system_ui and self.system_waits < 3:
                    self.system_waits += 1
                    self.record("system-ui-anr", handling="Wait", count=self.system_waits)
                    self.tap(self.node(root, "Wait"))
                    continue
                if self.node(root, text, enabled=enabled) is not None:
                    return root
            except (RuntimeError, ET.ParseError, subprocess.TimeoutExpired):
                pass  # Android can briefly expose no accessibility root during launch.
            time.sleep(1)
        self.screenshot("timeout")
        raise AssertionError("Timed out waiting for " + text)

    def smoke(self, already_open=False):
        if not already_open:
            self.run("shell", "am", "force-stop", "dev.duraknearby.durak_bt")
            self.run("shell", "am", "start", "-n", "dev.duraknearby.durak_bt/.MainActivity")
        root = self.wait("Играть с ботом", timeout=240)
        for label in ["Создать стол", "Найти стол рядом"]:
            assert self.node(root, label) is not None, label
        self.screenshot("01-menu")
        self.record("menu-visible")
        self.tap(self.node(root, "Играть с ботом"))
        root = self.wait("Ваши карты", timeout=60)
        self.screenshot("02-table")
        self.record("game-visible", labels=[self.label(n) for n in root.iter("node") if self.label(n)])
        self.exercise_game(root)
        return root

    def exact(self, root, text, enabled=None):
        return next((n for n in root.iter("node") if self.label(n) == text
                     and (enabled is None or (n.get("enabled") == "true") == enabled)), None)

    def count(self, root, prefix):
        label = next(self.label(n) for n in root.iter("node") if self.label(n).startswith(prefix))
        return int(re.findall(r"\d+", label)[0])

    def wait_count(self, prefix, previous, direction):
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            root = self.wait("Ваши карты")
            current = self.count(root, prefix)
            if (current - previous) * direction > 0:
                return root
            time.sleep(1)
        raise AssertionError(f"{prefix} did not change from {previous}")

    def wait_card_gone(self, card_label):
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            root = self.wait("Ваши карты")
            if not any(n.get("class") == "android.widget.Button"
                       and self.label(n).split("\n")[0] == card_label for n in root.iter("node")):
                return root
            time.sleep(1)
        raise AssertionError("Defense card did not leave hand: " + card_label)

    def swipe(self, source, target):
        if source is None or target is None:
            raise AssertionError("Gesture endpoint not found")
        x1, y1 = self.center(source)
        x2, y2 = self.center(target)
        self.run("shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), "700", timeout=120)
        self.record("drag", source=self.label(source), target=self.label(target), start=[x1,y1], end=[x2,y2])

    def exercise_game(self, root):
        played = finished_round = took = False
        for turn in range(28):
            pile = self.node(root, "Карты на столе.")
            finish = self.node(root, "Карты вверх")
            take = self.node(root, "Карты со стола сюда")
            if finish is not None and pile is not None:
                before = self.count(root, "Колода")
                self.swipe(pile, finish)
                root = self.wait_count("Колода", before, -1)
                finished_round = True
                self.record("round-finished-and-refilled", deck_before=before, deck_after=self.count(root, "Колода"))
            elif take is not None and pile is not None and not took:
                before = self.count(root, "Ваши карты")
                self.swipe(pile,take)
                root = self.wait_count("Ваши карты",before,1)
                took = True
                self.record("take-resolved",hand_before=before,hand_after=self.count(root,"Ваши карты"))
            elif self.node(root,"Ваш ход") is not None and self.node(root,"Стол свободен") is not None:
                card = next((n for n in root.iter("node") if n.get("class")=="android.widget.Button" and re.match(r"^(?:[6789]|10|[ВДКТ])[♣♦♥♠](?:\n|$)",self.label(n))),None)
                before = self.count(root,"Ваши карты")
                name = self.label(card).split("\n")[0]
                self.swipe(card,self.node(root,"Стол свободен"))
                root = self.wait_card_gone(name)
                assert self.count(root,"Ваши карты")==before-1
                played=True
                self.record("attack-accepted",hand_before=before,hand_after=self.count(root,"Ваши карты"))
                self.screenshot("03-attack")
            elif take is not None and pile is not None:
                attacks=[n for n in root.iter("node") if self.label(n).startswith("Атака ") and "небита" in self.label(n)]
                trump_label=self.label(self.node(root,"Козырь"))
                trump=next(x for x in "♣♦♥♠" if x in trump_label)
                ranks=["6","7","8","9","10","В","Д","К","Т"]
                defense=target=None
                for attack in attacks:
                    match=re.search(r"(?:[6789]|10|[ВДКТ])[♣♦♥♠]",self.label(attack))
                    if match is None:continue
                    label=match[0]
                    for n in root.iter("node"):
                        m=re.match(r"^([6789]|10|[ВДКТ])([♣♦♥♠])(?:\n|$)",self.label(n))
                        if n.get("class")!="android.widget.Button" or not m:continue
                        if (m[2]==label[-1] and ranks.index(m[1])>ranks.index(label[:-1])) or (m[2]==trump and label[-1]!=trump):
                            defense,target=n,attack
                            break
                    if defense is not None:break
                if defense is not None:
                    name=self.label(defense).split("\n")[0]
                    self.swipe(defense,target)
                    root=self.wait_card_gone(name)
                    self.record("defense-accepted",card=name)
                else:
                    before=self.count(root,"Ваши карты")
                    self.swipe(pile,take)
                    root=self.wait_count("Ваши карты",before,1)
            else:
                time.sleep(1)
                root=self.wait("Ваши карты")
            if played and finished_round and took:break
        assert played and finished_round and took,"Required gesture actions not reached"
        self.screenshot("04-after-rounds")
        # Use the actual app-bar buttons, whose empty icon labels are currently
        # located at the two top corners. Bounds scale with the native viewport.
        root = self.wait("Ваши карты")
        back = self.exact(root, "Выйти из партии")
        help_button = self.exact(root, "Правила")
        assert back is not None and help_button is not None, "App-bar buttons missing"
        self.tap(help_button)
        root = self.wait("Как играть")
        self.tap(self.exact(root, "Понятно"))
        root = self.wait("Ваши карты")
        self.record("help-opened-and-closed")
        self.tap(back)
        root = self.wait("Выйти из партии?")
        self.tap(self.exact(root, "Остаться"))
        self.wait("Ваши карты")
        self.record("leave-cancelled")
        self.tap(back)
        root = self.wait("Выйти из партии?")
        self.tap(self.exact(root, "Выйти"))
        self.wait("Играть с ботом")
        self.record("returned-to-menu")
        self.screenshot("05-returned-menu")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial")
    parser.add_argument("--output", default="android-qa")
    parser.add_argument("--wait-system-ui", action="store_true", help="Allow up to three Wait actions for emulator System UI ANR dialogs; always recorded")
    parser.add_argument("--already-open", action="store_true", help="Continue from an already open menu without a cold relaunch")
    args = parser.parse_args()
    ui = AndroidUi(args.adb, args.serial, args.output, args.wait_system_ui)
    ui.smoke(already_open=args.already_open)
