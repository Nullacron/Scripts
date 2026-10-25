# Scripts

This repository is a small collection of utilities and automation scripts I've put together for game modding, config generation, and browser automation. Most of the files here were created by me or with the help of AI, and they focus on practical tools for Source Engine workflows and a few quality-of-life helpers for web-based games.

The goal is to make repetitive tasks easier: packaging mod files into VPKs, converting data dumps into clean config files, and automating browser-based gameplay loops where manual repetition would be tedious.

## Repository overview

The scripts in this repo are split between two main areas:

- Source Engine tools for modding and config generation
- Browser automation utilities for game tasks and repetitive actions

These are lightweight, task-focused scripts rather than large applications, intended to save time during mod development or gameplay automation.

## Files

### `AutoVPK.ps1`
Creates a ready-to-use `pak01_dir.vpk` from a mod folder using VPKEdit CLI. It helps streamline the workflow of packaging a Source Engine mod by letting you select a folder, choose a destination, remember your last output path, and automatically remove outdated `pak01*.vpk` files before rebuilding. This is useful when iterating on a mod and needing a quick, repeatable packaging step.

### `CVARLIST Format Tool.ps1`
Converts Source Engine `CVARLIST` CSV exports into clean, organized `.cfg` files. It supports filtering by command type, handling flags, grouping entries into sections, and customizing naming and output structure. This is especially helpful when working with large lists of console variables and wanting more readable, usable config files instead of raw export data.

### `NealFun Stimulation Script.js`
A browser userscript for the NealFun “Stimulation” game. It adds a control panel that automates repeated gameplay tasks such as clicking, minigame actions, upgrades, stock trading, inbox handling, and muting audio. It is designed to reduce the amount of manual clicking and micromanagement required during long play sessions.

### `SAR Dump Format Tool.ps1`
Formats SAR JSON dump data into readable `.cfg` files in the same spirit as the CVARLIST formatter, but tailored to Source Engine SAR plugin command dumps. It can separate game commands from SAR-specific entries, tag SAR commands, and generate organized output files that are easier to review and use. This is useful for developers working with large command dumps that need to be turned into structured config content.

## Usage

These scripts are intended to be practical, direct tools rather than polished end-user applications. Some are Windows PowerShell utilities for Source Engine modding, while others are browser automation scripts meant to assist with repetitive in-game tasks.

The repository is still evolving, and the scripts may be updated over time as workflows change or new utilities are added.

## Notes

Most of these scripts were created by me or with the help of AI, and they reflect a hands-on approach to solving common tasks in a fast and practical way.
