// backend/lib/base-outputs.ts
// Type definition for base_outputs.json produced by cognito-s3-stack-893.
// This is a local copy — keep in sync with the base repo's shared/types/base-outputs.ts.

export interface BaseOutputs {
  version:    string;
  aws_region: string;
  auth: {
    user_pool_id:        string;
    user_pool_client_id: string;
    user_pool_provider:  string;
    identity_pool_id:    string;
    auth_role_arn:       string;
  };
  storage: {
    public_bucket:  string;
    private_bucket: string;
  };
}
