#!/usr/bin/env python3
"""End-to-end tests: a second Talkify daemon, real speech, every feature.

The daemon runs beside the user's, isolated by TALKIFY_SOCKET,
TALKIFY_CONFIG_DIR and TALKIFY_DATA_DIR, with TALKIFY_DRY_INSERT=1 so nothing
touches the clipboard or presses a key. Its microphone is a PipeWire null
sink; synthesized speech (espeak-ng) is played into that sink in real time,
so the audio path, the Speech Model and the whole text pipeline are the real
ones.

    python3 tests/e2e.py              all tests
    python3 tests/e2e.py tidy vocab   only those
"""

import json
import os
import queue
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BINARY = REPO / "target" / "release" / "talkify"
MODELS = Path.home() / ".local/share/talkify/models"
SINK = "talkify_e2e"
SPIKE_AUDIO = REPO / "spikes" / "parakeet" / "audio"


class Daemon:
  def __init__(self, root: Path, config: str, extra_env=None):
    self.root = root
    self.config_dir = root / "config"
    self.data_dir = root / "data"
    self.socket = root / "talkify.sock"
    self.selection_file = root / "selection.txt"
    self.window_file = root / "window.txt"
    self.config_dir.mkdir(parents=True, exist_ok=True)
    self.data_dir.mkdir(parents=True)
    (self.data_dir / "models").symlink_to(MODELS)
    (self.config_dir / "config.toml").write_text(config)
    self.selection_file.write_text("")
    self.window_file.write_text("org.talkify.Editor")
    env = dict(os.environ)
    env.update({
      "TALKIFY_SOCKET": str(self.socket),
      "TALKIFY_CONFIG_DIR": str(self.config_dir),
      "TALKIFY_DATA_DIR": str(self.data_dir),
      "TALKIFY_DRY_INSERT": "1",
      "TALKIFY_TEST_SELECTION_FILE": str(self.selection_file),
      "TALKIFY_TEST_WINDOW_FILE": str(self.window_file),
      "TALKIFY_TEST_MPRIS_PREFIX": "org.mpris.MediaPlayer2.talkify_e2e",
      "TALKIFY_LOG": "talkify=debug",
      "PIPEWIRE_PROPS": '{ target.object = "%s" stream.capture.sink = true }' % SINK,
    })
    env.update(extra_env or {})
    self.env = env
    self.log = open(root / "daemon.log", "w")
    self.process = subprocess.Popen([str(BINARY), "daemon"], env=env, stdout=self.log, stderr=self.log)
    self.events = queue.Queue()
    for _ in range(100):
      if self.socket.exists():
        break
      time.sleep(0.05)
    self.watcher = socket.socket(socket.AF_UNIX)
    self.watcher.connect(str(self.socket))
    self.watcher.sendall(b'{"cmd":"watch"}\n')
    threading.Thread(target=self._read, daemon=True).start()
    self.wait_for(lambda e: e["t"] == "engine" and e["status"] == "ready", 30)

  def _read(self):
    for line in self.watcher.makefile():
      try:
        self.events.put(json.loads(line))
      except json.JSONDecodeError:
        pass

  def command(self, payload: dict) -> str:
    with socket.socket(socket.AF_UNIX) as s:
      s.connect(str(self.socket))
      s.sendall((json.dumps(payload) + "\n").encode())
      return s.makefile().readline().strip()

  def drain(self):
    while not self.events.empty():
      self.events.get_nowait()

  def wait_for(self, predicate, timeout=20.0, seen=None):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
      try:
        event = self.events.get(timeout=max(0.01, deadline - time.monotonic()))
      except queue.Empty:
        break
      if seen is not None:
        seen.append(event)
      if predicate(event):
        return event
    raise AssertionError("timed out waiting for an event")

  def dictate(self, clip: Path, mode="toggle", before_finish=None):
    """A latched session: start, play the clip into the microphone, finish.
    Returns the result event and every event on the way."""
    self.drain()
    seen = []
    assert self.command({"cmd": mode}) == "ok"
    self.wait_for(lambda e: e["t"] == "recording" and e["active"], 5, seen)
    time.sleep(0.25)
    play(clip)
    time.sleep(0.4)
    if before_finish:
      before_finish()
    assert self.command({"cmd": mode}) == "ok"
    result = self.wait_for(lambda e: e["t"] == "result", 30, seen)
    # The result reaches the HUD before it is told to hide, so the HUD can
    # play what landed.
    after_finish = seen[[i for i, e in enumerate(seen) if e["t"] == "hud" and e["phase"] == "finalizing"][-1]:] \
      if any(e["t"] == "hud" and e["phase"] == "finalizing" for e in seen) else seen
    assert not any(e["t"] == "hud" and e["phase"] in ("hidden", "message") for e in after_finish), \
      "the HUD was hidden before the result arrived"
    self.wait_for(lambda e: e["t"] == "recording" and not e["active"], 5, seen)
    return result, seen

  def log_text(self):
    self.log.flush()
    return (self.root / "daemon.log").read_text()

  def stop(self):
    self.process.terminate()
    try:
      self.process.wait(5)
    except subprocess.TimeoutExpired:
      self.process.kill()
    self.log.close()


