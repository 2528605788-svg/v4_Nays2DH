# Dynamic Vegetation Nays2DH for iRIC Design

## Goal

Produce an iRIC v4 solver derived from the official `v4_Nays2DH` source that preserves Nays2DH hydrodynamics and sediment transport while adding physically constrained vegetation growth and scour mortality. Compile it in GitHub Actions with Intel Classic Fortran `ifort` 2023.1, the earliest official installer still accessible to the runner, so no Intel compiler is installed locally.

## Scope

The first version models above-ground vegetation effects only:

- retain the existing Nays2DH shallow-water, sediment-transport, bed-evolution, wetting/drying, and iRIC CGNS interfaces;
- retain the existing vegetation body drag term based on vegetation density, height, and drag coefficient;
- update vegetation density and height using age-based willow allometry, annual recruitment, and scour-driven uprooting;
- expose vegetation parameters and vegetation result fields in iRIC;
- omit root-induced sediment reduction, root cohesion, bank reinforcement, seed dispersal, and species competition.

## Physical Model

Each computational cell carries vegetation presence, vegetation age in years, the bed elevation at the beginning of the current flood cycle, stem density, stem diameter, tree height, and rooting depth. The existing Nays2DH body-drag formulation continues to act in both momentum directions. Its projected-area density is calculated as `N_tree * D_tree`, with the diameter converted from centimetres to metres.

Vegetation size follows the willow allometry used by Nagata et al. (2016) and reproduced as Eqs. 18-22 in the target paper:

- `N_tree = 1.52 Y^-0.63` trees per square metre;
- `D_tree = 0.11 Y^1.77` centimetres;
- `H_tree = 1.27 D_tree^0.79` metres;
- `H_root = 28.9 D_tree^0.23` centimetres.

The diameter used by the allometry is calculated from effective age `Y_eff = min(growth_multiplier * Y, allometry_age_limit)`. Thus `growth_multiplier = 1` is normal growth and `2` is the doubled-growth experiment. This assumption is explicit and configurable because the 2025 paper identifies the doubled rate but does not publish a separate doubled coefficient set. The age limit prevents extrapolation of the empirical power laws into nonphysical tree sizes.

At the start of every configured flood cycle, the model records the bed elevation under each vegetated cell. During the flood, vegetation is removed when cumulative local erosion below that reference elevation exceeds `H_root`. Deposition does not count as uprooting. At the end of the low-flow stage, surviving vegetation increases in chronological age by one year. An unvegetated cell recruits one-year-old vegetation when its water depth is below the paper's default threshold of 0.05 m. The remainder of the year is represented by this event and is not hydrodynamically simulated.

This is deliberately a reduced process model. It is physically interpretable but is not a calibrated ecological succession model.

## Solver Integration

Vegetation state and parameters will be isolated in a focused Fortran module added to `src/Nays2DH.f90`, because the upstream project compiles that file as one translation unit. The main time loop will call the vegetation update after bed evolution has produced the current elevation change and before the next momentum solve uses `cd_veg` and `vege_h`.

The existing fields remain compatible:

- `vege_density`: initial vegetation density;
- `vege_height`: initial vegetation height;
- `c_tree`: body drag coefficient;
- `j_vege`: whether finite vegetation height is used.

New calculation-condition parameters will control enable/disable, flood-cycle duration, first cycle boundary, growth multiplier, recruitment depth threshold, initial vegetation age, and allometry age limit. Defaults will preserve the original static-vegetation behavior unless dynamic vegetation is explicitly enabled. The dynamic path will use the article defaults of a 25 h cycle, 0.05 m recruitment depth, growth multiplier 1.0, and a conservative 30-year allometry limit.

The solver will write vegetation presence, chronological age, effective growth age, projected-area density, tree height, rooting depth, cumulative scour, and survival status as iRIC cell solution fields alongside bed elevation, depth, velocity, and shear stress. This allows direct spatial comparison inside iRIC without an external plotting program.

The forked solver will use a unique `SolverDefinition.name`, caption, and installation directory. It will therefore appear beside stock Nays2DH and will not overwrite the official solver.

## Cloud Build and Packaging

