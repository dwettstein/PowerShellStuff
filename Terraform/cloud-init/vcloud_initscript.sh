#!/usr/bin/env bash
# Copyright (c) David Wettstein, licensed under the MIT License

/bin/sed -E -i 's/^root:([^:]+):.*$/root:\\1:99999:0:99999:0:::/' /etc/shadow
usermod -p '{{Output of `openssl passwd -6 -salt any_salt`}}' root
