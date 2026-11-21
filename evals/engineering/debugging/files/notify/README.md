# notify

Sends user notifications through the messaging gateway. `Gateway` posts each
message to the gateway's HTTP API and returns a `Receipt`;
`NotificationService` looks up the user and picks the priority: alerts go out
as `high`, everything else as `normal`.

```python
from notify import Gateway, NotificationService, UserDirectory

service = NotificationService(Gateway("https://gateway.internal", token="..."), UserDirectory())
service.alert("u-1", "Disk almost full")
```

## Tests

```bash
python3 -m unittest discover -s tests -t .
```
