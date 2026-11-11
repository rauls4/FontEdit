# FontEdit

A native macOS editor for Atari XL/XE bitmap fonts and font-based screens. Based on the file formats and editing workflow of [Atari FontMaker](https://github.com/matosimi/atari-fontmaker) by matosimi and RetroCoder. The build fetches the default font and Altirra PAL color table from a pinned upstream revision and verifies their SHA-256 checksums.

## Run

With Xcode or its Command Line Tools installed, run `./build.sh`, then open `build/FontEdit.app` in Finder. The build targets the current Mac’s architecture and requires macOS 14 or later. The first build needs internet access to fetch the Atari resources.

Run `./check.sh` to verify the file and pixel operations. Pass an original `.atrview` file to check its round-trip.

## Edit

- Select a font bank and click a character in the bank grid. The bottom half shows the inverse screen codes. The glyph editor edits the underlying eight bytes.
- Drag to draw and right-drag to write pixel value zero. Rewrite toggles the starting pixel between the selected value and zero, then applies that value for the entire stroke. Insert applies the selected value directly.
- Paint characters in the screen editor. Right-click to pick a character and its bank. Click a row number to change its font bank, or right-click to cycle backwards.
- Use the page menu to add, duplicate, rename, resize, or remove pages. Insert Text maps printable ASCII to Atari screen codes.
- Save an `.atrview` to keep all four banks, screen pages, and colors. Import or export standalone raw font banks with `.fnt` files.

FontEdit reads Atari FontMaker JSON views and imports legacy `.vfn` and version 2/3 `.vf2` screens. It exports raw screens, PNG images, Assembly, and C arrays. Existing tile records are preserved on save. The upstream Mega Copy workflow, tile-set editing, and ZX compression are outside this version.
