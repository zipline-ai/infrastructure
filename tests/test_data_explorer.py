"""Render the chart with Helm: python3 -m unittest discover -s tests."""

from pathlib import Path
import re
import subprocess
import unittest


CHART = Path(__file__).resolve().parents[1] / "charts/zipline-orchestration"


class DataExplorerTest(unittest.TestCase):
    def test_toggle(self):
        for enabled in (None, False, True):
            with self.subTest(enabled=enabled):
                command = [
                    "helm", "template", "test", str(CHART),
                    "--set", "global.customer_name=test",
                    "--set", "database.host=postgres",
                    "--set", "polaris.bootstrap.rbac.catalog.storage.type=S3",
                    "--set", "orchestration.hub.image=test/hub",
                    "--set", "orchestration.hub.verticleClass=test.Hub",
                    "--set", "orchestration.eval.image=test/eval",
                ]
                if enabled is not None:
                    command += ["--set", f"dataExplorer.enabled={str(enabled).lower()}"]
                rendered = subprocess.check_output(command, text=True)
                self.assertEqual("name: starrocks-catalog-init" in rendered, bool(enabled))
                flag = re.search(r'name: DATA_EXPLORER\s+value: "(true|false)"', rendered)
                self.assertIsNotNone(flag)
                self.assertEqual(flag.group(1), str(bool(enabled)).lower())
                self.assertEqual("name: STARROCKS_HOST" in rendered, bool(enabled))


if __name__ == "__main__":
    unittest.main()
