#+build windows
package game

import "core:os"
import win32 "core:sys/windows"

// Game servers the lobby starts are put in a job object that kills them when the lobby
// dies, however it dies: a closed console, Ctrl+C or Task Manager. Without it a server
// outlives a lobby that was ended by force, listening on its port with nobody to clean up.

// not in core:sys/windows
foreign import kernel32 "system:Kernel32.lib"
@(default_calling_convention="system")
foreign kernel32 {
	CreateJobObjectW :: proc(lpJobAttributes: ^win32.SECURITY_ATTRIBUTES, lpName: win32.LPCWSTR) -> win32.HANDLE ---
	SetInformationJobObject :: proc(hJob: win32.HANDLE, JobObjectInformationClass: i32, lpJobObjectInformation: rawptr, cbJobObjectInformationLength: win32.DWORD) -> win32.BOOL ---
	AssignProcessToJobObject :: proc(hJob: win32.HANDLE, hProcess: win32.HANDLE) -> win32.BOOL ---
}

@(private="file")
JobObjectExtendedLimitInformation :: i32(9)
@(private="file")
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE :: win32.DWORD(0x2000)

@(private="file")
JOBOBJECT_BASIC_LIMIT_INFORMATION :: struct {
	PerProcessUserTimeLimit: i64,
	PerJobUserTimeLimit: i64,
	LimitFlags: win32.DWORD,
	MinimumWorkingSetSize: uint,
	MaximumWorkingSetSize: uint,
	ActiveProcessLimit: win32.DWORD,
	Affinity: uint,
	PriorityClass: win32.DWORD,
	SchedulingClass: win32.DWORD
}
@(private="file")
IO_COUNTERS :: struct {
	ReadOperationCount, WriteOperationCount, OtherOperationCount: u64,
	ReadTransferCount, WriteTransferCount, OtherTransferCount: u64
}
@(private="file")
JOBOBJECT_EXTENDED_LIMIT_INFORMATION :: struct {
	BasicLimitInformation: JOBOBJECT_BASIC_LIMIT_INFORMATION,
	IoInfo: IO_COUNTERS,
	ProcessMemoryLimit: uint,
	JobMemoryLimit: uint,
	PeakProcessMemoryUsed: uint,
	PeakJobMemoryUsed: uint
}

// one job for all the servers, never closed: it goes when the lobby's process does
@(private="file")
childJob: win32.HANDLE

// ties a started server's life to the lobby's; false when Windows wouldn't allow it
bindChildToLobby :: proc(process: os.Process) -> bool {
	if childJob == nil {
		childJob = CreateJobObjectW(nil, nil)
		if childJob == nil do return false
		limits := JOBOBJECT_EXTENDED_LIMIT_INFORMATION {}
		limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
		if !SetInformationJobObject(childJob, JobObjectExtendedLimitInformation, &limits, size_of(limits)) {
			win32.CloseHandle(childJob)
			childJob = nil
			return false
		}
	}
	return bool(AssignProcessToJobObject(childJob, win32.HANDLE(process.handle)))
}
