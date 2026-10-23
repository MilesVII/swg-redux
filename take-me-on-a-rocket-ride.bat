odin build . -subsystem:windows
@echo off
start "" "./swg-redux" --mode lobby
start "" "./swg-redux" --name alpha
start "" "./swg-redux" --name beta