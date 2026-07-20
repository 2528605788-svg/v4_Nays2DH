# Dynamic Vegetation Nays2DH for iRIC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a separately installable iRIC v4 Nays2DH solver with age-based willow body drag, low-flow recruitment, scour-driven uprooting, and a GitHub Actions `ifx` artifact build.

**Architecture:** Keep upstream Nays2DH hydrodynamics and sediment transport intact. Put dynamic vegetation state transitions and allometry in a focused Fortran module, call it from the existing time loop, and expose state through iRIC cell outputs. Replace the upstream release-publishing workflow with a personal-fork workflow that compiles, collects Intel redistributables, and uploads a solver ZIP.

**Tech Stack:** Fortran 2008, iRIC Fortran API/CGNS, XML SolverDefinition, Python standard-library contract tests, PowerShell, GitHub Actions, Intel oneAPI `ifx`.

---

## File Map

- Create `src/vegetation_dynamic.f90`: vegetation parameters, state arrays, allometry, initialization, scour removal, cycle-end ageing/recruitment, and drag-field synchronization.
- Modify `src/Nays2DH.f90`: read new parameters, initialize vegetation, call update routines, and write vegetation cell results.
- Modify `install/definition.xml`: unique solver identity, dynamic vegetation controls, and cell outputs.
- Modify `make.bat`: compile the new module before Nays2DH with `ifx`.
- Create `scripts/install_oneapi_windows.bat`: pinned official Intel component installation for CI.
- Create `scripts/collect_intel_runtimes.ps1`: inspect the executable and copy required Intel runtime DLLs.
- Replace `.github/workflows/build.yml`: compile and upload the standalone solver artifact only.
- Create `tests/test_solver_contract.py`: locally runnable structural and physics-contract tests.
- Modify `README.md` and `install/README`: document model limits and installation.

### Task 1: Establish failing source-contract tests

**Files:**
- Create: `tests/test_solver_contract.py`
- Test: `tests/test_solver_contract.py`

- [ ] **Step 1: Write the failing tests**

