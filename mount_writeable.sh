#!/bin/zsh

# this is necessary in order to place things in /system/library/frameworks. that isn't always necessary,
# but it prevents sandboxing from being an issue.
mount -uw /
