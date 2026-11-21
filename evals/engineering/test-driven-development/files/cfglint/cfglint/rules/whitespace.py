from ..model import Finding


class TrailingWhitespace:
    name = "trailing-whitespace"

    def check(self, lines):
        return [Finding(n, self.name, "trailing whitespace")
                for n, line in enumerate(lines, start=1) if line != line.rstrip()]