```python
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def read_source(relative_path):
    path = ROOT / relative_path
    return path.read_text(encoding="utf-8") if path.exists() else ""


class SolverContractTests(unittest.TestCase):
    def test_dynamic_module_contains_paper_allometry(self):
        source = read_source("src/vegetation_dynamic.f90")
        compact = re.sub(r"\s+", "", source.lower())
        self.assertIn("1.52d0*y_eff**(-0.63d0)", compact)
        self.assertIn("0.11d0*y_eff**1.77d0", compact)
        self.assertIn("1.27d0*d_cm**0.79d0", compact)
        self.assertIn("28.9d0*d_cm**0.23d0/100.d0", compact)

    def test_growth_multiplier_uses_capped_effective_age(self):
        source = read_source("src/vegetation_dynamic.f90")
        compact = re.sub(r"\s+", "", source.lower())
        self.assertIn("min(age*params%growth_multiplier,params%allometry_age_limit)", compact)

    def test_uprooting_uses_scour_but_does_not_modify_sediment_flux(self):
        source = read_source("src/vegetation_dynamic.f90")
        self.assertIn("anchor_elevation - bed_elevation", source)
        self.assertIn("max_scour > root_depth", source)
        self.assertNotRegex(source.lower(), r"\b(qb|bedload|sediment_flux)\b")

    def test_cycle_end_recruits_only_shallow_cells(self):
        source = read_source("src/vegetation_dynamic.f90")
        self.assertIn("water_depth <= params%recruitment_depth", source)
        self.assertIn("age = 1.d0", source)

    def test_definition_has_unique_identity_controls_and_cell_outputs(self):
        root = ET.parse(ROOT / "install/definition.xml").getroot()
        self.assertEqual(root.attrib["name"], "Nays2DHVegetation")
        items = {item.attrib["name"] for item in root.findall(".//{*}CalculationCondition//{*}Item")}
        self.assertTrue({"j_veg_dynamic", "veg_cycle_hours", "veg_growth_multiplier",
                         "veg_recruitment_depth", "veg_initial_age",
                         "veg_allometry_age_limit"} <= items)
        outputs = {o.attrib["name"]: o.find("{*}Definition").attrib["position"]
                   for o in root.findall(".//{*}Output")
                   if o.find("{*}Definition") is not None}
        for name in ("VegetationPresence", "VegetationAge(year)", "VegetationEffectiveAge(year)",
                     "VegetationProjectedDensity(m-1)", "VegetationHeight(m)",
                     "VegetationRootDepth(m)", "VegetationMaxScour(m)"):
            self.assertEqual(outputs[name], "cell")

    def test_build_uses_ifx_and_uploads_standalone_artifact(self):
        workflow = read_source(".github/workflows/build.yml")
        makefile = read_source("make.bat")
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("actions/upload-artifact@v4", workflow)
        self.assertNotIn("ONLINE_UPDATE_TOKEN", workflow)
        self.assertNotIn("actions-js/push", workflow)
        self.assertIn("ifx", makefile.lower())
        self.assertLess(makefile.lower().index("vegetation_dynamic.f90"),
                        makefile.lower().index("nays2dh.f90"))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests and verify RED**

Run: `python -m unittest tests/test_solver_contract.py -v`

Expected: failures because `src/vegetation_dynamic.f90` and the new XML/workflow contracts do not exist yet.

- [ ] **Step 3: Commit the failing tests**

```bash
git add tests/test_solver_contract.py
git commit -m "test: define dynamic vegetation solver contract"
```

### Task 2: Implement the isolated vegetation physics module

**Files:**
- Create: `src/vegetation_dynamic.f90`
- Test: `tests/test_solver_contract.py`

- [ ] **Step 1: Add the parameter and state types**

```fortran
module vegetation_dynamic_m
  implicit none
  private

  type, public :: vegetation_parameters
    logical :: enabled = .false.
    real(8) :: cycle_seconds = 90000.d0
    real(8) :: first_boundary_seconds = 90000.d0
    real(8) :: growth_multiplier = 1.d0
    real(8) :: recruitment_depth = 0.05d0
    real(8) :: initial_age = 1.d0
    real(8) :: allometry_age_limit = 30.d0
  end type vegetation_parameters

  type, public :: vegetation_state
    integer(4), allocatable :: presence(:,:), survived(:,:)
    real(8), allocatable :: age(:,:), effective_age(:,:)
    real(8), allocatable :: projected_density(:,:), height(:,:), root_depth(:,:)
    real(8), allocatable :: anchor_elevation(:,:), max_scour(:,:)
  end type vegetation_state

  public :: validate_vegetation_parameters, allocate_vegetation_state
  public :: initialize_vegetation_state, update_vegetation_scour
  public :: finish_vegetation_cycle, sync_vegetation_drag, vegetation_allometry
contains
```

- [ ] **Step 2: Implement parameter validation and allometry**

```fortran
  subroutine validate_vegetation_parameters(params, ok)
    type(vegetation_parameters), intent(in) :: params
    logical, intent(out) :: ok
    ok = params%cycle_seconds > 0.d0 .and. &
         params%first_boundary_seconds >= 0.d0 .and. &
         params%growth_multiplier > 0.d0 .and. &
         params%recruitment_depth >= 0.d0 .and. &
         params%initial_age >= 0.d0 .and. &
         params%allometry_age_limit > 0.d0
  end subroutine validate_vegetation_parameters

  pure subroutine vegetation_allometry(age, params, effective_age, projected_density, height, root_depth)
    real(8), intent(in) :: age
    type(vegetation_parameters), intent(in) :: params
    real(8), intent(out) :: effective_age, projected_density, height, root_depth
    real(8) :: y_eff, n_tree, d_cm
    if (age <= 0.d0) then
      effective_age = 0.d0; projected_density = 0.d0
      height = 0.d0; root_depth = 0.d0
      return
    end if
    y_eff = min(age * params%growth_multiplier, params%allometry_age_limit)
    n_tree = 1.52d0 * y_eff**(-0.63d0)
    d_cm = 0.11d0 * y_eff**1.77d0
    effective_age = y_eff
    projected_density = n_tree * d_cm / 100.d0
    height = 1.27d0 * d_cm**0.79d0
    root_depth = 28.9d0 * d_cm**0.23d0 / 100.d0
  end subroutine vegetation_allometry
