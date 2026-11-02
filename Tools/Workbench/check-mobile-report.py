#!/usr/bin/env python3
"""Validate one explicitly exported Workbench mobile report; no device access, launch or UI control."""
import argparse
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import uuid

spec = importlib.util.spec_from_file_location('workbench', Path(__file__).with_name('workbench.py'))
workbench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workbench)
BUILD_ID = 'c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f'
CATALOGUE_SHA = 'e341bfc0385fea9b2b026dc624daa26cdeac33286f4bb07243b37c1c31837d0e'


def check(raw, *, run_id, pid, scenario, app_version):
    """Correlate independently selected launch/run identities and require full actual scene/build assertions."""
    if len(raw) > 65536 or scenario not in ('host.lifecycle', 'host.lifecycle-active', 'host.lifecycle-worker'):
        raise ValueError('select one bounded mobile lifecycle report')
    report = json.loads(raw, object_pairs_hook=workbench.unique_object)
    if (not isinstance(report, dict) or report.get('appVersion') != app_version
            or report.get('status') != 'passed' or report.get('catalogueSHA256') != CATALOGUE_SHA):
        raise ValueError('report is incomplete, failed or from another app/catalogue')
    request = dict(schema=1, requestID=str(uuid.UUID(run_id)).upper(), operation='run', scenarioID=scenario, firmwareBuildID=BUILD_ID)
    response = dict(schema=1, request=request, processID=pid, scenarios=[], report=report)
    envelope = workbench.PREFIX + base64.b64encode(json.dumps(response).encode())
    workbench.decode_response(envelope, request, pid, interactive=True)
    for artifact in report['artifacts']:
        receipt = json.loads(base64.b64decode(artifact['receiptJSON'], validate=True), object_pairs_hook=workbench.unique_object)
        if (receipt.get('capsuleSHA256') != artifact['sha256'] or receipt.get('firmwareBuildID') != BUILD_ID
                or receipt.get('catalogueSHA256') != CATALOGUE_SHA):
            raise ValueError('SDK receipt differs from the selected artifact/catalogue')
    return dict(status='passed_mobile_workbench_report', runID=request['requestID'], processID=pid,
                scenarioID=scenario, reportSHA256=hashlib.sha256(raw).hexdigest(), exercise=report['exercise'],
                scope='Actual app scene delivery and known SDK artifacts; no OS suspension, pressure, board or minimum-OS claim')


def main():
    """Read only the selected local exported file and emit a bounded validation result."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--scenario', required=True)
    parser.add_argument('--app-version', required=True)
    args = parser.parse_args()
    if args.pid <= 0:
        parser.error('select the independently recorded positive launch PID')
    print(json.dumps(check(workbench.bounded_file(args.report, 65536), run_id=args.run_id, pid=args.pid,
                           scenario=args.scenario, app_version=args.app_version), indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        raise SystemExit(str(error)) from error
