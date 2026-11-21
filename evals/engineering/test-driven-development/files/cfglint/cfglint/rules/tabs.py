from ..model import Finding


class NoTabs:
    name = "no-tabs"

    def check(self, lines):
        return [Finding(n, self.name, "tab character; indent with spaces")
                for n, line in enumerate(lines, start=1) if "\t" in line]