```

- [ ] **Step 3: Implement state allocation, initialization, scour removal, cycle completion, and drag synchronization**

```fortran
  subroutine update_vegetation_scour(state, bed_elevation, nx, ny)
    type(vegetation_state), intent(inout) :: state
    real(8), intent(in) :: bed_elevation(0:,0:)
    integer, intent(in) :: nx, ny
    integer :: i, j
    do j = 1, ny
      do i = 1, nx
        if (state%presence(i,j) == 1) then
          state%max_scour(i,j) = max(state%max_scour(i,j), &
               state%anchor_elevation(i,j) - bed_elevation(i,j))
          if (state%max_scour(i,j) > state%root_depth(i,j)) then
            state%presence(i,j) = 0; state%survived(i,j) = 0
            state%age(i,j) = 0.d0
          end if
        end if
      end do
    end do
  end subroutine update_vegetation_scour

  subroutine finish_vegetation_cycle(state, params, bed_elevation, water_depth, nx, ny)
    type(vegetation_state), intent(inout) :: state
    type(vegetation_parameters), intent(in) :: params
    real(8), intent(in) :: bed_elevation(0:,0:), water_depth(0:,0:)
    integer, intent(in) :: nx, ny
    integer :: i, j
    do j = 1, ny
      do i = 1, nx
        if (state%presence(i,j) == 1) then
          state%age(i,j) = state%age(i,j) + 1.d0
          state%survived(i,j) = 1
        else if (water_depth(i,j) <= params%recruitment_depth) then
          state%presence(i,j) = 1; state%survived(i,j) = 0
          state%age(i,j) = 1.d0
        end if
        state%anchor_elevation(i,j) = bed_elevation(i,j)
        state%max_scour(i,j) = 0.d0
      end do
    end do
  end subroutine finish_vegetation_cycle
```

Complete the module with three explicit routines: `allocate_vegetation_state` allocates every component with bounds `(0:nx,0:ny)` and zero-initializes it; `initialize_vegetation_state` sets `presence=1`, `age=initial_age`, and the anchor elevation wherever the existing input density is positive; `sync_vegetation_drag` recomputes allometry for present cells and sets `cd_veg=0.5d0*c_tree*projected_density` and `vege_h=height`, while zeroing all dynamic fields for absent cells. These routines receive `nx, ny` explicitly and use dummy arrays declared `(0:,0:)` so Nays2DH's zero-based bounds are preserved.

- [ ] **Step 4: Run the focused tests and verify GREEN for module contracts**

Run: `python -m unittest tests.test_solver_contract.SolverContractTests.test_dynamic_module_contains_paper_allometry tests.test_solver_contract.SolverContractTests.test_growth_multiplier_uses_capped_effective_age tests.test_solver_contract.SolverContractTests.test_uprooting_uses_scour_but_does_not_modify_sediment_flux tests.test_solver_contract.SolverContractTests.test_cycle_end_recruits_only_shallow_cells -v`

Expected: four tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/vegetation_dynamic.f90 tests/test_solver_contract.py
git commit -m "feat: add age-based vegetation dynamics"
```

### Task 3: Connect vegetation dynamics to Nays2DH and iRIC

**Files:**
- Modify: `src/Nays2DH.f90`
- Modify: `install/definition.xml`
- Test: `tests/test_solver_contract.py`

- [ ] **Step 1: Add failing integration assertions**

Add assertions that `Nays2DH.f90` imports `vegetation_dynamic_m`, reads each `veg_*` value, calls `update_vegetation_scour` after `etacal*`, calls `finish_vegetation_cycle` at integer cycle boundaries, calls `sync_vegetation_drag`, and writes all declared cell fields with `cg_iric_write_sol_cell_*`.

- [ ] **Step 2: Run the integration assertions and verify RED**

Run: `python -m unittest tests/test_solver_contract.py -v`

Expected: integration assertions fail because Nays2DH and `definition.xml` still expose only static vegetation.

- [ ] **Step 3: Wire parameters and state into the main program**

Add `use vegetation_dynamic_m`, instances of `vegetation_parameters` and `vegetation_state`, and integer cycle-step variables. Read XML values with the existing `cg_iric_read_*` calls, convert hours to seconds, validate, allocate state on `(0:im,0:jm)`, and initialize from `vege4`, `vegeh`, and `eta`.

Use integer step arithmetic to avoid floating-point boundary drift:

