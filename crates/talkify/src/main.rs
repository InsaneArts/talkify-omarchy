//! `talkify`: the daemon and the commands that talk to it.

mod daemon;
mod paths;

use std::io::{BufRead, BufReader, IsTerminal, Write};
use std::os::unix::net::UnixStream;
use std::process::ExitCode;

use anyhow::Context;
use talkify_core::protocol::Command;

const USAGE: &str = "\
talkify: dictation for Omarchy

  talkify daemon            run the daemon (systemd starts this)
  talkify connect           connect / start the daemon (saves RAM & CPU when disconnected)
  talkify disconnect        disconnect / stop the daemon (frees ~1 GB RAM & CPU)
  talkify toggle-connection toggle daemon between connected and disconnected
  talkify watch             stream events as JSON lines (the shell plugin reads this)
  talkify status            print the daemon's state once
  talkify toggle            start a latched session, or finish the one in flight
  talkify cancel            cancel the session in flight
  talkify press | release   the trigger as two commands, for compositor key binds
  talkify tap               a compositor-seen tap: toggles only when the daemon
                            cannot read the keyboard itself
  talkify pause             pause or resume the hands-free session in flight
  talkify paste-last [N] [--raw]
                            insert a recent dictation again (0 is the latest;
                            --raw: as heard, before cleanup)
  talkify copy-last [N] [--raw]
                            put it on the clipboard
  talkify retry [N]         decode a recent dictation's audio again and insert it
  talkify teach             learn the selected text as the spelling of a word the
                            last dictation got wrong
  talkify vocab add LINE    add a vocabulary line: `Word`, `heard -> written`,
                            or `trigger => expansion`
  talkify vocab remove LINE remove one
  talkify history clear     forget the recent dictations and their audio
  talkify set KEY VALUE     change a setting, e.g. `talkify set hud.visual glow`
  talkify load-model        load the Speech Model, downloading it if missing
  talkify transcribe FILE   transcribe a 16 kHz mono WAV without the daemon
  talkify raw JSON          send one protocol command (docs/protocol.md)";

fn main() -> ExitCode {
  tracing_subscriber::fmt()
    .with_env_filter(
      tracing_subscriber::EnvFilter::try_from_env("TALKIFY_LOG")
        .unwrap_or_else(|_| "talkify=info".into()),
    )
    .with_writer(std::io::stderr)
    .with_ansi(std::io::stderr().is_terminal())
    .init();

  let args: Vec<String> = std::env::args().skip(1).collect();
  let args: Vec<&str> = args.iter().map(String::as_str).collect();
  let result = match args.as_slice() {
    ["daemon"] => daemon::run(),
    ["connect"] => connect_daemon(),
    ["disconnect"] => disconnect_daemon(),
    ["toggle-connection" | "toggle-connect"] => toggle_connection(),
    ["watch"] => watch(None),
    ["status"] => watch(Some(daemon::GREETING_EVENTS)),
    ["toggle"] => send(Command::Toggle),
    ["cancel"] => send(Command::Cancel),
    ["press"] => send(Command::Press),
    ["release"] => send(Command::Release),
    ["tap"] => send(Command::Tap),
    ["load-model"] => send(Command::LoadModel),
    ["pause"] => send(Command::Pause),
    ["paste-last", rest @ ..] => {
      past(rest).and_then(|(index, raw)| send(Command::PasteLast { index, raw }))
    }
    ["copy-last", rest @ ..] => {
      past(rest).and_then(|(index, raw)| send(Command::CopyLast { index, raw }))
    }
    ["retry", rest @ ..] => past(rest).and_then(|(index, _)| send(Command::Retry { index })),
    ["teach"] => send(Command::Teach),
    ["vocab", "add", line @ ..] if !line.is_empty() => send(Command::VocabAdd {
      line: line.join(" "),
    }),
    ["vocab", "remove", line @ ..] if !line.is_empty() => send(Command::VocabRemove {
      line: line.join(" "),
    }),
    ["history", "clear"] => send(Command::HistoryClear),
    ["raw", json] => serde_json::from_str::<Command>(json)
      .context("not a protocol command")
      .and_then(send),
    ["set", key, value] => send(Command::ConfigSet {
      key: (*key).into(),
      value: (*value).into(),
    }),
    ["transcribe", file] => daemon::transcribe_file(file),
    ["help" | "--help" | "-h"] => {
      println!("{USAGE}");
      Ok(())
    }
    _ => {
      eprintln!("{USAGE}");
      return ExitCode::from(2);
    }
  };
  match result {
    Ok(()) => ExitCode::SUCCESS,
    Err(error) => {
      eprintln!("talkify: {error:#}");
      ExitCode::FAILURE
    }
  }
}

