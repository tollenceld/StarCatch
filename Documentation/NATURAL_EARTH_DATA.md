# Natural Earth coastline data

`StarCatch/Resources/earth_coastlines_50m.bin` is derived from the Natural Earth
1:50m physical coastline dataset. Natural Earth data is in the public domain.

`StarCatch/Resources/earth_land_dots_50m.bin` is derived from the matching Natural
Earth 1:50m land polygon dataset. It is the primary globe surface treatment: a
deterministic, approximately equal-area Fibonacci lattice is clipped to land at
build time, and each retained sample stores a coastal-proximity size class.

- Source: https://www.naturalearthdata.com/downloads/50m-physical-vectors/50m-coastline/
- Land source: https://www.naturalearthdata.com/downloads/50m-physical-vectors/50m-land/
- Upstream vector repository: https://github.com/nvkelso/natural-earth-vector
- App transform: Douglas–Peucker simplification at 0.30 degrees, then Float32
  latitude/longitude encoding by `Scripts/compile_coastlines.py`.
- Land transform: 20,000 deterministic equal-area candidates, clipped to the land
  polygons and classified by nearby water samples, then encoded by
  `Scripts/compile_land_dots.py`.

The binaries are bundled for offline rendering. The app performs no map download,
does not parse GeoJSON or shapefiles at runtime, and never evaluates land polygons
inside the 30fps Canvas path. The coastline asset remains a loading/corruption
fallback so continents never disappear.