```fortran
veg_cycle_steps = max(1, nint(veg_params%cycle_seconds / dt))
veg_first_boundary_step = max(0, nint(veg_params%first_boundary_seconds / dt))
veg_cycle_due = icount + 1 >= veg_first_boundary_step .and. &
  mod(icount + 1 - veg_first_boundary_step, veg_cycle_steps) == 0
```

After all active `etacal*` paths, update scour. When `veg_cycle_due`, complete the cycle. Synchronize `cd_veg` and `vege_h` before the next momentum solve.

Because the Nays2DH time loop is inside an OpenMP parallel region, enclose the state transition and drag synchronization block in `!$omp single` / `!$omp end single`, followed by `!$omp barrier`. This prevents each worker thread from ageing or recruiting the same cell independently. Keep the entire block conditional on `veg_params%enabled` so disabling the extension preserves the upstream static-vegetation path bit-for-bit.

- [ ] **Step 4: Add iRIC controls and cell outputs**

Set `SolverDefinition.name="Nays2DHVegetation"`, caption `Nays2DH Dynamic Vegetation iRIC4`, and a distinct version. Add a Dynamic Vegetation tab with defaults:

```xml
<Item name="j_veg_dynamic" caption="Dynamic vegetation">
  <Definition valueType="integer" default="0">
    <Enumerations>
      <Enumeration value="0" caption="Disabled (original static vegetation)"/>
      <Enumeration value="1" caption="Enabled"/>
    </Enumerations>
  </Definition>
</Item>
<Item name="veg_cycle_hours" caption="Flood cycle duration (hour)">
  <Definition valueType="real" default="25" min="0.000001"/>
</Item>
<Item name="veg_growth_multiplier" caption="Growth multiplier">
  <Definition valueType="real" default="1" min="0.000001"/>
</Item>
<Item name="veg_recruitment_depth" caption="Recruitment water-depth threshold (m)">
  <Definition valueType="real" default="0.05" min="0"/>
</Item>
```

Add the remaining first-boundary, initial-age, and 30-year cap values with the same enable dependency. Add cell outputs named exactly as asserted in Task 1. Write the state arrays between `cg_iric_write_sol_start` and `cg_iric_write_sol_end`.

- [ ] **Step 5: Validate XML and run tests**

Run: `python -c "import xml.etree.ElementTree as E; E.parse('install/definition.xml'); print('XML OK')"`

Expected: `XML OK`.

Run: `python -m unittest tests/test_solver_contract.py -v`

Expected: physics and iRIC integration contracts pass; only build workflow assertions may still fail.

- [ ] **Step 6: Commit**

```bash
git add src/Nays2DH.f90 install/definition.xml tests/test_solver_contract.py
git commit -m "feat: integrate dynamic vegetation with iRIC"
```

### Task 4: Add the `ifx` artifact build and runtime packaging

**Files:**
- Modify: `make.bat`
- Create: `scripts/install_oneapi_windows.bat`
- Create: `scripts/collect_intel_runtimes.ps1`
- Replace: `.github/workflows/build.yml`
- Test: `tests/test_solver_contract.py`

- [ ] **Step 1: Extend failing build-contract tests**

Assert that the workflow pins an official `oneapi-src/oneapi-ci` 2026.1 Windows toolkit URL, uses `windows-latest`, invokes `make.bat`, invokes the runtime collector, checks `install/Nays2DH.exe`, and uploads `iRICsolvers_v4_Nays2DH_Vegetation` with `actions/upload-artifact@v4`.

- [ ] **Step 2: Run tests and verify RED**

Run: `python -m unittest tests.test_solver_contract.SolverContractTests.test_build_uses_ifx_and_uploads_standalone_artifact -v`

Expected: failure against the upstream workflow and `ifort` make script.

- [ ] **Step 3: Replace the compiler script**

`make.bat` must activate `setvars-vcvarsall.bat vs2022`, compile `iric.f90`, `vegetation_dynamic.f90`, then `Nays2DH.f90`, link against `lib/iriclib.lib`, and copy the executable to `install` only after a successful link. Every command must use `|| exit /b 1`.

- [ ] **Step 4: Add compiler installation and runtime collection scripts**

The installer script must download the pinned Intel offline installer with retry, extract it, install only `intel.oneapi.win.ifort-compiler` (the official component name that contains current `ifx`), disable Visual Studio IDE integration, and return the installer exit code.

