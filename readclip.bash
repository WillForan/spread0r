#!/usr/bin/env bash
cd $(dirname $0)

./spread0r.pl <(xclip -o)
