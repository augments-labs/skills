from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class Entry:
    id: int
    account: str
    amount: int
    memo: str = ""

    def to_dict(self):
        return asdict(self)

    @classmethod
    def from_dict(cls, data):
        return cls(id=int(data["id"]), account=data["account"],
                   amount=int(data["amount"]), memo=data.get("memo", ""))
