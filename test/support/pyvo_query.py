# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "astropy==8.0.2",
#   "pyvo==1.9.1",
# ]
# ///

# Prints what PyVO reads as JSON, for SpaceTAP's parity tests
# (test/support/pyvo.ex). Either the result of a query sent to a service:
#
#     uv run pyvo_query.py SERVICE_URL ADQL [MAXREC]
#
# or VOTable files, as an object with what it reads from each path:
#
#     uv run pyvo_query.py --files PATH...
#
# or the job documents of async jobs, the same way:
#
#     uv run pyvo_query.py --jobs PATH...

import json
import math
import sys
import warnings

import pyvo
from astropy.io import votable
from pyvo.dal.exceptions import DALOverflowWarning
from pyvo.io import uws


def main():
    # PyVO warns on stderr when the service truncates the result, which the
    # JSON already reports as overflow. GAVO sends one row more than MAXREC,
    # so the warning would show up in every run of the release tests.
    warnings.filterwarnings("ignore", category=DALOverflowWarning)

    if sys.argv[1] == "--files":
        files = {path: read_file(path) for path in sys.argv[2:]}
        print(json.dumps(files, allow_nan=False))
        return 0

    if sys.argv[1] == "--jobs":
        print(json.dumps({path: read_job(path) for path in sys.argv[2:]}))
        return 0

    service_url = sys.argv[1]
    adql = sys.argv[2]
    maxrec = int(sys.argv[3]) if len(sys.argv) == 4 else None

    try:
        result = pyvo.dal.TAPService(service_url).search(adql, maxrec=maxrec)
    except Exception as error:
        print(json.dumps({"error": f"{type(error).__name__}: {error}"}))
        return 1

    print(json.dumps(to_json(result), allow_nan=False))
    return 0


# A file is read as PyVO reads a service's answer: astropy parses the
# VOTable, and TAPResults reads its QUERY_STATUS and raises DALQueryError on
# an ERROR. A file it can't read, such as an error document, gives an error.
def read_file(path):
    try:
        return to_json(pyvo.dal.TAPResults(votable.parse(path)))
    except Exception as error:
        return {"error": f"{type(error).__name__}: {error}"}


# A job document is read with the parser PyVO reads it with when it waits
# for a job, and gives what SpaceTAP reads from it: the phase, the message of
# the error summary and the href of the result named result, which is the
# one PyVO fetches when no href ends in results/result. Messages are trimmed,
# as SpaceTAP trims them. The parser warns about elements it doesn't know,
# such as the executionduration KOA spells in lower case, on stderr, which
# would show up in every test run.
def read_job(path):
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            job = uws.parse_job(path)
    except Exception as error:
        return {"error": f"{type(error).__name__}: {error}"}

    summary = job.errorsummary
    message = summary.message.content if summary and summary.message else None
    hrefs = [result.href for result in job.results if result.id_ == "result"]

    return {
        "phase": job.phase,
        "error_summary": message.strip() if message else None,
        "results": hrefs,
    }


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
