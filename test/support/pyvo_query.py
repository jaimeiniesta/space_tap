# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "pyvo==1.9.1",
# ]
# ///

import json
import sys

import pyvo


def main():
    service_url = sys.argv[1]
    adql = sys.argv[2]
    maxrec = int(sys.argv[3]) if len(sys.argv) == 4 else None

    try:
        result = pyvo.dal.TAPService(service_url).search(adql, maxrec=maxrec)
    except Exception as error:
        print(json.dumps({"error": f"{type(error).__name__}: {error}"}))
        return 1

    print(
        json.dumps(
            {
                "columns": list(result.fieldnames),
                "row_count": len(result),
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