def play(clip: Path):
  subprocess.run(["pw-play", "--target", SINK, str(clip)], check=True)


def say(root: Path, name: str, ssml: str, speed=150) -> Path:
  out = root / f"{name}.wav"
  subprocess.run(["espeak-ng", "-m", "-s", str(speed), "-w", str(out), f"<speak>{ssml}</speak>"], check=True)
  return out


def pause(ms=700):
  return f'<break time="{ms}ms"/>'


def active_class() -> str:
  try:
    out = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True).stdout
    return json.loads(out).get("class", "")
  except Exception:
    return ""


BASE_CONFIG = """
# No trigger key: the test daemon must never react to the user's keyboard.
[trigger]
key = ""

[insertion]
destination = "insert"
method = "paste"
live = false

[sounds]
enabled = false

[media]
mode = "off"

[history]
save = true
"""

# Keys a config written before Prompt Shaping and Edit by voice were dropped
# still carries, and the prompt library file they left beside it. The daemon
# must start with them, drop the keys on its next save, and leave the file.
LEGACY_CONFIG = """
[shaping]
enabled = true
server = "http://127.0.0.1:9"
prompt = "tighten-grammar"

[apps.terminal]
final_period = false
send = "spoken"
shaping = false

[apps."org.talkify.Legacy"]
shaping = false
prompt = "bullet-lists"
"""
LEGACY_TRIGGER_KEY = 'edit_key = "KEY_F13"\n'
LEGACY_PROMPTS = """[[prompt]]
id = "tighten-grammar"
name = "Tighten grammar"
pre = "Fix grammar."
"""


def normalized(text: str) -> str:
  return " ".join("".join(c.lower() if c.isalnum() else " " for c in text).split())


TESTS = []


def test(fn):
  TESTS.append(fn)
  return fn


@test
def legacy_settings_load_and_go_on_save(d, root):
  # The daemon started on a config with the dropped keys (main()).
  assert d.process.poll() is None, "the daemon did not survive the legacy config"
  hello = greeting(d, "hello")
  assert "shaping" not in hello["config"], hello
  assert "edit_key" not in hello["config"]["trigger"], hello
  assert "org.talkify.Legacy" not in hello["config"]["apps"], hello
  assert hello["config"]["apps"]["terminal"] == {"final_period": False, "send": "spoken"}, hello
  assert d.command({"cmd": "config-set", "key": "shaping.enabled", "value": "true"}).startswith("error")
  assert d.command({"cmd": "config-set", "key": "trigger.edit_key", "value": "KEY_F13"}).startswith("error")
  for dropped in ["edit", "prompts-reset", "shaper-probe"]:
    assert d.command({"cmd": dropped}).startswith("error"), dropped
  assert d.command({"cmd": "config-set", "key": "history.save", "value": "true"}) == "ok"
  saved = (d.config_dir / "config.toml").read_text()
  for dropped in ["shaping", "edit_key", "prompt", "org.talkify.Legacy"]:
    assert dropped not in saved, (dropped, saved)
  assert (d.config_dir / "prompts.toml").read_text() == LEGACY_PROMPTS, "prompts.toml was touched"


