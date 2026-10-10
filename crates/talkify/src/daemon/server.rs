//! The daemon's Unix socket. Each connection sends one command line; `watch`
//! keeps the connection open and streams events back.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};

use anyhow::{Context, bail};
use crossbeam_channel::Sender;
use talkify_core::protocol::Command;

use super::Msg;
use crate::paths;

/// Events a watcher may fall behind by before it is dropped.
const WATCHER_BACKLOG: usize = 2048;

pub fn bind() -> anyhow::Result<UnixListener> {
  let path = paths::socket();
  if UnixStream::connect(&path).is_ok() {
    bail!("Talkify is already running ({})", path.display());
  }
  let _ = std::fs::remove_file(&path);
  UnixListener::bind(&path).with_context(|| format!("bind {}", path.display()))
}

pub fn serve(listener: UnixListener, events: Sender<Msg>) {
  for stream in listener.incoming().flatten() {
    let events = events.clone();
    let _ = std::thread::Builder::new()
      .name("client".into())
      .spawn(move || handle(stream, events));
  }
}

fn handle(stream: UnixStream, events: Sender<Msg>) {
  let mut line = String::new();
  if BufReader::new(&stream).read_line(&mut line).is_err() {
    return;
  }
  let mut writer = stream;
  let command = match serde_json::from_str::<Command>(line.trim()) {
    Ok(command) => command,
    Err(error) => {
      let _ = writeln!(writer, "error: {error}");
      return;
    }
  };

  if command == Command::Watch {
    let (tx, rx) = crossbeam_channel::bounded::<String>(WATCHER_BACKLOG);
    if events.send(Msg::Watch(tx)).is_err() {
      return;
    }
    for event in rx {
      if writer.write_all(event.as_bytes()).is_err() {
        return;
      }
    }
    return;
  }

  let (reply_tx, reply_rx) = crossbeam_channel::bounded(1);
  if events.send(Msg::Command(command, reply_tx)).is_err() {
    return;
  }
  if let Ok(reply) = reply_rx.recv() {
    let _ = writeln!(writer, "{reply}");
  }
}
