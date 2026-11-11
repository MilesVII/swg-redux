odin build . -subsystem:windows
@echo off
rem the lobby in a window of its own, waiting on the windowless build;
rem closing the window stops the lobby and the game servers it started
start "swg lobby" cmd /c "start /b /wait swg-redux.exe --mode lobby"
start "" "./swg-redux" --name alpha
start "" "./swg-redux" --name beta