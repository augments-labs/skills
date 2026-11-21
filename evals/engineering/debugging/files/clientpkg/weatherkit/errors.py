class WeatherKitError(Exception):
    """Base class for every error this package raises."""


class TransportError(WeatherKitError):
    """The request never got a response."""


class ApiError(WeatherKitError):
    def __init__(self, status, message):
        super().__init__(f"{status}: {message}")
        self.status = status
        self.message = message
