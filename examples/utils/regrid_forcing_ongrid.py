"""Build on-grid daily flux forcing for MOM6's solo-driver "file" forcing (WIND_CONFIG = BUOY_CONFIG =
"file"), the way examples/cesm_t232 is forced, for the run window of a standalone perf example.
Source: the tx2_3v2 forcing of examples/cesm_t232 (365 daily records + 12 monthly precip/runoff
records). Every target cell takes the value of the nearest *wet* tx2_3v2 cell (no missing values).
usage: regrid_forcing_ongrid.py <hgrid supergrid file> <ndays> <output file>"""
import sys, numpy as np, netCDF4 as nc
from scipy.spatial import cKDTree
src = "/glade/work/altuntas/mom6.standalone.runs/cesm/INPUT/t232"
hgrid, ndays, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
def xyz(lon, lat):
    la = np.deg2rad(lat); lo = np.deg2rad(lon)
    return np.stack([np.cos(la)*np.cos(lo), np.cos(la)*np.sin(lo), np.sin(la)], -1)
geo = nc.Dataset(f"{src}/ocean_geometry.nc")
glon = geo["geolon"][:].filled(np.nan); glat = geo["geolat"][:].filled(np.nan); wet = geo["wet"][:].filled(0) > 0.5
wet_idx = np.flatnonzero(wet.ravel())
tree = cKDTree(xyz(glon.ravel()[wet_idx], glat.ravel()[wet_idx]))
h = nc.Dataset(hgrid); x = h["x"][:].filled(0); y = h["y"][:].filled(0)
tlon = x[1::2, 1::2]; tlat = y[1::2, 1::2]                       # cell centres of the target grid
ny, nx = tlon.shape; print("target", nx, "x", ny, flush=True)
flat = np.empty(tlon.size, dtype=np.int64)
for s in range(0, tlon.size, 2_000_000):                         # chunked KD-tree query
    _, nn = tree.query(xyz(tlon.ravel()[s:s+2_000_000], tlat.ravel()[s:s+2_000_000])); flat[s:s+2_000_000] = wet_idx[nn]
print("mapping done", flush=True)
ds = nc.Dataset(out, "w", format="NETCDF4_CLASSIC")
ds.createDimension("time", None); ds.createDimension("yh", ny); ds.createDimension("xh", nx)
v = ds.createVariable("xh", "f8", ("xh",)); v[:] = x[1, 1::2]; v.units = "degrees_east"; v.cartesian_axis = "X"; v.long_name = "nominal longitude (supergrid row 1)"
v = ds.createVariable("yh", "f8", ("yh",)); v[:] = y[1::2, 2*(nx//2)+1]; v.units = "degrees_north"; v.cartesian_axis = "Y"; v.long_name = "nominal latitude (supergrid column nx/2)"
v = ds.createVariable("time", "f8", ("time",)); v[:] = np.arange(ndays) + 0.5
v.units = "days since 0001-01-01 00:00:00"; v.calendar = "noleap"; v.cartesian_axis = "T"
ds.source = f"{src}/ocean_forcing_daily.nc + ocean_precip_monthly.nc, nearest wet-cell regrid to the cell centres of {hgrid} (regrid_forcing_ongrid.py)"
ds.history = "created 2026-10-28 for the turbo-stack standalone perf examples (solo-driver file forcing)"
d = nc.Dataset(f"{src}/ocean_forcing_daily.nc"); p = nc.Dataset(f"{src}/ocean_precip_monthly.nc")
mstart = np.cumsum([0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30])     # noleap month start days
month_of_day = np.searchsorted(mstart, np.arange(ndays), side="right") - 1
for vin, srcds, daily in [("taux", d, 1), ("tauy", d, 1), ("SW", d, 1), ("LW", d, 1), ("latent", d, 1), ("sensible", d, 1), ("evap", d, 1),
                          ("liq_precip", p, 0), ("froz_precip", p, 0), ("liq_runoff", p, 0), ("froz_runoff", p, 0)]:
    a = srcds[vin]; o = ds.createVariable(vin, "f4", ("time", "yh", "xh"))
    o.long_name = getattr(a, "long_name", vin) + ("" if daily else " (monthly value repeated daily)"); o.units = getattr(a, "units", "")
    for t in range(ndays):
        rec = t if daily else month_of_day[t]
        blk = a[rec].filled(np.nan).ravel()[flat].reshape(ny, nx)
        if np.isnan(blk).any(): raise RuntimeError(f"NaN in {vin} rec {rec}")
        o[t] = blk
    print("done", vin, flush=True)
ds.close(); print("ALL DONE")
