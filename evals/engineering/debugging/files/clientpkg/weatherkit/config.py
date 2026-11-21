import os
from dataclasses import dataclass
from typing import Optional

DEFAULT_URL = "https://api.weatherkit.example"


@dataclass(frozen=True)
class ClientConfig:
    base_url: str = DEFAULT_URL
    api_key: Optional[str] = None
    page_size: int = 100
    timeout: float = 10.0

    @classmethod
    def from_env(cls):
        return cls(
            base_url=os.environ.get("WEATHERKIT_URL", DEFAULT_URL),
            api_key=os.environ.get("WEATHERKIT_API_KEY"),
            page_size=int(os.environ.get("WEATHERKIT_PAGE_SIZE", "100")),
        )
