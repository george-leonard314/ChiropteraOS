#!/usr/bin/env python3
"""
Check the internet again, just before the steps that need it.

Calamares checks the connection once, on the welcome page, and stores the
result as the global "hasInternet". The packages module trusts that value:
false means it skips the extra apps without an error. The live session opens
the installer seconds after the desktop appears, usually before a laptop has
joined a Wi-Fi network, so that first answer is often "no" even though the
network is up by the time the install runs. Found on mainLaptop, 2026-09-13:
the apps step never ran pacman at all.

This job asks again and overwrites "hasInternet" with the current answer.
It never fails the install.
"""

import time
import urllib.request

import libcalamares


def pretty_name():
    return "Checking the internet connection"


def reachable(url, timeout):
    try:
        request = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(request, timeout=timeout):
            return True
    except Exception as error:  # any failure just means "not reachable"
        libcalamares.utils.debug("chiroptera-netcheck: {}: {}".format(url, error))
        return False


def run():
    conf = libcalamares.job.configuration or {}
    urls = conf.get("urls", ["https://archlinux.org"])
    attempts = max(1, int(conf.get("attempts", 6)))
    wait = int(conf.get("wait", 5))

    for attempt in range(attempts):
        if any(reachable(url, 10) for url in urls):
            libcalamares.utils.debug("chiroptera-netcheck: online")
            libcalamares.globalstorage.insert("hasInternet", True)
            return None
        if attempt + 1 < attempts:
            time.sleep(wait)

    libcalamares.utils.warning("chiroptera-netcheck: offline; the online steps will be skipped")
    libcalamares.globalstorage.insert("hasInternet", False)
    return None