/// `[N] [--raw]`, in either order.
fn past(args: &[&str]) -> anyhow::Result<(usize, bool)> {
  let mut index = 0;
  let mut raw = false;
  for arg in args {
    match *arg {
      "--raw" => raw = true,
      number => index = number.parse().context("expected a number or --raw")?,
    }
  }
  Ok((index, raw))
}

fn connect(command: &Command) -> anyhow::Result<UnixStream> {
  let path = paths::socket();
  let mut stream = UnixStream::connect(&path)
    .with_context(|| format!("Talkify is not running ({})", path.display()))?;
  let mut line = serde_json::to_string(command)?;
  line.push('\n');
  stream.write_all(line.as_bytes())?;
  Ok(stream)
}

fn send(command: Command) -> anyhow::Result<()> {
  let stream = connect(&command)?;
  let mut reply = String::new();
  BufReader::new(stream).read_line(&mut reply)?;
  let reply = reply.trim();
  if let Some(error) = reply.strip_prefix("error: ") {
    anyhow::bail!("{error}");
  }
  Ok(())
}

/// Copies the event stream to stdout, line by line, flushing each so a
/// reader on the other end of a pipe sees it at once.
fn watch(limit: Option<usize>) -> anyhow::Result<()> {
  let stream = connect(&Command::Watch)?;
  let mut stdout = std::io::stdout().lock();
  for line in BufReader::new(stream)
    .lines()
    .take(limit.unwrap_or(usize::MAX))
  {
    let line = line?;
    if writeln!(stdout, "{line}")
      .and_then(|()| stdout.flush())
      .is_err()
    {
      break;
    }
  }
  Ok(())
}

fn is_connected() -> bool {
  let path = paths::socket();
  UnixStream::connect(&path).is_ok()
}

fn connect_daemon() -> anyhow::Result<()> {
  if is_connected() {
    println!("Talkify is already connected.");
    return Ok(());
  }

  // Try starting via systemd user service first
  let systemd_success = std::process::Command::new("systemctl")
    .args(["--user", "start", "talkify.service"])
    .status()
    .map(|s| s.success())
    .unwrap_or(false);

  // If systemd service start failed, attempt spawning daemon in background directly
  if !systemd_success {
    let exe = std::env::current_exe().context("get current exe")?;
    std::process::Command::new(exe)
      .arg("daemon")
      .stdin(std::process::Stdio::null())
      .stdout(std::process::Stdio::null())
      .stderr(std::process::Stdio::null())
      .spawn()
      .context("spawn daemon")?;
  }

  // Wait briefly for daemon to bind socket
  let path = paths::socket();
  let start = std::time::Instant::now();
  let timeout = std::time::Duration::from_secs(5);
  while start.elapsed() < timeout {
    if UnixStream::connect(&path).is_ok() {
      println!("Talkify connected.");
      return Ok(());
    }
    std::thread::sleep(std::time::Duration::from_millis(100));
  }

  anyhow::bail!("Talkify daemon started, but socket did not appear within 5s")
}

fn disconnect_daemon() -> anyhow::Result<()> {
  let was_connected = is_connected();

  // Try stopping systemd service
  let _ = std::process::Command::new("systemctl")
    .args(["--user", "stop", "talkify.service"])
    .status();

  // Also send Disconnect command over socket if still connected or not using systemd
  if was_connected && is_connected() {
    let _ = send(Command::Disconnect);
  }

  // Wait briefly for socket to disappear
  let path = paths::socket();
  let start = std::time::Instant::now();
  let timeout = std::time::Duration::from_secs(3);
  while start.elapsed() < timeout {
    if !path.exists() && UnixStream::connect(&path).is_err() {
      break;
    }
    std::thread::sleep(std::time::Duration::from_millis(50));
  }

  println!("Talkify disconnected (daemon stopped, RAM and CPU freed).");
  Ok(())
}

fn toggle_connection() -> anyhow::Result<()> {
  if is_connected() {
    disconnect_daemon()
  } else {
    connect_daemon()
  }
}
