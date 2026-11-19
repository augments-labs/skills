from .units import coordinate, feet


def display_name(station):
    return station.name.strip().title()


def station_row(station):
    lat = coordinate(station.latitude, "N", "S")
    lon = coordinate(station.longitude, "E", "W")
    return f"{station.id:<10} {display_name(station):<28} {lat:>9} {lon:>9}"


def station_detail(station):
    return "\n".join(
        [
            display_name(station),
            f"  id:        {station.id}",
            f"  network:   {station.network}",
            f"  position:  {coordinate(station.latitude, 'N', 'S')} "
            f"{coordinate(station.longitude, 'E', 'W')}",
            f"  elevation: {feet(station.elevation_m)} ft",
        ]
    )