A dedicated Windows GitHub Actions workflow will replace the upstream online-update publishing workflow in the fork. The upstream publishing workflow reads `config.json` with `build=false` and expects an i-RIC publishing secret that is unavailable to a personal fork. Upstream specifies Intel Classic Fortran 2021.2, but Intel now returns HTTP 403 for that archived installer; the cloud build therefore uses the earliest still-accessible official Intel CI release, 2023.1.

The replacement workflow will:

1. install Intel Classic Fortran (`ifort`) 2023.1 in the hosted runner;
2. use the `lib/iriclib.lib` import library already versioned in the official solver repository;
3. compile `src/iric.f90` and `src/Nays2DH.f90` with OpenMP and the runtime options corresponding to the upstream build;
4. link `Nays2DH.exe` against `iriclib.lib`;
5. inspect executable dependencies and copy the exact redistributable Intel runtime DLLs required by the new executable into the solver directory;
6. place the executable, `definition.xml`, translations, README, license, and required runtimes in an `iRICsolvers_v4_Nays2DH_Vegetation` directory;
7. upload that directory as a downloadable ZIP artifact.

The workflow will support manual dispatch and pushes to the development branch. Compiler installation and compilation occur only on the GitHub runner; the local machine receives only the packaged solver. Packaging the matching redistributables avoids relying on whichever Intel runtime version happens to be present in a user's iRIC installation.

## Error Handling

The solver validates vegetation parameter ranges at startup and stops with a clear console message for a non-positive flood cycle, non-positive growth multiplier, negative recruitment depth, negative initial age, or an invalid first cycle boundary. Missing new parameters fall back to compatibility defaults. Every iRIC read/write used for the new fields checks the returned status code, and dynamic vegetation is disabled safely if its optional inputs are unavailable.

The build workflow fails before packaging if compilation, linking, dependency collection, or the expected executable check fails. It records compiler version, imported DLL names, and artifact contents in the Actions log. The workflow has read-only repository permissions and does not attempt to publish into the official i-RIC online-update repository.

## Verification

Local tests that do not require Intel Fortran will verify the source contract: parameter definitions exist, defaults preserve static behavior, the update is inserted at the intended point, vegetation results are declared and written, and the workflow packages all required iRIC files.

Cloud verification will compile with `ifort`, confirm that `Nays2DH.exe` exists and is non-empty, and publish the ZIP. Installation verification will first run a cold-start Nays2DH case outside the installed solver directory, then copy the verified ZIP contents into the iRIC v4 `solvers` directory, launch iRIC, confirm the solver appears separately from stock Nays2DH, open its calculation conditions, and run a minimal case that produces bed-elevation and vegetation result fields.

The compiler choice is based on staged A/B diagnostics: both the coupled solver
and an unmodified upstream baseline compiled with `ifx` 2026.1 produced the
same first-step floating overflow in `HCAL`; a coupled `ifort` 2024.2 build also
stopped at time zero; the installed upstream executable advanced the same
cold-start case. The cloud build therefore tests the closest downloadable
classic compiler release and retains the cold-start smoke test as the actual
acceptance gate. These tests isolate the failure from the vegetation coupling.

## Acceptance Criteria

- Stock Nays2DH remains installed and untouched.
- The new solver appears as a separate selectable solver in iRIC v4.
- With dynamic vegetation disabled, the source follows the original static vegetation path.
- With dynamic vegetation enabled, recruitment occurs only at a cycle boundary in cells shallower than the configured threshold, and vegetation is removed only when cumulative flood scour exceeds its age-dependent rooting depth.
- Vegetation affects flow only through the existing body-drag term.
- Rooting depth is used only as an uprooting criterion; root-induced sediment-transport reduction is absent from source, parameters, and result interpretation.
- GitHub Actions produces a downloadable, installable solver ZIP without a local oneAPI installation.

## References

- Wattanachareekul, P., Inoue, T., and Johnson, J. P. L. (2025), https://doi.org/10.1186/s40645-025-00774-8
- Nagata, T. et al. (2016), https://doi.org/10.2208/jscejhe.72.I_1081
- Intel oneAPI CI samples, https://github.com/oneapi-src/oneapi-ci
