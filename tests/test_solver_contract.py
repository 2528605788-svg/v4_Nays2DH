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
        compact = re.sub(r"\s+", "", read_source("src/vegetation_dynamic.f90").lower())
        self.assertIn("1.52d0*y_eff**(-0.63d0)", compact)
        self.assertIn("0.11d0*y_eff**1.77d0", compact)
        self.assertIn("1.27d0*d_cm**0.79d0", compact)
        self.assertIn("28.9d0*d_cm**0.23d0/100.d0", compact)

    def test_growth_multiplier_uses_capped_effective_age(self):
        compact = re.sub(r"\s+", "", read_source("src/vegetation_dynamic.f90").lower())
        self.assertIn(
            "min(age*params%growth_multiplier,params%allometry_age_limit)",
            compact,
        )

    def test_uprooting_uses_scour_but_does_not_modify_sediment_flux(self):
        source = read_source("src/vegetation_dynamic.f90")
        compact = re.sub(r"\s+", "", source.lower())
        self.assertIn("anchor_elevation(i,j)-bed_elevation(i,j)", compact)
        self.assertIn("max_scour(i,j)>state%root_depth(i,j)", compact)
        self.assertNotRegex(source.lower(), r"\b(qb|bedload|sediment_flux)\b")

    def test_cycle_end_recruits_only_shallow_cells(self):
        compact = re.sub(r"\s+", "", read_source("src/vegetation_dynamic.f90").lower())
        self.assertIn("water_depth(i,j)<=params%recruitment_depth", compact)
        self.assertIn("state%age(i,j)=1.d0", compact)

    def test_initialization_reads_only_real_iric_cells(self):
        source = read_source("src/vegetation_dynamic.f90").lower()
        block = source.split("subroutine initialize_vegetation_state", 1)[1]
        block = block.split("end subroutine initialize_vegetation_state", 1)[0]
        compact = re.sub(r"\s+", "", block)
        self.assertIn("doj=1,ny", compact)
        self.assertIn("doi=1,nx", compact)

    def test_definition_has_unique_identity_controls_and_cell_outputs(self):
        root = ET.parse(ROOT / "install/definition.xml").getroot()
        self.assertEqual(root.attrib["name"], "Nays2DHVegetation")
        items = {
            item.attrib["name"]
            for item in root.findall(".//{*}CalculationCondition//{*}Item")
        }
        self.assertTrue(
            {
                "j_veg_dynamic",
                "veg_cycle_hours",
                "veg_first_boundary_hours",
                "veg_growth_multiplier",
                "veg_recruitment_depth",
                "veg_initial_age",
                "veg_allometry_age_limit",
            }
            <= items
        )
        outputs = {
            output.attrib["name"]: definition.attrib["position"]
            for output in root.findall(".//{*}Output")
            if (definition := output.find("{*}Definition")) is not None
        }
        for name in (
            "VegetationPresence",
            "VegetationAge(year)",
            "VegetationEffectiveAge(year)",
            "VegetationProjectedDensity(m-1)",
            "VegetationHeight(m)",
            "VegetationRootDepth(m)",
            "VegetationMaxScour(m)",
        ):
            self.assertEqual(outputs.get(name), "cell")

    def test_build_uses_ifx_and_uploads_standalone_artifact(self):
        workflow = read_source(".github/workflows/build.yml")
        makefile = read_source("make.bat")
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("actions/upload-artifact@v4", workflow)
        self.assertNotIn("ONLINE_UPDATE_TOKEN", workflow)
        self.assertNotIn("actions-js/push", workflow)
        self.assertIn("ifx", makefile.lower())
        self.assertIn("vegetation_dynamic.f90", makefile.lower())
        self.assertLess(
            makefile.lower().index("vegetation_dynamic.f90"),
            makefile.lower().index("nays2dh.f90"),
        )


if __name__ == "__main__":
    unittest.main()
