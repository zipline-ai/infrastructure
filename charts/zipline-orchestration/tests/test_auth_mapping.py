"""Render the UI template in isolation to check role-mapping escaping."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class AuthMappingTest(unittest.TestCase):
    def test_role_mapping_round_trip(self):
        chart = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "templates").mkdir()
            (root / "Chart.yaml").write_text("apiVersion: v2\nname: auth-test\nversion: 1.0.0\n")
            for name in ("values.yaml",):
                shutil.copy(chart / name, root / name)
            for name in ("_helpers.tpl", "orchestration-ui.yaml"):
                shutil.copy(chart / "templates" / name, root / "templates" / name)
            for value in ('plain-string', '{"admins":"admin"}', 'group\\name\n"quoted"'):
                with self.subTest(value=value):
                    values = root / "test-values.json"
                    values.write_text(json.dumps({"database": {"url": "postgresql://test"}, "auth": {"enabled": True, "idp_role_mapping": value}}))
                    result = subprocess.run(
                        ["helm", "template", "auth-test", str(root), "-f", str(values)],
                        capture_output=True, text=True,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    lines = result.stdout.splitlines()
                    index = next(i for i, line in enumerate(lines) if "name: IDP_ROLE_MAPPING" in line)
                    scalar = lines[index + 1].strip().removeprefix("value: ")
                    self.assertEqual(json.loads(scalar), value)


if __name__ == "__main__":
    unittest.main()
