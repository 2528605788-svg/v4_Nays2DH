# Dynamic Vegetation Nays2DH for iRIC Design

## Goal

Produce an iRIC v4 solver derived from the official `v4_Nays2DH` source that preserves Nays2DH hydrodynamics and sediment transport while adding physically constrained vegetation growth and scour mortality. Compile it in GitHub Actions with Intel `ifx`, so no Intel compiler is installed locally.

## Scope

The first version models above-ground vegetation effects only:

- retain the existing Nays2DH shallow-water, sediment-transport, bed-evolution, wetting/drying, and iRIC CGNS interfaces;
- retain the existing vegetation body drag term based on vegetation density, height, and drag coefficient;
- update vegetation density and height during the simulation using bounded growth and hydraulic/scour mortality;
- expose vegetation parameters and vegetation result fields in iRIC;
- omit root-induced sediment reduction, root cohesion, bank reinforcement, seed dispersal, and species competition.

## Physical Model

Each wet or dry computational cell carries normalized vegetation occupancy `V` in `[0, 1]`. The existing iRIC grid field `vege_density` supplies the initial vegetation distribution. Actual drag density is `V * density_max`, and the existing Nays2DH body-drag formulation continues to act in both momentum directions.

Vegetation evolves at a configurable interval rather than every hydrodynamic iteration:

`dV/dt = r V (1 - V) - M V`

where `r` is the growth rate and `M` is mortality. Mortality increases smoothly when either bed shear stress or absolute bed-elevation change exceeds its configured tolerance. Cells that are continuously submerged above the configured vegetation tolerance receive no recruitment or growth. The numerical update clamps `V` to `[0, 1]`, density to non-negative values, and height to `[0, height_max]`.

This is deliberately a reduced process model. It is physically interpretable but is not a calibrated ecological succession model.

## Solver Integration

Vegetation state and parameters will be isolated in a focused Fortran module added to `src/Nays2DH.f90`, because the upstream project compiles that file as one translation unit. The main time loop will call the vegetation update after bed evolution has produced the current elevation change and before the next momentum solve uses `cd_veg` and `vege_h`.

The existing fields remain compatible:

- `vege_density`: initial vegetation density;
- `vege_height`: initial vegetation height;
- `c_tree`: body drag coefficient;
- `j_vege`: whether finite vegetation height is used.

New calculation-condition parameters will control enable/disable, growth rate, carrying density, maximum height, update interval, shear mortality threshold, bed-change mortality threshold, mortality rate, and inundation tolerance. Defaults will preserve the original static-vegetation behavior unless dynamic vegetation is explicitly enabled.

The solver will write vegetation occupancy, vegetation density, and vegetation height as iRIC solution fields alongside bed elevation, depth, velocity, and shear stress. This allows direct spatial comparison inside iRIC without an external plotting program.

## Cloud Build and Packaging

A Windows GitHub Actions workflow will:

1. install the current Intel Fortran compiler (`ifx`) in the hosted runner;
2. obtain or locate the iRIC import library needed by the upstream build;
3. compile `src/iric.f90` and `src/Nays2DH.f90` with OpenMP and the runtime options corresponding to the upstream build;
4. link `Nays2DH.exe` against `iriclib.lib`;
5. place the executable, `definition.xml`, translations, README, and license in an `iRICsolvers_v4_Nays2DH_Vegetation` directory;
6. upload that directory as a downloadable ZIP artifact.

The workflow will also support manual dispatch. Compiler installation and compilation occur only on the GitHub runner; the local machine receives only the packaged solver.

## Error Handling

The solver validates vegetation parameter ranges at startup and stops with a clear console message for negative rates, non-positive carrying density, invalid thresholds, or a non-positive update interval. Missing new parameters fall back to compatibility defaults. Every iRIC read/write used for the new fields checks the returned status code, and dynamic vegetation is disabled safely if its optional inputs are unavailable.

The build workflow fails before packaging if compilation, linking, or the expected executable check fails. It also records compiler version and artifact contents in the Actions log.

## Verification

Local tests that do not require Intel Fortran will verify the source contract: parameter definitions exist, defaults preserve static behavior, the update is inserted at the intended point, vegetation results are declared and written, and the workflow packages all required iRIC files.

Cloud verification will compile with `ifx`, confirm that `Nays2DH.exe` exists and is non-empty, and publish the ZIP. Installation verification will copy the ZIP contents into the iRIC v4 `solvers` directory, launch iRIC, confirm the solver appears separately from stock Nays2DH, open its calculation conditions, and run a minimal case that produces bed-elevation and vegetation result fields.

## Acceptance Criteria

- Stock Nays2DH remains installed and untouched.
- The new solver appears as a separate selectable solver in iRIC v4.
- With dynamic vegetation disabled, the source follows the original static vegetation path.
- With dynamic vegetation enabled, vegetation remains bounded and affects flow only through the existing body-drag term.
- Root-induced sediment reduction is absent from source, parameters, and result interpretation.
- GitHub Actions produces a downloadable, installable solver ZIP without a local oneAPI installation.