@test
def status_prints_the_greeting_and_exits(d, root):
  out = subprocess.run([str(BINARY), "status"], env=d.env, capture_output=True, text=True, timeout=5)
  assert out.returncode == 0, out
  kinds = [json.loads(line)["t"] for line in out.stdout.splitlines()]
  assert kinds[0] == "hello" and kinds[-1] == "insights", kinds


@test
def plain(d, root):
  result, _ = d.dictate(SPIKE_AUDIO / "jfk.wav")
  text = normalized(result["text"])
  assert "ask not what your country can do for you" in text, result
  assert result["inserted"], result


@test
def tidy(d, root):
  clip = say(root, "fillers", f"Um, {pause(300)} so the plan is, {pause(300)} uh, {pause(300)} fine.")
  result, _ = d.dictate(clip)
  words = normalized(result["text"]).split()
  assert "um" not in words and "uh" not in words, result
  assert "plan" in words, result
  assert normalized(result["raw"]) != normalized(result["text"]), result


@test
def spoken_punctuation(d, root):
  clip = say(root, "punct", f"Hello {pause()} comma {pause()} world {pause()} question mark")
  result, _ = d.dictate(clip)
  assert result["text"].startswith("Hello,"), result
  assert result["text"].rstrip().endswith("?"), result
  assert "comma" not in result["text"].lower(), result


@test
def scratch_that(d, root):
  # espeak swallows the "th" of "scratch that" (the model hears "scratch
  # at"); "delete that" is the same rule and survives the synthetic voice.
  clip = say(root, "scratch", f"Lunch is at noon {pause()} delete that {pause()} lunch is at one.", speed=130)
  result, _ = d.dictate(clip)
  text = normalized(result["text"])
  assert "noon" not in text and "delete" not in text, result
  assert "one" in text or "1" in text, result


@test
def vocabulary(d, root):
  assert d.command({"cmd": "vocab-add", "line": "banana -> Bonanza"}) == "ok"
  assert d.command({"cmd": "vocab-add", "line": "my sign off => Best, Ghost"}) == "ok"
  clip = say(root, "vocab", f"I really like banana. {pause()} My sign off")
  result, seen = d.dictate(clip)
  assert "Bonanza" in result["text"], result
  assert "Best, Ghost" in result["text"], result
  vocab = [e for e in seen if e["t"] == "vocab"]
  assert vocab and any(entry["hits"] > 0 for entry in vocab[-1]["entries"]), vocab
  marks = [m for e in seen if e["t"] == "hud" for m in e.get("marks", []) if m["kind"] == "vocabulary"]
  assert any(m.get("replacement") == "Bonanza" for m in marks), marks


@test
def spoken_send(d, root):
  # Terminals send on the spoken phrase and drop the closing period by default.
  d.window_file.write_text("foot terminal")
  try:
    result, _ = d.dictate(say(root, "send", f"Run the tests {pause(800)} send it."))
    assert result["sent"], result
    assert result["rule"] == "terminal", result
    assert "send" not in normalized(result["text"]), result
    assert not result["text"].endswith("."), result
    assert "enter true" in d.log_text(), "the paste was not followed by Enter"
    # Elsewhere the phrase is just words until an App rule says otherwise.
    d.window_file.write_text("org.talkify.Chat")
    result, _ = d.dictate(say(root, "nosend", f"Run the tests {pause(800)} send it."))
    assert not result["sent"] and "send" in normalized(result["text"]), result
    assert d.command({"cmd": "config-set", "key": "apps.org.talkify.Chat.send", "value": "spoken"}) == "ok"
    result, _ = d.dictate(say(root, "chatsend", f"Thank you very much {pause(800)} send it."))
    assert result["sent"] and result["rule"] == "org.talkify.Chat", result
    assert "thank you" in normalized(result["text"]) and "send" not in normalized(result["text"]), result
  finally:
    d.command({"cmd": "config-set", "key": "apps.org.talkify.Chat.send", "value": ""})
    d.window_file.write_text("org.talkify.Editor")


