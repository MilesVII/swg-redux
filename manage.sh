#!/usr/bin/env bash
# interactive manager for an ubuntu deployment: shows whether the lobby runs,
# starts or stops it, and updates it from git
#
# the lobby and the game servers it spawns are all the same executable, so every
# process started from EXE counts as part of the deployment

EXE="${SWGR_EXE:-/opt/swgr/swgr}"
REPO="$(dirname "$EXE")"
LOG="$REPO/swgr.log"
# arguments for the lobby, config.toml next to the executable sets the rest
START_ARGS=(--mode lobby)
STOP_PATIENCE_S=5

set -u

say() { printf '%s\n' "$*"; }
hr() { printf -- '--------------------------------------------\n'; }

# pids of every process running EXE, lobby first
pids() { pgrep -f "^$EXE( |$)" 2>/dev/null; }

running() { [ -n "$(pids)" ]; }

status() {
	hr
	if ! running; then
		say "$EXE is NOT RUNNING"
		if [ -f "$EXE" ]; then
			say "binary built: $(date -r "$EXE" '+%Y-%m-%d %H:%M')"
		else
			say "binary missing, update to build it"
		fi
		hr
		return
	fi
	say "$EXE is RUNNING"
	local pid etime args
	while read -r pid etime args; do
		case "$args" in
			*--managed*) say "  game server  pid $pid  up $etime  ${args#"$EXE" --managed}" ;;
			*)           say "  lobby        pid $pid  up $etime" ;;
		esac
	done < <(ps -o pid=,etime=,args= -p "$(pids | paste -sd,)" 2>/dev/null)
	hr
}

start() {
	if running; then
		say "already running"
		return
	fi
	if [ ! -x "$EXE" ]; then
		say "no executable at $EXE, update first"
		return 1
	fi
	say "starting $EXE ${START_ARGS[*]}, log in $LOG"
	(cd "$REPO" && setsid nohup "$EXE" "${START_ARGS[@]}" >>"$LOG" 2>&1 &)
	sleep 1
	if running; then
		say "started"
	else
		say "it quit right away, last lines of the log:"
		tail -n 20 "$LOG" 2>/dev/null
		return 1
	fi
}

stop() {
	if ! running; then
		say "not running"
		return
	fi
	say "stopping lobby and game servers"
	pkill -TERM -f "^$EXE( |$)"
	local waited=0
	while running && [ "$waited" -lt "$STOP_PATIENCE_S" ]; do
		sleep 1
		waited=$((waited + 1))
	done
	if running; then
		say "still alive after ${STOP_PATIENCE_S}s, killing"
		pkill -KILL -f "^$EXE( |$)"
		sleep 1
	fi
	running && { say "could not stop it"; return 1; }
	say "stopped"
}

update() {
	if running; then
		stop || return 1
	fi
	say "updating $REPO"
	# an explicit chain: `set -e` is ignored inside a subshell that's part of an || list
	(
		cd "$REPO" &&
		git stash &&
		git stash clear &&
		git pull &&
		odin build . -define:HEADLESS=true -out:"$EXE"
	) || {
		say "UPDATE FAILED, see above"
		return 1
	}
	say "updated and built"
	local answer
	read -rp "start it now? [Y/n] " answer
	case "$answer" in
		n|N) ;;
		*) start ;;
	esac
}

logs() {
	if [ -f "$LOG" ]; then
		tail -n 40 "$LOG"
	else
		say "no log at $LOG yet"
	fi
}

for tool in pgrep pkill git odin; do
	command -v "$tool" >/dev/null || { say "missing $tool"; exit 1; }
done

while true; do
	status
	if running; then
		say "  u) update (stops it first)   s) stop   l) log   q) quit"
	else
		say "  u) update   s) start   l) log   q) quit"
	fi
	read -rp "> " choice
	case "$choice" in
		u|U) update ;;
		s|S) if running; then stop; else start; fi ;;
		l|L) logs ;;
		q|Q|"") exit 0 ;;
		*) say "u, s, l or q" ;;
	esac
	echo
done
