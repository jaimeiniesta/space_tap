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
# or of the same query run as an async job:
#
#     uv run pyvo_query.py --async SERVICE_URL ADQL [MAXREC]
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
import time
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

    args = sys.argv[1:]
    run = run_async if args[0] == "--async" else run_sync
    args = args[1:] if args[0] == "--async" else args
    service_url = args[0]
    adql = args[1]
    maxrec = int(args[2]) if len(args) == 3 else None

    try:
        result = run(service_url, adql, maxrec)
    except Exception as error:
        print(json.dumps({"error": f"{type(error).__name__}: {error}"}))
        return 1

    print(json.dumps(to_json(result), allow_nan=False))
    return 0


def run_sync(service_url, adql, maxrec):
    return pyvo.dal.TAPService(service_url).search(adql, maxrec=maxrec)


# PyVO's run_async, step by step. Its own deletes the job with DELETE alone,
# and raises when the service refuses it, after it has read the result, as
# NED (403), KOA (500) and the NASA Exoplanet Archive (502) do. SpaceTAP
# deletes the job as best it can, and so does this.
def run_async(service_url, adql, maxrec):
    job = pyvo.dal.TAPService(service_url).submit_job(adql, maxrec=maxrec)

    try:
        wait(job.run())
        job.raise_if_error()
        return job.fetch_result()
    finally:
        try:
            job.delete()
        except Exception:
            pass


# PyVO's wait asks the service to block with WAIT=-1, which GAVO cuts after
# about 120 seconds without an answer, and which timed out at IRSA, so a job
# in a queue would fail the test. The parity tests compare results, not how
# a client waits, so this reads the phase every 2 seconds, for up to 5
# minutes, as long as the service may still move the job on.
def wait(job):
    deadline = time.monotonic() + 300

    while job.phase in ("PENDING", "QUEUED", "EXECUTING", "SUSPENDED", "UNKNOWN"):
        if time.monotonic() > deadline:
            raise TimeoutError(f"the job is still {job.phase} after 300 seconds")
        time.sleep(2)


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


# The table also gives the names of its columns, which astropy makes unique
# where the service repeats one, and their NumPy dtypes, for SpaceTAP's
# Result.to_dataframe/1.
def to_json(result):
    table = result.to_table()
    columns = [column.tolist() for column in table.columns.values()]

    return {
        "columns": list(result.fieldnames),
        "rows": [[value(cell) for cell in row] for row in zip(*columns)],
        "overflow": result.query_status == "OVERFLOW",
        "names": table.colnames,
        "dtypes": [dtype(column) for column in table.columns.values()],
    }


# The NumPy dtype of a column, such as float32 or int16, or "string" for
# text and "list" for an array. astropy holds a variable-length string or
# array in an object column, and an array of fixed size in a column with
# more than one dimension.
def dtype(column):
    if column.dtype.kind in "US":
        return "string"
    if column.dtype.kind == "O":
        cells = [cell for cell in column.tolist() if cell is not None]
        return "string" if all(isinstance(cell, str) for cell in cells) else "list"
    if column.ndim > 1:
        return "list"
    return column.dtype.name


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
