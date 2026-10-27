This repository is a small collection of utilities and automation scripts I've put together for game modding, config generation, and browser automation. Most of the files here were created by me or with help from other modding resources and personal scripts over time.

## Files

### [AutoVPK.ps1](/AutoVPK.ps1)
Creates a ready-to-use `pak01_dir.vpk` from a mod folder using VPKEdit CLI. It helps streamline the workflow of packaging a Source Engine mod by letting you select a folder, choose a destination, remember the output path, and generate the final VPK with minimal manual work.

### [CVAR Dump Format Tool (P2CE).ps1](/CVAR%20Dump%20Format%20Tool%20(P2CE).ps1)
Converts P2CE dump exports into clean, organized `.cfg` files. It supports filtering by command type, grouping entries into sections, and customizing naming and output formatting for easier mod configuration work.

### [CVAR Dump Format Tool (SAR).ps1](/CVAR%20Dump%20Format%20Tool%20(SAR).ps1)
Formats SAR JSON dump data into readable `.cfg` files in the same spirit as the Source Engine formatter, but tailored to Source Engine SAR plugin command dumps. It can separate game commands from SAR-specific commands and organize them into cleaner output.

### [CVAR Dump Format Tool (Source).ps1](/CVAR%20Dump%20Format%20Tool%20(Source).ps1)
Converts Source Engine `CVARLIST` CSV exports into clean, organized `.cfg` files. It supports filtering by command type, handling flags, grouping entries into sections, and customizing naming and output formatting.

### [NealFun Stimulation Script.js](/NealFun%20Stimulation%20Script.js)
A browser userscript for the NealFun “Stimulation” game. It adds a control panel that automates repeated gameplay tasks such as clicking, minigame actions, upgrades, stock trading, inbox handling, and other repetitive actions to help run the game more efficiently.

## Note
These scripts are not meant to be polished end-use applications, their just scripts that I made with AI to make things easier for me to do stuff.
