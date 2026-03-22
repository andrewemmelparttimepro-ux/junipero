# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## What Goes Here

Things like:

- Camera names and locations
- SSH hosts and aliases
- Preferred voices for TTS
- Speaker/room names
- Device nicknames
- Anything environment-specific

## Examples

```markdown
### Cameras

- living-room → Main area, 180° wide angle
- front-door → Entrance, motion-triggered

### SSH

- home-server → 192.168.1.100, user: admin

### TTS

- Preferred voice: "Nova" (warm, slightly British)
- Default speaker: Kitchen HomePod
```

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

## CLI Tools

### CLI-Anything

- Repo: `tools/CLI-Anything`
- Virtualenv: `.venvs/cli-anything`
- Blender CLI command: `. .venvs/cli-anything/bin/activate && cli-anything-blender --help`
- Native Blender binary: `/Applications/Blender.app/Contents/MacOS/Blender`

### Brain Drive

- Mounted at: `/Volumes/brain`
- NDAI root: `/Volumes/brain/NDAI`
- Organized by Andrew, Thrawn, R2-D2, C-3PO, Qui-Gon, Lando, Boba, Shared, Projects, Reports, Assets, and Archive

#### Assets Folder (canonical location for all creative assets)
- Root: `/Volumes/brain/NDAI/Assets/`
- Profile Pictures: `/Volumes/brain/NDAI/Assets/Images/Profile Pictures/`
- Brand Marks: `/Volumes/brain/NDAI/Assets/Images/Brand Marks/`
- Generated (unsorted AI output): `/Volumes/brain/NDAI/Assets/Images/Generated/`
- Logos: `/Volumes/brain/NDAI/Assets/Images/Logos/`
- Icons: `/Volumes/brain/NDAI/Assets/Icons/`
- Fonts: `/Volumes/brain/NDAI/Assets/Fonts/`
- Video: `/Volumes/brain/NDAI/Assets/Video/`
- Audio: `/Volumes/brain/NDAI/Assets/Audio/`
- **All future AI-generated assets go here, never to Desktop or temp dirs**

Add whatever helps you do your job. This is your cheat sheet.