@test
def history_paste_again_and_retry(d, root):
  result, _ = d.dictate(SPIKE_AUDIO / "espeak_short_16k.wav")
  d.drain()
  assert d.command({"cmd": "paste-last", "index": 0}) == "ok"
  replayed = d.wait_for(lambda e: e["t"] == "replayed", 10)
  assert replayed["text"] == result["text"], (replayed, result)
  assert d.command({"cmd": "paste-last", "index": 0, "raw": True}) == "ok"
  raw = d.wait_for(lambda e: e["t"] == "replayed", 10)
  assert raw["text"] == result["raw"], (raw, result)
  assert d.command({"cmd": "retry", "index": 0}) == "ok"
  retried = d.wait_for(lambda e: e["t"] == "replayed", 20)
  assert normalized(retried["text"]) == normalized(result["text"]), (retried, result)
  assert d.command({"cmd": "copy-last", "index": 0}) == "ok"
  assert d.command({"cmd": "paste-last", "index": 99}).startswith("error"), "a missing entry must fail"
  history_file = list((d.data_dir / "history").glob("*.txt"))
  assert history_file and result["text"] in history_file[0].read_text(), "history not saved"


@test
def teach(d, root):
  assert d.command({"cmd": "vocab-add", "line": "banana -> Bonanza"}) == "ok"
  d.command({"cmd": "vocab-remove", "line": "banana -> Bonanza"})
  clip = say(root, "teach", "Send it to the banana team.")
  result, _ = d.dictate(clip)
  assert "banana" in result["text"].lower(), result
  d.selection_file.write_text("Bonanza")
  d.drain()
  assert d.command({"cmd": "teach"}) == "ok"
  taught = d.wait_for(lambda e: e["t"] == "taught", 5)
  assert taught["heard"] == "banana" and taught["written"] == "Bonanza", taught
  assert "banana -> Bonanza" in (d.config_dir / "words.txt").read_text()
  d.selection_file.write_text("")


@test
def live_insertion(d, root):
  assert d.command({"cmd": "config-set", "key": "insertion.live", "value": "true"}) == "ok"
  before = d.log_text().count("dry live insert \"")
  result, seen = d.dictate(SPIKE_AUDIO / "jfk.wav")
  chunks = d.log_text().count("dry live insert \"") - before
  assert chunks >= 3, f"only {chunks} live chunks"
  assert "ask not what your country can do for you" in normalized(result["text"]), result
  committed = [e for e in seen if e["t"] == "hud" and e.get("committed")]
  assert committed, "the HUD never showed committed text"
  d.command({"cmd": "config-set", "key": "insertion.live", "value": "false"})


@test
def pause_session(d, root):
  d.drain()
  assert d.command({"cmd": "pause"}).startswith("error"), "pause outside a session must fail"
  assert d.command({"cmd": "toggle"}) == "ok"
  d.wait_for(lambda e: e["t"] == "recording" and e["active"], 5)
  time.sleep(0.3)
  assert d.command({"cmd": "pause"}) == "ok"
  d.wait_for(lambda e: e["t"] == "hud" and e.get("paused"), 5)
  play(SPIKE_AUDIO / "jfk.wav")  # spoken while paused: must be dropped
  assert d.command({"cmd": "pause"}) == "ok"
  d.wait_for(lambda e: e["t"] == "hud" and not e.get("paused"), 5)
  play(say(root, "after-pause", "Only this sentence."))
  time.sleep(0.4)
  assert d.command({"cmd": "toggle"}) == "ok"
  result = d.wait_for(lambda e: e["t"] == "result", 30)
  text = normalized(result["text"])
  assert "sentence" in text and "country" not in text, result


