"""Validate an Apple profile and write export options, without printing secrets."""

import datetime
import os
import plistlib
import re
import sys
from pathlib import Path


def export_options(profile, bundle_id, distribution):
    if distribution not in {'app-store-connect', 'release-testing'}:
        raise ValueError('Unsupported distribution method.')
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', bundle_id):
        raise ValueError('Set IOS_BUNDLE_ID to your registered explicit App ID.')
    teams = profile.get('TeamIdentifier', [])
    if len(teams) != 1 or not re.fullmatch(r'[A-Z0-9]{10}', teams[0]):
        raise ValueError('Profile must contain one valid Apple team identifier.')
    uuid = profile.get('UUID', '')
    if not re.fullmatch(r'[A-Fa-f0-9-]{36}', uuid):
        raise ValueError('Invalid provisioning profile UUID.')
    entitlement = profile.get('Entitlements', {})
    app_id = entitlement.get('application-identifier', '')
    prefixes = profile.get('ApplicationIdentifierPrefix', teams)
    if app_id not in [f'{prefix}.{bundle_id}' for prefix in prefixes]:
        raise ValueError('The profile App ID does not match IOS_BUNDLE_ID.')
    expiry = profile.get('ExpirationDate')
    if not isinstance(expiry, datetime.datetime) or expiry.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError('The provisioning profile has expired or has no expiry.')
    if entitlement.get('get-task-allow') or profile.get('ProvisionsAllDevices'):
        raise ValueError('Use an Apple Distribution profile, not development or enterprise.')
    registered_devices = bool(profile.get('ProvisionedDevices'))
    if distribution == 'release-testing' and not registered_devices:
        raise ValueError('Ad Hoc distribution needs a profile containing your iPhone UDID.')
    if distribution == 'app-store-connect' and registered_devices:
        raise ValueError('Use an App Store Connect profile for this distribution method.')
    return {
        'method': distribution,
        'teamID': teams[0],
        'signingStyle': 'manual',
        'signingCertificate': 'Apple Distribution',
        'provisioningProfiles': {bundle_id: uuid},
        'destination': 'export',
        'manageAppVersionAndBuildNumber': False,
        'stripSwiftSymbols': True,
    }


def main():
    profile = plistlib.loads(Path(sys.argv[1]).read_bytes())
    options = export_options(profile, os.environ['IOS_BUNDLE_ID'], os.environ['DISTRIBUTION'])
    Path(sys.argv[2]).write_bytes(plistlib.dumps(options))
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as environment:
        environment.write(f"IOS_TEAM_ID={options['teamID']}\n")
        environment.write(f"IOS_PROFILE_UUID={profile['UUID']}\n")


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, IndexError) as error:
        sys.exit(f'Signing configuration error: {error}')
