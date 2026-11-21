import asyncio
import json
import urllib.error
import urllib.parse
import urllib.request

from .errors import ApiError, TransportError


class HttpTransport:
    def __init__(self, config):
        self.config = config

    def get_json(self, path, params=None):
        query = urllib.parse.urlencode(params or {})
        url = self.config.base_url.rstrip("/") + path + ("?" + query if query else "")
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
        if self.config.api_key:
            request.add_header("Authorization", "Bearer " + self.config.api_key)
        try:
            with urllib.request.urlopen(request, timeout=self.config.timeout) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            raise ApiError(exc.code, exc.reason) from exc
        except (urllib.error.URLError, OSError) as exc:
            raise TransportError(str(exc)) from exc


class AsyncHttpTransport:
    def __init__(self, config):
        self._sync = HttpTransport(config)

    async def get_json(self, path, params=None):
        return await asyncio.to_thread(self._sync.get_json, path, params)
