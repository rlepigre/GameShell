#!/bin/bash

dir=$(eval_gettext '$GASH_HOME/Castle/Main_building/Throne_room/Kings_quarter')
chmod -x "$dir"

[ "$(REALPATH "$(pwd)")" = "$(REALPATH "$dir")" ] && cd ..
