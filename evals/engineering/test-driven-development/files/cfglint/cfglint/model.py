from dataclasses import dataclass


@dataclass(frozen=True)
class Finding:
    line: int      # 1-based
    rule: str
    message: str

    def format(self, path):
        return f"{path}:{self.line}: [{self.rule}] {self.message}"
