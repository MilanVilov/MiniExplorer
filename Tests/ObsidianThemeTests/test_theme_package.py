import base64
import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
THEME_DIR = ROOT / "ObsidianThemes" / "MiniWriter"


class MiniWriterThemePackageTests(unittest.TestCase):
    def test_manifest_describes_installable_theme(self):
        manifest = json.loads((THEME_DIR / "manifest.json").read_text())

        self.assertEqual(manifest["name"], "MiniWriter")
        self.assertEqual(manifest["version"], "1.0.0")
        self.assertEqual(manifest["minAppVersion"], "1.5.0")
        self.assertEqual(manifest["author"], "MiniExplorer")

    def test_theme_embeds_four_valid_ia_writer_mono_faces(self):
        css = (THEME_DIR / "theme.css").read_text()
        faces = re.findall(
            r"@font-face\s*\{(?P<body>.*?)\}", css, flags=re.DOTALL
        )

        self.assertEqual(len(faces), 4)
        expected_styles = {
            ("400", "normal"),
            ("400", "italic"),
            ("700", "normal"),
            ("700", "italic"),
        }
        actual_styles = set()
        for face in faces:
            weight = re.search(r"font-weight:\s*(\d+)", face).group(1)
            style = re.search(r"font-style:\s*(\w+)", face).group(1)
            actual_styles.add((weight, style))
            payload = re.search(
                r"src:\s*url\(['\"]data:font/ttf;base64,([^'\"]+)", face
            ).group(1)
            decoded = base64.b64decode(payload)
            self.assertGreater(len(decoded), 50_000)
            self.assertIn(decoded[:4], (b"\x00\x01\x00\x00", b"OTTO"))

        self.assertEqual(actual_styles, expected_styles)

    def test_theme_supports_both_appearance_modes_and_editor_surfaces(self):
        css = (THEME_DIR / "theme.css").read_text()

        required_selectors = (
            ".theme-dark",
            ".theme-light",
            ".markdown-source-view.mod-cm6 .cm-content",
            ".markdown-preview-view",
            ".cm-formatting",
            ".HyperMD-codeblock",
            "blockquote",
            ".task-list-item-checkbox",
            ".callout",
        )
        for selector in required_selectors:
            self.assertIn(selector, css)

        self.assertIn("--file-line-width: 780px", css)
        self.assertIn("--font-text-size: 18px", css)
        self.assertIn("--font-text-theme: \"iA Writer Mono S\"", css)

    def test_package_includes_font_license_and_installation_guide(self):
        self.assertTrue((THEME_DIR / "OFL.txt").is_file())
        readme = (THEME_DIR / "README.md").read_text()

        self.assertIn(".obsidian/themes/MiniWriter", readme)
        self.assertIn("Appearance", readme)
        self.assertIn("MiniWriter", readme)


if __name__ == "__main__":
    unittest.main()
