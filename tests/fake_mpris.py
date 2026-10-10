#!/usr/bin/env python3
"""A media player on the session bus that only remembers what was asked of it.

    fake_mpris.py NAME LOGFILE

Owns org.mpris.MediaPlayer2.NAME, starts Playing, and appends every Pause and
Play it receives to LOGFILE, so a test can check Talkify paused it for the
session and resumed it after.
"""

import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

XML = """
<node>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Pause"/>
    <method name="Play"/>
    <property name="PlaybackStatus" type="s" access="read"/>
  </interface>
</node>
"""

name, log = sys.argv[1], sys.argv[2]
state = {"status": "Playing"}


def call(_conn, _sender, _path, _iface, method, _params, invocation):
  state["status"] = "Paused" if method == "Pause" else "Playing"
  with open(log, "a") as out:
    out.write(method + "\n")
  invocation.return_value(None)


def get(_conn, _sender, _path, _iface, prop):
  return GLib.Variant("s", state["status"])


def on_bus(connection, _name):
  node = Gio.DBusNodeInfo.new_for_xml(XML)
  connection.register_object("/org/mpris/MediaPlayer2", node.interfaces[0], call, get, None)


Gio.bus_own_name(Gio.BusType.SESSION, f"org.mpris.MediaPlayer2.{name}", Gio.BusNameOwnerFlags.NONE, on_bus, None, None)
GLib.MainLoop().run()
