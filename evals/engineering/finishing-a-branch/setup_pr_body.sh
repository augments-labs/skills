. "$(dirname "$0")/_git_setup.sh"
git checkout -q -b feature/export-v2
python3 - <<'PY'
import pathlib
p = pathlib.Path("app/export.py")
s = p.read_text()
s = s.replace('HEADER = "id,amount_cents,currency"', 'HEADER = "order_id,amount_cents,currency"')
s = s[:s.index("\n\ndef old_export")] + "\n"
p.write_text(s)
p = pathlib.Path("tests/test_export.py")
s = p.read_text().replace("from app.export import export_csv, old_export", "from app.export import export_csv")
s = s[:s.index("    def test_old_export")].rstrip() + "\n\n\nif __name__ == \"__main__\":\n    unittest.main()\n"
p.write_text(s)
PY
git commit -qam "Export v2: rename the id column and drop the legacy format"
git push -q -u origin feature/export-v2
