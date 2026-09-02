# Upstream sources

- 3Dmigoto: https://github.com/bo3b/3Dmigoto.git
  - pinned commit: 8f329bd94fecc9bbcb9211ffd42a95dd7fe6b43e
  - license: GPL-3.0-only (see third_party/licenses/3Dmigoto-GPL-3.0.txt)
- genshin-fps-unlock: https://github.com/34736384/genshin-fps-unlock.git
  - pinned commit: 2b85d61dd06f6e11ad86fdd6bd90339f9abc58eb
  - license: MIT (see third_party/licenses/genshin-fps-unlock-MIT.txt)
- GI-Model-Importer (GIMI ecosystem reference): https://github.com/SilentNightSound/GI-Model-Importer.git
  - inspected commit: 4232c26
  - license and source remain upstream; this repository does not redistribute its mod files
- ReShade: https://github.com/crosire/reshade.git
  - inspected commit: ec0346e035b7d1c267103ea0d7c231b3945fc2b
  - license: BSD 3-Clause (see third_party/licenses/ReShade-BSD-3-Clause.md)

The binaries in the repository are built artifacts produced from the first two
projects after applying the patches under src/patches/. No Genshin game files,
mods, ReShade DLLs, presets, or user-specific absolute paths are included.