@test
def insights(d, root):
  d.drain()
  d.dictate(SPIKE_AUDIO / "espeak_short_16k.wav")
  usage = json.loads((d.data_dir / "usage.json").read_text())
  assert usage["days"][0]["words"] > 0 and usage["days"][0]["sessions"] > 0, usage
  with socket.socket(socket.AF_UNIX) as s:
    s.connect(str(d.socket))
    s.sendall(b'{"cmd":"watch"}\n')
    reader = s.makefile()
    for _ in range(12):
      event = json.loads(reader.readline())
      if event["t"] == "insights":
        assert event["insights"]["total_words"] > 0, event
        assert len(event["insights"]["heatmap"]) == 112, event
        return
  raise AssertionError("no insights event on watch")


@test
def media_pauses_and_resumes(d, root):
  log = root / "player.log"
  log.write_text("")
  player = subprocess.Popen([sys.executable, str(REPO / "tests" / "fake_mpris.py"), "talkify_e2e", str(log)])
  try:
    time.sleep(0.8)
    assert d.command({"cmd": "config-set", "key": "media.mode", "value": "pause"}) == "ok"
    paused_during = []
    d.dictate(say(root, "media", "Quiet please."), before_finish=lambda: paused_during.append(log.read_text()))
    time.sleep(0.8)
    assert paused_during[0].split() == ["Pause"], paused_during
    assert log.read_text().split() == ["Pause", "Play"], log.read_text()
  finally:
    d.command({"cmd": "config-set", "key": "media.mode", "value": "off"})
    player.terminate()


def greeting(d, kind):
  with socket.socket(socket.AF_UNIX) as s:
    s.connect(str(d.socket))
    s.sendall(b'{"cmd":"watch"}\n')
    reader = s.makefile()
    for _ in range(12):
      event = json.loads(reader.readline())
      if event["t"] == kind:
        return event
  raise AssertionError(f"no {kind} event on watch")


def main():
  wanted = set(sys.argv[1:])
  if not BINARY.exists():
    sys.exit(f"build first: {BINARY} is missing")
  module = subprocess.run(
    ["pactl", "load-module", "module-null-sink", f"sink_name={SINK}", "rate=16000", "channels=1",
     "sink_properties=device.description=TalkifyE2E"],
    capture_output=True, text=True, check=True).stdout.strip()
  root = Path(tempfile.mkdtemp(prefix="talkify-e2e-"))
  (root / "config").mkdir()
  (root / "config" / "prompts.toml").write_text(LEGACY_PROMPTS)
  config = BASE_CONFIG.replace('key = ""\n', 'key = ""\n' + LEGACY_TRIGGER_KEY) + LEGACY_CONFIG
  daemon = None
  failures = 0
  try:
    daemon = Daemon(root, config)
    for fn in TESTS:
      if wanted and fn.__name__ not in wanted:
        continue
      started = time.monotonic()
      try:
        fn(daemon, root)
        print(f"  ok    {fn.__name__} ({time.monotonic() - started:.1f}s)")
      except Exception as error:
        failures += 1
        print(f"  FAIL  {fn.__name__}: {error!r}")
  finally:
    if daemon:
      daemon.stop()
    subprocess.run(["pactl", "unload-module", module], check=False)
    if failures:
      print(f"logs kept in {root}")
    else:
      shutil.rmtree(root, ignore_errors=True)
  print("failed" if failures else "passed")
  sys.exit(1 if failures else 0)


if __name__ == "__main__":
  main()
