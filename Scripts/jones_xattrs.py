"""Read macOS attribute names without following the final symlink or reading values."""

import ctypes
import errno
from functools import lru_cache
import os
import sys


MAX_NAMES_BYTES = 64 * 1024
XATTR_NOFOLLOW = 0x0001


@lru_cache(maxsize=1)
def _darwin_listxattr():
    native = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
    function = native.listxattr
    function.argtypes = (ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int)
    function.restype = ctypes.c_ssize_t
    return function


def list_xattrs(path):
    # Python's os.listxattr is Linux-only. Use Darwin's bounded name-list API.
    if sys.platform != "darwin":
        raise OSError(errno.ENOTSUP, "macOS attribute inspection is unavailable")
    encoded = os.fsencode(path)
    if b"\0" in encoded:
        raise OSError(errno.EINVAL, "Attribute path contains a null byte")
    native = _darwin_listxattr()
    for _ in range(3):
        size = native(encoded, None, 0, XATTR_NOFOLLOW)
        if size < 0:
            raise OSError(ctypes.get_errno(), "Cannot measure attribute names")
        if size > MAX_NAMES_BYTES:
            raise OSError(errno.E2BIG, "Attribute names exceed the inspection bound")
        if size == 0:
            return []
        buffer = ctypes.create_string_buffer(size)
        written = native(encoded, buffer, size, XATTR_NOFOLLOW)
        if written < 0:
            error = ctypes.get_errno()
            if error == errno.ERANGE:
                continue
            raise OSError(error, "Cannot read attribute names")
        if written > size:
            raise OSError(errno.EIO, "Attribute name result exceeds its buffer")
        if written == 0:
            return []
        names = buffer.raw[:written]
        if not names.endswith(b"\0"):
            raise OSError(errno.EIO, "Malformed attribute name result")
        parts = names[:-1].split(b"\0")
        if not all(parts):
            raise OSError(errno.EIO, "Empty attribute name in native result")
        return [os.fsdecode(name) for name in parts]
    raise OSError(errno.ERANGE, "Attribute names changed during bounded inspection")
