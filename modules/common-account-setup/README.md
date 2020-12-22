# common-account-setup
This module creates roles that can be used by the deployment pipeline during a deployment. The _deployment_ role is granted administrator access, and can only be assumed by a specific role. The _set-version_ role is allowed to write to AWS SSM parameters with a specific prefix.

The module should be instantiated in all accounts that the deployment pipeline is set up to deploy to (e.g., _service_, _test_, _stage_ and _prod_).