The PowerShell collector must run `dumpbin /dependents`, select imports matching `^(libif|libiomp|libmmd|svml|libirc)`, locate each under the oneAPI compiler directory, copy it beside `Nays2DH.exe`, and fail if any selected import cannot be found.

- [ ] **Step 5: Replace the workflow**

Use `permissions: contents: read`, `workflow_dispatch`, `push` on the development branch, `actions/checkout@v4`, `actions/cache@v4` for the compiler directory, the two scripts above, a package-directory copy of `install/*` plus `LICENSE`, and `actions/upload-artifact@v4` with a 14-day retention.

- [ ] **Step 6: Run all local tests and YAML sanity checks**

Run: `python -m unittest tests/test_solver_contract.py -v`

Expected: all tests pass.

Run: `git diff --check`

Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add make.bat scripts .github/workflows/build.yml tests/test_solver_contract.py
git commit -m "ci: build installable solver with ifx"
```

### Task 5: Documentation and local release review

**Files:**
- Modify: `README.md`
- Modify: `install/README`
- Test: `tests/test_solver_contract.py`

- [ ] **Step 1: Add a failing documentation assertion**

Require the README to state: body drag only, no root sediment reduction, 25 h default cycle, 0.05 m recruitment threshold, effective-age multiplier, 30-year cap, separate iRIC solver folder, and GitHub artifact installation steps.

- [ ] **Step 2: Run and verify RED**

Run: `python -m unittest tests/test_solver_contract.py -v`

Expected: README contract fails.

- [ ] **Step 3: Update both README files**

Document the model equations and units, cycle ordering, `growth_multiplier=2` interpretation, root-depth-only uprooting role, parameter defaults, output names, ZIP installation into `C:\Users\ASUS\iRIC_v4\solvers`, and how to retain stock Nays2DH.

- [ ] **Step 4: Verify GREEN and review the complete diff**

Run: `python -m unittest tests/test_solver_contract.py -v`

Expected: all tests pass.

Run: `git diff --check && git status --short`

Expected: no whitespace errors; only intended files are modified.

- [ ] **Step 5: Commit**

```bash
git add README.md install/README tests/test_solver_contract.py
git commit -m "docs: document dynamic vegetation solver"
```

### Task 6: Fork, run cloud build, and install the artifact

**Files:**
- External: GitHub repository `2528605788-svg/v4_Nays2DH`
- Install: `C:\Users\ASUS\iRIC_v4\solvers\iRICsolvers_v4_Nays2DH_Vegetation`

- [ ] **Step 1: Create the fork in the authenticated GitHub browser**

Create `2528605788-svg/v4_Nays2DH` from `iRICsolvers/v4_Nays2DH` without modifying the upstream repository.

- [ ] **Step 2: Publish the reviewed local commits**

Push the local commit chain to a development branch in the fork using the connected GitHub capability. If the GitHub App does not automatically expose the new fork, stop and request repository access rather than using or exposing credentials.

- [ ] **Step 3: Trigger and monitor GitHub Actions**

Run the manual `build-dynamic-vegetation-solver` workflow. Inspect compiler output and fix failures through new failing local contract tests where applicable. Repeat until compilation, link, dependency collection, and artifact upload all succeed.

- [ ] **Step 4: Download and inspect the artifact**

Confirm the ZIP contains a non-empty `Nays2DH.exe`, unique `definition.xml`, translations, README, license, and every Intel DLL reported by the dependency collector.

- [ ] **Step 5: Install without overwriting stock Nays2DH**

Copy the extracted directory to exactly `C:\Users\ASUS\iRIC_v4\solvers\iRICsolvers_v4_Nays2DH_Vegetation`. Confirm the existing `iRICsolvers_v4_Nays2DH` directory is unchanged.

- [ ] **Step 6: Perform iRIC smoke verification**

Launch iRIC, confirm both solver entries appear, create/open a minimal case, verify the Dynamic Vegetation tab, run a short case, and confirm bed elevation plus vegetation-age/density/height/scour fields are visible.

- [ ] **Step 7: Record final evidence**

Report the fork URL, workflow run URL, artifact size, installed folder, test output, compiler version, and any physical/numerical limitations observed during the smoke run.
