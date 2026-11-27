. "$(dirname "$0")/_git_setup.sh"
git checkout -q -b feature/export-currency
sed -i "s/o.get('currency', 'USD')/o.get('currency', 'USD').upper()/" app/export.py
commit app/export.py "Upper-case currency codes in the export"
cat >> tests/test_export.py.new <<'PY'
PY
rm tests/test_export.py.new
python3 - <<'PY'
import pathlib
p = pathlib.Path("tests/test_export.py")
s = p.read_text().replace(
    "    def test_old_export(self):",
    "    def test_currency_upper(self):\n        self.assertIn(\"o4,5,GBP\", export_csv([{\"id\": \"o4\", \"status\": \"paid\", \"amount_cents\": 5, \"currency\": \"gbp\"}]))\n\n    def test_old_export(self):")
p.write_text(s)
PY
commit tests/test_export.py "Test currency upper-casing"
note main "$(git rev-parse origin/main)"
note feature "$(git rev-parse HEAD)"
