import copy
import datetime
import unittest

from prepare_ios_signing import export_options


class SigningConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.profile = {
            'UUID': '12345678-1234-1234-1234-123456789abc',
            'TeamIdentifier': ['ABCDE12345'],
            'ApplicationIdentifierPrefix': ['ABCDE12345'],
            'ExpirationDate': datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=30),
            'Entitlements': {
                'application-identifier': 'ABCDE12345.com.example.rihla',
                'get-task-allow': False,
            },
        }

    def test_app_store_export_is_manual_and_does_not_upload(self):
        result = export_options(self.profile, 'com.example.rihla', 'app-store-connect')
        self.assertEqual(result['destination'], 'export')
        self.assertEqual(result['teamID'], 'ABCDE12345')
        self.assertEqual(result['provisioningProfiles']['com.example.rihla'], self.profile['UUID'])

    def test_ad_hoc_requires_registered_devices(self):
        with self.assertRaises(ValueError):
            export_options(self.profile, 'com.example.rihla', 'release-testing')
        self.profile['ProvisionedDevices'] = ['test-device']
        result = export_options(self.profile, 'com.example.rihla', 'release-testing')
        self.assertEqual(result['method'], 'release-testing')
        with self.assertRaises(ValueError):
            export_options(self.profile, 'com.example.rihla', 'app-store-connect')

    def test_expired_development_enterprise_and_mismatched_profiles_fail(self):
        variants = []
        expired = copy.deepcopy(self.profile)
        expired['ExpirationDate'] = datetime.datetime(2020, 1, 1)
        variants.append(expired)
        development = copy.deepcopy(self.profile)
        development['Entitlements']['get-task-allow'] = True
        variants.append(development)
        enterprise = copy.deepcopy(self.profile)
        enterprise['ProvisionsAllDevices'] = True
        variants.append(enterprise)
        wrong_app = copy.deepcopy(self.profile)
        wrong_app['Entitlements']['application-identifier'] = 'ABCDE12345.com.wrong.app'
        variants.append(wrong_app)
        for profile in variants:
            with self.subTest(profile=profile), self.assertRaises(ValueError):
                export_options(profile, 'com.example.rihla', 'app-store-connect')

    def test_rejects_values_that_could_corrupt_environment_output(self):
        self.profile['UUID'] += '\nINJECTED=value'
        with self.assertRaises(ValueError):
            export_options(self.profile, 'com.example.rihla', 'app-store-connect')

    def test_legacy_app_identifier_prefix_may_differ_from_team(self):
        self.profile['ApplicationIdentifierPrefix'] = ['LEGACY1234']
        self.profile['Entitlements']['application-identifier'] = 'LEGACY1234.com.example.rihla'
        result = export_options(self.profile, 'com.example.rihla', 'app-store-connect')
        self.assertEqual(result['teamID'], 'ABCDE12345')


if __name__ == '__main__':
    unittest.main()
