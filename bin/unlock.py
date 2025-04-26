#!/usr/bin/env python3
"""
GNOME Keyring Unlocker

Unlocks the default login keyring from a CLI environment by communicating
with the gnome-keyring control socket directly.

Author: Håvard Moen <post@haavard.name>
SPDX-License-Identifier: GPL-3.0-or-later
"""

from enum import IntEnum
import os
from pathlib import Path
import socket
import sys


class ControlOp(IntEnum):
    """Operations for keyring control communication."""
    INITIALIZE = 0
    UNLOCK = 1
    CHANGE = 2
    QUIT = 4


class ControlResult(IntEnum):
    """Results returned from gnome-keyring control socket."""
    OK = 0
    DENIED = 1
    FAILED = 2
    NO_DAEMON = 3


def buffer_encode_uint32(val):
    """
    Encode a 32-bit integer into a 4-byte array.

    Args:
        val (int): Integer to encode.

    Returns:
        bytearray: 4-byte encoded integer.
    """
    return bytearray([
        (val >> 24) & 0xFF,
        (val >> 16) & 0xFF,
        (val >> 8) & 0xFF,
        val & 0xFF
    ])


def buffer_decode_uint32(val):
    """
    Decode a 4-byte array into a 32-bit integer.

    Args:
        val (bytes): 4-byte encoded integer.

    Returns:
        int: Decoded integer.
    """
    return val[0] << 24 | val[1] << 16 | val[2] << 8 | val[3]


def get_control_socket():
    """
    Locate the gnome-keyring control socket.

    Returns:
        Path: Path to the control socket.

    Raises:
        RuntimeError: If the control socket cannot be found.
    """
    if "GNOME_KEYRING_CONTROL" in os.environ:
        control_socket = Path(os.environ["GNOME_KEYRING_CONTROL"]) / "control"
        if control_socket.exists() and control_socket.is_socket():
            return control_socket
    if "XDG_RUNTIME_DIR" in os.environ:
        control_socket = Path(os.environ["XDG_RUNTIME_DIR"]) / "keyring/control"
        if control_socket.exists() and control_socket.is_socket():
            return control_socket
    raise RuntimeError("Unable to find control socket")


def unlock_keyring():
    """
    Unlock the GNOME keyring by sending the password to the control socket.

    Raises:
        RuntimeError: If unlocking fails or communication errors occur.
    """
    pw = sys.stdin.read().strip()

    control_socket = get_control_socket()
    sock = socket.socket(family=socket.AF_UNIX, type=socket.SOCK_STREAM)
    sock.connect(str(control_socket))

    if sock.send(bytearray(1)) < 0:
        raise RuntimeError("Error writing credentials byte")

    oplen = 8 + 4 + len(pw)

    if sock.send(buffer_encode_uint32(oplen)) != 4:
        raise RuntimeError("Error sending data length to keyring")

    if sock.send(buffer_encode_uint32(ControlOp.UNLOCK.value)) != 4:
        raise RuntimeError("Error sending unlock opcode to keyring")

    pw_len = len(pw)
    if sock.send(buffer_encode_uint32(pw_len)) != 4:
        raise RuntimeError("Error sending password length to keyring")

    while pw_len > 0:
        sent = sock.send(pw.encode())
        if sent < 0:
            raise RuntimeError("Error sending password data to keyring")
        pw = pw[sent:]
        pw_len = len(pw)

    response = sock.recv(4)
    response_len = buffer_decode_uint32(response)
    if response_len != 8:
        raise RuntimeError("Invalid response length from keyring")

    result_code = buffer_decode_uint32(sock.recv(4))
    sock.close()

    if result_code == ControlResult.DENIED:
        raise RuntimeError("Unlock denied")
    if result_code == ControlResult.FAILED:
        raise RuntimeError("Unlock failed")
    if result_code != ControlResult.OK:
        raise RuntimeError(f"Unexpected keyring result: {result_code}")


if __name__ == "__main__":
    try:
        unlock_keyring()
    except Exception as e:
        sys.stderr.write(f"{e}\n")
        sys.exit(1)
