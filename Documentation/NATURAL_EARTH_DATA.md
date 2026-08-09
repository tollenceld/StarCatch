# Natural Earth coastline data

`StarCatch/Resources/earth_coastlines_50m.bin` is derived from the Natural Earth
1:50m physical coastline dataset. Natural Earth data is in the public domain.

- Source: https://www.naturalearthdata.com/downloads/50m-physical-vectors/50m-coastline/
- Upstream vector repository: https://github.com/nvkelso/natural-earth-vector
- App transform: Douglas–Peucker simplification at 0.30 degrees, then Float32
  latitude/longitude encoding by `Scripts/compile_coastlines.py`.

The binary is bundled for offline rendering. The app performs no map download and
does not parse GeoJSON at runtime.
