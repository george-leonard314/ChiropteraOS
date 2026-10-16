# Names ChiropteraOS inherited from the projects its shell and greeter were
# forked from. They survive only where installed systems still hold them:
#
# - the greeter package ChiropteraOS shipped before chiroptera-greeter, which
#   chiroptera-greeter replaces, and the state directory, greetd command line
#   and passwordless-sync rule that package left behind;
# - the cache directory Zen Browser's palette template, installed from the old
#   template catalog, still writes into.
#
# Code reads them to carry those installs over and never writes them anew.
# This is the only file allowed to spell them; ci/check-names.sh enforces that.
# Sourced by PKGBUILDs at build time and, installed by chiroptera-greeter as
# /usr/share/chiroptera-greeter/legacy-names.sh, by its install script.
# shellcheck shell=bash disable=SC2034

LEGACY_NAME=noctalia
# Its stem, which inflected forms in other languages share ("…Noctalie",
# "…Noctaliában"): what ci/check-names.sh looks for.
LEGACY_NAME_STEM=${LEGACY_NAME%a}

# The greeter package chiroptera-greeter replaces. Its state directory was
# /var/lib/$LEGACY_GREETER, its session wrapper /usr/bin/$LEGACY_GREETER-session.
LEGACY_GREETER=$LEGACY_NAME-greeter
# Prefix of that greeter's environment variables (…ASSETS_DIR, …STATE_DIR).
LEGACY_GREETER_ENV_PREFIX=${LEGACY_NAME^^}_GREETER_
# The passwordless-sync rule its CLI managed under /etc/polkit-1/rules.d.
LEGACY_GREETER_SYNC_RULE=49-$LEGACY_GREETER-passwordless-sync.rules

# Directory under $XDG_CACHE_HOME the installed zen-browser template renders
# the palette CSS into (zen-browser/zen-userChrome.css).
LEGACY_CACHE_NAME=$LEGACY_NAME
