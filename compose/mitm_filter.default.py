# This script can be modified while the system is running, it will do a hot reload.

from mitmproxy import http


def request(flow: http.HTTPFlow) -> None:
    return


def responseheaders(flow: http.HTTPFlow) -> None:
    # This prevents megabytes/gigabytes of data from being buffered in RAM.
    flow.response.stream = True
