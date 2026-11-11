#+build !windows
package game

import "core:os"

// on other systems servers aren't tied to the lobby's life; manage.sh stops them by name
bindChildToLobby :: proc(process: os.Process) -> bool {
	return false
}
