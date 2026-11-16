# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "astropy==8.0.2",
#   "pyvo==1.9.1",
# ]
# ///

import json
import math
import sys
import warnings

import pyvo
from pyvo.dal.exceptions import DALOverflowWarning


def main():
    service_url = sys.argv[1]
    adql = sys.argv[2]
    maxrec = int(sys.argv[3]) if len(sys.argv) == 4 else None

    # PyVO warns on stderr when the service truncates the result, which the
    # JSON already reports as overflow. GAVO sends one row more than MAXREC,
    # so the warning would show up in every run of the release tests.
    warnings.filterwarnings("ignore", category=DALOverflowWarning)

    try:
        result = pyvo.dal.TAPService(service_url).search(adql, maxrec=maxrec)
    except Exception as error:
        print(json.dumps({"error": f"{type(error).__name__}: {error}"}))
        return 1

    print(json.dumps(to_json(result), allow_nan=False))
    return 0


def to_json(result):
    table = result.to_table()
    columns = [column.tolist() for column in table.columns.values()]

    return {
        "columns": list(result.fieldnames),
        "rows": [[value(cell) for cell in row] for row in zip(*columns)],
        "overflow": result.query_status == "OVERFLOW",
    }


# tolist() gives Python values, and None for a masked cell, which is how
# astropy marks a null and a NaN. The rest follows SpaceTAP's ADR 0007: an
# empty string or array is null, and so is NaN inside an array.
def value(cell):
    if hasattr(cell, "tolist"):
        cell = cell.tolist()

    if isinstance(cell, list):
        return [value(item) for item in cell] or None
    if isinstance(cell, float) and math.isnan(cell):
        return None
    if isinstance(cell, float) and math.isinf(cell):
        return "Infinity" if cell > 0 else "-Infinity"
    if cell == "":
        return None
    return cell


if __name__ == "__main__":
    raise SystemExit(main())
