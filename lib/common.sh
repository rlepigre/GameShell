#!/bin/bash

if [ -z "$GSH_ROOT" ]
then
 echo "Error: GSH_ROOT undefined"
 exit 1
fi

TEXTDOMAINDIR="$GSH_ROOT/locale"
TEXTDOMAIN="gsh"

# generate GameShell translation files for gettext
shopt -s nullglob
for PO_FILE in "$GSH_ROOT"/i18n/*.po; do
  PO_LANG=$(basename "$PO_FILE" .po)
  MO_FILE="$GSH_ROOT/locale/$PO_LANG/LC_MESSAGES/$TEXTDOMAIN.mo"
  if ! [ -f "$MO_FILE" ] || [ "$PO_FILE" -nt "$MO_FILE" ]
  then
    mkdir -p "$GSH_ROOT/locale/$PO_LANG/LC_MESSAGES"
    msgfmt -o "$GSH_ROOT/locale/$PO_LANG/LC_MESSAGES/$TEXTDOMAIN.mo" "$PO_FILE"
  fi
done
shopt -u nullglob


case $OSTYPE in
  linux|linux-gnu|linux-gnueabihf)
    # shellcheck source=./lib/common_gnu.sh
    source "$GSH_ROOT"/lib/common_gnu.sh
    ;;
  darwin*)
    # shellcheck source=./lib/common_macos.sh
    source "$GSH_ROOT"/lib/common_macos.sh
    ;;
  freebsd*|netbsd*|openbsd*)
    # shellcheck source=./lib/common_bsd.sh
    source "$GSH_ROOT"/lib/common_bsd.sh
    ;;
  *)
    read -erp "$(eval_gettext "Error: unknown system: OSTYPE=\$OSTYPE.
GameShell will use 'gnu-linux', without guarantee.")"
    read -serpn1 "$(gettext "Press any key to continue.")"
    # shellcheck source=./lib/common_gnu.sh
    source "$GSH_ROOT"/lib/common_gnu.sh
    ;;
esac
if ! bash "$GSH_ROOT/lib/common_test.sh"
then
  echo "$(gettext "Error: a least one base function is not working properly.
Aborting!")"
  exit 1
fi

export GSH_ROOT=$(REALPATH "$GSH_ROOT")
export TEXTDOMAINDIR="$GSH_ROOT/locale"

textdomainname() {
  local MISSION_DIR=$(REALPATH "$1")  # follow symbolic links to make sure translation is found
  echo "${MISSION_DIR#$GSH_MISSIONS/}" | tr "/" ","
}
export -f textdomainname

# simple "echo" command with colors
color_echo() {
  local color
  case "$1" in
    black   | bk) color=0; shift;;
    red     |  r) color=1; shift;;
    green   |  g) color=2; shift;;
    yellow  |  y) color=3; shift;;
    blue    |  b) color=4; shift;;
    magenta |  m) color=5; shift;;
    cyan    |  c) color=6; shift;;
    white   |  w) color=7; shift;;
    *) color=7;;
  esac
  if [ -n "$GSH_COLOR" ]
  then
    tput setaf $color 2>/dev/null
    echo "$@"
    tput sgr0 2>/dev/null
  else
    echo "$@"
  fi
}

# draws a parchment around a text file
parchment() {
  local file=$1
  [ -n "$file" ] && [ ! -e "$file" ] && return 1
  local P=$2
  [ -z "$P" ] && P=$(( 16#$(CHECKSUM "$GSH_UID:$MISSION_DIR" | cut -c 10-17) % 7 ))
  case "$P" in
    0) P="Parchment1";;
    1) P="Parchment2";;
    2) P="Parchment3";;
    3) P="Parchment4";;
    4) P="Parchment5";;
    5) P="Parchment6";;
    6) P="Parchment7";;
    7) P="Parchment8";;
    8) P="Parchment9";;
  esac
  echo
  if command -v python3 &> /dev/null
  # if available, use the python box8.py script
  then
    if [ -z "$file" ]
    then
      python3 "$GSH_UTILS/box8.py" --center --box="$P"
    else
      python3 "$GSH_UTILS/box8.py" --center --box="$P" < "$file"
    fi
  else
  # if not, use the awk version
    if [ -z "$file" ]
    then
      bash "$GSH_UTILS/box.sh" "$P"
      rm -f "$tempfile"
    else
      bash "$GSH_UTILS/box.sh" "$P" "$file"
    fi
  fi
  echo
}

# display a treasure message
treasure_message() {
  local WIDTH=31  # width of treasure-chest.txt file (wc -L)
  paste "$GSH_LIB/ascii-art/treasure-chest.txt" "$1" | awk -v width=$WIDTH -v seed=$RANDOM '
BEGIN{
    srand(seed) ;
    chars = ".\",-_ ";
}
/^\t/ {
    s = "";
    for (i=0; i<width; i++) {
        if (rand() < 0.05) {
            s = s "" substr(chars, int(rand()*length(chars)), 1);
        } else {
            s = s " ";
        }
    }
    print s "" $0;
}
/^[^\t]/ { print $0; }
' | column -t -s$'\t'
}

# ask admin password, except in DEBUG mode
admin_mode() {
  if [ "$GSH_MODE" = "DEBUG" ]
  then
    return 0
  fi

  if ! [ -f "$GSH_CONFIG/admin_hash" ]
  then
    echo "$(gettext "Error: you are not allowed to run this command.")" >&2
    return 1
  fi

  local HASH=$(cat "$GSH_CONFIG/admin_hash")
  local try=0
  # NOTE: seq is not POSIX compliant
  while [ "$try" -lt 3 ]
  do
    read -serp "$(gettext "password:" )" mdp
    echo
    if [ "$(CHECKSUM "$mdp")" = "$HASH" ]
    then
      return 0
    fi
    try=$((try+1))
  done
  echo "$(gettext "Error: wrong password")" >&2
  return 1
}


# this function is used to source a mission file with the corresponding
# MISSION_DIR and TEXTDOMAIN values. Since those values are derived from the
# directory containing the file, **the file MUST be in the root directory of
# the mission**.
# The current values of MISSION_DIR and TEXTDOMAIN are saved and restored
# after.
# Also, in DEBUG mode, is compares the environment before / after to make it
# easier to detect variables that haven't been unset.
# NOTE: MISSION_DIR and TEXTDOMAIN refer to the physical location (symbolic
# links are resolved), while MISSION_NAME refers to the logical location of the
# file.
mission_source() {
  local FILENAME=$1
  # the function corresponding to the file name:
  #   static.sh => _mission_static
  #   check.sh => _mission_check
  #   etc.
  local MISSION_FN=$(basename "$FILENAME")
  case "$MISSION_FN" in
    auto.sh | check.sh | clean.sh | deps.sh | init.sh | static.sh | test.sh)
      MISSION_FN=_mission_${MISSION_FN%.*}
      ;;
    *)
      MISSION_FN='^\s*$'
      ;;
  esac
  # if we are not running in DEBUG mode, just source the file
  if [ "$GSH_MODE" != "DEBUG" ] || [ -z "$GSH_VERBOSE_DEBUG" ]
  then
    echo "DEBUG: sourcing ${FILENAME#GSH_ROOT/}"
    local _MISSION_DIR=$MISSION_DIR
    export MISSION_DIR=$(dirname "$(REALPATH "$FILENAME")")
    local _TEXTDOMAIN=$TEXTDOMAIN
    export TEXTDOMAIN=$(textdomainname "$MISSION_DIR")
    local _MISSION_NAME=$MISSION_NAME
    export MISSION_NAME=${FILENAME#$GSH_MISSIONS/}
    local _PATH=$PATH
    export PATH=$PATH:$GSH_SBIN
    source "$FILENAME"
    local exit_status=$?
    export TEXTDOMAIN=$_TEXTDOMAIN
    export MISSION_NAME=$_MISSION_NAME
    export MISSION_DIR=$_MISSION_DIR
    export PATH=$_PATH
    unset -f "$MISSION_FN"
    return $exit_status
  fi

  local TEMP=$(mktemp -d "$GSH_VAR/env-XXXXXX")
  local source_ret_value=""  # otherwise, it appears in the environment!
  local _MISSION_DIR=""
  local _TEXTDOMAIN=""
  local _MISSION_NAME=""
  local MISSION_NAME=""
  local _PATH=""
  local exit_status=""

  # otherwise, record the environment (variables, functions and aliases)
  # before and after to echo a message when there are differences
  compgen -v | sort > "$TEMP"/before-V
  compgen -A function | sort > "$TEMP"/before-F
  compgen -a | sort > "$TEMP"/before-A
  local _MISSION_DIR=$MISSION_DIR
  export MISSION_DIR=$(dirname "$(REALPATH "$FILENAME")")
  _TEXTDOMAIN=$TEXTDOMAIN
  export TEXTDOMAIN=$(textdomainname "$MISSION_DIR")
  _MISSION_NAME=$MISSION_NAME
  export MISSION_NAME=${FILENAME#$GSH_MISSIONS/}
  local _PATH=$PATH
  export PATH=$PATH:$GSH_SBIN
  source "$FILENAME"
  exit_status=$?
  export TEXTDOMAIN=$_TEXTDOMAIN
  export MISSION_NAME=$_MISSION_NAME
  export MISSION_DIR=$_MISSION_DIR
  export PATH=$_PATH
  compgen -v | sort > "$TEMP"/after-V
  compgen -A function | sed "/$MISSION_FN/d" | sort > "$TEMP"/after-F
  compgen -a | sort > "$TEMP"/after-A

  local msg="DEBUG: environment modifications while sourcing .../${FILENAME#$GSH_ROOT/}"
  if ! cmp -s "$TEMP"/{before,after}-V
  then
    [ -n "$msg" ] && echo "$msg"
    msg=""
    echo "variables before / after"
    comm -3 "$TEMP"/{before,after}-V
  fi

  if ! cmp -s "$TEMP"/{before,after}-F
  then
    [ -n "$msg" ] && echo "$msg"
    msg=""
    echo "functions before / after"
    comm -3 "$TEMP"/{before,after}-F
  fi

  if ! cmp -s "$TEMP"/{before,after}-A
  then
    [ -n "$msg" ] && echo "$msg"
    msg=""
    echo "Alias before / after"
    comm -3 "$TEMP"/{before,after}-A
  fi

  rm -rf "$TEMP"
  unset -f "$MISSION_FN"
  return $exit_status
}

# display some info about the system
systemconfig() {
  echo "========================="
  echo "OSTYPE=$OSTYPE"
  echo "========================="
  echo "uname -a"
  uname -a
  echo "========================="
  echo "bash --version"
  bash --version | head -n1
  echo "========================="
  echo "awk --version"
  (awk -Wversion 2>/dev/null || awk --version 2>/dev/null || awk -V 2>/dev/null) | head -n1
  echo "========================="
}

# parse a single mission
parse_mission() {
  local MISSION_DIR=$1
  case $MISSION_DIR in
     # "dummy" mission: it will only be used during the initialisation phase
    "!"*)
      DUMMY="!"
      MISSION_DIR=$(echo "$MISSION_DIR" | cut -c2-)
      ;;

    # standard mission
    *)
      DUMMY=""
      ;;
  esac

  # if the mission is in fact a file, we assume it is an index file,
  # we call parse_index recursively
  if [ -f "$MISSION_DIR" ]
  then
    parse_index "$MISSION_DIR"
  elif [ -d "$MISSION_DIR" ]
  then
    # if a directory contains index.txt, call parse_index recursively
    if  [ -f "$MISSION_DIR/index.txt" ]
    then
      parse_index "$MISSION_DIR/index.txt"

    # if a directory contains a check.sh script, it is a standard mission
    elif  [ -f "$MISSION_DIR/check.sh" ] || [ -n "$DUMMY" ]
    then
      echo "$DUMMY${MISSION_DIR#$GSH_MISSIONS/}"

    # when given a directory containing either a "bin" directory or a
    # "static.sh" script, this is a dummy mission. Just print the path
    # prefixed with a "!"
    elif [ -f "$MISSION_DIR/static.sh" ] || [ -d "$MISSION_DIR/bin" ]
    then
      echo "!${MISSION_DIR#$GSH_MISSIONS/}"

    else
      echo "***** invalid argument (parse_mission): '$MISSION_DIR'" >&2
    fi
  else
    echo "***** invalid argument (parse_mission): '$MISSION_DIR'" >&2
  fi
}


# generate an index of missions
# parse_index take a single argument: a path to an index file
parse_index() {
  local index_file=$(REALPATH "$1")
  local dir DUMMY

  case "$index_file" in
    "$GSH_MISSIONS"* )
      # if the index file lives under $GSH_MISSIONS, the "current root
      # directory" for missions is just dirname $index_file: all missions read
      # from the file will be relative to $dir
      dir=$(dirname "$index_file")
      ;;
    *)
      # otherwise, we assume all the missions in the file are given relative to
      # $GSH_MISSIONS
      dir=$GSH_MISSIONS
      ;;
  esac

  cat "$index_file" | while read MISSION_DIR
  do
  case $MISSION_DIR in
    # ignore comments and empty lines
    "" | "#"* )
      continue
      ;;

     # "dummy" mission: it will only be used during the initialisation phase
    "!"*)
      DUMMY="!"
      MISSION_DIR=$(echo "$MISSION_DIR" | cut -c2-)
      ;;

    # standard mission
    *)
      DUMMY=""
      ;;
  esac
  MISSION_DIR=$dir/$MISSION_DIR
  if [ -e "$MISSION_DIR" ]
  then
    parse_mission "$DUMMY$(REALPATH "$MISSION_DIR")"
  else
    echo "***** invalid argument (parse_index): '${MISSION_DIR#$GSH_MISSIONS/}'" >&2
  fi
  done
}

make_index() {
  if [ "$#" -eq 0 ]
  then
    # without argument, use the default index file
    parse_index "$GSH_MISSIONS/index.txt"
    return 0
      # when given a directory containing either a "bin" directory or a
      # "static.sh" script, this is a dummy mission. Just print the path
      # prefixed with a "!"
  fi

  while [ "$#" -gt 0 ]
  do
    local MISSION_DIR=$(REALPATH "$1")
    if [ -e "$MISSION_DIR" ]
    then
      parse_mission "$MISSION_DIR"
    else
      echo "***** invalid argument (make_index): '$1'" >&2
    fi
    shift
  done
}

sed-i() {
  if [ $# -gt 2 ]
  then
    echo "usage: sed-i 'EXPRESSION' FILENAME" >&2
    return 1
  fi
  local expr=$1
  local filename=$2
  local tmp=$(mktemp)
  local bak="$filename~"
  trap "rm -f \"$tmp\" \"$bak\"" SIGTERM SIGINT
  if sed -e "$expr" "$filename" > "$tmp"
  then
    cp "$filename" "$bak"
    trap "" SIGTERM SIGINT
    cp "$tmp" "$filename"
    rm -f "$tmp" "$bak"
  else
    local ret=$?
    rm -f "$tmp" "$bak"
    return $ret
  fi
}
export -f sed-i

# vim: shiftwidth=2 tabstop=2 softtabstop=2
