# Bright Star background data

`StarCatch/Resources/bright_stars_bsc5p.bin` is derived from the NASA HEASARC
Bright Star Catalog (BSC5P), a machine-readable form of the Bright Star Catalog,
5th Edition, preliminary.

- Source table: https://heasarc.gsfc.nasa.gov/W3Browse/catalog/bsc5p.html
- Source export: https://heasarc.gsfc.nasa.gov/FTP/heasarc/dbase/tdat_files/heasarc_bsc5p.tdat.gz
- Catalogue reference: Hoffleit, D. and Warren, Jr., W.H. (1991),
  *The Bright Star Catalog, 5th Revised Edition (Preliminary Version)*.
- Retrieved: 2026-08-29.
- Transformation: `Scripts/compile_bright_stars.py` excludes the 14 non-stellar
  HR records identified by HEASARC, keeps finite J2000 positions with V magnitude
  at or brighter than 6.5, converts angles to radians, and emits a compact
  little-endian binary file containing HR, RA, Dec, V magnitude, and B-V colour.

The compiled asset is used only as an offline visual background. It does not
participate in satellite capture, filtering, or visibility decisions, and the app
does not contact HEASARC at runtime.
